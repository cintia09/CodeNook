#!/usr/bin/env python3
"""task-config-set/set.py — Python entry equivalent to ``set.sh``."""
from __future__ import annotations
import argparse, os, runpy, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

def _find_workspace(start: Path):
    for p in [start, *start.parents]:
        if (p / ".codenook").is_dir():
            return p
    return None

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="set")
    ap.add_argument("--task", required=True)
    ap.add_argument("--key", default="")
    ap.add_argument("--value", default="")
    ap.add_argument("--workspace", default="")
    ap.add_argument("--unset", action="store_true")
    ap.add_argument("--mode", default="")
    ap.add_argument("--plugin", default="")
    ap.add_argument("--role", default="")
    args = ap.parse_args(argv)
    unset = args.unset
    key = args.key
    if args.mode == "clear":
        unset = True
    if not key and args.role:
        key = f"models.{args.role}"
    if not key:
        print("set.py: --key (or --role) is required", file=sys.stderr)
        return 2
    workspace = args.workspace or os.environ.get("CODENOOK_WORKSPACE", "")
    if not workspace:
        ws = _find_workspace(Path.cwd())
        if ws is None:
            print("set.py: could not locate workspace (set --workspace or CODENOOK_WORKSPACE)", file=sys.stderr)
            return 2
        workspace = str(ws)
    if not Path(workspace).is_dir():
        print(f"set.py: workspace not found: {workspace}", file=sys.stderr)
        return 2
    task_dir = Path(workspace) / ".codenook" / "tasks" / args.task
    if not task_dir.is_dir():
        print(f"set.py: task not found: {args.task}", file=sys.stderr)
        return 1
    state_file = task_dir / "state.json"
    if not state_file.is_file():
        print(f"set.py: state.json not found for task {args.task}", file=sys.stderr)
        return 1
    os.environ["PYTHONIOENCODING"] = "utf-8"
    os.environ["CN_TASK"] = args.task
    os.environ["CN_KEY"] = key
    os.environ["CN_VALUE"] = args.value
    os.environ["CN_UNSET"] = "1" if unset else "0"
    os.environ["CN_STATE_FILE"] = str(state_file)
    os.environ["CN_WORKSPACE"] = workspace
    os.environ["CN_PLUGIN"] = args.plugin
    helper = HERE / "_set.py"
    sys.argv = [str(helper)]
    try:
        runpy.run_path(str(helper), run_name="__main__")
    except SystemExit as e:
        code = e.code
        return int(code) if isinstance(code, int) else (0 if code is None else 1)
    return 0

if __name__ == "__main__":
    sys.exit(main())
