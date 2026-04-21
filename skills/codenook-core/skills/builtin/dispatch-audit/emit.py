#!/usr/bin/env python3
"""dispatch-audit/emit.py — Python entry equivalent to ``emit.sh``.

v0.24.0 — preferred on Windows hosts without bash on PATH. The .sh
wrapper is retained for Linux/Mac users; it now delegates to this script.
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import _emit  # noqa: E402


def _find_workspace(start: Path) -> Path | None:
    for p in [start, *start.parents]:
        if (p / ".codenook").is_dir():
            return p
    return None


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="emit")
    ap.add_argument("--role", required=True)
    ap.add_argument("--payload", required=True)
    ap.add_argument("--workspace")
    args = ap.parse_args(argv)

    ws_arg = args.workspace or os.environ.get("CODENOOK_WORKSPACE")
    workspace = Path(ws_arg) if ws_arg else _find_workspace(Path.cwd())
    if not workspace or not workspace.is_dir():
        print("emit.py: workspace not found (set --workspace or "
              "CODENOOK_WORKSPACE)", file=sys.stderr)
        return 2
    return _emit.run(role=args.role, payload=args.payload, workspace=workspace)


if __name__ == "__main__":
    sys.exit(main())
