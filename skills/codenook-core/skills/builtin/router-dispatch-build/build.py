#!/usr/bin/env python3
"""router-dispatch-build/build.py — Python entry equivalent to ``build.sh``."""
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
    ap = argparse.ArgumentParser(prog="build")
    ap.add_argument("--target", required=True)
    ap.add_argument("--user-input", required=True, dest="user_input")
    ap.add_argument("--task", default="")
    ap.add_argument("--workspace", default="")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    workspace = args.workspace or os.environ.get("CODENOOK_WORKSPACE", "")
    if not workspace:
        ws = _find_workspace(Path.cwd())
        if ws is not None:
            workspace = str(ws)
    if not workspace or not Path(workspace, ".codenook").is_dir():
        print("build.py: workspace not located (set --workspace)", file=sys.stderr)
        return 2
    emit_py = str((HERE / "../dispatch-audit/emit.py").resolve())
    os.environ["PYTHONIOENCODING"] = "utf-8"
    os.environ["CN_TARGET"] = args.target
    os.environ["CN_USER_INPUT"] = args.user_input
    os.environ["CN_TASK"] = args.task
    os.environ["CN_WORKSPACE"] = workspace
    os.environ["CN_JSON"] = "1" if args.json else "0"
    os.environ["CN_EMIT_SH"] = emit_py
    helper = HERE / "_build.py"
    sys.argv = [str(helper)]
    try:
        runpy.run_path(str(helper), run_name="__main__")
    except SystemExit as e:
        code = e.code
        return int(code) if isinstance(code, int) else (0 if code is None else 1)
    return 0

if __name__ == "__main__":
    sys.exit(main())
