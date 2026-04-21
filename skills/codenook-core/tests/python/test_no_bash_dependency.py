"""v0.24.0 — verify the kernel never requires bash on PATH.

Strategy: monkey-patch shutil.which / sh_run.find_bash to behave as if
bash is missing, then exercise key kernel-internal paths (preflight emit,
extractor-batch dispatch). None must raise FileNotFoundError or fall
through to subprocess('bash', ...).
"""
from __future__ import annotations

import importlib
import json
import os
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[4]
KERNEL = REPO / "skills" / "codenook-core" / "skills" / "builtin"


def _add_to_path(p: Path) -> None:
    s = str(p)
    if s not in sys.path:
        sys.path.insert(0, s)


@pytest.fixture
def no_bash(monkeypatch):
    """Simulate a host where bash cannot be located anywhere."""
    monkeypatch.delenv("CN_BASH", raising=False)
    import shutil
    real_which = shutil.which

    def fake_which(cmd, *a, **k):
        if cmd in ("bash", "bash.exe"):
            return None
        return real_which(cmd, *a, **k)
    monkeypatch.setattr(shutil, "which", fake_which)

    _add_to_path(KERNEL / "_lib")
    import sh_run
    sh_run._reset_cache_for_tests()
    monkeypatch.setattr(sh_run, "_scan_well_known", lambda: None)
    yield
    sh_run._reset_cache_for_tests()


def test_preflight_module_importable():
    _add_to_path(KERNEL / "preflight")
    mod = importlib.import_module("_preflight")
    assert hasattr(mod, "run"), "_preflight.run() must be importable"


def test_emit_module_importable():
    _add_to_path(KERNEL / "dispatch-audit")
    mod = importlib.import_module("_emit")
    assert hasattr(mod, "run"), "_emit.run() must be importable"


def test_extractor_batch_module_importable():
    _add_to_path(KERNEL / "extractor-batch")
    mod = importlib.import_module("_extractor_batch")
    assert hasattr(mod, "run"), "_extractor_batch.run() must be importable"


def test_emit_run_works_without_bash(no_bash, tmp_path):
    _add_to_path(KERNEL / "dispatch-audit")
    import _emit
    ws = tmp_path
    (ws / ".codenook").mkdir()
    payload = json.dumps({"task": "T-024-smoke", "phase": "x"})
    rc = _emit.run(role="executor", payload=payload, workspace=ws)
    assert rc == 0
    log = ws / ".codenook" / "history" / "dispatch.jsonl"
    assert log.is_file()


def test_preflight_run_works_without_bash(no_bash, tmp_path):
    _add_to_path(KERNEL / "preflight")
    import _preflight
    ws = tmp_path
    task = "T-024-smoke"
    task_dir = ws / ".codenook" / "tasks" / task
    task_dir.mkdir(parents=True)
    state = {"task_id": task, "phase": "implement", "iteration": 1,
             "total_iterations": 5, "dual_mode": "sub_agent"}
    state_file = task_dir / "state.json"
    state_file.write_text(json.dumps(state), encoding="utf-8")
    rc, phase, reasons = _preflight.run(
        task=task, state_file=str(state_file),
        workspace=str(ws), json_out=True,
    )
    assert rc == 0, f"unexpected reasons: {reasons}"
    assert phase == "implement"


def test_extractor_batch_run_works_without_bash(no_bash, tmp_path):
    _add_to_path(KERNEL / "extractor-batch")
    import _extractor_batch
    ws = tmp_path
    (ws / ".codenook").mkdir()
    out = _extractor_batch.run(task_id="T-024-smoke", reason="after_phase",
                               workspace=ws, phase="implement")
    assert "enqueued_jobs" in out
    assert "skipped" in out


def test_after_phase_no_filenotfound_without_bash(no_bash, tmp_path,
                                                   monkeypatch):
    """Regression: v0.23.0 raised FileNotFoundError [WinError 2] here."""
    _add_to_path(KERNEL / "_lib")
    _add_to_path(KERNEL / "orchestrator-tick")
    monkeypatch.delenv("CN_EXTRACTOR_BATCH", raising=False)
    import _tick
    ws = tmp_path
    (ws / ".codenook").mkdir()
    # Should NOT raise FileNotFoundError nor [WinError 2].
    try:
        _tick.after_phase(ws, "T-024-smoke", "implement", "advanced")
    except FileNotFoundError as e:  # pragma: no cover
        pytest.fail(f"after_phase raised FileNotFoundError: {e}")
