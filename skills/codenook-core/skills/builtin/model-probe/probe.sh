#!/usr/bin/env bash
# model-probe/probe.sh — capability discovery + tier resolution.
# See SKILL.md for full contract.
set -euo pipefail

OUTPUT=""
TIER_PRIORITY_FILE=""
CHECK_TTL_FILE=""
TTL_DAYS="30"
OUTPUT_STATE_JSON=""

while [ $# -gt 0 ]; do
  case "$1" in
    --output)             OUTPUT="$2"; shift 2 ;;
    --output-state-json)  OUTPUT_STATE_JSON="$2"; shift 2 ;;
    --tier-priority)      TIER_PRIORITY_FILE="$2"; shift 2 ;;
    --check-ttl)          CHECK_TTL_FILE="$2"; shift 2 ;;
    --ttl-days)           TTL_DAYS="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,40p' "$(dirname "$0")/SKILL.md"; exit 0 ;;
    *) echo "probe failed: unknown arg: $1" >&2; exit 2 ;;
  esac
done

PYTHONIOENCODING=utf-8 \
CN_OUTPUT="$OUTPUT" \
CN_OUTPUT_STATE_JSON="$OUTPUT_STATE_JSON" \
CN_TIER_PRIORITY="$TIER_PRIORITY_FILE" \
CN_CHECK_TTL="$CHECK_TTL_FILE" \
CN_TTL_DAYS="$TTL_DAYS" \
exec python3 "$(dirname "$0")/_probe.py"
