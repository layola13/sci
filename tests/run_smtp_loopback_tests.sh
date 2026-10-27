#!/bin/sh
# Run the SMTP loopback client tests: start the fixed-behaviour
# stub (tests/smtp_loopback_stub.py) on 127.0.0.1:25256, run
# tests/smtp_client_loopback.sla against it, then verify the DATA
# block the stub captured (CRLF normalisation, dot-stuffing, the
# terminating "." line) and stop the stub.
# Run from the sci repo root with `sa` on PATH and SA_PLUGIN_DEV=1.
set -e
cd "$(dirname "$0")/.."
export SA_PLUGIN_DEV=1
export SA_STD_DIR="$PWD/sa_std"
CAPTURE="$(mktemp)"
python3 tests/smtp_loopback_stub.py 25256 "$CAPTURE" &
STUB_PID=$!
trap 'kill $STUB_PID 2>/dev/null || true' EXIT
sleep 1
timeout 300 sa test tests/smtp_client_loopback.sla
python3 - "$CAPTURE" <<'PYEOF'
import sys
data = open(sys.argv[1], "rb").read()
assert b"Subject: hi\r\n" in data, "subject line was not CRLF-normalised"
assert b"\r\n..dotted\r\n" in data, "leading dot was not stuffed"
assert data.endswith(b"last\r\n.\r\n"), "payload lacks CRLF + terminator ending"
print("capture assertions ok")
PYEOF
