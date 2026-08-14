#!/bin/zsh
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

identity_label=${RAM_PROJECT_SIGNING_LABEL:-Roblox Account Manager Project Release}
identity_organization="Roblox Account Manager for Mac"
keychain_path=${RAM_PROJECT_SIGNING_KEYCHAIN:-}
ram_device=""

cleanup() {
    unset private_key certificate p12_password
    if [[ -n "$ram_device" ]]; then
        /usr/bin/hdiutil detach "$ram_device" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT INT TERM

if [[ -z "$keychain_path" ]]; then
    keychain_path=$(
        /usr/bin/security default-keychain -d user \
            | /usr/bin/sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//'
    )
fi
if [[ ! -f "$keychain_path" ]]; then
    print -u2 "The selected Keychain does not exist: $keychain_path"
    exit 1
fi

certificate_fingerprint() {
    print -rn -- "$1" \
        | /usr/bin/openssl x509 -noout -fingerprint -sha256 \
        | /usr/bin/awk -F= '{print tolower($2)}' \
        | /usr/bin/tr -d ':'
}

existing_certificate=$(
    /usr/bin/security find-certificate -c "$identity_label" -p "$keychain_path" 2>/dev/null || true
)
if [[ -n "$existing_certificate" ]]; then
    if ! /usr/bin/security find-key -t private -s -l "$identity_label" \
        "$keychain_path" >/dev/null 2>&1; then
        print -u2 "The project certificate exists, but its private key is missing."
        exit 1
    fi
    if print -rn -- "$existing_certificate" \
        | /usr/bin/openssl x509 -noout -subject -issuer -nameopt RFC2253 \
        | /usr/bin/grep -Eiq '[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}'; then
        print -u2 "The existing project certificate contains an email address."
        exit 1
    fi
    identity_hash=$(
        /usr/bin/security find-certificate -c "$identity_label" -Z "$keychain_path" \
            | /usr/bin/awk '/SHA-1 hash:/{print $3; exit}'
    )
    print "The project signing identity is already installed."
    print "Certificate SHA-256: $(certificate_fingerprint "$existing_certificate")"
    print "Signing identity: $identity_hash"
    exit 0
fi

ram_device=$(
    /usr/bin/hdiutil attach -nomount ram://32768 2>/dev/null \
        | /usr/bin/awk 'NR == 1 {print $1}'
)
if [[ -z "$ram_device" ]]; then
    print -u2 "A temporary memory disk could not be created."
    exit 1
fi
ram_volume="RAMacSigning-$RANDOM-$$"
/usr/sbin/diskutil erasevolume HFS+ "$ram_volume" "$ram_device" >/dev/null
p12_path="/Volumes/$ram_volume/project-signing.p12"

umask 077
private_key=$(
    /usr/bin/openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 2>/dev/null
)
certificate=$(
    print -rn -- "$private_key" \
        | /usr/bin/openssl req -new -x509 -key /dev/stdin -sha256 -days 7305 \
            -subj "/CN=$identity_label/O=$identity_organization" \
            -addext "basicConstraints=critical,CA:FALSE" \
            -addext "keyUsage=critical,digitalSignature" \
            -addext "extendedKeyUsage=codeSigning"
)

certificate_details=$(
    print -rn -- "$certificate" \
        | /usr/bin/openssl x509 -noout -subject -issuer -nameopt RFC2253
)
if print -r -- "$certificate_details" \
    | /usr/bin/grep -Eiq '[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}'; then
    print -u2 "The generated certificate unexpectedly contains an email address."
    exit 1
fi

if [[ ! -t 0 ]]; then
    print -u2 "Run this command in an interactive Terminal so the import password stays private."
    exit 1
fi
print "Enter a temporary password for the in-memory Keychain transfer."
read -s "p12_password?Temporary password: "
print
if [[ ${#p12_password} -lt 12 ]]; then
    print -u2 "Use at least 12 characters."
    exit 1
fi
print "macOS will ask for this temporary password again during import."
print -rn -- "$p12_password" | /usr/bin/openssl pkcs12 -export \
    -inkey <(print -rn -- "$private_key") \
    -in <(print -rn -- "$certificate") \
    -name "$identity_label" \
    -passout stdin \
    -out "$p12_path"
unset p12_password
/usr/bin/security import "$p12_path" \
    -k "$keychain_path" \
    -x >/dev/null

identity_hash=$(
    /usr/bin/security find-certificate -c "$identity_label" -Z "$keychain_path" \
        | /usr/bin/awk '/SHA-1 hash:/{print $3; exit}'
)
if [[ -z "$identity_hash" ]] \
    || ! /usr/bin/security find-key -t private -s -l "$identity_label" \
        "$keychain_path" >/dev/null 2>&1; then
    print -u2 "The project signing identity was not installed correctly."
    exit 1
fi

print "Created a project-owned code-signing identity with no email address."
print "Certificate SHA-256: $(certificate_fingerprint "$certificate")"
print "Signing identity: $identity_hash"
