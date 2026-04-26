#!/usr/bin/env python3
"""model-probe/probe.py — Python entry equivalent to ``probe.sh``."""
from __future__ import annotations
import argparse, os, runpy, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="probe")
    ap.add_argument("--output", default="")
    ap.add_argument("--output-state-json", default="", dest="output_state_json")
    ap.add_argument("--tier-priority", default="", dest="tier_priority")
    ap.add_argument("--check-ttl", default="", dest="check_ttl")
    ap.add_argument("--ttl-days", default="30", dest="ttl_days")
    args = ap.parse_args(argv)
    os.environ["PYTHONIOENCODING"] = "utf-8"
    os.environ["CN_OUTPUT"] = args.output
    os.environ["CN_OUTPUT_STATE_JSON"] = args.output_state_json
    os.environ["CN_TIER_PRIORITY"] = args.tier_priority
    os.environ["CN_CHECK_TTL"] = args.check_ttl
    os.environ["CN_TTL_DAYS"] = args.ttl_days
    helper = HERE / "_probe.py"
    sys.argv = [str(helper)]
    try:
        runpy.run_path(str(helper), run_name="__main__")
    except SystemExit as e:
        code = e.code
        return int(code) if isinstance(code, int) else (0 if code is None else 1)
    return 0

if __name__ == "__main__":
    sys.exit(main())
