#!/usr/bin/env bash
set -euo pipefail
# Multi-Agent Framework: Staleness Detection
# Checks for tasks and agents inactive beyond threshold.
# Called from session-start hook or standalone.

AGENTS_DIR="${1:-.agents}"
THRESHOLD_HOURS="${2:-24}"

[ -d "$AGENTS_DIR/runtime" ] || exit 0

# Detect which date conversion tool works (once, not per-call)
_DATE_TOOL=""
if date -j -f "%Y-%m-%dT%H:%M:%SZ" "2024-01-01T00:00:00Z" +%s &>/dev/null; then
  _DATE_TOOL="bsd"
elif date -d "2024-01-01T00:00:00Z" +%s &>/dev/null; then
  _DATE_TOOL="gnu"
elif perl -e "use Time::Piece" &>/dev/null; then
  _DATE_TOOL="perl"
fi

iso_to_epoch() {
  local ts="$1"
  case "$_DATE_TOOL" in
    bsd)  date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || echo 0 ;;
    gnu)  date -d "$ts" +%s 2>/dev/null || echo 0 ;;
    perl) TS_VAL="$ts" perl -e 'use Time::Piece; print Time::Piece->strptime($ENV{"TS_VAL"},"%Y-%m-%dT%H:%M:%SZ")->epoch' 2>/dev/null || echo 0 ;;
    *)    echo 0 ;;
  esac
}

THRESHOLD_SEC=$((THRESHOLD_HOURS * 3600))
NOW_SEC=$(date +%s)
FOUND_STALE=0

# Check agent staleness (consolidate 3 jq calls → 1 per state file)
for state_file in "$AGENTS_DIR"/runtime/*/state.json; do
  [ -f "$state_file" ] || continue
  IFS=$'\t' read -r AGENT STATUS LAST TASK < <(jq -r '[.agent, .status, .last_activity, (.current_task // "—")] | @tsv' "$state_file" 2>/dev/null) || continue

  [ "$STATUS" = "idle" ] && continue
  [ -z "$LAST" ] || [ "$LAST" = "null" ] && continue

  LAST_SEC=$(iso_to_epoch "$LAST")
  DIFF=$((NOW_SEC - LAST_SEC))

  if [ "$DIFF" -gt "$THRESHOLD_SEC" ]; then
    HOURS=$((DIFF / 3600))
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
