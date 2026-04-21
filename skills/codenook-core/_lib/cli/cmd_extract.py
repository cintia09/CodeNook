"""``codenook extract`` — fan out memory extractors for a task phase
or a context-pressure event.

This is a thin wrapper around ``extractor-batch/extractor-batch.sh``
so the main session never needs to invoke the bash script directly.
The underlying contract is unchanged (idempotent on
``(task, phase, reason)``, exit 0 best-effort, single JSON object on
stdout).

Usage::

    codenook extract --task T-NNN --reason after_phase --phase clarify
    codenook extract --task T-NNN --reason context-pressure
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from typing import Sequence

from .config import CodenookContext


def _resolve_bash() -> str | None:
    """Locate bash via the kernel's sh_run.find_bash helper, with a
    PATH fallback if the helper module is not importable."""
    try:
        from pathlib import Path as _P
        import sys as _sys
        _lib = _P(__file__).resolve().parents[2] / "skills" / "builtin" / "_lib"
        if str(_lib) not in _sys.path:
            _sys.path.insert(0, str(_lib))
        from sh_run import find_bash  # type: ignore
        return find_bash()
    except Exception:
        return shutil.which("bash")

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

    helper = ctx.kernel_dir / "extractor-batch" / "extractor-batch.sh"
    if not helper.is_file():
        sys.stderr.write(f"codenook extract: helper missing: {helper}\n")
        return 1

    bash = _resolve_bash()
    if bash is None:
        sys.stderr.write(
            "codenook extract: bash not found (tried $CN_BASH, PATH, and "
            "well-known Windows install locations); install Git for Windows "
            "or set CN_BASH to a bash.exe path\n"
        )
        return 1

    cmd = [
        bash,
        str(helper),
        "--task-id", task,
        "--reason", reason,
        "--workspace", str(ctx.workspace),
    ]
    if phase:
        cmd += ["--phase", phase]

    env = os.environ.copy()
    env["CODENOOK_WORKSPACE"] = str(ctx.workspace)
    env["CN_WORKSPACE"] = str(ctx.workspace)

    cp = subprocess.run(cmd, env=env, text=True)
    return cp.returncode
