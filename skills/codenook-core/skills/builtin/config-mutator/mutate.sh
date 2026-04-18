#!/usr/bin/env bash
# config-mutator/mutate.sh — write Layer-3 (workspace) or Layer-4 (task)
# config override, with audit log. See SKILL.md.
set -euo pipefail

PLUGIN=""; PATH_KEY=""; VALUE=""; REASON=""; ACTOR=""
WORKSPACE=""; SCOPE="workspace"; TASK=""; VALUE_SET=0; VALUE_JSON=0

while [ $# -gt 0 ]; do
  case "$1" in
    --plugin)     PLUGIN="$2"; shift 2 ;;
    --path)       PATH_KEY="$2"; shift 2 ;;
    --value)      VALUE="$2"; VALUE_SET=1; VALUE_JSON=0; shift 2 ;;
    --value-json) VALUE="$2"; VALUE_SET=1; VALUE_JSON=1; shift 2 ;;
    --reason)    REASON="$2"; shift 2 ;;
    --actor)     ACTOR="$2"; shift 2 ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --scope)     SCOPE="$2"; shift 2 ;;
    --task)      TASK="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,40p' "$(dirname "$0")/SKILL.md"; exit 0 ;;
    *) echo "mutate.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$PLUGIN" ] || [ -z "$PATH_KEY" ] || [ "$VALUE_SET" = 0 ] \
   || [ -z "$REASON" ] || [ -z "$ACTOR" ] || [ -z "$WORKSPACE" ]; then
  echo "mutate.sh: --plugin, --path, --value, --reason, --actor, --workspace are required" >&2
  exit 2
fi

if [ "$SCOPE" = "task" ] && [ -z "$TASK" ]; then
  echo "mutate.sh: --task is required with --scope task" >&2
  exit 2
fi

PYTHONIOENCODING=utf-8 \
CN_PLUGIN="$PLUGIN" \
CN_PATH="$PATH_KEY" \
CN_VALUE="$VALUE" \
CN_VALUE_JSON="$VALUE_JSON" \
CN_REASON="$REASON" \
CN_ACTOR="$ACTOR" \
CN_WORKSPACE="$WORKSPACE" \
CN_SCOPE="$SCOPE" \
CN_TASK="$TASK" \
CN_CORE_DIR="$(cd "$(dirname "$0")/../../.." && pwd)" \
exec python3 "$(dirname "$0")/_mutate.py"
