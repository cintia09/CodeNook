#!/usr/bin/env bash
# config-extractor — M9.5 entrypoint.
#
# Thin wrapper around extract.py. Same CLI contract as M9.3 / M9.4:
#   --task-id <id> --workspace <ws> --phase <phase> --reason <r> [--input <f>]
#
# Best-effort: extract.py exits 0 on every failure path *except* secret-
# blocked candidates (parity with knowledge / skill extractors).

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$HERE/extract.py" "$@"
