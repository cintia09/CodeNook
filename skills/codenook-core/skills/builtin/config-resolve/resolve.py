#!/usr/bin/env python3
"""config-resolve/resolve.py — Python entry equivalent to ``resolve.sh``."""
from __future__ import annotations
import argparse, os, runpy, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="resolve")
    ap.add_argument("--plugin", required=True)
    ap.add_argument("--task", default="")
    ap.add_argument("--workspace", required=True)
    ap.add_argument("--catalog", default="")
    args = ap.parse_args(argv)
    catalog = args.catalog
    if not catalog:
        catalog = str(Path(args.workspace) / ".codenook" / "state.json")
    os.environ["PYTHONIOENCODING"] = "utf-8"
    os.environ["CN_PLUGIN"] = args.plugin
    os.environ["CN_TASK"] = args.task
    os.environ["CN_WORKSPACE"] = args.workspace
    os.environ["CN_CATALOG"] = catalog
    helper = HERE / "_resolve.py"
    sys.argv = [str(helper)]
    try:
        runpy.run_path(str(helper), run_name="__main__")
    except SystemExit as e:
        code = e.code
        return int(code) if isinstance(code, int) else (0 if code is None else 1)
    return 0

if __name__ == "__main__":
    sys.exit(main())
