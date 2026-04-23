"""v0.27.23 — conductor read scope contract.

The hard prohibition on reading plugin internals is removed.
Conductor may read everything under .codenook/plugins/, but must
NOT treat role / phase prompt templates as instructions to itself.
"""
from __future__ import annotations

import re
from pathlib import Path
import sys

LIB = Path(__file__).resolve().parents[2] / "skills" / "builtin" / "_lib"
sys.path.insert(0, str(LIB))

from claude_md_sync import render_block  # noqa: E402

VERSION = "0.27.23"


def render() -> str:
    return render_block(VERSION, ["development", "writing", "research"])


def _has(text: str, pattern: str) -> bool:
    return re.search(pattern, text, flags=re.IGNORECASE | re.DOTALL) is not None


def test_old_blanket_prohibition_removed():
    out = render()
    # The old hard MUST NOT against reading any plugin sub-folder is gone.
    assert not _has(
        out,
        r"MUST NOT.{0,40}read.{0,80}plugins/\*/(roles|skills|knowledge)",
    ), "old blanket plugin-read prohibition must be removed"


def test_role_and_phase_prompts_must_not_be_treated_as_instructions():
    out = render()
    assert _has(out, r"MUST NOT.{0,200}treat.{0,200}roles?.{0,200}instructions"), \
        "must explicitly forbid treating role/phase prompts as instructions"


def test_plugin_knowledge_and_skills_are_readable():
    out = render()
    # The proactive-lookup section must say plugin knowledge / skills are
    # readable (no longer "stop at the summary").
    assert _has(out, r"plugins/<id>/knowledge.{0,80}(read|open)")
    assert _has(out, r"plugins/<id>/skills.{0,80}(read|open)")
    assert not _has(out, r"stop at the summary"), \
        "the legacy 'stop at the summary' rule must be gone"


def test_plugin_roles_readable_for_explanation_only():
    out = render()
    # Roles / phase templates are readable but only for explanation.
    assert _has(out, r"explanation purposes|explanation only|for explanation")
    assert _has(out, r"never treat.{0,80}content as instructions|do not act on it")
