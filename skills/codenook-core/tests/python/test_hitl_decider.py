"""v0.30 — HITL gates can be delegated to the main-session LLM."""
from __future__ import annotations

import json
from pathlib import Path

import _tick


PLUGIN = "development"


def _write_pipeline(workspace: Path) -> None:
    pdir = workspace / ".codenook" / "plugins" / PLUGIN
    pdir.mkdir(parents=True, exist_ok=True)
    (pdir / "phases.yaml").write_text(
        "phases:\n"
        "  - id: review\n"
        "    role: reviewer\n"
        "    gate: review_signoff\n"
        "    produces: outputs/phase-1-reviewer.md\n",
        encoding="utf-8",
    )
    (pdir / "transitions.yaml").write_text(
        "transitions:\n"
        "  review:\n"
        "    ok: complete\n",
        encoding="utf-8",
    )
    (pdir / "hitl-gates.yaml").write_text(
        "gates:\n"
        "  review_signoff:\n"
        "    description: Confirm reviewer output.\n",
        encoding="utf-8",
    )


def _seed_completed_phase(workspace: Path, *, decider: str | None) -> Path:
    tid = "T-001"
    tdir = workspace / ".codenook" / "tasks" / tid
    (tdir / "outputs").mkdir(parents=True)
    (tdir / "outputs" / "phase-1-reviewer.md").write_text(
        "---\nverdict: ok\n---\n"
        "# Review\n\nThe output satisfies the gate and has enough body "
        "text for the verdict reader to accept it.\n",
        encoding="utf-8",
    )
    state = {
        "schema_version": 2,
        "task_id": tid,
        "plugin": PLUGIN,
        "phase": "review",
        "iteration": 0,
        "max_iterations": 3,
        "status": "in_progress",
        "history": [],
        "in_flight_agent": {
            "agent_id": "ag_T-001_1_0",
            "role": "reviewer",
            "dispatched_at": "2026-01-01T00:00:00Z",
            "expected_output": "outputs/phase-1-reviewer.md",
        },
    }
    if decider is not None:
        state["hitl_decider"] = decider
    state_file = tdir / "state.json"
    state_file.write_text(json.dumps(state, indent=2), encoding="utf-8")
    return state_file


def test_main_session_llm_hitl_returns_delegated_instruction(workspace: Path):
    _write_pipeline(workspace)
    state_file = _seed_completed_phase(
        workspace, decider="main-session-llm")

    new_state, summary = _tick.tick(workspace, state_file)

    assert new_state["status"] == "waiting"
    assert summary["status"] == "waiting"
    assert summary["next_action"] == "hitl:review_signoff"
    assert summary["hitl_decider"] == "main-session-llm"
    instruction = summary["conductor_instruction"]
    assert "LLM-DELEGATED HITL" in instruction
    assert "main-session LLM" in instruction
    assert "do NOT call ask_user" in instruction
    assert "codenook decide --task T-001 --phase review" in instruction
    assert 'question: "Render this gate' not in instruction


def test_human_hitl_keeps_channel_choice_instruction(workspace: Path):
    _write_pipeline(workspace)
    state_file = _seed_completed_phase(workspace, decider=None)

    _, summary = _tick.tick(workspace, state_file)

    assert summary["hitl_decider"] == "human"
    instruction = summary["conductor_instruction"]
    assert "MANDATORY HITL ritual" in instruction
    assert 'question: "Render this gate' in instruction
