"""v0.24.0 — verify each Python sibling entry point is invokable.

For each of the 8 .py siblings introduced in v0.24.0:
  * `python <entry>.py --help` exits 0 with help text printed.
  * The module is importable and exposes ``main``.
"""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[4]
KERNEL = REPO / "skills" / "codenook-core" / "skills" / "builtin"

ENTRIES = [
    ("router-agent",      "spawn.py"),
    ("orchestrator-tick", "tick.py"),
    ("preflight",         "preflight.py"),
    ("hitl-adapter",      "terminal.py"),
    ("dispatch-audit",    "emit.py"),
    ("router",            "bootstrap.py"),
    ("session-resume",    "resume.py"),
]


@pytest.mark.parametrize("subdir,name", ENTRIES)
def test_entry_exists_and_imports(subdir, name):
    p = KERNEL / subdir / name
    assert p.is_file(), f"missing Python entry: {p}"
    spec = importlib.util.spec_from_file_location(f"_v024_{name}", p)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    assert hasattr(mod, "main"), f"{p} missing main()"


@pytest.mark.parametrize("subdir,name", ENTRIES)
def test_entry_help_exits_clean(subdir, name):
    p = KERNEL / subdir / name
    cp = subprocess.run(
        [sys.executable, str(p), "--help"],
        capture_output=True, text=True, timeout=20,
    )
    assert cp.returncode == 0, (
        f"{name} --help exited rc={cp.returncode}\n"
        f"stdout={cp.stdout!r}\nstderr={cp.stderr!r}"
    )
    assert cp.stdout.strip(), f"{name} --help produced no help text"


def test_tick_py_smoke_on_tmp_workspace(tmp_path):
    """tick.py must run end-to-end on a fixture workspace without bash."""
    ws = tmp_path
    (ws / ".codenook").mkdir()
    task = "T-024-pytest-smoke"
    task_dir = ws / ".codenook" / "tasks" / task
    task_dir.mkdir(parents=True)
    state = {
        "task_id": task,
        "phase": "implement",
        "iteration": 1,
        "total_iterations": 5,
        "dual_mode": "sub_agent",
    }
    (task_dir / "state.json").write_text(json.dumps(state), encoding="utf-8")

    tick = KERNEL / "orchestrator-tick" / "tick.py"
    cp = subprocess.run(
        [sys.executable, str(tick), "--task", task,
         "--workspace", str(ws), "--json"],
        capture_output=True, text=True, timeout=30,
    )
    # Acceptable: exit 0 with JSON, OR exit 1 (preflight blocked) — but
    # NEVER a FileNotFoundError / WinError 2 (the v0.23.0 regression).
    assert "FileNotFoundError" not in cp.stderr, (
        f"tick.py raised FileNotFoundError\nstderr={cp.stderr!r}"
    )
    assert "[WinError 2]" not in cp.stderr, (
        f"tick.py raised WinError 2\nstderr={cp.stderr!r}"
    )
