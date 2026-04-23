"""Regression tests for v0.27.20 — `codenook task show`."""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[4]
INSTALL_PY = REPO_ROOT / "install.py"


def _run(cmd: list[str], cwd: Path | None = None,
         env: dict | None = None) -> subprocess.CompletedProcess:
    e = os.environ.copy()
    e["PYTHONUTF8"] = "1"
    e["PYTHONIOENCODING"] = "utf-8"
    if env:
        e.update(env)
    return subprocess.run(cmd, cwd=str(cwd) if cwd else None,
                          env=e, text=True, capture_output=True,
                          encoding="utf-8", errors="replace")


@pytest.fixture(scope="module")
def ws(tmp_path_factory) -> Path:
    d = tmp_path_factory.mktemp("cn_v1720")
    cp = _run([sys.executable, str(INSTALL_PY), "--target", str(d), "--yes"])
    assert cp.returncode == 0, cp.stderr
    return d


def _bin(ws: Path) -> list[str]:
    if sys.platform == "win32":
        return [str(ws / ".codenook" / "bin" / "codenook.cmd")]
    return [sys.executable, str(ws / ".codenook" / "bin" / "codenook")]


def _seed_task(ws: Path, tid: str, state: dict) -> None:
    td = ws / ".codenook" / "tasks" / tid
    td.mkdir(parents=True, exist_ok=True)
    state.setdefault("task_id", tid)
    (td / "state.json").write_text(
        json.dumps(state, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def test_task_show_missing_id(ws: Path) -> None:
    cp = _run(_bin(ws) + ["task", "show"])
    assert cp.returncode == 2, (cp.stdout, cp.stderr)
    assert "required" in cp.stderr


def test_task_show_unknown_task(ws: Path) -> None:
    cp = _run(_bin(ws) + ["task", "show", "T-777"])
    assert cp.returncode == 1, (cp.stdout, cp.stderr)
    assert "no such task" in cp.stderr


def test_task_show_human_basic(ws: Path) -> None:
    _seed_task(ws, "T-010-show-basic", {
        "title": "widget prototype",
        "summary": "build the thing",
        "plugin": "development",
        "profile": "feature",
        "phase": "design",
        "status": "in_progress",
        "priority": "P1",
        "dual_mode": "serial",
        "execution_mode": "sub-agent",
        "max_iterations": 5,
        "schema_version": 2,
        "created_at": "2026-04-23T00:00:00Z",
        "updated_at": "2026-04-23T01:00:00Z",
    })
    cp = _run(_bin(ws) + ["task", "show", "T-010"])
    assert cp.returncode == 0, cp.stderr
    out = cp.stdout
    assert "T-010-show-basic" in out
    assert "widget prototype" in out
    assert "plugin       : development" in out
    assert "profile      : feature" in out
    assert "phase        : design" in out
    assert "status       : in_progress" in out
    assert "priority     : P1" in out


def test_task_show_history_limit(ws: Path) -> None:
    _seed_task(ws, "T-011-show-history", {
        "title": "history task",
        "plugin": "development",
        "phase": "review",
        "status": "in_progress",
        "schema_version": 2,
        "history": [
            {"ts": f"2026-04-23T{i:02d}:00:00Z",
             "phase": f"phase{i}", "verdict": "ok"}
            for i in range(10)
        ],
    })
    # default (5)
    cp = _run(_bin(ws) + ["task", "show", "T-011"])
    assert cp.returncode == 0, cp.stderr
    assert "History (last 5 of 10)" in cp.stdout
    assert "5 earlier entries hidden" in cp.stdout
    # --history-limit 0 hides history entirely
    cp2 = _run(_bin(ws) + ["task", "show", "T-011", "--history-limit", "0"])
    assert cp2.returncode == 0
    assert "History" not in cp2.stdout
    # negative shows all
    cp3 = _run(_bin(ws) + ["task", "show", "T-011", "--history-limit", "-1"])
    assert cp3.returncode == 0
    assert "History (10)" in cp3.stdout
    assert "hidden" not in cp3.stdout


def test_task_show_pending_hitl(ws: Path) -> None:
    tid = "T-012-show-hitl"
    _seed_task(ws, tid, {
        "title": "hitl task",
        "plugin": "development",
        "phase": "build",
        "status": "in_progress",
        "schema_version": 2,
    })
    qdir = ws / ".codenook" / "hitl-queue"
    qdir.mkdir(parents=True, exist_ok=True)
    (qdir / f"{tid}-build_signoff.json").write_text(json.dumps({
        "id": f"{tid}-build_signoff", "task_id": tid, "gate": "build_signoff",
    }), encoding="utf-8")
    try:
        cp = _run(_bin(ws) + ["task", "show", "T-012"])
        assert cp.returncode == 0, cp.stderr
        assert "Pending HITL (1)" in cp.stdout
        assert "build_signoff" in cp.stdout
    finally:
        for f in qdir.glob(f"{tid}-*.json"):
            f.unlink(missing_ok=True)


def test_task_show_json(ws: Path) -> None:
    _seed_task(ws, "T-013-show-json", {
        "title": "json task",
        "plugin": "development",
        "phase": "plan",
        "status": "in_progress",
        "schema_version": 2,
    })
    cp = _run(_bin(ws) + ["task", "show", "T-013", "--json"])
    assert cp.returncode == 0, cp.stderr
    data = json.loads(cp.stdout)
    assert data["task_id"] == "T-013-show-json"
    assert data["title"] == "json task"
    assert data["_resolved_task"] == "T-013-show-json"
    assert isinstance(data["pending_hitl"], list)


def test_task_show_json_includes_corrupt_history_gracefully(ws: Path) -> None:
    """A well-formed state.json with weird history entries must not crash."""
    _seed_task(ws, "T-014-show-weird", {
        "title": "weird",
        "plugin": "development",
        "phase": "clarify",
        "status": "in_progress",
        "schema_version": 2,
        "history": ["not-a-dict-entry", {"phase": "x"}, 42],
    })
    cp = _run(_bin(ws) + ["task", "show", "T-014"])
    assert cp.returncode == 0, cp.stderr
    assert "History" in cp.stdout


def test_task_show_unknown_flag(ws: Path) -> None:
    cp = _run(_bin(ws) + ["task", "show", "T-001", "--bogus"])
    assert cp.returncode == 2
    assert "unknown flag" in cp.stderr
