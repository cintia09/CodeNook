"""``codenook chain <link|show|detach>`` — delegates to ``task_chain``."""
from __future__ import annotations

import json
import subprocess
import sys
from typing import Sequence

from . import _subproc
from .config import CodenookContext, is_safe_task_component


def run(ctx: CodenookContext, args: Sequence[str]) -> int:
    if not args:
        sys.stderr.write(
            "codenook chain: subcommand required (link|show|detach)\n")
        return 2
    sub, rest = args[0], list(args[1:])

    if sub in ("link", "attach"):
        child = parent = ""
        force_flag: list[str] = []
        it = iter(rest)
        try:
            for a in it:
                if a == "--child":
                    child = next(it)
                elif a == "--parent":
                    parent = next(it)
                elif a == "--force":
                    force_flag = ["--force"]
                else:
                    sys.stderr.write(f"codenook chain link: unknown arg: {a}\n")
                    return 2
        except StopIteration:
            sys.stderr.write("codenook chain link: missing value for last flag\n")
            return 2
        if not (child and parent):
            sys.stderr.write(
                "codenook chain link: --child and --parent required\n")
            return 2
        if not is_safe_task_component(child):
            sys.stderr.write(
                f"codenook chain link: invalid --child (path traversal "
                f"rejected): {child!r}\n")
            return 2
        if not is_safe_task_component(parent):
            sys.stderr.write(
                f"codenook chain link: invalid --parent (path traversal "
                f"rejected): {parent!r}\n")
            return 2

        cp = subprocess.run(
            [sys.executable, "-m", "task_chain",
             "--workspace", str(ctx.workspace),
             "attach", child, parent, *force_flag],
            env=_subproc.kernel_env(ctx),
            text=True,
        )
        sf = ctx.workspace / ".codenook" / "tasks" / child / "state.json"
        if sf.is_file():
            try:
                d = json.loads(sf.read_text(encoding="utf-8"))
                print(json.dumps({
                    "child": d.get("task_id"),
                    "parent_id": d.get("parent_id"),
                    "chain_root": d.get("chain_root"),
                }))
            except Exception:
                pass
        return cp.returncode

    if sub == "show":
        cp = subprocess.run(
            [sys.executable, "-m", "task_chain",
             "--workspace", str(ctx.workspace), "show", *rest],
            env=_subproc.kernel_env(ctx),
            text=True,
        )
        return cp.returncode

    if sub == "detach":
        cp = subprocess.run(
            [sys.executable, "-m", "task_chain",
             "--workspace", str(ctx.workspace), "detach", *rest],
            env=_subproc.kernel_env(ctx),
            text=True,
        )
        return cp.returncode

    sys.stderr.write(f"codenook chain: unknown subcommand: {sub}\n")
    sys.stderr.write("  use: link | show | detach\n")
    return 2
