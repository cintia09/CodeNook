#!/usr/bin/env bash
# task-config-set/set.sh — write Layer-4 override
set -euo pipefail

TASK=""; KEY=""; VALUE=""; WORKSPACE="${CODENOOK_WORKSPACE:-}"; UNSET="0"; VALUE_SET="0"

while [ $# -gt 0 ]; do
  case "$1" in
    --task)      TASK="$2"; shift 2 ;;
    --key)       KEY="$2"; shift 2 ;;
    --value)     VALUE="$2"; VALUE_SET="1"; shift 2 ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --unset)     UNSET="1"; shift ;;
    -h|--help)
      sed -n '1,40p' "$(dirname "$0")/SKILL.md"; exit 0 ;;
    *) echo "set.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$TASK" ] || [ -z "$KEY" ]; then
  echo "set.sh: --task and --key are required" >&2
  exit 2
fi

if [ "$UNSET" = "0" ] && [ "$VALUE_SET" = "0" ]; then
  echo "set.sh: --value is required (or use --unset)" >&2
  exit 2
fi

if [ -z "$WORKSPACE" ]; then
  cur="$(pwd)"
  while [ "$cur" != "/" ]; do
    if [ -d "$cur/.codenook" ]; then WORKSPACE="$cur"; break; fi
    cur="$(dirname "$cur")"
  done
  if [ -z "$WORKSPACE" ]; then
    echo "set.sh: could not locate workspace (set --workspace or CODENOOK_WORKSPACE)" >&2
    exit 2
  fi
fi

if [ ! -d "$WORKSPACE" ]; then
  echo "set.sh: workspace not found: $WORKSPACE" >&2
  exit 2
fi

TASK_DIR="$WORKSPACE/.codenook/tasks/$TASK"
if [ ! -d "$TASK_DIR" ]; then
  echo "set.sh: task not found: $TASK" >&2
  exit 1
fi

STATE_FILE="$TASK_DIR/state.json"
if [ ! -f "$STATE_FILE" ]; then
  echo "set.sh: state.json not found for task $TASK" >&2
  exit 1
fi

PYTHONIOENCODING=utf-8 \
CN_TASK="$TASK" \
CN_KEY="$KEY" \
CN_VALUE="$VALUE" \
CN_UNSET="$UNSET" \
CN_STATE_FILE="$STATE_FILE" \
exec python3 "$(dirname "$0")/_set.py"
