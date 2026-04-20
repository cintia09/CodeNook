"""``codenook decide`` — resolve the pending HITL gate for a (task, phase)."""
from __future__ import annotations

import getpass
import glob
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Sequence

import yaml  # type: ignore[import-untyped]

from . import _subproc
from .config import CodenookContext


def run(ctx: CodenookContext, args: Sequence[str]) -> int:
    task = phase = decision = comment = ""
    it = iter(args)
    try:
        for a in it:
            if a == "--task":
                task = next(it)
            elif a == "--phase":
                phase = next(it)
            elif a == "--decision":
                decision = next(it)
            elif a == "--comment":
                comment = next(it)
            else:
                sys.stderr.write(f"codenook decide: unknown arg: {a}\n")
                return 2
    except StopIteration:
        sys.stderr.write("codenook decide: missing value for last flag\n")
        return 2

    if not (task and phase and decision):
        sys.stderr.write(
            "codenook decide: --task, --phase, --decision required\n")
        return 2

    state_p = ctx.workspace / ".codenook" / "tasks" / task / "state.json"
    if not state_p.is_file():
        sys.stderr.write(f"codenook decide: no such task: {task}\n")
        return 1
    plugin = json.loads(state_p.read_text(encoding="utf-8")).get("plugin") or ""

    gate = phase
    phases_yaml = ctx.workspace / ".codenook" / "plugins" / plugin / "phases.yaml"
    if phases_yaml.is_file():
        try:
            phases = (yaml.safe_load(phases_yaml.read_text(encoding="utf-8"))
                      or {}).get("phases", []) or []
            for p in phases:
                if p.get("id") == phase:
                    gate = p.get("gate") or phase
                    break
        except Exception:
            pass

    qdir = ctx.workspace / ".codenook" / "hitl-queue"
    entry_id = ""
    if qdir.is_dir():
        for p in sorted(qdir.glob("*.json")):
            try:
                e = json.loads(p.read_text(encoding="utf-8"))
            except Exception:
                continue
            if (e.get("task_id") == task
                    and e.get("gate") == gate
                    and not e.get("decision")):
                entry_id = e.get("id") or ""
                break

    if not entry_id:
        sys.stderr.write(
            f"codenook decide: no pending HITL entry for task={task} "
            f"phase={phase} (gate={gate})\n")
        return 1

    helper = ctx.kernel_dir / "hitl-adapter" / "_hitl.py"
    reviewer = os.environ.get("USER") or getpass.getuser() or "cli"
    extra = {
        "CN_SUBCMD": "decide",
        "CN_ID": entry_id,
        "CN_DECISION": decision,
        "CN_REVIEWER": reviewer,
        "CN_COMMENT": comment,
        "CN_WORKSPACE": str(ctx.workspace),
        "CN_JSON": "0",
    }
    cp = subprocess.run(
        [sys.executable, str(helper)],
        env=_subproc.kernel_env(ctx, extra),
        text=True,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
    )
    sys.stderr.write(cp.stderr)
    if cp.returncode != 0:
        return cp.returncode
    print(json.dumps({
        "id": entry_id, "task": task, "phase": phase,
        "gate": gate, "decision": decision,
    }))
    return 0
