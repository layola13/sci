#!/usr/bin/env bash
# 10-Agent local concurrency + incremental verdict benchmark for sa daemon.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SA="${SA_BIN:-$ROOT/zig-out/bin/sa}"
SOCK="${SA_BENCH_SOCK:-/tmp/sa-agent-bench-$$.sock}"
LOG="${SA_BENCH_LOG:-/tmp/sa-agent-bench-$$.log}"
OUT="${SA_BENCH_OUT:-$ROOT/tools/agent_bench_out.json}"
FILE="${SA_BENCH_FILE:-$ROOT/demos/rosetta/01_hello_world/main.sa}"
AGENTS="${SA_BENCH_AGENTS:-10}"
ROUNDS="${SA_BENCH_ROUNDS:-3}"

if [[ ! -x "$SA" ]]; then
  echo "missing sa binary: $SA" >&2
  exit 1
fi

cleanup() {
  if [[ -f /tmp/sa-agent-bench-$$.pid ]]; then
    kill "$(cat /tmp/sa-agent-bench-$$.pid)" 2>/dev/null || true
  fi
  rm -f "$SOCK" /tmp/sa-agent-bench-$$.pid
}
trap cleanup EXIT

rm -f "$SOCK"
"$SA" daemon --socket "$SOCK" --max-workers 8 --per-agent-limit 2 >"$LOG" 2>&1 &
echo $! >/tmp/sa-agent-bench-$$.pid
for i in $(seq 1 50); do
  [[ -S "$SOCK" ]] && break
  sleep 0.1
done
[[ -S "$SOCK" ]] || { echo "daemon failed to start"; cat "$LOG"; exit 1; }

export SA_DAEMON_SOCKET="$SOCK"

# cold single check
start=$(date +%s%3N)
"$SA" check "$FILE" --json >/tmp/sa-bench-cold.json
cold_ms=$(( $(date +%s%3N) - start ))
cold_hit=$(python3 -c 'import json;print(json.load(open("/tmp/sa-bench-cold.json")).get("metrics",{}).get("cache",{}).get("hit",False))')

# warm single check
start=$(date +%s%3N)
"$SA" check "$FILE" --json >/tmp/sa-bench-warm.json
warm_ms=$(( $(date +%s%3N) - start ))
warm_hit=$(python3 -c 'import json;print(json.load(open("/tmp/sa-bench-warm.json")).get("metrics",{}).get("cache",{}).get("hit",False))')

# concurrent agents
start=$(date +%s%3N)
pids=()
for a in $(seq 1 "$AGENTS"); do
  (
    export SA_AGENT_ID="agent-$a"
    for r in $(seq 1 "$ROUNDS"); do
      export SA_AGENT_GENERATION="$r"
      "$SA" check "$FILE" --json >/dev/null
    done
  ) &
  pids+=($!)
done
fail=0
for p in "${pids[@]}"; do
  if ! wait "$p"; then fail=1; fi
done
wall_ms=$(( $(date +%s%3N) - start ))
jobs=$(( AGENTS * ROUNDS ))
# jobs/sec * 1000 approx
jps=$(python3 - <<PY
print(round($jobs / max($wall_ms,1) * 1000, 3))
PY
)

# cancel path
python3 - <<PY
import socket, json, os
sock=os.environ['SA_DAEMON_SOCKET']
def send(o):
    s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
    s.connect(sock)
    s.sendall((json.dumps(o)+'\n').encode())
    d=b''
    while True:
        c=s.recv(65536)
        if not c: break
        d+=c
    s.close(); return d
send({"argv":["sa","version"],"agent_id":"cancel-demo","generation":9})
body=send({"argv":["sa","version"],"agent_id":"cancel-demo","generation":1})
assert b'canceled' in body, body
ping=send({"op":"ping"})
open('/tmp/sa-bench-ping.json','wb').write(ping.split(b'\n')[0])
print('cancel-ok')
PY

python3 - <<PY
import json
ping=json.loads(open('/tmp/sa-bench-ping.json').read())
metrics=ping.get('metrics',{})
out={
  "cold_ms": $cold_ms,
  "warm_ms": $warm_ms,
  "cold_hit": bool($cold_hit) if isinstance($cold_hit, bool) else str($cold_hit).lower()=='true',
  "warm_hit": bool($warm_hit) if isinstance($warm_hit, bool) else str($warm_hit).lower()=='true',
  "agents": $AGENTS,
  "rounds": $ROUNDS,
  "jobs": $jobs,
  "concurrent_wall_ms": $wall_ms,
  "concurrent_jobs_per_sec": $jps,
  "daemon_metrics": metrics,
  "fail": $fail,
}
# gates
assert out["warm_hit"] is True or str(out["warm_hit"]).lower()=="true", out
assert out["warm_ms"] <= max(out["cold_ms"], 1), out
assert out["fail"] == 0, out
assert metrics.get("verdict_hits", 0) >= 1, out
open("$OUT","w").write(json.dumps(out, indent=2)+"\n")
print(json.dumps(out, indent=2))
print("AGENT_BENCH_OK")
PY
