#!/usr/bin/env bash
# Generates a throwaway mTLS lab: a dev CA (name constrained to localhost and this
# machine's LAN IP), a server cert for the proxy, and client identities as .p12 files.
# Output goes to Scripts/mtls/out (gitignored). Pass the force flag to regenerate.
set -euo pipefail

cd "$(dirname "$0")"
OUT="${OUT:-out}"
DAYS="${DAYS:-397}"
P12_PASSWORD="${P12_PASSWORD:-nextexplorer}"
LAN_IP="${LAN_IP:-$(ipconfig getifaddr en0 2>/dev/null || true)}"
# Space separated extra IPs the server cert must cover, such as a LAN gateway host.
EXTRA_IPS="${EXTRA_IPS:-}"

if [[ -d "$OUT" && "${1:-}" != "--force" ]]; then
  echo "$OUT already exists. Use --force to regenerate." >&2
  exit 1
fi
rm -rf "$OUT"
mkdir -p "$OUT"
cd "$OUT"

SAN="DNS:localhost,IP:127.0.0.1"
CONSTRAINTS="permitted;DNS:localhost,permitted;IP:127.0.0.1/255.255.255.255"
if [[ -n "$LAN_IP" && "$LAN_IP" != "none" ]]; then
  SAN="$SAN,IP:$LAN_IP"
  CONSTRAINTS="$CONSTRAINTS,permitted;IP:$LAN_IP/255.255.255.255"
fi
for ip in $EXTRA_IPS; do
  SAN="$SAN,IP:$ip"
  CONSTRAINTS="$CONSTRAINTS,permitted;IP:$ip/255.255.255.255"
done

cat > ca.cnf <<CNF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = NextExplorer mTLS Dev CA
O = NextExplorer Dev
[ext]
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
nameConstraints = critical,$CONSTRAINTS
CNF

openssl req -x509 -new -newkey rsa:2048 -nodes -sha256 -days "$DAYS" \
  -keyout ca.key -out ca.pem -config ca.cnf -extensions ext 2>/dev/null

issue() {
  local name="$1" cn="$2" eku="$3" san="$4" days="$5"
  cat > "$name.ext" <<CNF
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = $eku
authorityKeyIdentifier = keyid
${san:+subjectAltName = $san}
CNF
  openssl req -new -newkey rsa:2048 -nodes -keyout "$name.key" -out "$name.csr" \
    -subj "/CN=$cn/O=NextExplorer Dev" 2>/dev/null
  openssl x509 -req -in "$name.csr" -CA ca.pem -CAkey ca.key -CAcreateserial \
    -out "$name.pem" -days "$days" -sha256 -extfile "$name.ext" 2>/dev/null
  rm -f "$name.csr" "$name.ext"
}

issue server localhost serverAuth "$SAN" "$DAYS"
issue client "Dev Client" clientAuth "" "$DAYS"

# A second CA the proxy does not trust, to exercise the "certificate rejected" path.
openssl req -x509 -new -newkey rsa:2048 -nodes -sha256 -days "$DAYS" \
  -keyout rogue-ca.key -out rogue-ca.pem -subj "/CN=Rogue CA" \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign" 2>/dev/null
openssl req -new -newkey rsa:2048 -nodes -keyout rogue-client.key -out rogue-client.csr \
  -subj "/CN=Rogue Client" 2>/dev/null
printf 'extendedKeyUsage = clientAuth\n' > rogue.ext
openssl x509 -req -in rogue-client.csr -CA rogue-ca.pem -CAkey rogue-ca.key -CAcreateserial \
  -out rogue-client.pem -days "$DAYS" -sha256 -extfile rogue.ext 2>/dev/null
rm -f rogue-client.csr rogue.ext

# Modern PKCS#12 (AES + PBKDF2), the OpenSSL 3+ default, and the legacy 3DES flavor
# older tools still produce, so both import paths get tested.
openssl pkcs12 -export -inkey client.key -in client.pem -certfile ca.pem \
  -name "Dev Client" -out client.p12 -passout "pass:$P12_PASSWORD"
openssl pkcs12 -export -legacy -inkey client.key -in client.pem -certfile ca.pem \
  -name "Dev Client (legacy)" -out client-legacy.p12 -passout "pass:$P12_PASSWORD" 2>/dev/null || true
openssl pkcs12 -export -inkey server.key -in server.pem -certfile ca.pem \
  -name "Dev Server" -out server.p12 -passout "pass:$P12_PASSWORD"
openssl x509 -in ca.pem -outform der -out ca.der
openssl pkcs12 -export -inkey rogue-client.key -in rogue-client.pem \
  -name "Rogue Client" -out rogue-client.p12 -passout "pass:$P12_PASSWORD"

chmod 600 ./*.key ./*.p12
echo "Generated in $(pwd)"
echo "  CA:            ca.pem (trust this on the simulator / Mac)"
echo "  Server cert:   server.pem  SAN: $SAN"
echo "  Client .p12:   client.p12, client-legacy.p12, rogue-client.p12 (password: $P12_PASSWORD)"
