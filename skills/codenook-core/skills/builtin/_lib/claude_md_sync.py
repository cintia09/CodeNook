#!/usr/bin/env python3
"""Idempotently sync the CodeNook bootloader block in a workspace CLAUDE.md.

Wraps the bootloader between explicit ``<!-- codenook:begin -->`` and
``<!-- codenook:end -->`` markers. Re-running replaces the block in
place; user content outside the markers is never touched. When no
CLAUDE.md exists, a stub is created containing only the block.

Used by the top-level ``install.sh`` (DR-006).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

BEGIN = "<!-- codenook:begin -->"
END = "<!-- codenook:end -->"


def render_block(version: str, plugin: str) -> str:
    return f"""{BEGIN}
<!-- DO NOT EDIT BY HAND. Managed by `bash install.sh`. To remove this block,
     re-run install.sh with --no-claude-md and delete the markers manually. -->

## CodeNook v{version} bootloader

This workspace has the CodeNook plugin **`{plugin}`** installed. To start
working with multi-agent flows, invoke the **`router-agent`** skill from
your Claude Code or Copilot CLI session at the start of every turn:

> "Use the router-agent skill to ingest this turn against `.codenook/`."

The router agent reads:

- `.codenook/state.json` — installed plugins
- `.codenook/plugins/{plugin}/` — read-only phase prompts and roles
- `.codenook/memory/` — knowledge / skills / config / history
- `.codenook/tasks/<task_id>/` — per-task state, prompts, audit log

…then dispatches the next phase via `dispatch_subagent` and writes back
to `.codenook/tasks/` only. **Plugin and source files are read-only.**

For the live status of init.sh subcommands and the install flow, see the
project README and `docs/architecture.md`.
{END}
"""


def sync(workspace: Path, version: str, plugin: str) -> None:
    claude = workspace / "CLAUDE.md"
    block = render_block(version, plugin)

    if not claude.exists():
        claude.write_text(block + "\n", encoding="utf-8")
        return

    text = claude.read_text(encoding="utf-8")
    bi = text.find(BEGIN)
    ei = text.find(END)

    if bi != -1 and ei != -1 and ei > bi:
        # Replace existing block (idempotent — second run = zero diff).
        ei_end = ei + len(END)
        new_text = text[:bi] + block.rstrip("\n") + text[ei_end:]
        if new_text != text:
            claude.write_text(new_text, encoding="utf-8")
        return

    if bi != -1 or ei != -1:
        # Half-open marker — refuse rather than corrupt user content.
        raise SystemExit(
            "claude_md_sync: CLAUDE.md has an unbalanced codenook marker; "
            "fix manually before re-running."
        )

    # No block yet → append, preserving existing content.
    sep = "" if text.endswith("\n") else "\n"
    claude.write_text(text + sep + "\n" + block + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--workspace", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--plugin", required=True)
    args = p.parse_args(argv)
    ws = Path(args.workspace).resolve()
    if not ws.is_dir():
        print(f"claude_md_sync: not a directory: {ws}", file=sys.stderr)
        return 2
    sync(ws, args.version, args.plugin)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
