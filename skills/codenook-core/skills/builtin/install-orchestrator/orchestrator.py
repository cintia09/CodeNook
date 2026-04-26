#!/usr/bin/env python3
"""install-orchestrator/orchestrator.py — Python entry equivalent to ``orchestrator.sh``."""
from __future__ import annotations
import argparse, os, runpy, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="orchestrator")
    ap.add_argument("--src", required=True)
    ap.add_argument("--workspace", required=True)
    ap.add_argument("--upgrade", action="store_true")
    ap.add_argument("--dry-run", action="store_true", dest="dry_run")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    core_version = os.environ.get("CN_CORE_VERSION", "")
    if not core_version:
        vp = HERE / "../../../VERSION"
        try:
            core_version = vp.resolve().read_text(encoding="utf-8").strip()
        except (OSError, FileNotFoundError):
            core_version = ""
    os.environ["CN_SRC"] = args.src
    os.environ["CN_WORKSPACE"] = args.workspace
    os.environ["CN_UPGRADE"] = "1" if args.upgrade else "0"
    os.environ["CN_DRY_RUN"] = "1" if args.dry_run else "0"
    os.environ["CN_JSON"] = "1" if args.json else "0"
    os.environ["CN_REQUIRE_SIG"] = os.environ.get("CODENOOK_REQUIRE_SIG", "0")
    os.environ["CN_BUILTIN_DIR"] = str((HERE / "..").resolve())
    os.environ["CN_CORE_VERSION"] = core_version
    helper = HERE / "_orchestrator.py"
    sys.argv = [str(helper)]
    try:
        runpy.run_path(str(helper), run_name="__main__")
    except SystemExit as e:
        code = e.code
        return int(code) if isinstance(code, int) else (0 if code is None else 1)
    return 0

if __name__ == "__main__":
    sys.exit(main())
