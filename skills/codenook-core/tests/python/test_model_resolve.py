"""v0.18 — model resolution chain + envelope wiring + CLI flow tests."""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[4]
CORE = REPO / "skills" / "codenook-core"
sys.path.insert(0, str(CORE))

from _lib import models  # noqa: E402
from _lib.cli import cmd_task  # noqa: E402
from _lib.cli.config import CodenookContext  # noqa: E402


def _ws(tmp_path: Path, plugin: str = "demo") -> Path:
    (tmp_path / ".codenook" / "tasks").mkdir(parents=True)
    (tmp_path / ".codenook" / "plugins" / plugin).mkdir(parents=True)
    return tmp_path


def _write(p: Path, body: str) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(body, encoding="utf-8")


# ────────────── resolve_model: layered priority chain ──────────────

def test_resolve_d_only_workspace(tmp_path: Path):
    ws = _ws(tmp_path)
    _write(ws / ".codenook" / "config.yaml", "default_model: ws-haiku\n")
    assert models.resolve_model(ws, "demo", "design", {}) == "ws-haiku"


def test_resolve_a_overrides_d(tmp_path: Path):
    ws = _ws(tmp_path)
    _write(ws / ".codenook" / "config.yaml", "default_model: ws-haiku\n")
    _write(ws / ".codenook" / "plugins" / "demo" / "plugin.yaml",
           "id: demo\nname: demo\nversion: 0.1\ndefault_model: plugin-sonnet\n")
    assert models.resolve_model(ws, "demo", "design", {}) == "plugin-sonnet"


def test_resolve_b_overrides_a(tmp_path: Path):
    ws = _ws(tmp_path)
    _write(ws / ".codenook" / "config.yaml", "default_model: ws-haiku\n")
    _write(ws / ".codenook" / "plugins" / "demo" / "plugin.yaml",
           "default_model: plugin-sonnet\n")
    _write(ws / ".codenook" / "plugins" / "demo" / "phases.yaml",
           "phases:\n  - id: design\n    role: x\n    model: phase-opus\n")
    assert models.resolve_model(ws, "demo", "design", {}) == "phase-opus"


def test_resolve_b_map_layout(tmp_path: Path):
    ws = _ws(tmp_path)
    _write(ws / ".codenook" / "plugins" / "demo" / "phases.yaml",
           "phases:\n  design:\n    role: x\n    model: phase-opus\n")
    assert models.resolve_model(ws, "demo", "design", {}) == "phase-opus"


def test_resolve_c_overrides_b(tmp_path: Path):
    ws = _ws(tmp_path)
    _write(ws / ".codenook" / "config.yaml", "default_model: ws-haiku\n")
    _write(ws / ".codenook" / "plugins" / "demo" / "plugin.yaml",
           "default_model: plugin-sonnet\n")
    _write(ws / ".codenook" / "plugins" / "demo" / "phases.yaml",
           "phases:\n  - id: design\n    model: phase-opus\n")
    state = {"model_override": "task-opus-4.7"}
    assert models.resolve_model(ws, "demo", "design", state) == "task-opus-4.7"


def test_resolve_all_absent_returns_none(tmp_path: Path):
    ws = _ws(tmp_path)
    assert models.resolve_model(ws, "demo", "design", {}) is None


def test_resolve_empty_string_treated_as_unset(tmp_path: Path):
    ws = _ws(tmp_path)
    _write(ws / ".codenook" / "config.yaml", "default_model: ws-haiku\n")
    state = {"model_override": ""}
    assert models.resolve_model(ws, "demo", "design", state) == "ws-haiku"


# ────────────── envelope construction (cmd_tick._augment_envelope) ──

def test_envelope_includes_model_when_resolved(tmp_path: Path):
    """End-to-end: state.json model_override → envelope.model field."""
    ws = _ws(tmp_path)
    task = "T-001"
    tdir = ws / ".codenook" / "tasks" / task
    tdir.mkdir(parents=True, exist_ok=True)
    state = {
        "schema_version": 1,
        "task_id": task,
        "plugin": "demo",
        "phase": "design",
        "iteration": 0,
        "max_iterations": 3,
        "status": "in_progress",
        "history": [],
        "model_override": "task-opus-4.7",
        "in_flight_agent": {
            "agent_id": "ag1",
            "role": "designer",
            "dispatched_at": "2025-01-01T00:00:00Z",
            "expected_output": ".codenook/tasks/T-001/outputs/phase-1-designer.md",
        },
    }
    (tdir / "state.json").write_text(json.dumps(state), encoding="utf-8")

    from _lib.cli import cmd_tick
    ctx = CodenookContext(
        workspace=ws,
        state_file=tdir / "state.json",
        state={},
        kernel_dir=CORE / "skills" / "builtin",
    )
    tick_out = json.dumps({"status": "advanced", "next_action": "dispatched designer"})
    augmented = cmd_tick._augment_envelope(ctx, task, tick_out)
    summary = json.loads(augmented)
    assert summary["envelope"]["model"] == "task-opus-4.7"


def test_envelope_omits_model_when_unset(tmp_path: Path):
    ws = _ws(tmp_path)
    task = "T-002"
    tdir = ws / ".codenook" / "tasks" / task
    tdir.mkdir(parents=True, exist_ok=True)
    state = {
        "schema_version": 1,
        "task_id": task,
        "plugin": "demo",
        "phase": "design",
        "iteration": 0,
        "max_iterations": 3,
        "status": "in_progress",
        "history": [],
        "in_flight_agent": {
            "agent_id": "ag1",
            "role": "designer",
            "dispatched_at": "2025-01-01T00:00:00Z",
            "expected_output": ".codenook/tasks/T-002/outputs/phase-1-designer.md",
        },
    }
    (tdir / "state.json").write_text(json.dumps(state), encoding="utf-8")

    from _lib.cli import cmd_tick
    ctx = CodenookContext(
        workspace=ws,
        state_file=tdir / "state.json",
        state={},
        kernel_dir=CORE / "skills" / "builtin",
    )
    tick_out = json.dumps({"status": "advanced", "next_action": "dispatched designer"})
    augmented = cmd_tick._augment_envelope(ctx, task, tick_out)
    summary = json.loads(augmented)
    assert "model" not in summary["envelope"]


# ────────────── CLI: task new --model / task set-model ────────────

def _ctx(ws: Path) -> CodenookContext:
    return CodenookContext(
        workspace=ws,
        state_file=ws / ".codenook" / "state.json",
        state={"installed_plugins": [{"id": "demo"}]},
        kernel_dir=CORE / "skills" / "builtin",
    )


def test_task_new_model_writes_state(tmp_path: Path, capsys):
    ws = _ws(tmp_path)
    rc = cmd_task.run(_ctx(ws), [
        "new", "--title", "T", "--accept-defaults",
        "--id", "T-100", "--model", "claude-opus-4.7",
    ])
    assert rc == 0
    sf = ws / ".codenook" / "tasks" / "T-100" / "state.json"
    state = json.loads(sf.read_text(encoding="utf-8"))
    assert state["model_override"] == "claude-opus-4.7"


def test_task_set_model_then_clear(tmp_path: Path):
    ws = _ws(tmp_path)
    cmd_task.run(_ctx(ws), [
        "new", "--title", "T", "--accept-defaults", "--id", "T-101"])
    sf = ws / ".codenook" / "tasks" / "T-101" / "state.json"
    assert "model_override" not in json.loads(sf.read_text())

    rc = cmd_task.run(_ctx(ws), [
        "set-model", "--task", "T-101", "--model", "opus-x"])
    assert rc == 0
    assert json.loads(sf.read_text())["model_override"] == "opus-x"

    rc = cmd_task.run(_ctx(ws), [
        "set-model", "--task", "T-101", "--clear"])
    assert rc == 0
    assert "model_override" not in json.loads(sf.read_text())


def test_task_set_model_requires_one_of(tmp_path: Path):
    ws = _ws(tmp_path)
    cmd_task.run(_ctx(ws), [
        "new", "--title", "T", "--accept-defaults", "--id", "T-102"])
    rc = cmd_task.run(_ctx(ws), ["set-model", "--task", "T-102"])
    assert rc == 2
    rc = cmd_task.run(_ctx(ws), [
        "set-model", "--task", "T-102", "--model", "x", "--clear"])
    assert rc == 2


def test_task_new_help_mentions_model(capsys):
    rc = cmd_task.run(_ctx(Path.cwd()), ["new", "--help"])
    assert rc == 0
    out = capsys.readouterr().out
    assert "--model" in out
