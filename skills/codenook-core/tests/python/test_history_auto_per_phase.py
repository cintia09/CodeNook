"""v0.29.0 — `codenook tick` auto-snapshots task history per phase advance.

The orchestrator-tick.after_phase() hook delegates to
history.snapshot_task_phase(). This test exercises the helper directly
(the integration path is covered by test_python_entries / cli_smoke).
"""
from __future__ import annotations

import json
from pathlib import Path

import history


def _task_ws(tmp_path: Path, task_id: str = "T-001") -> Path:
    troot = tmp_path / ".codenook" / "tasks" / task_id
    troot.mkdir(parents=True)
    (troot / "state.json").write_text(json.dumps({
        "task_id": task_id,
        "phase": "design",
        "history": [{"ts": "2025-01-01T00:00:00Z", "phase": "design",
                     "verdict": "ok"}],
    }), encoding="utf-8")
    return tmp_path


def test_snapshot_task_phase_creates_dir_with_meta_and_body(tmp_path: Path):
    ws = _task_ws(tmp_path)
    snap = history.snapshot_task_phase(
        workspace=ws, task_id="T-001", phase="design", status="advanced")
    assert snap is not None and snap.is_dir()
    assert snap.parent == ws / ".codenook" / "tasks" / "T-001" / "history"
    meta = json.loads((snap / "meta.json").read_text(encoding="utf-8"))
    assert meta["scope"] == "task"
    assert meta["kind"] == "auto"
    assert meta["task_id"] == "T-001"
    assert meta["phase"] == "design"
    assert meta["status"] == "advanced"
    body = (snap / "content.md").read_text(encoding="utf-8")
    assert "design" in body
    # Body includes the last state.history entry as JSON.
    assert "verdict" in body and "ok" in body


def test_snapshot_task_phase_returns_none_for_missing_task(tmp_path: Path):
    snap = history.snapshot_task_phase(
        workspace=tmp_path, task_id="T-999",
        phase="design", status="advanced")
    assert snap is None


def test_snapshot_task_phase_filters_status(tmp_path: Path):
    """Only advanced/done/blocked statuses are auto-snapshotted by
    after_phase, but the helper itself snapshots whatever it's given —
    callers (the tick hook) gate it. Verify the helper is permissive."""
    ws = _task_ws(tmp_path)
    snap = history.snapshot_task_phase(
        workspace=ws, task_id="T-001", phase="clarify", status="done")
    assert snap is not None and snap.is_dir()


def test_after_phase_hook_writes_task_snapshot(tmp_path: Path):
    """End-to-end: orchestrator-tick.after_phase() -> task history dir."""
    import _tick as tick  # type: ignore
    ws = _task_ws(tmp_path)
    tick.after_phase(ws, "T-001", "design", "advanced")
    history_dir = ws / ".codenook" / "tasks" / "T-001" / "history"
    assert history_dir.is_dir()
    snaps = list(history_dir.iterdir())
    assert len(snaps) == 1
    assert (snaps[0] / "meta.json").is_file()
