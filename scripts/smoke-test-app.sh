#!/bin/zsh
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

script_dir=${0:A:h}
project_dir=${script_dir:h}
app_path="$project_dir/dist/Roblox Account Manager.app"
binary_path="$app_path/Contents/MacOS/RobloxAccountManager"
smoke_dir=$(/usr/bin/mktemp -d /tmp/ramac-ui-smoke.XXXXXX)
app_pid=""

cleanup() {
    if [[ "$app_pid" == <-> ]] && /bin/kill -0 "$app_pid" 2>/dev/null; then
        /bin/kill -TERM "$app_pid" 2>/dev/null || true
        wait "$app_pid" 2>/dev/null || true
    fi
    if [[ "$smoke_dir" == /tmp/ramac-ui-smoke.?????? ]]; then
        /usr/bin/find "$smoke_dir" -depth -delete
    fi
}
trap cleanup EXIT

cd "$project_dir"
RAM_ALLOW_AD_HOC_BUILD=1 RAM_EXPECTED_PROJECT_CERT_SHA256= "$script_dir/build-app.sh"

expected_version=$(/usr/bin/tr -d '[:space:]' < "$project_dir/VERSION")
actual_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app_path/Contents/Info.plist")
actual_identifier=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_path/Contents/Info.plist")

[[ "$actual_version" == "$expected_version" ]] || {
    print -u2 "The packaged version does not match VERSION."
    exit 1
}
[[ "$actual_identifier" == "com.intraducine.RobloxAccountManager" ]] || {
    print -u2 "The packaged bundle identifier is wrong."
    exit 1
}
if /usr/bin/grep -F -q '$(MARKETING_VERSION)' "$app_path/Contents/Info.plist"; then
    print -u2 "The packaged app contains an unresolved version placeholder."
    exit 1
fi

/usr/bin/plutil -lint "$app_path/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict "$app_path"
/usr/bin/lipo "$binary_path" -verify_arch arm64 x86_64

/usr/bin/open -n -F \
    --stdout "$smoke_dir/app.log" \
    --stderr "$smoke_dir/app.log" \
    --env "RAM_UI_SMOKE_TEST=1" \
    --env "RAM_UI_SMOKE_DATA_DIRECTORY=$smoke_dir" \
    "$app_path" \
    --args --ram-ui-smoke "$smoke_dir"

for _ in {1..75}; do
    [[ -f "$smoke_dir/main-window-ready" ]] && break
    if [[ -z "$app_pid" ]]; then
        app_pid=$(/usr/bin/pgrep -n -f -- "--ram-ui-smoke $smoke_dir" 2>/dev/null || true)
    fi
    if [[ "$app_pid" == <-> ]] && ! /bin/kill -0 "$app_pid" 2>/dev/null; then
        /bin/cat "$smoke_dir/app.log" >&2
        print -u2 "The packaged app stopped before its main window appeared."
        exit 1
    fi
    /bin/sleep 0.2
done

[[ -f "$smoke_dir/main-window-ready" ]] || {
    /bin/cat "$smoke_dir/app.log" >&2
    print -u2 "The packaged app did not report a main window within 15 seconds."
    exit 1
}
[[ "$(/usr/bin/tr -d '\n' < "$smoke_dir/main-window-ready")" == "ready $expected_version" ]] || {
    print -u2 "The running app did not read the packaged version."
    exit 1
}

print "Packaged app smoke test passed for version $actual_version."
