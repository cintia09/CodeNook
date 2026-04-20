"""``codenook router`` — delegates to router-agent/render_prompt.py."""
from __future__ import annotations

import sys
from typing import Sequence

from . import _subproc
from .config import CodenookContext


def run(ctx: CodenookContext, args: Sequence[str]) -> int:
    task = user_turn = ""
    it = iter(args)
    try:
        for a in it:
            if a == "--task":
                task = next(it)
            elif a == "--user-turn":
                user_turn = next(it)
            else:
                sys.stderr.write(f"codenook router: unknown arg: {a}\n")
                return 2
    except StopIteration:
        sys.stderr.write("codenook router: missing value for last flag\n")
        return 2

    if not task:
        sys.stderr.write("codenook router: --task required\n")
        return 2
    if not user_turn:
        sys.stderr.write("codenook router: --user-turn required\n")
        return 2

    helper = ctx.kernel_dir / "router-agent" / "render_prompt.py"
    if not helper.is_file():
        sys.stderr.write(f"codenook router: helper missing: {helper}\n")
        return 1

    cp = _subproc.run_helper(
        ctx, helper,
        args=["--task-id", task, "--workspace", str(ctx.workspace),
              "--user-turn", user_turn],
    )
    return cp.returncode
