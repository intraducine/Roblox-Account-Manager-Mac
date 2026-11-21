#!/bin/zsh
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

cd "${0:A:h:h}"
fixture_dir=$(/usr/bin/mktemp -d /private/tmp/ramac-keychain-continuity.XXXXXX)
cleanup() {
    if [[ "$fixture_dir" == (/private/tmp|/tmp)/ramac-keychain-continuity.?????? && ! -L "$fixture_dir" ]]; then
        if [[ -f "$fixture_dir/Fixture.keychain-db" ]]; then
            /usr/bin/security delete-keychain "$fixture_dir/Fixture.keychain-db" >/dev/null 2>&1 || true
        fi
        /usr/bin/find "$fixture_dir" -depth -delete
    fi
}
trap cleanup EXIT

project_label='Roblox Account Manager Project Release'
identity=$(/usr/bin/security find-certificate -c "$project_label" -Z |
    /usr/bin/awk '/SHA-1 hash:/{ print tolower($3); exit }')
certificate_sha256=$(/usr/bin/security find-certificate -c "$project_label" -p |
    /usr/bin/openssl x509 -noout -sha256 -fingerprint |
    /usr/bin/awk -F= '{ print tolower($2) }' | /usr/bin/tr -d ':')
[[ "$identity" =~ '^[a-f0-9]{40}$' && "$certificate_sha256" =~ '^[a-f0-9]{64}$' ]]

build=(swift build --scratch-path .build/keychain-fixture -c release --arch arm64 --arch x86_64 \
    -Xswiftc -DRAM_KEYCHAIN_FIXTURE)
/usr/bin/xcrun "${build[@]}"
binary_dir=$(/usr/bin/xcrun "${build[@]}" --show-bin-path)
helper_id=com.intraducine.RobloxAccountManager.Keychain.Fixture
helper="$fixture_dir/$helper_id.xpc"
/bin/mkdir -p "$helper/Contents/MacOS"
/bin/cp packaging/KeychainService-Info.plist "$helper/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $helper_id" "$helper/Contents/Info.plist"
/usr/bin/xcrun clang -Os -fblocks -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -arch arm64 -arch x86_64 -mmacosx-version-min=13.0 -DRAM_KEYCHAIN_FIXTURE \
    "-DRAM_CERTIFICATE_SHA1=\"$identity\"" -framework CoreFoundation -framework Security \
    packaging/KeychainService.c -o "$helper/Contents/MacOS/RAMKeychainService"
/usr/bin/codesign --force --sign "$identity" --options runtime --timestamp=none "$helper"

make_app() {
    local app="$1" version="$2" build_number="$3"
    local contents="$app/Contents"
    /bin/mkdir -p "$contents/MacOS" "$contents/XPCServices"
    /bin/cp "$binary_dir/RobloxAccountManager" "$contents/MacOS/RobloxAccountManager"
    /usr/bin/ditto "$helper" "$contents/XPCServices/$helper_id.xpc"
    /bin/cp packaging/Info.plist "$contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" \
        -c "Set :CFBundleVersion $build_number" \
        -c "Add :RAMExpectedProjectCertificateSHA256 string $certificate_sha256" \
        -c "Add :RAMKeychainCertificateSHA1 string $identity" \
        -c 'Add :RAMKeychainAccessVersion string 1' "$contents/Info.plist"
    /usr/bin/codesign --force --sign "$identity" --options runtime --timestamp=none "$app"
    /usr/bin/codesign --verify --deep --strict "$app"
}

installed="$fixture_dir/Roblox Account Manager.app"
incoming="$fixture_dir/Candidate.app"
exe="$installed/Contents/MacOS/RobloxAccountManager"
fixture_helper="Contents/XPCServices/$helper_id.xpc/Contents/MacOS/RAMKeychainService"
run_fixture() {
    "$exe" --keychain-continuity-fixture "$fixture_dir" "$@"
}

make_app "$installed" 1.3.0 133
run_fixture seed
run_fixture verify
previous_app_hash=$(/usr/bin/codesign -d --verbose=4 "$installed" 2>&1 | /usr/bin/sed -n 's/^CDHash=//p')
[[ -n "$previous_app_hash" ]]
for stage in 1 2; do
    version="1.3.$stage"
    build_number=$(( 133 + stage ))
    make_app "$incoming" "$version" "$build_number"
    run_fixture install "$incoming" "$version"
    /usr/bin/cmp "$helper/Contents/MacOS/RAMKeychainService" "$installed/$fixture_helper"
    app_hash=$(/usr/bin/codesign -d --verbose=4 "$installed" 2>&1 | /usr/bin/sed -n 's/^CDHash=//p')
    [[ -n "$app_hash" && "$app_hash" != "$previous_app_hash" ]]
    previous_app_hash="$app_hash"
    run_fixture verify
    /usr/bin/find "$incoming" -depth -delete
done

print 'Passed two signed updates with an existing Keychain entry and Keychain prompts disabled.'
