#!/bin/bash
# Generate Wazuh single-node TLS certs.
#
# The official wazuh-certs-tool image is not published on Docker Hub, so this
# script reproduces its output with openssl, using the same DNs the tool uses:
#   admin, wazuh.indexer, wazuh.manager, wazuh.dashboard
#   /C=US/L=California/O=Wazuh/OU=Wazuh/CN=<node>
#
# Usage:
#   sh scripts/gen-certs.sh <output-dir>
#
# Output: root-ca.pem (+key, keep it for renewals), root-ca-manager.pem, and
# the four node cert/key pairs. Everything is gitignored.
set -euo pipefail
OUT="${1:-wazuh/config/wazuh_indexer_ssl_certs}"
DAYS=3650

mkdir -p "$OUT"
cd "$OUT"

openssl genrsa -out root-ca.key 2048 2>/dev/null
openssl req -new -x509 -sha256 -key root-ca.key -out root-ca.pem -days "$DAYS" \
  -subj "/C=US/L=California/O=Wazuh/OU=Wazuh/CN=Wazuh" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null

gen_node() {
  local CN="$1" KEY="$2" CERT="$3"
  openssl genrsa -out "$KEY" 2048 2>/dev/null
  openssl req -new -key "$KEY" -out /tmp/${CN}.csr \
    -subj "/C=US/L=California/O=Wazuh/OU=Wazuh/CN=$CN" 2>/dev/null
  openssl x509 -req -sha256 -in /tmp/${CN}.csr -CA root-ca.pem -CAkey root-ca.key \
    -CAcreateserial -out "$CERT" -days "$DAYS" \
    -extfile <(printf "keyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth,clientAuth") 2>/dev/null
  rm -f /tmp/${CN}.csr
}

gen_node admin admin-key.pem admin.pem
gen_node wazuh.indexer wazuh.indexer-key.pem wazuh.indexer.pem
gen_node wazuh.manager wazuh.manager-key.pem wazuh.manager.pem
gen_node wazuh.dashboard wazuh.dashboard-key.pem wazuh.dashboard.pem

cp root-ca.pem root-ca-manager.pem
rm -f root-ca.srl

# Containers read certs as uid 1000 (wazuh/opensearch); Docker Desktop bind
# mounts preserve POSIX perms, so keys generated as root:0600 are unreadable.
chmod 644 ./*.pem ./*-key.pem 2>/dev/null || true
chmod 600 root-ca.key

echo "certificates written to $OUT"
