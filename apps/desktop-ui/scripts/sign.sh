#!/usr/bin/env bash
# Signs an app bundle with a local certificate, creating it on first use: scripts/sign.sh <app> <bundle identifier>
# macOS ties the Accessibility permission to an app's signature. An ad-hoc signature changes with every build,
# so the switch in System Settings stops applying after a rebuild. Signing each build with this one certificate
# keeps the permission. The certificate is self-signed, lives in its own keychain, and never leaves this Mac.
set -euo pipefail
app="$1"
identifier="$2"

name="Nora Local Signing"
keychain="$HOME/Library/Keychains/nora-local-signing.keychain-db"
# Guards nothing secret: the keychain only holds this throwaway certificate.
password="nora-local-signing"

searched=()
while IFS= read -r line; do
  searched+=("$(echo "$line" | sed -e 's/^ *"//' -e 's/"$//')")
done < <(security list-keychains -d user)
# codesign only finds identities in the keychain search list, so the signing keychain joins it just while signing.
# Left there, it would be locked after a restart and other apps could ask for its password.
trap 'security list-keychains -d user -s "${searched[@]}"' EXIT

if [[ ! -f "$keychain" ]]; then
  work="$(mktemp -d)"
  trap 'rm -rf "$work"; security list-keychains -d user -s "${searched[@]}"' EXIT
  cat > "$work/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$work/cert.conf" \
    -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
  openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -out "$work/identity.p12" -passout pass:"$password"
  security create-keychain -p "$password" "$keychain"
  security set-keychain-settings "$keychain"
  security unlock-keychain -p "$password" "$keychain"
  security import "$work/identity.p12" -k "$keychain" -P "$password" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null
fi

security unlock-keychain -p "$password" "$keychain"
security list-keychains -d user -s "${searched[@]}" "$keychain"
certificate="$(security find-certificate -c "$name" -Z "$keychain" | awk '/SHA-1/ { print $NF }')"
codesign --force --sign "$certificate" --identifier "$identifier" "$app"
