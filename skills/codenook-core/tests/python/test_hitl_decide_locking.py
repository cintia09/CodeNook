"""Regression tests for HITL decision locking."""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path


REPO = Path(__file__).resolve().parents[4]
CORE = REPO / "skills" / "codenook-core"
LIB = CORE / "skills" / "builtin" / "_lib"
HITL_ADAPTER = CORE / "skills" / "builtin" / "hitl-adapter" / "_hitl.py"


def _load_hitl_adapter():
    sys.path.insert(0, str(LIB))
    spec = importlib.util.spec_from_file_location(
        "hitl_adapter_under_test", HITL_ADAPTER)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_decide_locks_sidecar_not_entry_file(tmp_path: Path) -> None:
    """Windows cannot atomically replace a JSON file held open as a lock."""
    hitl = _load_hitl_adapter()
    eid = "T-001-review_signoff"
    qdir = tmp_path / ".codenook" / "hitl-queue"
    qdir.mkdir(parents=True)
    entry = qdir / f"{eid}.json"
    entry.write_text(json.dumps({
        "id": eid,
        "task_id": "T-001",
        "plugin": "development",
        "gate": "review_signoff",
        "created_at": "2026-05-13T00:00:00Z",
        "context_path": "",
        "decision": None,
        "decided_at": None,
        "reviewer": None,
        "comment": None,
        "verdict_at_gate": "ok",
        "prompt": "approve?",
    }), encoding="utf-8")

    assert hitl.entry_lock_path(tmp_path, eid) != hitl.entry_path(tmp_path, eid)

    rc = hitl.cmd_decide(tmp_path, eid, "approve", "tester", "looks good")

    assert rc == 0
    assert hitl.entry_lock_path(tmp_path, eid).is_file()
    decided = json.loads(entry.read_text(encoding="utf-8"))
    assert decided["decision"] == "approve"
    assert decided["reviewer"] == "tester"
