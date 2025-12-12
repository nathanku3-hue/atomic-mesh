#!/bin/bash
# Usage: ./worker.sh [frontend|backend] [claude|codex]
TYPE=$1
TOOL=$2
ID="${TYPE}_$(date +%s)"

echo "🛡️ Worker $ID ($TYPE) online via $TOOL."

while true; do
  # 1. POLL (Using uvx to run mcp-cli without global install)
  TASK_JSON=$(uvx mcp-cli call pick_task --config-file server_config.json --server atomic-mesh --arg worker_type "$TYPE" --arg worker_id "$ID")
  
  if [[ "$TASK_JSON" == *"NO_WORK"* ]]; then
    sleep 3; continue
  fi

  # 2. PARSE (Minimalist grep/cut extraction)
  TASK_ID=$(echo "$TASK_JSON" | grep -o '"id": [0-9]*' | cut -d: -f2 | tr -d ' ')
  DESC=$(echo "$TASK_JSON" | grep -o '"description": ".*"' | cut -d: -f2- | sed 's/^ "//;s/"$//')
  
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
