#!/usr/bin/env python3
"""config-validate/validate.py — Python entry equivalent to ``validate.sh``."""
from __future__ import annotations
import argparse, os, runpy, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="validate")
    ap.add_argument("--config", required=True)
    ap.add_argument("--schema", default="")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    if not Path(args.config).is_file():
        print(f"validate.py: config file not found: {args.config}", file=sys.stderr)
        return 2
    schema = args.schema or str(HERE / "config-schema.yaml")
    if not Path(schema).is_file():
        print(f"validate.py: schema file not found: {schema}", file=sys.stderr)
        return 2
    os.environ["PYTHONIOENCODING"] = "utf-8"
    os.environ["CN_CONFIG"] = args.config
    os.environ["CN_SCHEMA"] = schema
    os.environ["CN_JSON"] = "1" if args.json else "0"
    helper = HERE / "_validate.py"
    sys.argv = [str(helper)]
    try:
        runpy.run_path(str(helper), run_name="__main__")
    except SystemExit as e:
        code = e.code
        return int(code) if isinstance(code, int) else (0 if code is None else 1)
    return 0

if __name__ == "__main__":
    sys.exit(main())
