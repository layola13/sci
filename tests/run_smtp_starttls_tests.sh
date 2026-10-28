#!/bin/sh
# Run the SMTP STARTTLS loopback tests: generate a throwaway
# self-signed certificate, start tests/smtp_starttls_stub.py on
# 127.0.0.1:25257, run tests/smtp_starttls_loopback.sla against
# it, and stop the stub. Run from the sci repo root with `sa` on
# PATH and SA_PLUGIN_DEV=1.
set -e
cd "$(dirname "$0")/.."
export SA_PLUGIN_DEV=1
export SA_STD_DIR="$PWD/sa_std"
TMPD="$(mktemp -d)"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -subj "/CN=localhost" \
    -keyout "$TMPD/key.pem" -out "$TMPD/cert.pem" >/dev/null 2>&1
python3 tests/smtp_starttls_stub.py 25257 "$TMPD/cert.pem" "$TMPD/key.pem" &
STUB_PID=$!
trap 'kill $STUB_PID 2>/dev/null || true; rm -rf "$TMPD"' EXIT
sleep 1
timeout 300 sa test tests/smtp_starttls_loopback.sla
