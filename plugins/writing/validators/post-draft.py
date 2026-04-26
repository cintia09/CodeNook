#!/usr/bin/env python3
"""validators/post-draft.py — mechanical post-condition check.

Verifies the expected output file exists and has YAML frontmatter
with a verdict field.

Usage: post-draft.py <task_id>
CWD == workspace root.
"""
from __future__ import annotations
import sys
from pathlib import Path


def main(argv=None) -> int:
    args = (argv if argv is not None else sys.argv)[1:]
    if not args:
        print("usage: post-draft.py <task_id>", file=sys.stderr)
        return 2
    tid = args[0]
    out = Path(f".codenook/tasks/$TID/outputs/phase-2-drafter.md".replace("$TID", tid))
    if not out.is_file():
        print(f"post-draft: missing {out}", file=sys.stderr)
        return 1
    with out.open(encoding="utf-8", errors="replace") as fh:
        for i, line in enumerate(fh):
            if i >= 10:
                break
            if line.startswith("verdict:"):
                return 0
    print(f"post-draft: {out} lacks verdict frontmatter", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
