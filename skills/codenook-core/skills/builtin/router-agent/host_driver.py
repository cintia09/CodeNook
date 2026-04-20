#!/usr/bin/env python3
"""router-agent/host_driver.py — minimal LLM driver for plain-shell / CI use.

Background (E2E-002):
    `spawn.sh` is intentionally LLM-less — it only renders the per-turn
    prompt to ``.codenook/tasks/<task>/.router-prompt.md`` and hands
    control back to a host (Claude Code / Copilot CLI) that knows how
    to read the prompt, call the LLM, and write back ``router-reply.md``.

    Plain-shell users and CI scripts don't have such a host. This driver
    closes that gap: it reads ``.router-prompt.md``, dispatches via the
    shared ``llm_call.call_llm`` adapter (defaults to ``CN_LLM_MODE=mock``;
    set ``CN_LLM_MODE=real`` to shell out to the configured CLI driver
    such as ``claude --print --no-stream``), and writes the response to
    ``router-reply.md`` so the orchestrator can resume.

CLI contract::

    host_driver.py --task-id <id> --workspace <ws> [--mode mock|real]
                   [--call-name router] [--system <text>]

Exit codes::

    0  reply written
    1  prompt missing / LLM call failed
    2  usage / IO error

Hosted environments (Claude Code, Copilot CLI) should NOT use this
driver — they already drive the loop natively.
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_LIB = _HERE.parent / "_lib"
sys.path.insert(0, str(_LIB))

from llm_call import call_llm  # noqa: E402


def _task_dir(workspace: Path, task_id: str) -> Path:
    return workspace / ".codenook" / "tasks" / task_id


def drive(workspace: Path, task_id: str, *, mode: str | None = None,
          call_name: str = "router", system: str | None = None) -> int:
    tdir = _task_dir(workspace, task_id)
    prompt_path = tdir / ".router-prompt.md"
    reply_path = tdir / "router-reply.md"

    if not prompt_path.is_file():
        print(f"host_driver: prompt missing: {prompt_path}", file=sys.stderr)
        return 1

    prompt = prompt_path.read_text(encoding="utf-8")
    try:
        reply = call_llm(prompt, call_name=call_name, system=system, mode=mode)
    except Exception as e:  # noqa: BLE001 — surface any provider error
        print(f"host_driver: llm call failed: {e}", file=sys.stderr)
        return 1

    reply_path.write_text(reply if reply.endswith("\n") else reply + "\n",
                          encoding="utf-8")
    print(str(reply_path))
    return 0


def cli_main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(prog="router-agent/host_driver",
                                description=__doc__.split("\n\n", 1)[0])
    p.add_argument("--task-id", required=True)
    p.add_argument("--workspace", required=True)
    p.add_argument("--mode", default=None,
                   help="LLM mode (mock|real). Falls back to CN_LLM_MODE.")
    p.add_argument("--call-name", default="router")
    p.add_argument("--system", default=None)
    args = p.parse_args(argv)

    ws = Path(args.workspace).resolve()
    if not ws.is_dir():
        print(f"host_driver: workspace not a directory: {ws}", file=sys.stderr)
        return 2
    return drive(ws, args.task_id, mode=args.mode,
                 call_name=args.call_name, system=args.system)


if __name__ == "__main__":  # pragma: no cover
    sys.exit(cli_main(sys.argv[1:]))
