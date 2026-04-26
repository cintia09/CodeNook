#!/usr/bin/env python3
"""plugin-subsystem-claim/subsystem-claim.py — Python entry equivalent to ``subsystem-claim.sh``."""
from __future__ import annotations
import argparse, os, runpy, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="subsystem-claim")
    ap.add_argument("--src", required=True)
    ap.add_argument("--workspace", default="")
    ap.add_argument("--upgrade", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    if not Path(args.src).is_dir():
        print(f"subsystem-claim.py: --src must be a directory", file=sys.stderr)
        return 2
    os.environ["CN_SRC"] = args.src
    os.environ["CN_WORKSPACE"] = args.workspace or ""
    os.environ["CN_UPGRADE"] = "1" if args.upgrade else "0"
    os.environ["CN_JSON"] = "1" if args.json else "0"
    helper = HERE / "_subsystem_claim.py"
    sys.argv = [str(helper)]
    try:
        runpy.run_path(str(helper), run_name="__main__")
    except SystemExit as e:
        code = e.code
        return int(code) if isinstance(code, int) else (0 if code is None else 1)
    return 0

if __name__ == "__main__":
    sys.exit(main())
