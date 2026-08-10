#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
app_dir="$project_dir/dist/Roblox Account Manager.app"
contents_dir="$app_dir/Contents"

cd "$project_dir"
swift build -c release --arch arm64 --arch x86_64
binary_dir=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$binary_dir/RobloxAccountManager" "$contents_dir/MacOS/RobloxAccountManager"
cp "packaging/Info.plist" "$contents_dir/Info.plist"

swift scripts/make-icon.swift "$project_dir/dist"
cp "$project_dir/dist/AppIcon.icns" "$contents_dir/Resources/AppIcon.icns"

chmod 755 "$contents_dir/MacOS/RobloxAccountManager"
signing_identity="-"
identity_output=$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)
for identity_label in "Developer ID Application" "Apple Development" "Mac Developer"; do
    identity_line=$(print -r -- "$identity_output" | grep -m 1 "$identity_label" || true)
    if [[ -n "$identity_line" ]]; then
        signing_identity=$(print -r -- "$identity_line" | awk '{print $2}')
        break
    fi
done

codesign --force --deep --timestamp=none --sign "$signing_identity" "$app_dir"
plutil -lint "$contents_dir/Info.plist"
codesign --verify --deep --strict "$app_dir"

print "Built: $app_dir"
