#!/usr/bin/env python3
"""sec-audit/audit.py — Python entry equivalent to ``audit.sh``."""
from __future__ import annotations
import argparse, os, runpy, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="audit")
    ap.add_argument("--workspace", required=True)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    if not Path(args.workspace).is_dir():
        print(f"audit.py: workspace not found: {args.workspace}", file=sys.stderr)
        return 2
    os.environ["PYTHONIOENCODING"] = "utf-8"
    os.environ["CN_WORKSPACE"] = args.workspace
    os.environ["CN_JSON"] = "1" if args.json else "0"
    os.environ["CN_PATTERNS"] = str(HERE / "patterns.txt")
    helper = HERE / "_audit.py"
    sys.argv = [str(helper)]
    try:
        runpy.run_path(str(helper), run_name="__main__")
    except SystemExit as e:
        code = e.code
        return int(code) if isinstance(code, int) else (0 if code is None else 1)
    return 0

if __name__ == "__main__":
    sys.exit(main())
