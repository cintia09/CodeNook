#!/usr/bin/env python3
"""init.py — CodeNook v6 installer & plugin manager (M1 skeleton).

Python port of the legacy ``init.sh``. M1 scope: subcommand
dispatcher only. Each non-meta subcommand body is a stub that
prints "TODO: ..." and exits 2 (not implemented). Real logic is
implemented incrementally in M2..M5 per docs/implementation.md.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

SELF_DIR = Path(__file__).resolve().parent
VERSION_FILE = SELF_DIR / "VERSION"

USAGE = """\
CodeNook v6 — installer & plugin manager

Usage:
  init.py                                 seed workspace in CWD (M1 stub)
  init.py --install-plugin <path|url>     install a plugin tarball/zip/url
  init.py --uninstall-plugin <name>       uninstall a workspace plugin
  init.py --scaffold-plugin <name>        create a new plugin skeleton
  init.py --pack-plugin <dir>             validate + tar.gz a plugin dir
  init.py --upgrade-core                  upgrade the codenook-core skeleton
  init.py --refresh-models                re-probe model catalog (resets 30d TTL)
  init.py --version                       print core version
  init.py --help                          show this help

All non-meta subcommands are stubs in M1 (exit 2: TODO).
"""


def usage() -> None:
    sys.stdout.write(USAGE)


def stub(label: str) -> None:
    sys.stderr.write(f"TODO: {label} not implemented in M1 skeleton\n")
    sys.exit(2)


def main(argv: list[str]) -> int:
    if not argv:
        usage()
        return 0
    cmd = argv[0]
    if cmd in ("--help", "-h"):
        usage()
        return 0
    if cmd == "--version":
        try:
            sys.stdout.write(VERSION_FILE.read_text(encoding="utf-8"))
        except OSError as exc:
            sys.stderr.write(f"init.py: cannot read VERSION: {exc}\n")
            return 2
        return 0
    if cmd == "--install-plugin":
        stub("--install-plugin")
    if cmd in ("--uninstall-plugin", "--remove-plugin"):
        stub("--uninstall-plugin")
    if cmd == "--scaffold-plugin":
        stub("--scaffold-plugin")
    if cmd == "--pack-plugin":
        stub("--pack-plugin")
    if cmd == "--upgrade-core":
        stub("--upgrade-core")
    if cmd == "--refresh-models":
        ws = Path(os.getcwd())
        if not (ws / ".codenook").is_dir():
            sys.stderr.write(
                f"init.py: no .codenook/ in {ws} (run from a workspace root)\n"
            )
            return 2
        probe = SELF_DIR / "skills" / "builtin" / "model-probe" / "probe.py"
        if not probe.exists():
            probe = SELF_DIR / "skills" / "builtin" / "model-probe" / "probe.sh"
        if not probe.exists() or not os.access(probe, os.X_OK):
            sys.stderr.write(f"init.py: model-probe not found: {probe}\n")
            return 2
        os.execv(
            str(probe),
            [str(probe), "--output-state-json", str(ws / ".codenook" / "state.json")],
        )

    sys.stderr.write(f"unknown subcommand: {cmd}\n")
    sys.stderr.write(USAGE)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
