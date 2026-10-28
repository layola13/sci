#!/bin/sh
# Run the Redis client loopback tests: start two throwaway
# redis-server instances (127.0.0.1:6390 without auth and
# 127.0.0.1:6391 with requirepass sla-test-pass), seed one key
# through redis-cli, run tests/redis_client_loopback.sla against
# them, then verify with redis-cli that a key written by the SLA
# client reads back exactly. Run from the sci repo root with `sa`
# on PATH and SA_PLUGIN_DEV=1. redis-server / redis-cli must be on
# PATH. SLA_NO_FRESHNESS_CACHE=1 keeps std edits visible between
# iterations (the plugin freshness cache is not keyed on compiler
# behavior; the same rule the SLA corpus uses).
set -e
cd "$(dirname "$0")/.."
export SA_PLUGIN_DEV=1
export SLA_NO_FRESHNESS_CACHE=1
PORT=6390
APORT=6391
redis-server --port $PORT --bind 127.0.0.1 --protected-mode no \
    --save '' --appendonly no --daemonize no \
    --dir /tmp --logfile /tmp/redis_loopback_$PORT.log &
PID1=$!
redis-server --port $APORT --bind 127.0.0.1 --protected-mode no \
    --requirepass sla-test-pass \
    --save '' --appendonly no --daemonize no \
    --dir /tmp --logfile /tmp/redis_loopback_$APORT.log &
PID2=$!
trap 'kill $PID1 $PID2 2>/dev/null || true' EXIT
# Wait for both instances to accept commands.
i=0
while [ $i -lt 50 ]; do
    if redis-cli -p $PORT ping 2>/dev/null | grep -q PONG \
        && redis-cli -p $APORT -a sla-test-pass ping 2>/dev/null | grep -q PONG; then
        break
    fi
    i=$((i + 1))
    sleep 0.2
done
redis-cli -p $PORT ping | grep -q PONG
redis-cli -p $APORT -a sla-test-pass ping 2>/dev/null | grep -q PONG
# Cross-check seed: the SLA suite must read this exact value back.
redis-cli -p $PORT set sla:seed written-by-redis-cli > /dev/null
timeout 600 sa test tests/redis_client_loopback.sla
# Cross-check in the other direction: what the SLA client wrote,
# the reference client must read back exactly.
GOT=$(redis-cli -p $PORT get sla:probe)
if [ "$GOT" != "written-by-sla" ]; then
    echo "redis-cli cross-check failed: sla:probe = '$GOT'" >&2
    exit 1
fi
echo "redis loopback tests + redis-cli cross-checks passed"
