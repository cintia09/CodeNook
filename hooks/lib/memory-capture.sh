#!/usr/bin/env bash
# Module: Memory Capture — detects status transitions and triggers memory snapshot
# Sourced by agent-post-tool-use.sh. Expects: TASK_BOARD_CACHE, SNAPSHOT, AGENTS_DIR, ACTIVE_AGENT, TIMESTAMP, EVENTS_DB, CWD, sql_escape()

run_memory_capture() {
  if [ -z "$TASK_BOARD_CACHE" ] || [ ! -f "$SNAPSHOT" ]; then
    return 0
  fi

  # Pre-load old statuses from snapshot (1 jq call)
  local SNAPSHOT_STATUSES
  SNAPSHOT_STATUSES=$(jq -r '.tasks[] | "\(.id)\t\(.status)"' "$SNAPSHOT" 2>/dev/null || true)

  # Extract id, status, title in ONE jq call
  while IFS=$'\t' read -r TASK_ID NEW_STATUS TITLE; do
    [ -z "$TASK_ID" ] || [ -z "$NEW_STATUS" ] && continue
    OLD_STATUS=$(echo "$SNAPSHOT_STATUSES" | awk -F'\t' -v tid="$TASK_ID" '$1==tid{print $2; exit}')

    # Only trigger on actual transitions (skip FSM-violated tasks)
    if [ -n "$OLD_STATUS" ] && [ "$OLD_STATUS" != "$NEW_STATUS" ]; then
      # Skip if FSM validation flagged this task as illegal
      if echo " $FSM_VIOLATED_TASKS " | grep -qF " $TASK_ID "; then
        continue
      fi

      TASK_ID_ESC=$(sql_escape "$TASK_ID")
      OLD_STATUS_ESC=$(sql_escape "$OLD_STATUS")
      NEW_STATUS_ESC=$(sql_escape "$NEW_STATUS")

      sqlite3 "$EVENTS_DB" "INSERT INTO events (timestamp, event_type, agent, task_id, detail) VALUES ($TIMESTAMP, 'memory_capture_needed', '$ACTIVE_AGENT_ESC', '$TASK_ID_ESC', '{\"from_status\":\"$OLD_STATUS_ESC\",\"to_status\":\"$NEW_STATUS_ESC\"}');" 2>/dev/null || true

      # Create memory directory
      MEMORY_DIR="$AGENTS_DIR/memory"
      if ! mkdir -p "$MEMORY_DIR" 2>/dev/null; then
        echo "⚠️ [Memory] Failed to create $MEMORY_DIR" && continue
      fi

      # Initialize memory file
      MEMORY_FILE="$MEMORY_DIR/${TASK_ID}-memory.json"
      if [ ! -f "$MEMORY_FILE" ]; then
        NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        jq -n --arg tid "$TASK_ID" --arg title "$TITLE" --arg ts "$NOW_ISO" \
          '{task_id:$tid,title:$title,version:1,created_at:$ts,last_updated:$ts,stages:{}}' \
          > "$MEMORY_FILE"
      fi

      echo "🧠 [Auto-Capture] Task $TASK_ID status changed: $OLD_STATUS → $NEW_STATUS. Please save memory snapshot to .agents/memory/${TASK_ID}-memory.json (summary, decisions, files_modified, handoff_notes)."

      # Trigger memory index rebuild on acceptance
      if [ "$NEW_STATUS" = "accepted" ]; then
        SCRIPT_PATH=""
        [ -f "$AGENTS_DIR/scripts/memory-index.sh" ] && SCRIPT_PATH="$AGENTS_DIR/scripts/memory-index.sh"
        [ -z "$SCRIPT_PATH" ] && [ -f "$CWD/scripts/memory-index.sh" ] && SCRIPT_PATH="$CWD/scripts/memory-index.sh"
        [ -n "$SCRIPT_PATH" ] && bash "$SCRIPT_PATH" 2>/dev/null || true
      fi
    fi
  done < <(echo "$TASK_BOARD_CACHE" | jq -r '.tasks[] | [.id // "", .status // "", .title // ""] | @tsv' 2>/dev/null)
}
