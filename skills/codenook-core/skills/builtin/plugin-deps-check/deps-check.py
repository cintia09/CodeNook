#!/usr/bin/env python3
"""plugin-deps-check/deps-check.py — Python entry equivalent to ``deps-check.sh``."""
from __future__ import annotations
import argparse, os, runpy, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="deps-check")
    ap.add_argument("--src", required=True)
    ap.add_argument("--core-version", default="", dest="core_version")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    if not Path(args.src).is_dir():
        print(f"deps-check.py: --src must be a directory", file=sys.stderr)
        return 2
    core_version = args.core_version
    if not core_version:
        vp = HERE / "../../../VERSION"
        try:
            core_version = vp.resolve().read_text(encoding="utf-8").strip()
        except (OSError, FileNotFoundError):
            core_version = ""
    os.environ["CN_SRC"] = args.src
    os.environ["CN_CORE_VERSION"] = core_version
    os.environ["CN_JSON"] = "1" if args.json else "0"
    helper = HERE / "_deps_check.py"
    sys.argv = [str(helper)]
    try:
        runpy.run_path(str(helper), run_name="__main__")
    except SystemExit as e:
        code = e.code
        return int(code) if isinstance(code, int) else (0 if code is None else 1)
    return 0

if __name__ == "__main__":
    sys.exit(main())
