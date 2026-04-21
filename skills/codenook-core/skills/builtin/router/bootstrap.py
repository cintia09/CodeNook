#!/usr/bin/env python3
"""router/bootstrap.py — Python entry equivalent to ``bootstrap.sh``.

v0.24.0 — preferred on Windows hosts without bash on PATH. The .sh
wrapper is retained for Linux/Mac users; it now delegates to this script.
"""
from __future__ import annotations

import argparse
import os
import runpy
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _find_workspace(start: Path) -> Path | None:
    for p in [start, *start.parents]:
        if (p / ".codenook").is_dir():
            return p
    return None


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="bootstrap")
    ap.add_argument("--user-input", required=True)
    ap.add_argument("--workspace")
    ap.add_argument("--task", default="")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    ws_arg = args.workspace or os.environ.get("CODENOOK_WORKSPACE")
    workspace = Path(ws_arg) if ws_arg else _find_workspace(Path.cwd())
    if not workspace or not (workspace / ".codenook").is_dir():
        print("bootstrap.py: workspace not located (set --workspace)",
              file=sys.stderr)
        return 2

    default_core = HERE.parent.parent.parent.resolve()
    core_root = os.environ.get("CN_CORE_ROOT", str(default_core))

    os.environ["PYTHONIOENCODING"] = "utf-8"
    os.environ["CN_USER_INPUT"] = args.user_input
    os.environ["CN_WORKSPACE"] = str(workspace)
    os.environ["CN_TASK"] = args.task
    os.environ["CN_JSON"] = "1" if args.json else "0"
    os.environ["CN_CORE_ROOT"] = core_root
    os.environ["CN_DEFAULT_CORE"] = str(default_core)

    helper = HERE / "_bootstrap.py"
    sys.argv = [str(helper)]
    try:
        runpy.run_path(str(helper), run_name="__main__")
    except SystemExit as e:
        code = e.code
        return int(code) if isinstance(code, int) else (0 if code is None else 1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
