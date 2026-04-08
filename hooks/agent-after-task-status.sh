#!/usr/bin/env bash
set -euo pipefail
# After task status change: log event to events.db
# Memory capture and index rebuild are handled by agent-post-tool-use.sh
INPUT=$(cat)
TASK_ID=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('task_id',''))")
NEW_STATUS=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('new_status',''))")
AGENT=$(echo "$INPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('agent',''))")

if [ -f ".agents/events.db" ]; then
  if ! sqlite3 .agents/events.db "INSERT INTO events(timestamp,event_type,agent,task_id,detail) VALUES(strftime('%s','now'),'task_status_change','$AGENT','$TASK_ID','Status changed to $NEW_STATUS');" 2>/dev/null; then
    echo "Warning: Failed to log task_status_change event" >&2
  fi
fi

echo '{"status": "ok"}'
