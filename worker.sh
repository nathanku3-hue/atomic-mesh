#!/bin/bash
# Usage: ./worker.sh [frontend|backend] [claude|codex]
TYPE=$1
TOOL=$2
ID="${TYPE}_$(date +%s)"

echo "🛡️ Worker $ID ($TYPE) online via $TOOL."

# Resolve repo root (where mesh_server.py and mcp_client.py live)
MESH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_DIR="$(pwd)"
LOG_DIR="$CURRENT_DIR/logs"
LOG_FILE="$LOG_DIR/$(date +%F)-$TYPE.log"
COMBINED_LOG="$LOG_DIR/combined.log"
MCP_CLIENT="$MESH_ROOT/mcp_client.py"

mkdir -p "$LOG_DIR"
touch "$COMBINED_LOG"

# v21.0: Ensure worker uses same DB as control panel
DB_FILE="$MESH_ROOT/mesh.db"
if [ -z "${ATOMIC_MESH_DB:-}" ]; then
  export ATOMIC_MESH_DB="$DB_FILE"
fi
echo "  DB: $ATOMIC_MESH_DB"

# Mirror worker.ps1 role-based lane isolation (avoid role leakage).
blocked_lanes_json="[]"
allowed_lanes_json='["backend","frontend","qa","ops","docs"]'
case "$(echo "$TYPE" | tr '[:upper:]' '[:lower:]')" in
  # Codex/generalist: owns backend/qa/ops by default (leave docs/frontend to Claude worker)
  backend)
    blocked_lanes_json='["frontend","docs"]'
    allowed_lanes_json='["backend","qa","ops"]'
    ;;
  # Claude/creative: owns frontend/docs by default (leave backend/qa/ops to Codex worker)
  frontend)
    blocked_lanes_json='["backend","qa","ops"]'
    allowed_lanes_json='["frontend","docs"]'
    ;;
  # Explicit QA worker (if launched): restrict to qa lane only
  qa)
    blocked_lanes_json='["backend","frontend","ops","docs"]'
    allowed_lanes_json='["qa"]'
    ;;
esac

backoff=1
max_backoff=10
last_heartbeat=0
heartbeat_interval="${MESH_WORKER_HEARTBEAT_SECS:-30}"
renew_interval="${MESH_LEASE_RENEW_SECS:-30}"
if ! [[ "$heartbeat_interval" =~ ^[0-9]+$ ]]; then heartbeat_interval=30; fi
if ! [[ "$renew_interval" =~ ^[0-9]+$ ]]; then renew_interval=30; fi
if [ "$heartbeat_interval" -lt 5 ]; then heartbeat_interval=5; fi
if [ "$renew_interval" -lt 5 ]; then renew_interval=5; fi

while true; do
  # 0. HEARTBEAT (throttled; failure is non-fatal)
  now=$(date +%s)
  if [ $((now - last_heartbeat)) -ge "$heartbeat_interval" ]; then
    hb_json="{\"worker_id\":\"$ID\",\"worker_type\":\"$TYPE\",\"allowed_lanes\":$allowed_lanes_json,\"task_ids\":[]}"
    (cd "$MESH_ROOT" && python "$MCP_CLIENT" worker_heartbeat "$hb_json" >/dev/null 2>&1) || true
    last_heartbeat=$now
  fi

  # 1. POLL
  args_json="{\"worker_id\":\"$ID\",\"worker_type\":\"$TYPE\",\"blocked_lanes\":$blocked_lanes_json}"
  TASK_JSON=$(cd "$MESH_ROOT" && python "$MCP_CLIENT" pick_task_braided "$args_json" 2>/dev/null || true)

  if [[ "$TASK_JSON" == *"NO_WORK"* ]]; then
    jitter=$((RANDOM % 3))
    sleep $((backoff + jitter))
    if [ "$backoff" -lt "$max_backoff" ]; then
      backoff=$((backoff * 2))
      if [ "$backoff" -gt "$max_backoff" ]; then
        backoff=$max_backoff
      fi
    fi
    continue
  fi
  backoff=1

  # 2. PARSE (JSON-safe)
  TASK_ID=$(python -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('id',''))" <<< "$TASK_JSON")
  DESC=$(python -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('description',''))" <<< "$TASK_JSON")
  LANE=$(python -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('lane',''))" <<< "$TASK_JSON")
  LEASE_ID=$(python -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('lease_id',''))" <<< "$TASK_JSON")

  if [ -z "$TASK_ID" ] || [ -z "$LEASE_ID" ]; then
    jitter=$((RANDOM % 3))
    sleep $((backoff + jitter))
    if [ "$backoff" -lt "$max_backoff" ]; then
      backoff=$((backoff * 2))
      if [ "$backoff" -gt "$max_backoff" ]; then
        backoff=$max_backoff
      fi
    fi
    continue
  fi
  
  echo "⚡ [$TYPE/$LANE] Task $TASK_ID: $DESC"
  echo "[$(date +%T)] ⚡ [$TYPE/$LANE] Task $TASK_ID : ${DESC:0:80}" >> "$LOG_FILE" || true
  echo "[$(date +%T)] ⚡ [$TYPE/$LANE] Task $TASK_ID : ${DESC:0:80}" >> "$COMBINED_LOG" || true

  # 2b. HEARTBEAT: mark task as active
  hb_task_json="{\"worker_id\":\"$ID\",\"worker_type\":\"$TYPE\",\"allowed_lanes\":$allowed_lanes_json,\"task_ids\":[$TASK_ID]}"
  (cd "$MESH_ROOT" && python "$MCP_CLIENT" worker_heartbeat "$hb_task_json" >/dev/null 2>&1) || true
  last_heartbeat=$(date +%s)

  # 3. EXECUTE
  PROMPT="You are a logic engine.
TASK_ID: $TASK_ID
INSTRUCTION: $DESC

CONTEXT PROTOCOL:
1. ANALYZE: If the instruction mentions specific files, READ THEM first.
2. EXECUTE: Perform the task.
3. REPORT: Print a 1-sentence summary of what you changed.

Do not chatter. Just do the work."

  start_ts=$(date +%s)
  renew_pid=""

  # v21.1: Background lease renewal + heartbeat during long executions
  (
    while true; do
      sleep "$renew_interval"
      renew_json="{\"task_id\":$TASK_ID,\"worker_id\":\"$ID\",\"lease_id\":\"$LEASE_ID\"}"
      hb_json="{\"worker_id\":\"$ID\",\"worker_type\":\"$TYPE\",\"allowed_lanes\":$allowed_lanes_json,\"task_ids\":[$TASK_ID]}"
      (cd "$MESH_ROOT" && python "$MCP_CLIENT" renew_task_lease "$renew_json" >/dev/null 2>&1) || true
      (cd "$MESH_ROOT" && python "$MCP_CLIENT" worker_heartbeat "$hb_json" >/dev/null 2>&1) || true
    done
  ) &
  renew_pid=$!

  if [ "$TOOL" == "claude" ]; then
    claude --print "$PROMPT" 2>&1 | tee -a "$LOG_FILE"
    exit_code=${PIPESTATUS[0]}
  elif [ "$TOOL" == "codex" ]; then
    codex exec "$PROMPT" 2>&1 | tee -a "$LOG_FILE"
    exit_code=${PIPESTATUS[0]}
  else
    echo "Unknown tool: $TOOL" | tee -a "$LOG_FILE"
    exit_code=2
  fi

  end_ts=$(date +%s)
  duration=$((end_ts - start_ts))

  # Stop renewal loop
  if [ -n "$renew_pid" ]; then
    kill "$renew_pid" >/dev/null 2>&1 || true
    wait "$renew_pid" >/dev/null 2>&1 || true
  fi

  # 4. COMPLETE (server-side claim token required)
  if [ "$exit_code" -eq 0 ]; then
    complete_json=$(python - <<PY
import json
print(json.dumps({
  "task_id": int("$TASK_ID"),
  "output": "Done in ${duration}s",
  "success": True,
  "worker_id": "$ID",
  "lease_id": "$LEASE_ID",
}))
PY
)
    (cd "$MESH_ROOT" && python "$MCP_CLIENT" complete_task "$complete_json" >/dev/null 2>&1) || true
  else
    complete_json=$(python - <<PY
import json
print(json.dumps({
  "task_id": int("$TASK_ID"),
  "output": "Exit $exit_code",
  "success": False,
  "worker_id": "$ID",
  "lease_id": "$LEASE_ID",
}))
PY
)
    (cd "$MESH_ROOT" && python "$MCP_CLIENT" complete_task "$complete_json" >/dev/null 2>&1) || true
  fi

  # 5. HEARTBEAT: clear active task list
  hb_idle_json="{\"worker_id\":\"$ID\",\"worker_type\":\"$TYPE\",\"allowed_lanes\":$allowed_lanes_json,\"task_ids\":[]}"
  (cd "$MESH_ROOT" && python "$MCP_CLIENT" worker_heartbeat "$hb_idle_json" >/dev/null 2>&1) || true
  last_heartbeat=$(date +%s)
done
