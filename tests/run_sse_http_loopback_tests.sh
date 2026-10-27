#!/bin/sh
# Run the SSE-over-HTTP composition test: start the one-shot HTTP
# stub (tests/sse_http_stub.py) on 127.0.0.1:18099, run
# tests/sse_http_loopback.sla against it, then stop the stub.
# Run from the sci repo root with `sa` on PATH and SA_PLUGIN_DEV=1.
set -e
cd "$(dirname "$0")/.."
export SA_PLUGIN_DEV=1
export SA_STD_DIR="$PWD/sa_std"
python3 tests/sse_http_stub.py 18099 &
STUB_PID=$!
trap 'kill $STUB_PID 2>/dev/null || true' EXIT
sleep 1
timeout 300 sa test tests/sse_http_loopback.sla
