#!/usr/bin/env python3
"""router-agent/spawn.py — Python entry equivalent to ``spawn.sh``.

v0.24.0 — preferred entry point on Windows hosts without bash on PATH.
The .sh wrapper is retained for Linux/Mac users who script against it
and now delegates to this script.

Usage::

    python spawn.py --workspace <ws> --task-id T-NNN [--user-turn-file PATH]
                    [--confirm]
"""
from __future__ import annotations

import os
import runpy
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def main(argv=None) -> int:
    # render_prompt.py owns the full CLI surface (lock acquisition,
    # prompt rendering, --confirm handoff). Delegate by setting argv
    # and running the helper as if it were the main script.
    argv = list(argv if argv is not None else sys.argv[1:])
    sys.argv = [str(HERE / "render_prompt.py"), *argv]
    try:
        runpy.run_path(str(HERE / "render_prompt.py"), run_name="__main__")
    except SystemExit as e:
        code = e.code
        return int(code) if isinstance(code, int) else (0 if code is None else 1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
