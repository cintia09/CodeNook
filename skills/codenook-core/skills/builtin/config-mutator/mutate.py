#!/usr/bin/env python3
"""config-mutator/mutate.py — Python entry equivalent to ``mutate.sh``."""
from __future__ import annotations
import argparse, os, runpy, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="mutate")
    ap.add_argument("--plugin", required=True)
    ap.add_argument("--path", required=True)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--value")
    g.add_argument("--value-json")
    ap.add_argument("--reason", required=True)
    ap.add_argument("--actor", required=True)
    ap.add_argument("--workspace", required=True)
    ap.add_argument("--scope", default="workspace")
    ap.add_argument("--task", default="")
    args = ap.parse_args(argv)
    if args.scope == "task" and not args.task:
        print("mutate.py: --task is required with --scope task", file=sys.stderr)
        return 2
    value_json = "0"
    value = ""
    if args.value is not None:
        value = args.value
        value_json = "0"
    elif args.value_json is not None:
        value = args.value_json
        value_json = "1"
    os.environ["PYTHONIOENCODING"] = "utf-8"
    os.environ["CN_PLUGIN"] = args.plugin
    os.environ["CN_PATH"] = args.path
    os.environ["CN_VALUE"] = value
    os.environ["CN_VALUE_JSON"] = value_json
    os.environ["CN_REASON"] = args.reason
    os.environ["CN_ACTOR"] = args.actor
    os.environ["CN_WORKSPACE"] = args.workspace
    os.environ["CN_SCOPE"] = args.scope
    os.environ["CN_TASK"] = args.task
    os.environ["CN_CORE_DIR"] = str((HERE / "../../..").resolve())
    helper = HERE / "_mutate.py"
    sys.argv = [str(helper)]
    try:
        runpy.run_path(str(helper), run_name="__main__")
    except SystemExit as e:
        code = e.code
        return int(code) if isinstance(code, int) else (0 if code is None else 1)
    return 0

if __name__ == "__main__":
    sys.exit(main())
