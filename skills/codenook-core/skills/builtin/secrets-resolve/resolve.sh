#!/usr/bin/env bash
# secrets-resolve/resolve.sh — resolve ${env:...} and ${file:...} placeholders
# inside a merged config JSON. Never logs resolved values on success.
set -euo pipefail

CONFIG=""; ALLOW_MISSING="0"

while [ $# -gt 0 ]; do
  case "$1" in
    --config)         CONFIG="$2"; shift 2 ;;
    --allow-missing)  ALLOW_MISSING="1"; shift ;;
    -h|--help)
      sed -n '1,40p' "$(dirname "$0")/SKILL.md"; exit 0 ;;
    *) echo "resolve.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$CONFIG" ]; then
  echo "resolve.sh: --config <merged.json> is required" >&2
  exit 2
fi

if [ ! -f "$CONFIG" ]; then
  echo "resolve.sh: config file not found: $CONFIG" >&2
  exit 2
fi

PYTHONIOENCODING=utf-8 \
CN_CONFIG="$CONFIG" \
CN_ALLOW_MISSING="$ALLOW_MISSING" \
exec python3 "$(dirname "$0")/_resolve.py"
