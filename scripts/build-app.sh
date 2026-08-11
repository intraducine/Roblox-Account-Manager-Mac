#!/bin/zsh
set -euo pipefail

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
swift build "${swift_build_args[@]}"
binary_dir=$(swift build "${swift_build_args[@]}" --show-bin-path)

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$binary_dir/RobloxAccountManager" "$contents_dir/MacOS/RobloxAccountManager"
cp "packaging/Info.plist" "$contents_dir/Info.plist"

swift scripts/make-icon.swift "$project_dir/dist"
cp "$project_dir/dist/AppIcon.icns" "$contents_dir/Resources/AppIcon.icns"

chmod 755 "$contents_dir/MacOS/RobloxAccountManager"
/usr/bin/strip -S "$contents_dir/MacOS/RobloxAccountManager"
signing_identity=${RAM_SIGNING_IDENTITY:--}

codesign --force --deep --timestamp=none --sign "$signing_identity" "$app_dir"
plutil -lint "$contents_dir/Info.plist"
codesign --verify --deep --strict "$app_dir"
/usr/bin/lipo "$contents_dir/MacOS/RobloxAccountManager" -verify_arch arm64 x86_64

print "Built: $app_dir"
