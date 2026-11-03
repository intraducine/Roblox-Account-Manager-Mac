#!/bin/zsh
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

script_dir=${0:A:h}
test_dir=$(/usr/bin/mktemp -d /tmp/ramac-sdk-test.XXXXXX)
trap '[[ "$test_dir" == /tmp/ramac-sdk-test.?????? ]] && /usr/bin/find "$test_dir" -depth -delete' EXIT
sdk_version=$(/usr/bin/xcrun --sdk macosx --show-sdk-version)
minimum_macos=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$script_dir/../packaging/Info.plist")
print 'int main(void) { return 0; }' > "$test_dir/main.c"

for architecture in arm64 x86_64; do
    /usr/bin/xcrun clang -arch "$architecture" -mmacosx-version-min="$minimum_macos" \
        -Wl,-platform_version,macos,"$minimum_macos","$sdk_version" \
        "$test_dir/main.c" -o "$test_dir/$architecture"
done
/usr/bin/lipo -create "$test_dir/arm64" "$test_dir/x86_64" -output "$test_dir/good"
"$script_dir/verify-build-sdk.sh" "$test_dir/good"

/usr/bin/xcrun clang -arch x86_64 -mmacosx-version-min="$minimum_macos" \
    -Wl,-platform_version,macos,"$minimum_macos","$minimum_macos" \
    "$test_dir/main.c" -o "$test_dir/bad-x86_64"
/usr/bin/lipo -create "$test_dir/arm64" "$test_dir/bad-x86_64" -output "$test_dir/bad"
if "$script_dir/verify-build-sdk.sh" "$test_dir/bad" > /dev/null 2>&1; then
    print -u2 'The SDK check accepted an incorrect x86_64 SDK version.'
    exit 1
fi
print 'SDK version check passed.'
