#!/bin/zsh
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

script_dir=${0:A:h}
project_dir=${script_dir:h}
app_dir="$project_dir/dist/Roblox Account Manager.app"
contents_dir="$app_dir/Contents"

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

/usr/bin/xcrun swift scripts/make-icon.swift "$project_dir/dist"
/bin/cp "$project_dir/dist/AppIcon.icns" "$contents_dir/Resources/AppIcon.icns"

/bin/chmod 755 "$contents_dir/MacOS/RobloxAccountManager"
/usr/bin/strip -S "$contents_dir/MacOS/RobloxAccountManager"
signing_identity=${RAM_SIGNING_IDENTITY:-}
if [[ -z "$signing_identity" ]]; then
    signing_identity=$(
        /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
            | /usr/bin/awk '/^[[:space:]]*[0-9]+\)/ { print $2; exit }'
    )
fi
if [[ -z "$signing_identity" ]]; then
    signing_identity=-
    print "No code-signing identity was found. Using an ad hoc signature."
else
    print "Using a stable installed code-signing identity."
fi

/usr/bin/codesign --force --deep --timestamp=none --sign "$signing_identity" "$app_dir"
/usr/bin/plutil -lint "$contents_dir/Info.plist"
/usr/bin/codesign --verify --deep --strict "$app_dir"
/usr/bin/lipo "$contents_dir/MacOS/RobloxAccountManager" -verify_arch arm64 x86_64

print "Built: $app_dir"
