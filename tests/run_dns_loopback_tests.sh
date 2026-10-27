#!/bin/sh
# Run the DNS loopback client tests: start the fixed-response UDP
# stub (tests/dns_loopback_stub.py) on 127.0.0.1:5399, run
# tests/dns_client_loopback.sla against it, then stop the stub.
# Run from the sci repo root with `sa` on PATH and SA_PLUGIN_DEV=1.
set -e
cd "$(dirname "$0")/.."
python3 tests/dns_loopback_stub.py 5399 &
STUB_PID=$!
trap 'kill $STUB_PID 2>/dev/null || true' EXIT
sleep 1
timeout 300 sa test tests/dns_client_loopback.sla
