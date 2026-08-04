#!/usr/bin/env bash
# Create the local self-signed code-signing identity WriterFlow builds are signed with.
#
# Why this exists (see also RELEASE.md "Signing identity"):
#
# macOS Keychain items live in the file-based login keychain, where access is
# gated by an ACL naming the calling app's code-signing identity. An ad-hoc
# signature has no stable identity — its designated requirement is a bare
# cdhash that changes with every build — so "Always Allow" never survives a
# rebuild or an app update, and users get re-prompted for their password
# indefinitely. Signing with a certificate instead makes the designated
# requirement `certificate leaf H"..."`, which is stable across rebuilds.
#
# This deliberately does NOT require an Apple Developer account (ADR-0010).
# It is not a Developer ID certificate and does not change the Gatekeeper
# story: users still approve WriterFlow manually on first launch.
#
# Idempotent — safe to re-run; it exits early if the identity already exists.
set -euo pipefail

CERT_NAME="${WRITERFLOW_SIGNING_IDENTITY:-WriterFlow Local Signing}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
VALIDITY_DAYS=3650

if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "▸ signing identity '${CERT_NAME}' already exists"
    security find-identity -v -p codesigning "$KEYCHAIN" | grep "$CERT_NAME" || true
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "▸ generating a self-signed code-signing certificate: ${CERT_NAME}"

cat > "$TMP/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions    = v3_codesign
prompt             = no

[ dn ]
CN = ${CERT_NAME}

[ v3_codesign ]
basicConstraints       = critical,CA:FALSE
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
subjectKeyIdentifier   = hash
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days "$VALIDITY_DAYS" -config "$TMP/cert.cnf" 2>/dev/null

# macOS cannot import OpenSSL 3.x's default PKCS#12 encryption, and rejects an
# empty passphrase outright — both fail with "MAC verification failed". Hence
# -legacy plus a throwaway password that never leaves this script.
P12_PASS="writerflow-import-$$"
openssl pkcs12 -export -legacy \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/identity.p12" -passout "pass:${P12_PASS}" 2>/dev/null \
    || openssl pkcs12 -export \
        -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
        -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
        -out "$TMP/identity.p12" -passout "pass:${P12_PASS}"

# -T /usr/bin/codesign puts codesign on the private key's ACL so signing does
# not pop a Keychain prompt on every build.
echo "▸ importing into the login keychain"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12_PASS" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null

# A self-signed certificate is only usable as a codesigning identity once it is
# trusted for that purpose. This is a user-domain trust setting, so it does not
# need sudo, but macOS will ask for confirmation.
echo "▸ marking the certificate as trusted for code signing (macOS will ask for confirmation)"
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

# Without an explicit partition list macOS still prompts on first use even
# though -T set the ACL. Needs the login keychain password.
echo "▸ authorising codesign to use the key (enter your login keychain password if prompted)"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "" "$KEYCHAIN" >/dev/null 2>&1 \
    || security set-key-partition-list -S apple-tool:,apple:,codesign: -s "$KEYCHAIN" >/dev/null \
    || echo "  (skipped — codesign may prompt once; choose 'Always Allow')"

echo
echo "▸ done. Available code-signing identities:"
security find-identity -v -p codesigning "$KEYCHAIN"
echo
echo "Builds will pick this up automatically. Rebuild and reinstall with:"
echo "  make install"
