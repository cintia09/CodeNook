#!/usr/bin/env python3
"""skill-resolve/_resolve_skill.py — 4-tier skill lookup."""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

SAFE_NAME_RE = re.compile(r"^[A-Za-z0-9._-]+$")


def die_usage(msg: str) -> None:
    print(f"resolve-skill.sh: invalid: {msg}", file=sys.stderr)
    sys.exit(2)


def main() -> None:
    name = os.environ["CN_NAME"]
    plugin = os.environ["CN_PLUGIN"]
    ws = Path(os.environ["CN_WORKSPACE"]).resolve()
    core = Path(os.environ["CN_CORE_DIR"]).resolve()

    if not SAFE_NAME_RE.match(name) or ".." in name:
        die_usage(f"unsafe skill name: {name!r}")
    if not SAFE_NAME_RE.match(plugin) or ".." in plugin:
        die_usage(f"unsafe plugin name: {plugin!r}")

    candidates: list[tuple[str, Path]] = [
        ("plugin_local",     ws / ".codenook/memory" / plugin / "skills" / name / "SKILL.md"),
        ("plugin_shipped",   ws / ".codenook/plugins" / plugin / "skills" / name / "SKILL.md"),
        ("workspace_custom", ws / ".codenook/skills/custom" / name / "SKILL.md"),
        ("builtin",          core / "skills/builtin" / name / "SKILL.md"),
    ]

    def contained(p: Path) -> bool:
        try:
            r = p.resolve()
        except OSError:
            return False
        s = str(r)
        return s.startswith(str(ws) + os.sep) or s.startswith(str(core) + os.sep)

    for tier, p in candidates:
        if p.is_file() and contained(p):
            print(json.dumps({
                "found": True,
                "name": name,
                "tier": tier,
                "path": str(p.resolve()),
            }, indent=2))
            return

    print(json.dumps({
        "found": False,
        "name": name,
        "candidates": [str(p) for _, p in candidates],
    }, indent=2))
    sys.exit(1)


if __name__ == "__main__":
    main()
