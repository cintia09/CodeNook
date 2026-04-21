#!/usr/bin/env python3
"""preflight/preflight.py — Python entry equivalent to ``preflight.sh``.

v0.24.0 — preferred on Windows hosts without bash on PATH. The .sh
wrapper is retained for Linux/Mac users; it now delegates to this script.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import _preflight  # noqa: E402


def _find_workspace(start: Path) -> Path | None:
    for p in [start, *start.parents]:
        if (p / ".codenook").is_dir():
            return p
    return None


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="preflight")
    ap.add_argument("--task", required=True)
    ap.add_argument("--workspace")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    ws_arg = args.workspace or os.environ.get("CODENOOK_WORKSPACE")
    workspace = Path(ws_arg) if ws_arg else _find_workspace(Path.cwd())
    if not workspace or not workspace.is_dir():
        print("preflight.py: workspace not found (set --workspace or "
              "CODENOOK_WORKSPACE)", file=sys.stderr)
        return 2

    state_file = workspace / ".codenook" / "tasks" / args.task / "state.json"
    if not state_file.is_file():
        print(f"preflight.py: state.json not found for task {args.task}",
              file=sys.stderr)
        return 2

    rc, phase, reasons = _preflight.run(
        task=args.task, state_file=str(state_file),
        workspace=str(workspace), json_out=args.json,
    )
    if args.json:
        print(json.dumps({"ok": rc == 0, "task": args.task,
                          "phase": phase, "reasons": reasons},
                         ensure_ascii=False))
    else:
        for r in reasons:
            print(r, file=sys.stderr)
    return rc


if __name__ == "__main__":
    sys.exit(main())
