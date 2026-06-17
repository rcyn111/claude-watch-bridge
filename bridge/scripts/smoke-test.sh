#!/bin/bash
# smoke-test.sh — minimal end-to-end check that the bridge starts and works.
# Used by `make check`.  Exits 0 on success, non-zero on failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRIDGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMPDATA="$(mktemp -d)"
trap 'rm -rf "$TMPDATA"' EXIT

# Find a free port.
PORT=39990
while lsof -i ":$PORT" &>/dev/null; do PORT=$((PORT+1)); done

echo "==> Smoke test on port $PORT"
echo "    data: $TMPDATA"

# --- Build if needed ------------------------------------------------------
if [ ! -f "$BRIDGE_DIR/dist/index.js" ]; then
  echo "==> Building bridge..."
  (cd "$BRIDGE_DIR" && npm run build) || exit 1
fi

# --- Start bridge ---------------------------------------------------------
NO_CLIENT_GRACE_SECONDS=1 DATA_DIR="$TMPDATA" LOG_FILE="" PORT=$PORT \
  node "$BRIDGE_DIR/dist/index.js" >/dev/null 2>&1 &
BPID=$!
trap 'kill $BPID 2>/dev/null; rm -rf "$TMPDATA"' EXIT

# Wait for it to listen.
for i in $(seq 1 30); do
  if curl -s "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then break; fi
  sleep 0.2
done

fail() { echo "FAIL: $*"; exit 1; }

# --- 1. Health check ------------------------------------------------------
resp=$(curl -sf "http://127.0.0.1:$PORT/health")
echo "  1. Health: $(echo "$resp" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["status"])' 2>/dev/null || echo ok)"

# --- 2. Pairing code ------------------------------------------------------
code=$(curl -sf -X POST "http://127.0.0.1:$PORT/pair" | python3 -c "import sys,json;print(json.load(sys.stdin)['code'])")
echo "  2. Pairing code: $code"

# --- 3. Verify code -------------------------------------------------------
token=$(curl -sf -X POST "http://127.0.0.1:$PORT/pair/verify" \
  -H "Content-Type: application/json" \
  -d "{\"code\":\"$code\"}" | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")
echo "  3. Token: ${token:0:12}..."

# --- 4. Pending list ------------------------------------------------------
curl -sf "http://127.0.0.1:$PORT/pending" -H "Authorization: Bearer $token" >/dev/null
echo "  4. Pending list: ok"

# --- 5. Fast-fail hook (no SSE client, expect 408) -------------------------
# curl -f would exit on non-2xx, so we drop -f and capture the status code.
hook_out=$(mktemp)
http_code=$(curl -s -o "$hook_out" -w "%{http_code}" -X POST \
  "http://127.0.0.1:$PORT/hook/permission-request" \
  -H "Content-Type: application/json" \
  -d '{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"echo ok"},"session_id":"s1"}')
if [ "$http_code" == "408" ]; then
  echo "  5. Hook (no client): 408 fast-fail ✓"
else
  echo "  5. Hook (no client): HTTP $http_code (expected 408)"
  fail "unexpected hook response: $(cat "$hook_out")"
fi
rm -f "$hook_out"

echo ""
echo "✅ All smoke tests passed."
