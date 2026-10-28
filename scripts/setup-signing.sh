#!/bin/zsh
# A separate, persistent identity for this local app. Never opens another
# project's keychain or changes certificate trust settings.
set -euo pipefail
umask 077

TILE_SIGNING_DIR="${TILE_SIGNING_DIR:-$HOME/Library/Application Support/Tile/Signing}"
TILE_KEYCHAIN="$TILE_SIGNING_DIR/Tile.keychain-db"
TILE_PASSWORD_FILE="$TILE_SIGNING_DIR/keychain-password"
TILE_CERTIFICATE="$TILE_SIGNING_DIR/certificate.pem"
mkdir -p "$TILE_SIGNING_DIR"
chmod 700 "$TILE_SIGNING_DIR"

tile_remove_from_search_list() {
  local -a current kept
  local entry
  current=("${(@f)$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//')}")
  for entry in "${current[@]}"; do
    if [[ "$entry" != "$TILE_KEYCHAIN" ]]; then kept+=("$entry"); fi
  done
  if (( ${#kept} != ${#current} )); then
    security list-keychains -d user -s "${kept[@]}"
  fi
}

if [[ ! -e "$TILE_KEYCHAIN" ]]; then
  if [[ -e "$TILE_PASSWORD_FILE" || -e "$TILE_CERTIFICATE" ]]; then
    echo 'Tile signing setup is incomplete; preserve this directory and repair it instead of replacing the identity.' >&2
    exit 1
  fi
  TILE_SIGNING_WORK=$(mktemp -d "$TILE_SIGNING_DIR/setup.XXXXXX")
  trap 'tile_remove_from_search_list; rm -rf "$TILE_SIGNING_WORK"' EXIT
  openssl rand -hex 32 > "$TILE_PASSWORD_FILE"
  TILE_KEYCHAIN_PASSWORD=$(<"$TILE_PASSWORD_FILE")
  cat > "$TILE_SIGNING_WORK/certificate.cnf" <<'CONFIG'
[req]
distinguished_name = subject
x509_extensions = codesign
prompt = no
[subject]
CN = Tile Local Development
[codesign]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CONFIG
  openssl req -new -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$TILE_SIGNING_WORK/certificate.cnf" \
    -keyout "$TILE_SIGNING_WORK/key.pem" -out "$TILE_CERTIFICATE" 2>/dev/null
  openssl pkcs12 -export -inkey "$TILE_SIGNING_WORK/key.pem" -in "$TILE_CERTIFICATE" \
    -name 'Tile Local Development' -out "$TILE_SIGNING_WORK/identity.p12" \
    -passout "file:$TILE_PASSWORD_FILE" -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

  # Remove only our newly added path, preserving other current entries/order.
  security create-keychain -p "$TILE_KEYCHAIN_PASSWORD" "$TILE_KEYCHAIN"
  tile_remove_from_search_list
  security unlock-keychain -p "$TILE_KEYCHAIN_PASSWORD" "$TILE_KEYCHAIN"
  security import "$TILE_SIGNING_WORK/identity.p12" -k "$TILE_KEYCHAIN" \
    -P "$TILE_KEYCHAIN_PASSWORD" -x -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple: -s \
    -k "$TILE_KEYCHAIN_PASSWORD" "$TILE_KEYCHAIN" >/dev/null
  security set-keychain-settings -lut 3600 "$TILE_KEYCHAIN"
fi

if [[ ! -f "$TILE_PASSWORD_FILE" || ! -f "$TILE_CERTIFICATE" ]]; then
  echo 'Tile signing files are missing; the existing identity was not modified.' >&2
  exit 1
fi
TILE_KEYCHAIN_PASSWORD=$(<"$TILE_PASSWORD_FILE")
security unlock-keychain -p "$TILE_KEYCHAIN_PASSWORD" "$TILE_KEYCHAIN"
unset TILE_KEYCHAIN_PASSWORD
echo 'Tile signing identity is ready.'
