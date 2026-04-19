#!/usr/bin/env bash
# router-agent/spawn.sh — entry the main session calls per turn.
#
# This is a thin wrapper around render_prompt.py. All logic
# (lock acquisition, context-prep, prompt render, --confirm handoff)
# lives in the python helper to keep the shell layer minimal and
# portable. See SKILL.md for the CLI contract.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$HERE/render_prompt.py" "$@"
