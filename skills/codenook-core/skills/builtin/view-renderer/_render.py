"""view-renderer/_render.py — the prepare envelope emitter.

Reads a single HITL queue entry, locates the role's phase output
markdown, and emits a JSON envelope on stdout. The host LLM then
produces the reviewer.html + reviewer.ansi outputs to the paths
specified in the envelope.

Pure stdlib; no LLM call here (that's the host's job).
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

_VALID_EID = re.compile(r"^[A-Za-z0-9_.\-]+$")


def _abort(msg: str, code: int = 2) -> int:
    print(f"render.sh: {msg}", file=sys.stderr)
    return code


def cmd_prepare(ws: Path, eid: str) -> int:
    if not eid:
        return _abort("--id is required")
    if not _VALID_EID.match(eid):
        return _abort(f"invalid --id: {eid!r}")

    entry_path = ws / ".codenook" / "hitl-queue" / f"{eid}.json"
    if not entry_path.is_file():
        # entry may already be _consumed/, but we only render pending
        return _abort(f"hitl entry not found: {eid}")

    try:
        entry = json.loads(entry_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        return _abort(f"hitl entry is not valid JSON: {e}")

    cp = entry.get("context_path") or ""
    context_text = ""
    if cp and not os.path.isabs(cp):
        try:
            target = (ws / cp).resolve()
            target.relative_to(ws.resolve())
            if target.is_file():
                context_text = target.read_text(encoding="utf-8")
        except ValueError:
            pass

    here = Path(__file__).resolve().parent
    queue_dir = ws / ".codenook" / "hitl-queue"
    envelope = {
        "eid": eid,
        "task_id": entry.get("task_id") or "",
        "gate": entry.get("gate") or "",
        "context_path": cp,
        "context": context_text,
        "html_out": str((queue_dir / f"{eid}.reviewer.html").relative_to(ws)),
        "ansi_out": str((queue_dir / f"{eid}.reviewer.ansi").relative_to(ws)),
        "html_template": str(here / "templates" / "reviewer.html.template"),
        "prompt_template": str(here / "templates" / "prompt.md"),
    }
    sys.stdout.write(json.dumps(envelope, ensure_ascii=False, indent=2))
    sys.stdout.write("\n")
    return 0


def main() -> None:
    sub = os.environ.get("CN_SUBCMD", "")
    ws = Path(os.environ.get("CN_WORKSPACE", "")).resolve()
    if not ws.is_dir():
        sys.exit(_abort(f"workspace not a directory: {ws}"))
    eid = os.environ.get("CN_ID", "")
    if sub == "prepare":
        sys.exit(cmd_prepare(ws, eid))
    sys.exit(_abort(f"unknown subcommand: {sub!r}"))


if __name__ == "__main__":
    main()
