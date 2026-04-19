#!/usr/bin/env bash
# skill-extractor — M9.4 entrypoint.
#
# Thin wrapper around extract.py. Same CLI contract as M9.3:
#   --task-id <id> --workspace <ws> --phase <phase> --reason <r> [--input <f>]
#
# Best-effort: extract.py exits 0 on any failure path *except* secret-blocked
# candidates (parity with M9.3 / TC-M9.3-12) — those exit non-zero so the
# dispatcher's per-extractor err log surfaces the rejection.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$HERE/extract.py" "$@"
