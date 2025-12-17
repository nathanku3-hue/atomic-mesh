#!/bin/bash
# Usage: ./worker.sh [frontend|backend] [claude|codex]
TYPE=$1
TOOL=$2
ID="${TYPE}_$(date +%s)"

echo "🛡️ Worker $ID ($TYPE) online via $TOOL."

# Mirror worker.ps1 role-based lane isolation (avoid role leakage).
blocked_lanes_json="[]"
case "$(echo "$TYPE" | tr '[:upper:]' '[:lower:]')" in
  # Codex/generalist: owns backend/qa/ops by default (leave docs/frontend to Claude worker)
  backend)
    blocked_lanes_json='["frontend","docs"]'
    ;;
  # Claude/creative: owns frontend/docs by default (leave backend/qa/ops to Codex worker)
  frontend)
    blocked_lanes_json='["backend","qa","ops"]'
    ;;
  # Explicit QA worker (if launched): restrict to qa lane only
  qa)
    blocked_lanes_json='["backend","frontend","ops","docs"]'
    ;;
esac

while true; do
  # 1. POLL (Using uvx to run mcp-cli without global install)
  TASK_JSON=$(uvx mcp-cli call pick_task_braided --config-file server_config.json --server atomic-mesh --arg worker_id "$ID" --arg blocked_lanes "$blocked_lanes_json")
  
  if [[ "$TASK_JSON" == *"NO_WORK"* ]]; then
    sleep 3; continue
  fi

  # 2. PARSE (JSON-safe)
  TASK_ID=$(python -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('id',''))" <<< "$TASK_JSON")
  DESC=$(python -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('description',''))" <<< "$TASK_JSON")
  
  echo "⚡ Executing Task $TASK_ID: $DESC"

  # 3. EXECUTE
  PROMPT="You are a logic engine. TASK_ID: $TASK_ID. INSTRUCTION: $DESC.
  PROTOCOL: 1. Perform task. 2. Call 'complete_task(task_id=$TASK_ID, output=summary)'. 
  If error, call 'complete_task' with success=False."

  if [ "$TOOL" == "claude" ]; then
    claude --print "$PROMPT"
  elif [ "$TOOL" == "codex" ]; then
    codex exec "$PROMPT"
  fi
done
