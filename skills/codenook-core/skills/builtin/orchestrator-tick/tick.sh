#!/usr/bin/env bash
# orchestrator-tick/tick.sh — advance task one phase
set -euo pipefail

TASK=""; WORKSPACE="${CODENOOK_WORKSPACE:-}"; DRY_RUN="0"; JSON="0"

while [ $# -gt 0 ]; do
  case "$1" in
    --task)      TASK="$2"; shift 2 ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --dry-run)   DRY_RUN="1"; shift ;;
    --json)      JSON="1"; shift ;;
    -h|--help)
      sed -n '1,40p' "$(dirname "$0")/SKILL.md"; exit 0 ;;
    *) echo "tick.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$TASK" ]; then
  echo "tick.sh: --task is required" >&2
  exit 2
fi

if [ -z "$WORKSPACE" ]; then
  cur="$(pwd)"
  while [ "$cur" != "/" ]; do
    if [ -d "$cur/.codenook" ]; then WORKSPACE="$cur"; break; fi
    cur="$(dirname "$cur")"
  done
  if [ -z "$WORKSPACE" ]; then
    echo "tick.sh: could not locate workspace (set --workspace or CODENOOK_WORKSPACE)" >&2
    exit 2
  fi
fi

if [ ! -d "$WORKSPACE" ]; then
  echo "tick.sh: workspace not found: $WORKSPACE" >&2
  exit 2
fi

TASK_DIR="$WORKSPACE/.codenook/tasks/$TASK"
if [ ! -d "$TASK_DIR" ]; then
  echo "tick.sh: task not found: $TASK" >&2
  exit 2
fi

STATE_FILE="$TASK_DIR/state.json"
if [ ! -f "$STATE_FILE" ]; then
  echo "tick.sh: state.json not found for task $TASK" >&2
  exit 2
fi

PYTHONIOENCODING=utf-8 \
CN_TASK="$TASK" \
CN_STATE_FILE="$STATE_FILE" \
CN_WORKSPACE="$WORKSPACE" \
CN_DRY_RUN="$DRY_RUN" \
CN_JSON="$JSON" \
CN_DISPATCH_CMD="${CODENOOK_DISPATCH_CMD:-}" \
exec python3 "$(dirname "$0")/_tick.py"
