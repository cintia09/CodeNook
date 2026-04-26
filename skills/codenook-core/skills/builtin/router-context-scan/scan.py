#!/usr/bin/env python3
"""router-context-scan/scan.py — Python entry equivalent to ``scan.sh``."""
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
    ap = argparse.ArgumentParser(prog="scan")
    ap.add_argument("--workspace", default="")
    ap.add_argument("--max-tasks", default="20")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    workspace = args.workspace or os.environ.get("CODENOOK_WORKSPACE", "")
    if not workspace:
        ws = _find_workspace(Path.cwd())
        if ws is None:
            print("scan.py: could not locate workspace (set --workspace)", file=sys.stderr)
            return 2
        workspace = str(ws)
    if not Path(workspace, ".codenook").is_dir():
        print(f"scan.py: workspace missing .codenook/: {workspace}", file=sys.stderr)
        return 2
    try:
        int(args.max_tasks)
    except ValueError:
        print("scan.py: --max-tasks must be a positive integer", file=sys.stderr)
        return 2
    os.environ["PYTHONIOENCODING"] = "utf-8"
    os.environ["CN_WORKSPACE"] = workspace
    os.environ["CN_MAX_TASKS"] = args.max_tasks
    os.environ["CN_JSON"] = "1" if args.json else "0"
    helper = HERE / "_scan.py"
    sys.argv = [str(helper)]
    try:
        runpy.run_path(str(helper), run_name="__main__")
    except SystemExit as e:
        code = e.code
        return int(code) if isinstance(code, int) else (0 if code is None else 1)
    return 0

if __name__ == "__main__":
    sys.exit(main())
