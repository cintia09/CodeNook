"""Canonical extractor audit-log writer (M9.4 refactor).

The 8-key schema (``asset_type, candidate_hash, existing_path, outcome,
reason, source_task, timestamp, verdict``) is locked by TC-M9.3-09 /
TC-M9.4-04 — the *last* line of ``history/extraction-log.jsonl`` after
a successful extractor run must contain exactly these keys when sorted.

``audit()`` writes the canonical record. If ``extra`` is provided, a
separate diagnostic side-record (``outcome=diagnostic, verdict=noop``)
is emitted *before* the canonical line so the schema check still
inspects only the pure 8-key payload.
"""

from __future__ import annotations

import datetime as _dt
from pathlib import Path
from typing import Any

import memory_layer as ml


def _now_iso() -> str:
    return _dt.datetime.now(tz=_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def audit(
    workspace: Path | str,
    *,
    asset_type: str,
    outcome: str,
    verdict: str,
    reason: str = "",
    source_task: str = "",
    candidate_hash: str = "",
    existing_path: str | None = None,
    extra: dict[str, Any] | None = None,
) -> None:
    rec: dict[str, Any] = {
        "asset_type": asset_type,
        "candidate_hash": candidate_hash,
        "existing_path": existing_path,
        "outcome": outcome,
        "reason": reason,
        "source_task": source_task,
        "timestamp": _now_iso(),
        "verdict": verdict,
    }
    if extra:
        side = dict(rec)
        side["outcome"] = "diagnostic"
        side["verdict"] = "noop"
        side.update(extra)
        ml.append_audit(workspace, side)
    ml.append_audit(workspace, rec)
