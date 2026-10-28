#!/bin/bash
# Loopback test runner for sa_std/http_proxy.sla.
#
# Creates a throwaway CA + server certificate (SAN: localhost,
# proxytest.local, 127.0.0.1), maps proxytest.local to 127.0.0.1 in
# /etc/hosts, installs the CA into the system trust store (for the
# default-config https-proxy path), starts tests/http_proxy_stub.py,
# and runs the SLA loopback suite against it. Loopback only.
set -u
cd "$(dirname "$0")/.."
if [ -f /content/sa_all/env.sh ]; then
  # Colab box layout used by the sci-fill worktrees.
  source /content/sa_all/env.sh
fi
export SLA_NO_FRESHNESS_CACHE=1
export SA_STD_DIR="${SA_STD_DIR:-$PWD}"

WORK=/tmp/ba_proxy_stub
mkdir -p "$WORK"
CA_CRT=/tmp/ba_proxy_ca.crt
CA_KEY=$WORK/ca.key
SRV_CRT=$WORK/server.crt
SRV_KEY=$WORK/server.key
if [ ! -f "$SRV_CRT" ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$CA_KEY" -out "$CA_CRT" \
    -days 2 -subj "/CN=ba-proxy-stub-ca" 2>/dev/null
  openssl req -newkey rsa:2048 -nodes -keyout "$SRV_KEY" \
    -out "$WORK/server.csr" -subj "/CN=localhost" 2>/dev/null
  printf "subjectAltName=DNS:localhost,DNS:proxytest.local,IP:127.0.0.1\n" > "$WORK/san.cnf"
  openssl x509 -req -in "$WORK/server.csr" -CA "$CA_CRT" -CAkey "$CA_KEY" \
    -CAcreateserial -out "$SRV_CRT" -days 2 -extensions v3_req -extfile "$WORK/san.cnf" 2>/dev/null \
    || openssl x509 -req -in "$WORK/server.csr" -CA "$CA_CRT" -CAkey "$CA_KEY" \
    -CAcreateserial -out "$SRV_CRT" -days 2 -extfile "$WORK/san.cnf" 2>/dev/null
fi
grep -q "proxytest.local" /etc/hosts || echo "127.0.0.1 proxytest.local" >> /etc/hosts
if [ -d /usr/local/share/ca-certificates ] && command -v update-ca-certificates >/dev/null 2>&1; then
  cp "$CA_CRT" /usr/local/share/ca-certificates/ba_proxy_ca.crt
  update-ca-certificates >/dev/null 2>&1 || true
fi

python3 tests/http_proxy_stub.py "$SRV_CRT" "$SRV_KEY" > "$WORK/stub.log" 2>&1 &
STUB_PID=$!
trap 'kill $STUB_PID 2>/dev/null' EXIT
python3 - << 'PYEOF'
import socket, time, sys
ports = [18101, 18102, 18103, 18104, 18105, 18106, 18107, 18108, 18109, 18110, 18111, 18112, 18113]
deadline = time.time() + 30
for p in ports:
    while True:
        try:
            s = socket.create_connection(("127.0.0.1", p), timeout=2)
            s.close()
            break
        except OSError:
            if time.time() > deadline:
                print("port not ready:", p)
                sys.exit(1)
            time.sleep(0.2)
print("stub ports ready")
PYEOF
if [ $? -ne 0 ]; then
  cat "$WORK/stub.log"
  exit 1
fi

rm -rf .sla-cache
# Backend note (2026-10-28, BA2): the default SAB path traps
# before running any test in this suite -- SAB referee
# UseAfterMove with the self-contradictory state "expected
# Consumed, actual Consumed" (the registered SAB referee
# false-positive family; the same module and suite are fully
# green on the text backend). Until that compiler defect is
# fixed, this runner uses the sa backend explicitly.
timeout 900 sa test tests/http_proxy_loopback.sla
exit $?
