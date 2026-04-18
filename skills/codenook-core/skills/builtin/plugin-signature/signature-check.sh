#!/usr/bin/env bash
set -euo pipefail
SRC=""; JSON_OUT="0"
while [ $# -gt 0 ]; do
  case "$1" in
    --src) SRC="$2"; shift 2 ;;
    --json) JSON_OUT="1"; shift ;;
    -h|--help) sed -n '1,40p' "$(dirname "$0")/SKILL.md"; exit 0 ;;
    *) echo "signature-check.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -z "$SRC" ] && { echo "signature-check.sh: --src required" >&2; exit 2; }
[ -d "$SRC" ] || { echo "signature-check.sh: --src must be a directory" >&2; exit 2; }
CN_SRC="$SRC" CN_JSON="$JSON_OUT" \
CN_REQUIRE_SIG="${CODENOOK_REQUIRE_SIG:-0}" \
  exec python3 "$(dirname "$0")/_signature_check.py"
