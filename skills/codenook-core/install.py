#!/usr/bin/env python3
"""install.py — top-level CodeNook plugin install CLI (M2).

Python port of the legacy ``install.sh``. Thin wrapper around the
install-orchestrator builtin skill. See
``skills/builtin/install-orchestrator/SKILL.md`` for full semantics.

Usage:
  install.py --src <tarball|dir> [--upgrade] [--dry-run]
             [--workspace <dir>] [--json]

Exit codes:
  0  installed (or dry-run pass)
  1  any gate failed
  2  usage / IO error
  3  already installed (without --upgrade)
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

SELF_DIR = Path(__file__).resolve().parent


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="install.py",
        description="install a CodeNook plugin into a workspace.",
        add_help=True,
    )
    parser.add_argument("--src", required=True,
                        help="plugin source (.tar.gz / .tgz or directory)")
    parser.add_argument("--workspace", default=os.getcwd(),
                        help="workspace root (default: $PWD)")
    parser.add_argument("--upgrade", action="store_true",
                        help="allow installing over an existing plugin id")
    parser.add_argument("--dry-run", action="store_true",
                        help="run all gates but do not commit")
    parser.add_argument("--json", action="store_true",
                        help="emit machine-readable summary on stdout")
    args = parser.parse_args(argv)

    workspace = Path(args.workspace)
    if not workspace.is_dir():
        sys.stderr.write(
            f"install.py: --workspace must be an existing directory: {workspace}\n"
        )
        return 2

    orch = SELF_DIR / "skills" / "builtin" / "install-orchestrator" / "orchestrator.py"
    if not orch.exists():
        orch = SELF_DIR / "skills" / "builtin" / "install-orchestrator" / "orchestrator.sh"
    if not orch.exists():
        sys.stderr.write(f"install.py: install-orchestrator not found: {orch}\n")
        return 2

    cmd = [str(orch), "--src", args.src, "--workspace", str(workspace)]
    if args.upgrade:
        cmd.append("--upgrade")
    if args.dry_run:
        cmd.append("--dry-run")
    if args.json:
        cmd.append("--json")

    os.execv(str(orch), cmd)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
