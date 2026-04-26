#!/usr/bin/env python3
"""secrets-resolve/resolve.py — Python entry equivalent to ``resolve.sh``."""
from __future__ import annotations
import argparse, os, runpy, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="resolve")
    ap.add_argument("--config", required=True)
    ap.add_argument("--allow-missing", action="store_true", dest="allow_missing")
    args = ap.parse_args(argv)
    if not Path(args.config).is_file():
        print(f"resolve.py: config file not found: {args.config}", file=sys.stderr)
        return 2
    os.environ["PYTHONIOENCODING"] = "utf-8"
    os.environ["CN_CONFIG"] = args.config
    os.environ["CN_ALLOW_MISSING"] = "1" if args.allow_missing else "0"
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
