#!/bin/zsh
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

script_dir=${0:A:h}
project_dir=${script_dir:h}
app_dir="$project_dir/dist/Roblox Account Manager.app"
app_name="Roblox Account Manager.app"
contents_dir="$app_dir/Contents"
release_version=$(/usr/bin/tr -d '[:space:]' < "$project_dir/VERSION")
if [[ ! "$release_version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    print -u2 "VERSION must contain one numeric version such as 1.1.2."
    exit 1
fi
version_parts=(${(s:.:)release_version})
release_number=$(( ${version_parts[1]:-0} * 10000 + ${version_parts[2]:-0} * 100 + ${version_parts[3]:-0} ))
requires_update_pin=$(( release_number >= 10101 ))
requires_project_certificate=$(( release_number >= 10102 ))
expected_project_certificate_sha256=${RAM_EXPECTED_PROJECT_CERT_SHA256:-}
project_signing_label=${RAM_PROJECT_SIGNING_LABEL:-Roblox Account Manager Project Release}
allow_ad_hoc_build=${RAM_ALLOW_AD_HOC_BUILD:-0}

if [[ "$allow_ad_hoc_build" != "0" && "$allow_ad_hoc_build" != "1" ]]; then
    print -u2 "RAM_ALLOW_AD_HOC_BUILD must be 0 or 1."
    exit 1
fi

if [[ -n "$expected_project_certificate_sha256" \
    && ! "$expected_project_certificate_sha256" =~ '^[a-f0-9]{64}$' ]]; then
    print -u2 "RAM_EXPECTED_PROJECT_CERT_SHA256 must be a lowercase SHA-256 certificate fingerprint."
    exit 1
fi
if (( requires_update_pin )) && [[ -z "$expected_project_certificate_sha256" && "$allow_ad_hoc_build" != "1" ]]; then
    print -u2 "RAM_EXPECTED_PROJECT_CERT_SHA256 is required for version $release_version."
    exit 1
fi

cd "$project_dir"
swift_build_args=(
    -c release
    --arch arm64
    --arch x86_64
    -Xswiftc -debug-prefix-map
    -Xswiftc "$project_dir=."
    -Xswiftc -file-prefix-map
    -Xswiftc "$project_dir=."
)
/usr/bin/xcrun swift build "${swift_build_args[@]}"
binary_dir=$(/usr/bin/xcrun swift build "${swift_build_args[@]}" --show-bin-path)

/bin/rm -rf "$app_dir"
/bin/mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
/bin/cp "$binary_dir/RobloxAccountManager" "$contents_dir/MacOS/RobloxAccountManager"
/bin/cp "packaging/Info.plist" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $release_version" "$contents_dir/Info.plist"
if [[ -n "$expected_project_certificate_sha256" ]]; then
    /usr/libexec/PlistBuddy -c \
        "Add :RAMExpectedProjectCertificateSHA256 string $expected_project_certificate_sha256" \
        "$contents_dir/Info.plist"
fi

/usr/bin/xcrun swift scripts/make-icon.swift "$project_dir/dist"
/bin/cp "$project_dir/dist/AppIcon.icns" "$contents_dir/Resources/AppIcon.icns"

/bin/chmod 755 "$contents_dir/MacOS/RobloxAccountManager"
/usr/bin/strip -S "$contents_dir/MacOS/RobloxAccountManager"
signing_identity=${RAM_SIGNING_IDENTITY:-}
if [[ -z "$signing_identity" && "$allow_ad_hoc_build" == "1" ]]; then
    signing_identity=-
fi
if [[ -z "$signing_identity" ]]; then
    if (( requires_project_certificate )); then
        signing_identity=$(
            /usr/bin/security find-certificate -c "$project_signing_label" -Z 2>/dev/null \
                | /usr/bin/awk '/SHA-1 hash:/{ print $3; exit }'
        )
    else
        signing_identity=$(
            /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
                | /usr/bin/awk '/^[[:space:]]*[0-9]+\)/ { print $2; exit }'
        )
    fi
fi
if [[ -z "$signing_identity" ]]; then
    if (( requires_project_certificate )) && [[ "$allow_ad_hoc_build" != "1" ]]; then
        print -u2 "The project signing identity is required for version $release_version and later."
        print -u2 "Run scripts/create-project-signing-identity.sh once on the release Mac."
        exit 1
    fi
    signing_identity=-
fi
if [[ "$signing_identity" == "-" ]]; then
    print "Using an ad hoc signature for local verification. Do not publish this build."
elif (( requires_project_certificate )); then
    print "Using the project-owned code-signing identity."
else
    print "Using a stable installed code-signing identity."
fi

codesign_arguments=(--force --deep --sign "$signing_identity")
codesign_arguments+=(--timestamp=none)
/usr/bin/codesign "${codesign_arguments[@]}" "$app_dir"
/usr/bin/plutil -lint "$contents_dir/Info.plist"
/usr/bin/codesign --verify --deep --strict "$app_dir"
/usr/bin/lipo "$contents_dir/MacOS/RobloxAccountManager" -verify_arch arm64 x86_64

if (( requires_project_certificate )) && [[ "$signing_identity" != "-" ]]; then
    certificate_dir=$(/usr/bin/mktemp -d /tmp/ramac-build-certificate.XXXXXX)
    certificate_prefix="$certificate_dir/certificate"
    /usr/bin/codesign -d --extract-certificates="$certificate_prefix" "$app_dir" >/dev/null 2>&1
    actual_certificate_sha256=$(
        /usr/bin/openssl x509 -inform DER -in "${certificate_prefix}0" -noout -fingerprint -sha256 \
            | /usr/bin/awk -F= '{print tolower($2)}' \
            | /usr/bin/tr -d ':'
    )
    /usr/bin/find "$certificate_dir" -depth -delete
    if [[ "$actual_certificate_sha256" != "$expected_project_certificate_sha256" ]]; then
        print -u2 "The project signing identity does not match RAM_EXPECTED_PROJECT_CERT_SHA256."
        exit 1
    fi
fi

print "Built: dist/$app_name"
