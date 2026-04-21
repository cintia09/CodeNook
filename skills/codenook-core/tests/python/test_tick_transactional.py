"""v0.18.1 — tick() must mutate state.json transactionally.

Bug repro: when a verdict is consumed and state is mutated in-memory
(``in_flight_agent`` cleared, ``history`` appended) but a downstream
branch then errors out (e.g. ``lookup_transition`` returns None
because ``transitions.yaml`` is missing), the previous behaviour was
to persist the partial state and return an error envelope. The next
tick then saw ``in_flight_agent=None`` + ``status=in_progress`` +
``phase`` unchanged → recovery branch → re-dispatched the same
phase, overwriting the completed output.

Fix: ``tick()`` snapshots the on-disk state at entry, runs the
algorithm body on a deep copy, and on any error path (exception or
``error`` summary envelope) returns the original snapshot so the
caller persists a byte-identical no-op.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import _tick


PLUGIN = "development"


def _sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def _write_phases(workspace: Path) -> None:
    pdir = workspace / ".codenook" / "plugins" / PLUGIN
    pdir.mkdir(parents=True, exist_ok=True)
    (pdir / "phases.yaml").write_text(
        "phases:\n"
        "  - id: anomaly_confirmation\n"
        "    role: clarifier\n"
        "    expected_output: outputs/phase-1.md\n"
    )


def _write_transitions(workspace: Path) -> None:
    pdir = workspace / ".codenook" / "plugins" / PLUGIN
    (pdir / "transitions.yaml").write_text(
        "transitions:\n"
        "  anomaly_confirmation:\n"
        "    ok: complete\n"
    )


def _seed_in_flight_state(workspace: Path, *, with_output: bool) -> Path:
    """Seed a task whose only outstanding work is "consume the
    in-flight verdict + transition". When ``with_output`` is True we
    also write a valid verdict file so the consumer succeeds.
    """
    tid = "T-001"
    tdir = workspace / ".codenook" / "tasks" / tid
    (tdir / "outputs").mkdir(parents=True)
    if with_output:
        (tdir / "outputs" / "phase-1.md").write_text(
            "---\nverdict: ok\n---\nbody\n"
        )
    state = {
        "schema_version": 1,
        "task_id": tid,
        "plugin": PLUGIN,
        "phase": "anomaly_confirmation",
        "iteration": 0,
        "max_iterations": 3,
        "status": "in_progress",
        "history": [],
        "in_flight_agent": {
            "role": "clarifier",
            "expected_output": "outputs/phase-1.md",
            "agent_id": "ag_T-001_0_0",
        },
    }
    state_file = tdir / "state.json"
    state_file.write_text(json.dumps(state, indent=2, sort_keys=True))
    return state_file


# ── 1. happy path ───────────────────────────────────────────────────────
def test_happy_path_advances_and_persists_once(workspace: Path):
    _write_phases(workspace)
    _write_transitions(workspace)
    state_file = _seed_in_flight_state(workspace, with_output=True)

    new_state, summary = _tick.tick(workspace, state_file)

    assert summary.get("status") in ("done", "advanced")
    assert new_state["phase"] == "complete"
    assert new_state["status"] == "done"
    # in-flight cleared on success
    assert new_state.get("in_flight_agent") is None
    # exactly one verdict-history entry recorded
    verdict_entries = [h for h in new_state["history"] if "verdict" in h]
    assert len(verdict_entries) == 1
    assert verdict_entries[0]["verdict"] == "ok"


# ── 2. error mid-tick → state.json byte-identical ───────────────────────
def test_error_mid_tick_leaves_state_file_unchanged(workspace: Path):
    _write_phases(workspace)
    # NOTE: no transitions.yaml on disk → lookup returns None → error.
    state_file = _seed_in_flight_state(workspace, with_output=True)

    before_hash = _sha(state_file)
    before_bytes = state_file.read_bytes()

    new_state, summary = _tick.tick(workspace, state_file)

    # Tick reports the error to the caller…
    assert summary["status"] == "error"
    assert "no transition" in summary["next_action"]
    # …but the on-disk state.json is byte-identical to before.
    assert _sha(state_file) == before_hash
    assert state_file.read_bytes() == before_bytes
    # And the dict tick returned is the original snapshot, not the
    # mid-mutation working copy: in_flight_agent is still set,
    # history is still empty.
    assert new_state["in_flight_agent"] is not None
    assert new_state["in_flight_agent"]["role"] == "clarifier"
    assert new_state["history"] == []
    assert new_state["phase"] == "anomaly_confirmation"
    assert new_state["status"] == "in_progress"


# ── 3. recovery after fixing the underlying issue ───────────────────────
def test_recovery_after_fix_does_not_redispatch(workspace: Path):
    _write_phases(workspace)
    state_file = _seed_in_flight_state(workspace, with_output=True)

    # First tick: errors out (no transitions.yaml).
    _, summary1 = _tick.tick(workspace, state_file)
    assert summary1["status"] == "error"

    # Operator fixes the missing fixture.
    _write_transitions(workspace)

    # Second tick: must advance cleanly. Critically, it must NOT take
    # the recovery branch and re-dispatch the same phase — that would
    # write a "recover: re-dispatch (no in_flight)" warning to history.
    new_state, summary2 = _tick.tick(workspace, state_file)
    assert summary2.get("status") in ("done", "advanced")
    assert new_state["phase"] == "complete"
    redispatch_warnings = [
        h for h in new_state["history"]
        if "_warning" in h and "re-dispatch" in h["_warning"]
    ]
    assert redispatch_warnings == [], (
        "tick re-dispatched the just-completed phase — "
        "transactional snapshot rollback failed"
    )


# ── 4. no phantom history entries on errored tick ───────────────────────
def test_errored_tick_does_not_append_phantom_history(workspace: Path):
    _write_phases(workspace)
    state_file = _seed_in_flight_state(workspace, with_output=True)

    pre = json.loads(state_file.read_text())
    assert pre["history"] == []

    new_state, summary = _tick.tick(workspace, state_file)
    assert summary["status"] == "error"

    post = json.loads(state_file.read_text())
    assert post["history"] == [], (
        "errored tick leaked a partial history entry to disk"
    )
    # The returned dict (snapshot) also carries no phantom entry.
    assert new_state["history"] == []
