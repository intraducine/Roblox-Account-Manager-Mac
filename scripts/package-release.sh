#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
app_name="Roblox Account Manager.app"
app_path="$project_dir/dist/$app_name"
archive_path="$project_dir/dist/Roblox-Account-Manager-for-Mac-1.0.0.zip"
checksum_path="$archive_path.sha256"

cd "$project_dir"
"$script_dir/build-app.sh"
/usr/bin/codesign --verify --deep --strict "$app_path"
/usr/bin/lipo "$app_path/Contents/MacOS/RobloxAccountManager" -verify_arch arm64 x86_64

/bin/rm -f "$archive_path" "$checksum_path"
/usr/bin/ditto -c -k --keepParent "$app_path" "$archive_path"
(
    cd "$project_dir/dist"
    /usr/bin/shasum -a 256 "${archive_path:t}"
) > "$checksum_path"

print "Archive: $archive_path"
print "Checksum: $checksum_path"
