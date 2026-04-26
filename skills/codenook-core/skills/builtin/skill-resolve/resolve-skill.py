#!/usr/bin/env python3
"""skill-resolve/resolve-skill.py — Python entry equivalent to ``resolve-skill.sh``."""
from __future__ import annotations
import argparse, os, runpy, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="resolve-skill")
    ap.add_argument("--name", required=True)
    ap.add_argument("--plugin", required=True)
    ap.add_argument("--workspace", required=True)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    core_dir = os.environ.get("CODENOOK_CORE_DIR", "")
    if not core_dir:
        core_dir = str((HERE / "../../..").resolve())
    os.environ["PYTHONIOENCODING"] = "utf-8"
    os.environ["CN_NAME"] = args.name
    os.environ["CN_PLUGIN"] = args.plugin
    os.environ["CN_WORKSPACE"] = args.workspace
    os.environ["CN_CORE_DIR"] = core_dir
    helper = HERE / "_resolve_skill.py"
    sys.argv = [str(helper)]
    try:
        runpy.run_path(str(helper), run_name="__main__")
    except SystemExit as e:
        code = e.code
        return int(code) if isinstance(code, int) else (0 if code is None else 1)
    return 0

if __name__ == "__main__":
    sys.exit(main())
