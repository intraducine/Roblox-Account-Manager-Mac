#!/bin/zsh
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

binary_path=${1:?Pass the built executable}
sdk_version=$(/usr/bin/xcrun --sdk macosx --show-sdk-version)
minimum_macos=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${0:A:h:h}/packaging/Info.plist")
if [[ ! "$sdk_version" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ]] || (( ${sdk_version%%.*} < 26 )); then
    print -u2 "Build with a macOS 26 or newer SDK to preserve the native interface."
    exit 1
fi

normalize_version() {
    print -r -- "$1" | /usr/bin/awk -F. '{ printf "%d.%d.%d", $1, $2, $3 }'
}

for architecture in arm64 x86_64; do
    build_versions=$(/usr/bin/otool -arch "$architecture" -l "$binary_path" | /usr/bin/awk '
        $1 == "cmd" && $2 == "LC_BUILD_VERSION" { found = 1; next }
        found && $1 == "minos" { minimum = $2 }
        found && $1 == "sdk" { print minimum, $2; found = 0 }
    ')
    versions=(${=build_versions})
    recorded_minimum=${versions[1]:-}
    recorded_sdk=${versions[2]:-}
    if [[ ! "$recorded_sdk" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ]] \
        || [[ "$(normalize_version "$recorded_sdk")" != "$(normalize_version "$sdk_version")" ]]; then
        print -u2 "The $architecture executable records SDK ${recorded_sdk:-unknown}; the selected SDK is $sdk_version."
        print -u2 "Build stopped to prevent an incorrect macOS interface. Check the Xcode toolchain."
        exit 1
    fi
    if [[ ! "$recorded_minimum" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ]] \
        || [[ "$(normalize_version "$recorded_minimum")" != "$(normalize_version "$minimum_macos")" ]]; then
        print -u2 "The $architecture executable has an incorrect minimum macOS version."
        exit 1
    fi
done
