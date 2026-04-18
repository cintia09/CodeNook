#!/usr/bin/env bash
set -euo pipefail
SRC=""; CORE_VERSION=""; JSON_OUT="0"
while [ $# -gt 0 ]; do
  case "$1" in
    --src) SRC="$2"; shift 2 ;;
    --core-version) CORE_VERSION="$2"; shift 2 ;;
    --json) JSON_OUT="1"; shift ;;
    -h|--help) sed -n '1,40p' "$(dirname "$0")/SKILL.md"; exit 0 ;;
    *) echo "deps-check.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -z "$SRC" ] && { echo "deps-check.sh: --src required" >&2; exit 2; }
[ -d "$SRC" ] || { echo "deps-check.sh: --src must be a directory" >&2; exit 2; }

if [ -z "$CORE_VERSION" ]; then
  CORE_VERSION="$(cat "$(dirname "$0")/../../../VERSION" 2>/dev/null | tr -d '[:space:]')"
fi

CN_SRC="$SRC" CN_CORE_VERSION="$CORE_VERSION" CN_JSON="$JSON_OUT" \
  exec python3 "$(dirname "$0")/_deps_check.py"
