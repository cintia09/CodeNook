#!/usr/bin/env bash
set -euo pipefail
# Multi-Agent Framework: Staleness Detection
# Checks for tasks and agents inactive beyond threshold.
# Called from session-start hook or standalone.

AGENTS_DIR="${1:-.agents}"
THRESHOLD_HOURS="${2:-24}"

[ -d "$AGENTS_DIR/runtime" ] || exit 0

# Portable ISO-to-epoch converter (macOS → Linux → perl → python3)
iso_to_epoch() {
  local ts="$1"
  date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || \
  date -d "$ts" +%s 2>/dev/null || \
  perl -e "use Time::Piece; print Time::Piece->strptime('$ts','%Y-%m-%dT%H:%M:%SZ')->epoch" 2>/dev/null || \
  echo 0
}

THRESHOLD_SEC=$((THRESHOLD_HOURS * 3600))
NOW_SEC=$(date +%s)
FOUND_STALE=0

# Check agent staleness
for state_file in "$AGENTS_DIR"/runtime/*/state.json; do
  [ -f "$state_file" ] || continue
  AGENT=$(jq -r '.agent' "$state_file" 2>/dev/null)
  STATUS=$(jq -r '.status' "$state_file" 2>/dev/null)
  LAST=$(jq -r '.last_activity' "$state_file" 2>/dev/null)

  [ "$STATUS" = "idle" ] && continue
  [ -z "$LAST" ] || [ "$LAST" = "null" ] && continue

  # Convert ISO to epoch (macOS + Linux + python3 fallback)
  LAST_SEC=$(iso_to_epoch "$LAST")
  DIFF=$((NOW_SEC - LAST_SEC))

  if [ "$DIFF" -gt "$THRESHOLD_SEC" ]; then
    HOURS=$((DIFF / 3600))
    TASK=$(jq -r '.current_task // "—"' "$state_file" 2>/dev/null)
    echo "⚠️  Agent $AGENT: busy for ${HOURS}h (task: $TASK)"
    FOUND_STALE=1
  fi
done

# Check task staleness
if [ -f "$AGENTS_DIR/task-board.json" ]; then
  while IFS='|' read -r TID TSTATUS TUPDATED TTITLE; do
    [ -z "$TUPDATED" ] || [ "$TUPDATED" = "null" ] && continue

    TASK_SEC=$(iso_to_epoch "$TUPDATED")
    DIFF=$((NOW_SEC - TASK_SEC))

    if [ "$DIFF" -gt "$THRESHOLD_SEC" ]; then
      HOURS=$((DIFF / 3600))
      echo "⚠️  Task ${TID} (${TSTATUS}): no activity for ${HOURS}h — ${TTITLE}"
      FOUND_STALE=1
    fi
  done < <(jq -r '.tasks[] | select(.status != "accepted" and .status != "blocked") | "\(.id)|\(.status)|\(.updated_at // .created_at)|\(.title)"' \
    "$AGENTS_DIR/task-board.json" 2>/dev/null)
fi

# Check for orphan blocked tasks (blocked > 48h with no activity)
ORPHAN_HOURS=48
ORPHAN_SEC=$((ORPHAN_HOURS * 3600))
if [ -f "$AGENTS_DIR/task-board.json" ]; then
  while IFS='|' read -r TID TUPDATED TTITLE; do
    [ -z "$TUPDATED" ] || [ "$TUPDATED" = "null" ] && continue
    TASK_SEC=$(iso_to_epoch "$TUPDATED")
    DIFF=$((NOW_SEC - TASK_SEC))
    if [ "$DIFF" -gt "$ORPHAN_SEC" ]; then
      DAYS=$((DIFF / 86400))
      echo "🔴 Orphan task ${TID}: blocked for ${DAYS}d with no activity — ${TTITLE}"
      FOUND_STALE=1
    fi
  done < <(jq -r '.tasks[] | select(.status == "blocked") | "\(.id)|\(.updated_at // .created_at)|\(.title)"' \
    "$AGENTS_DIR/task-board.json" 2>/dev/null)
fi

exit 0
