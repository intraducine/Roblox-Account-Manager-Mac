#!/bin/zsh
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

script_dir=${0:A:h}
project_dir=${script_dir:h}
app_name="Roblox Account Manager.app"
app_path="$project_dir/dist/$app_name"
release_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$project_dir/packaging/Info.plist")
archive_path="$project_dir/dist/Roblox-Account-Manager-for-Mac-$release_version.zip"
checksum_path="$archive_path.sha256"
signature_path="$archive_path.sig"
version_parts=(${(s:.:)release_version})
release_number=$(( ${version_parts[1]:-0} * 10000 + ${version_parts[2]:-0} * 100 + ${version_parts[3]:-0} ))
requires_bridge_base=$(( release_number == 10101 ))
requires_update_pin=$(( release_number >= 10101 ))
requires_project_certificate=$(( release_number >= 10102 ))
expected_project_certificate_sha256=${RAM_EXPECTED_PROJECT_CERT_SHA256:-}
project_signing_label=${RAM_PROJECT_SIGNING_LABEL:-Roblox Account Manager Project Release}
bridge_base_app=${RAM_BRIDGE_BASE_APP:-}
audit_dir=""

cleanup_audit_dir() {
    if [[ "$audit_dir" == /tmp/ramac-signing-audit.?????? ]]; then
        /bin/rm -rf -- "$audit_dir"
    fi
}
trap cleanup_audit_dir EXIT

if (( requires_update_pin )); then
    project_certificate_pem=$(
        /usr/bin/security find-certificate -c "$project_signing_label" -p 2>/dev/null
    )
    if [[ -z "$project_certificate_pem" ]]; then
        print -u2 "The project signing certificate is missing."
        print -u2 "Run scripts/create-project-signing-identity.sh once on the release Mac."
        exit 1
    fi
    installed_project_certificate_sha256=$(
        print -rn -- "$project_certificate_pem" \
            | /usr/bin/openssl x509 -noout -fingerprint -sha256 \
            | /usr/bin/awk -F= '{print tolower($2)}' \
            | /usr/bin/tr -d ':'
    )
    if [[ -z "$expected_project_certificate_sha256" ]]; then
        expected_project_certificate_sha256="$installed_project_certificate_sha256"
    fi
    if [[ ! "$expected_project_certificate_sha256" =~ '^[a-f0-9]{64}$' ]]; then
        print -u2 "RAM_EXPECTED_PROJECT_CERT_SHA256 must be a lowercase SHA-256 certificate fingerprint."
        exit 1
    fi
    if [[ "$expected_project_certificate_sha256" != "$installed_project_certificate_sha256" ]]; then
        print -u2 "RAM_EXPECTED_PROJECT_CERT_SHA256 does not match the installed project certificate."
        exit 1
    fi
    export RAM_EXPECTED_PROJECT_CERT_SHA256="$expected_project_certificate_sha256"
fi
if (( requires_bridge_base )); then
    if [[ ! -d "$bridge_base_app" ]]; then
        print -u2 "Set RAM_BRIDGE_BASE_APP to the public version 1.1.0 app."
        exit 1
    fi
    bridge_base_version=$(/usr/libexec/PlistBuddy \
        -c "Print :CFBundleShortVersionString" \
        "$bridge_base_app/Contents/Info.plist")
    bridge_base_identifier=$(/usr/libexec/PlistBuddy \
        -c "Print :CFBundleIdentifier" \
        "$bridge_base_app/Contents/Info.plist")
    if [[ "$bridge_base_version" != "1.1.0" \
        || "$bridge_base_identifier" != "com.intraducine.RobloxAccountManager" ]]; then
        print -u2 "RAM_BRIDGE_BASE_APP must be the public version 1.1.0 app."
        exit 1
    fi
fi

cd "$project_dir"
"$script_dir/build-app.sh"
/usr/bin/codesign --verify --deep --strict "$app_path"
/usr/bin/lipo "$app_path/Contents/MacOS/RobloxAccountManager" -verify_arch arm64 x86_64

if (( requires_update_pin )); then
    embedded_project_certificate_sha256=$(/usr/libexec/PlistBuddy \
        -c "Print :RAMExpectedProjectCertificateSHA256" \
        "$app_path/Contents/Info.plist")
    if [[ "$embedded_project_certificate_sha256" != "$expected_project_certificate_sha256" ]]; then
        print -u2 "The app does not contain the approved project certificate fingerprint."
        exit 1
    fi
fi

if (( requires_bridge_base )); then
    base_requirement=$(/usr/bin/codesign -d -r- "$bridge_base_app" 2>&1 \
        | /usr/bin/sed -n 's/^designated => //p')
    bridge_requirement=$(/usr/bin/codesign -d -r- "$app_path" 2>&1 \
        | /usr/bin/sed -n 's/^designated => //p')
    if [[ -z "$base_requirement" || -z "$bridge_requirement" ]] \
        || ! /usr/bin/codesign --verify --deep --strict \
            -R="$base_requirement" "$app_path" >/dev/null 2>&1 \
        || ! /usr/bin/codesign --verify --deep --strict \
            -R="$bridge_requirement" "$bridge_base_app" >/dev/null 2>&1; then
        print -u2 "Version 1.1.1 must remain compatible with the public version 1.1.0 signature."
        exit 1
    fi
fi

if (( requires_project_certificate )); then
    audit_dir=$(/usr/bin/mktemp -d /tmp/ramac-signing-audit.XXXXXX)
    signature_details="$audit_dir/codesign.txt"
    certificate_prefix="$audit_dir/certificate"
    certificate_details="$audit_dir/certificate.txt"
    /usr/bin/codesign -dv --verbose=4 "$app_path" >"$signature_details" 2>&1
    /usr/bin/codesign -d --extract-certificates="$certificate_prefix" "$app_path" >/dev/null 2>&1
    /usr/bin/openssl x509 -inform DER -in "${certificate_prefix}0" \
        -noout -subject -issuer -nameopt RFC2253 -fingerprint -sha256 >"$certificate_details"
    actual_project_certificate_sha256=$(
        /usr/bin/awk -F= '/^sha256 Fingerprint=|^SHA256 Fingerprint=/{print tolower($2); exit}' \
            "$certificate_details" \
            | /usr/bin/tr -d ':'
    )
    if [[ "$actual_project_certificate_sha256" != "$expected_project_certificate_sha256" ]]; then
        print -u2 "The packaged app does not match the approved project signing certificate."
        exit 1
    fi
    if /usr/bin/grep -Eiq '[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}' \
        "$signature_details" "$certificate_details"; then
        print -u2 "The release signature contains an email address. Packaging stopped."
        exit 1
    fi
    if LC_ALL=C /usr/bin/grep -ERaIq \
        '[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}|/Users/[^/]+' \
        "$app_path"; then
        print -u2 "The release app contains an email address or local user home path. Packaging stopped."
        exit 1
    fi
fi

/bin/rm -f "$archive_path" "$checksum_path" "$signature_path"
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --keepParent --norsrc --noextattr "$app_path" "$archive_path"
(
    cd "$project_dir/dist"
    /usr/bin/shasum -a 256 "${archive_path:t}"
) > "$checksum_path"
/usr/bin/xcrun swift "$script_dir/release-signature.swift" sign "$archive_path" "$signature_path"
/usr/bin/xcrun swift "$script_dir/release-signature.swift" verify "$archive_path" "$signature_path"

print "Archive: $archive_path"
print "Checksum: $checksum_path"
print "Signature: $signature_path"
