"""v0.27.24 — bootloader hardening (review fixes 1, 4-10, 12, 13).

Each test pins ONE concrete fix from the deep review of the
v0.27.23 workspace CLAUDE.md. Together they prove the rendered
template no longer has the contradictions / coverage gaps the
review flagged.
"""
from __future__ import annotations

import re
from pathlib import Path
import sys

LIB = Path(__file__).resolve().parents[2] / "skills" / "builtin" / "_lib"
sys.path.insert(0, str(LIB))

from claude_md_sync import render_block  # noqa: E402

VERSION = "0.27.24"


def render() -> str:
    return render_block(VERSION, ["development", "writing", "research"])


def _has(text: str, pattern: str) -> bool:
    return re.search(pattern, text, flags=re.IGNORECASE | re.DOTALL) is not None


# ---------------------------------------------------------------------
# Issue #1 — workflow ordering: Duplicate check BEFORE Pre-creation
# ---------------------------------------------------------------------

def test_issue1_auto_engagement_lists_duplicate_before_config():
    out = render()
    assert _has(
        out,
        r"Pick a profile.{0,30}Duplicate / parent check.{0,80}Pre-creation config ask",
    ), "auto-engagement flow must list Duplicate before Pre-creation"


def test_issue1_duplicate_section_says_before_config_ask():
    out = render()
    assert _has(
        out,
        r"Duplicate / parent check.{0,1500}before.{0,40}Pre-creation config ask",
    )


def test_issue1_pre_creation_says_after_duplicate_check():
    out = render()
    assert _has(
        out,
        r"Pre-creation config ask.{0,500}after.{0,80}Duplicate / parent check",
    )


# ---------------------------------------------------------------------
# Issue #4 — .codenook/ detection guidance
# ---------------------------------------------------------------------

def test_issue4_codenook_detection_uses_state_json():
    out = render()
    assert _has(out, r"\.codenook/state\.json.{0,200}(view|file-read|read|exists|parses)")


# ---------------------------------------------------------------------
# Issue #5 — unknown tick status fallback
# ---------------------------------------------------------------------

def test_issue5_unknown_tick_status_handled():
    out = render()
    assert _has(out, r"(any other value|other status|not in this list|future kernel).{0,300}(stop|surface|ask)")


# ---------------------------------------------------------------------
# Issue #6 — missing/empty memory inventory
# ---------------------------------------------------------------------

def test_issue6_missing_memory_inventory_handled():
    """v0.29.0+: there is no on-disk index.yaml; the bootloader must
    still tell the conductor what to do when memory holds zero entries
    on a fresh install."""
    out = render()
    assert _has(out, r"memory holds zero entries.{0,200}(normal|note|fresh install)|fresh install.{0,200}normal")


# ---------------------------------------------------------------------
# Issue #7 — "you" ambiguity in role/phase prompt restriction
# ---------------------------------------------------------------------

def test_issue7_inline_exception_documented():
    out = render()
    # Must explicitly carve out the inline-execution case.
    assert _has(out, r"Exception.{0,800}(clarifier|inline).{0,800}follow")
    assert _has(out, r"conductor mode")


# ---------------------------------------------------------------------
# Issue #8 — no-plugin / weak-match fallback
# ---------------------------------------------------------------------

def test_issue8_zero_plugins_fallback():
    out = render()
    assert _has(out, r"(zero plugins|no plugins (are )?(installed|present))")


def test_issue8_weak_match_acknowledged():
    out = render()
    assert _has(out, r"(weak match|none match well|all .* score < 0\.\d|no match.*overlap)")


# ---------------------------------------------------------------------
# Issue #9 — multiple HITL gates resolved serially
# ---------------------------------------------------------------------

def test_issue9_multiple_gates_serial():
    out = render()
    assert _has(out, r"multiple gates.{0,400}serial")
    assert _has(out, r"never batch|do not batch|never call .decide. for more than one gate")


# ---------------------------------------------------------------------
# Issue #10 — knowledge search is the live disk-walk surface (v0.29.0)
# ---------------------------------------------------------------------

def test_issue10_search_is_live_disk_scan():
    out = render()
    # The Proactive knowledge lookup section must describe the live
    # disk scan and recommend `knowledge search` as the surface.
    assert _has(out, r"(walks?|live).{0,80}(plugin|memory|disk).{0,200}knowledge search|knowledge search.{0,200}(walk|live|disk)")
    assert _has(out, r"no on-disk index|no index file|live disk scan")


# ---------------------------------------------------------------------
# Issue #12 — model verbatim vs omit-when-empty
# ---------------------------------------------------------------------

def test_issue12_model_verbatim_scope_clarified():
    out = render()
    # The hard rule must say: verbatim WHEN non-empty; omit when empty.
    assert _has(out, r"non-empty.{0,300}absent.{0,200}empty.{0,200}omit")


# ---------------------------------------------------------------------
# Issue #13 — manual entries (v0.29.0+: no _pending/, no extractor)
# ---------------------------------------------------------------------

def test_issue13_manual_knowledge_path_documented():
    """v0.29.0 removed the auto-extraction pipeline. The bootloader
    must tell the conductor where to write a manual knowledge entry
    and that no reindex step is required."""
    out = render()
    assert _has(out, r"memory/knowledge/<slug>/index\.md")
    # Must also mention there's no _pending/ or reindex step any more.
    assert _has(out, r"no\s+`?_pending|no\s+reindex|reindex.{0,80}any\s+more")
