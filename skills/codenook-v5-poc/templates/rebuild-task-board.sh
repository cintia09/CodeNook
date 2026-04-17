#!/usr/bin/env bash
# CodeNook v5.0 — Rebuild task-board.json from task state.json files
# task-board.json is a DERIVED index. If it is deleted or corrupted,
# rebuild from the authoritative per-task state.json files.
#
# Usage:
#   bash rebuild-task-board.sh
#   bash rebuild-task-board.sh --dry-run    # print without writing
set -euo pipefail

WS=".codenook"
TASKS="$WS/tasks"
BOARD="$TASKS/task-board.json"

DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

[[ -d "$TASKS" ]] || { echo "error: $TASKS/ missing" >&2; exit 2; }

python3 - "$TASKS" "$BOARD" "$DRY" <<'PY'
import json, os, sys, glob
tasks_dir, board_path, dry = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
entries = []
for sj in sorted(glob.glob(os.path.join(tasks_dir, "*/state.json"))):
    try:
        d = json.load(open(sj))
    except Exception as e:
        print(f"warn: could not parse {sj}: {e}", file=sys.stderr)
        continue
    tid = d.get("task_id") or os.path.basename(os.path.dirname(sj))
    entries.append({
        "task_id": tid,
        "status": d.get("status", "unknown"),
        "phase": d.get("phase", ""),
        "dual_mode": d.get("dual_mode"),
        "depends_on": d.get("depends_on", []),
        "subtask_count": len(d.get("subtasks", [])),
        "path": os.path.relpath(os.path.dirname(sj)),
    })
board = {
    "version": 1,
    "generated_at": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "tasks": entries,
}
out = json.dumps(board, indent=2, ensure_ascii=False)
if dry:
    print(out)
else:
    with open(board_path, "w") as f:
        f.write(out + "\n")
    print(f"wrote {board_path} ({len(entries)} task(s))")
PY
