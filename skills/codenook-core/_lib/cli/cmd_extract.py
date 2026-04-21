"""``codenook extract`` — fan out memory extractors for a task phase
or a context-pressure event.

v0.24.0 — calls the in-process Python helper
``extractor-batch._extractor_batch.run`` directly. The legacy bash
``extractor-batch.sh`` is still present for Linux/Mac users who script
against it, but the kernel CLI no longer requires bash on PATH.

The contract is unchanged (idempotent on ``(task, phase, reason)``,
exit 0 best-effort, single JSON object on stdout).

Usage::

    codenook extract --task T-NNN --reason after_phase --phase clarify
    codenook extract --task T-NNN --reason context-pressure
"""
from __future__ import annotations

import json
import os
import sys
from typing import Sequence

from .config import CodenookContext


HELP = """\
codenook extract — fan out memory extractors

Usage:
  extract --task T-NNN --reason <reason> [--phase <phase>]

Reasons (free-form, common values):
  after_phase        a tick phase just completed
  context-pressure   the conductor is approaching its context window cap
"""


def run(ctx: CodenookContext, args: Sequence[str]) -> int:
    if not args or args[0] in ("-h", "--help"):
        print(HELP)
        return 0

    task = ""
    reason = ""
    phase = ""

    it = iter(args)
    try:
        for a in it:
            if a == "--task":
                task = next(it)
            elif a == "--reason":
                reason = next(it)
            elif a == "--phase":
                phase = next(it)
            else:
                sys.stderr.write(f"codenook extract: unknown arg: {a}\n")
                return 2
    except StopIteration:
        sys.stderr.write("codenook extract: missing value for last flag\n")
        return 2

    if not task:
        sys.stderr.write("codenook extract: --task required\n")
        return 2
    if not reason:
        sys.stderr.write("codenook extract: --reason required\n")
        return 2

    helper_py = ctx.kernel_dir / "extractor-batch" / "_extractor_batch.py"
    if not helper_py.is_file():
        sys.stderr.write(f"codenook extract: helper missing: {helper_py}\n")
        return 1

    # Direct in-process call (no bash subprocess).
    eb_dir = str(helper_py.parent)
    if eb_dir not in sys.path:
        sys.path.insert(0, eb_dir)
    try:
        import _extractor_batch  # type: ignore
        result = _extractor_batch.run(
            task_id=task, reason=reason, workspace=ctx.workspace, phase=phase,
        )
        sys.stdout.write(json.dumps(result, ensure_ascii=False) + "\n")
        return 0
    except Exception as e:
        sys.stderr.write(f"codenook extract: {type(e).__name__}: {e}\n")
        return 1
