#!/usr/bin/env bash
# router-dispatch-build/build.sh — assemble the ≤500-char dispatch payload.
# See SKILL.md for full contract.
set -euo pipefail

TARGET=""; USER_INPUT=""; USER_INPUT_SET="0"
TASK=""; WORKSPACE="${CODENOOK_WORKSPACE:-}"; JSON_OUT="0"

while [ $# -gt 0 ]; do
  case "$1" in
    --target)     TARGET="$2"; shift 2 ;;
    --user-input) USER_INPUT="$2"; USER_INPUT_SET="1"; shift 2 ;;
    --task)       TASK="$2"; shift 2 ;;
    --workspace)  WORKSPACE="$2"; shift 2 ;;
    --json)       JSON_OUT="1"; shift ;;
    -h|--help)    sed -n '1,40p' "$(dirname "$0")/SKILL.md"; exit 0 ;;
    *) echo "build.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "build.sh: --target is required" >&2; exit 2
fi
if [ "$USER_INPUT_SET" != "1" ]; then
  echo "build.sh: --user-input is required" >&2; exit 2
fi

if [ -z "$WORKSPACE" ]; then
  cur="$(pwd)"
  while [ "$cur" != "/" ]; do
    if [ -d "$cur/.codenook" ]; then WORKSPACE="$cur"; break; fi
    cur="$(dirname "$cur")"
  done
fi
if [ -z "$WORKSPACE" ] || [ ! -d "$WORKSPACE/.codenook" ]; then
  echo "build.sh: workspace not located (set --workspace)" >&2
  exit 2
fi

EMIT_SH="$(cd "$(dirname "$0")/../dispatch-audit" && pwd)/emit.sh"

PYTHONIOENCODING=utf-8 \
CN_TARGET="$TARGET" \
CN_USER_INPUT="$USER_INPUT" \
CN_TASK="$TASK" \
CN_WORKSPACE="$WORKSPACE" \
CN_JSON="$JSON_OUT" \
CN_EMIT_SH="$EMIT_SH" \
exec python3 "$(dirname "$0")/_build.py"
