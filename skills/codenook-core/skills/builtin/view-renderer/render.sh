#!/usr/bin/env bash
# view-renderer/render.sh — emit a JSON envelope describing one HITL
# entry so the host LLM can produce a reviewer-friendly HTML + ANSI
# rewrite. See SKILL.md for the contract.
#
# Subcommands:
#   prepare --id <entry-id> [--workspace <dir>]
set -euo pipefail

SUBCMD="${1:-}"
[ $# -ge 1 ] && shift || true

ID=""; WORKSPACE="${CODENOOK_WORKSPACE:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --id)        ID="$2"; shift 2 ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,12p' "$0"; exit 0 ;;
    *) echo "render.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$WORKSPACE" ]; then
  cur="$(pwd)"
  while [ "$cur" != "/" ]; do
    if [ -d "$cur/.codenook" ]; then WORKSPACE="$cur"; break; fi
    cur="$(dirname "$cur")"
  done
  if [ -z "$WORKSPACE" ]; then
    echo "render.sh: cannot find .codenook upwards; pass --workspace" >&2
    exit 2
  fi
fi

case "$SUBCMD" in
  prepare)
    CN_SUBCMD=prepare CN_WORKSPACE="$WORKSPACE" CN_ID="$ID" \
      python3 "$(dirname "$0")/_render.py"
    ;;
  ""|-h|--help)
    sed -n '1,12p' "$0"; exit 0 ;;
  *)
    echo "render.sh: unknown subcommand: $SUBCMD" >&2; exit 2 ;;
esac
