"""Helpers for shelling out to the kernel's helper python scripts."""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from .config import CodenookContext


def kernel_env(ctx: CodenookContext, extra: dict | None = None) -> dict:
    env = os.environ.copy()
    env["PYTHONPATH"] = (
        str(ctx.kernel_lib)
        + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    )
    env["CODENOOK_WORKSPACE"] = str(ctx.workspace)
    env.setdefault("PYTHONUTF8", "1")
    env.setdefault("PYTHONIOENCODING", "utf-8")
    if extra:
        env.update({k: v for k, v in extra.items() if v is not None})
    return env


def run_helper(
    ctx: CodenookContext,
    helper: Path,
    *,
    args: list[str] | None = None,
    extra_env: dict | None = None,
    capture: bool = False,
) -> subprocess.CompletedProcess:
    """Run ``python <helper> [args...]`` with the kernel env."""
    cmd = [sys.executable, str(helper)]
    if args:
        cmd.extend(args)
    return subprocess.run(
        cmd,
        env=kernel_env(ctx, extra_env),
        text=True,
        capture_output=capture,
    )
