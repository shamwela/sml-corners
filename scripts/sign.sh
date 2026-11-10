#!/bin/bash
# Signs the app with a stable self-signed identity so the Accessibility grant
# survives rebuilds. Creates the identity in the login keychain on first use.
# Falls back to ad-hoc signing (grant resets on every rebuild) if that fails.
set -euo pipefail

APP="$1"
IDENTITY="SML Corners Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if ! security find-identity -p codesigning "$KEYCHAIN" | grep -q "$IDENTITY"; then
    echo "Creating signing identity \"$IDENTITY\" in the login keychain"
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    cat > "$TMP/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -config "$TMP/openssl.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
        -name "$IDENTITY" -out "$TMP/identity.p12" -passout pass:corners
    security import "$TMP/identity.p12" -k "$KEYCHAIN" -P corners -T /usr/bin/codesign || true
fi

if codesign --force --sign "$IDENTITY" "$APP" 2>/dev/null; then
    echo "Signed with \"$IDENTITY\""
else
    echo "warning: falling back to ad-hoc signing; Accessibility must be re-granted after each rebuild"
    codesign --force --sign - "$APP"
fi
