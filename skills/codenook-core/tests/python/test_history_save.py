"""v0.29.0 — manual `codenook history save` writes a memory snapshot.

Covers save_memory_snapshot (creates a fresh dated dir), the prune
helper (10-day default, deletes older snapshots), and basic list_snapshots
output.
"""
from __future__ import annotations

import datetime as dt
import json
from pathlib import Path

import pytest

import history


def _ws(tmp_path: Path) -> Path:
    (tmp_path / ".codenook" / "memory" / "history").mkdir(parents=True)
    return tmp_path


def test_save_memory_snapshot_creates_fresh_dir(tmp_path: Path):
    ws = _ws(tmp_path)
    snap = history.save_memory_snapshot(
        ws, "post-T007 validation", content="hello world\n")
    assert snap.is_dir()
    meta = json.loads((snap / "meta.json").read_text(encoding="utf-8"))
    assert meta["scope"] == "memory"
    assert meta["kind"] == "manual"
    assert meta["description"] == "post-T007 validation"
    assert (snap / "content.md").read_text(encoding="utf-8") == "hello world\n"
    # Filename starts with an ISO timestamp.
    assert snap.name[:11].count("-") >= 2


def test_save_memory_snapshot_no_dedup(tmp_path: Path):
    ws = _ws(tmp_path)
    a = history.save_memory_snapshot(ws, "x",
                                     now=dt.datetime(2025, 1, 1, 0, 0, 0,
                                                     tzinfo=dt.timezone.utc))
    b = history.save_memory_snapshot(ws, "x",
                                     now=dt.datetime(2025, 1, 1, 0, 0, 1,
                                                     tzinfo=dt.timezone.utc))
    assert a != b
    assert a.is_dir() and b.is_dir()


def test_list_snapshots_returns_newest_first(tmp_path: Path):
    ws = _ws(tmp_path)
    older = history.save_memory_snapshot(
        ws, "older",
        now=dt.datetime(2025, 1, 1, 0, 0, 0, tzinfo=dt.timezone.utc))
    newer = history.save_memory_snapshot(
        ws, "newer",
        now=dt.datetime(2025, 6, 1, 0, 0, 0, tzinfo=dt.timezone.utc))
    entries = history.list_snapshots(ws, scope="memory")
    assert len(entries) == 2
    assert entries[0]["path"] == str(newer)
    assert entries[1]["path"] == str(older)


def test_prune_deletes_old_snapshots_keeps_recent(tmp_path: Path):
    ws = _ws(tmp_path)
    now = dt.datetime(2025, 6, 1, 0, 0, 0, tzinfo=dt.timezone.utc)
    old = history.save_memory_snapshot(
        ws, "old",
        now=now - dt.timedelta(days=30))
    recent = history.save_memory_snapshot(
        ws, "recent",
        now=now - dt.timedelta(days=2))
    deleted = history.prune(ws, days=10, scope="memory", now=now)
    assert old in deleted
    assert recent not in deleted
    assert not old.exists()
    assert recent.exists()


def test_prune_zero_days_deletes_everything(tmp_path: Path):
    ws = _ws(tmp_path)
    a = history.save_memory_snapshot(ws, "a")
    b = history.save_memory_snapshot(ws, "b")
    # `now` defaults to current UTC; zero-day cutoff means anything in
    # the past gets deleted (used by validation tear-down).
    deleted = history.prune(ws, days=0, scope="memory")
    assert a in deleted and b in deleted
    assert not a.exists() and not b.exists()
