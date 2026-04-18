#!/usr/bin/env bash
# sec-audit/audit.sh — lightweight workspace security scanner.
set -euo pipefail

WORKSPACE=""; JSON_OUT="0"

while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --json)      JSON_OUT="1"; shift ;;
    -h|--help)
      sed -n '1,40p' "$(dirname "$0")/SKILL.md"; exit 0 ;;
    *) echo "audit.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$WORKSPACE" ]; then
  echo "audit.sh: --workspace <dir> is required" >&2
  exit 2
fi

if [ ! -d "$WORKSPACE" ]; then
  echo "audit.sh: workspace not found: $WORKSPACE" >&2
  exit 2
fi

PYTHONIOENCODING=utf-8 \
CN_WORKSPACE="$WORKSPACE" \
CN_JSON="$JSON_OUT" \
CN_PATTERNS="$(dirname "$0")/patterns.txt" \
exec python3 "$(dirname "$0")/_audit.py"
