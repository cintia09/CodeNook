#!/usr/bin/env python3
"""Gate G10 — plugin-shebang-scan."""
from __future__ import annotations

import json
import os
import stat
import sys
from pathlib import Path

GATE = "plugin-shebang-scan"
ALLOWED = {
    "#!/bin/sh",
    "#!/bin/bash",
    "#!/usr/bin/env bash",
    "#!/usr/bin/env python3",
}
EXEC_BITS = stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH


def main() -> int:
    src = Path(os.environ["CN_SRC"]).resolve()
    json_out = os.environ.get("CN_JSON", "0") == "1"
    reasons: list[str] = []

    for root, dirs, files in os.walk(src, followlinks=False):
        for name in files:
            p = Path(root) / name
            if p.is_symlink():
                continue
            try:
                st = p.lstat()
            except OSError:
                continue
            if not stat.S_ISREG(st.st_mode):
                continue
            if not (st.st_mode & EXEC_BITS):
                continue
            try:
                with open(p, "rb") as f:
                    head = f.readline(256)
            except OSError as e:
                reasons.append(f"cannot read executable: {p.relative_to(src)}: {e}")
                continue
            try:
                first = head.rstrip(b"\r\n").decode("ascii")
            except UnicodeDecodeError:
                reasons.append(
                    f"executable {p.relative_to(src)} is not text "
                    f"(no readable shebang)"
                )
                continue
            if not first.startswith("#!"):
                reasons.append(
                    f"executable {p.relative_to(src)} has no shebang"
                )
                continue
            if first not in ALLOWED:
                reasons.append(
                    f"executable {p.relative_to(src)} has disallowed shebang: {first}"
                )

    return _emit(json_out, reasons)


def _emit(json_out: bool, reasons: list[str]) -> int:
    ok = not reasons
    if json_out:
        print(json.dumps({"ok": ok, "gate": GATE, "reasons": reasons}))
    else:
        for r in reasons:
            print(f"[G10] {r}", file=sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
