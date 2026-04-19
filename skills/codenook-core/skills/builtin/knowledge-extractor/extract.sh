#!/usr/bin/env bash
# knowledge-extractor — M9.3 entrypoint.
#
# Thin wrapper around extract.py. The dispatcher (extractor-batch.sh)
# spawns this script with the canonical CLI agreed in M9.0:
#   --task-id <id> --workspace <ws> --phase <phase> --reason <r>
# Tests may also pass --input <file> for direct fixture wiring.
#
# Best-effort policy: extract.py always exits 0 except for secret-blocked
# candidates (TC-M9.3-12), which surface a non-zero exit so the
# dispatcher's per-extractor err log captures the rejection.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$HERE/extract.py" "$@"
