#!/usr/bin/env python3
"""CodeNook test runner — runs the complete bats + pytest suite.

Usage:  python3 skills/codenook-core/tests/run_all.py
"""
from __future__ import annotations

import glob
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def main() -> int:
    print("== bats ==")
    bats_files = sorted(glob.glob(str(HERE / "*.bats"))) + sorted(
        glob.glob(str(HERE / "e2e" / "*.bats"))
    )
    if bats_files:
        rc = subprocess.run(["bats", *bats_files]).returncode
        if rc != 0:
            return rc
    else:
        print("(no .bats files found, skipping)")

    print("")
    print("== pytest ==")
    rc = subprocess.run(
        ["python3", "-m", "pytest", str(HERE / "python"), "-q"]
    ).returncode
    return rc


if __name__ == "__main__":
    sys.exit(main())
