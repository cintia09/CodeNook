"""Unit tests for the unified sub-directory discovery scanner.

T-006: required field set is now ``id/title/type/tags/summary``
(``keywords:`` dropped).  Skill entities live in ``<slug>/SKILL.md``
and do not carry a ``type:`` field; knowledge entities (case /
playbook / error / knowledge) all live under ``knowledge/`` with
``type:`` selecting the kind.
"""
from __future__ import annotations

import os
import sys
import time
from pathlib import Path

import pytest

# Make the kernel _lib importable when running pytest from the repo root.
_HERE = Path(__file__).resolve()
_KERNEL = _HERE.parent.parent.parent  # <repo>/skills/codenook-core
sys.path.insert(0, str(_KERNEL))

from _lib.discovery import scan as D  # noqa: E402


KNOWLEDGE_TEMPLATE = """---
id: {id}
type: {type}
title: "{title}"
summary: "{summary}"
tags: [{tags}]
---
# {title}

{body}
"""

SKILL_TEMPLATE = """---
id: {id}
title: "{title}"
summary: "{summary}"
tags: [{tags}]
---
# {title}

{body}
"""


def _write_entity(root: Path, type_: str, slug: str, **overrides) -> Path:
    d = root / slug
    d.mkdir(parents=True, exist_ok=True)
    fm = {
        "id": overrides.get("id", slug),
        "type": overrides.get("type", type_),
        "title": overrides.get("title", slug.replace("-", " ").title()),
        "summary": overrides.get("summary", f"summary for {slug}"),
        "tags": overrides.get("tags", "kw1, kw2"),
        "body": overrides.get("body", f"body for {slug}"),
    }
    if type_ == "skill":
        fm.pop("type", None)
        (d / "SKILL.md").write_text(SKILL_TEMPLATE.format(**fm), encoding="utf-8")
    else:
        (d / "index.md").write_text(KNOWLEDGE_TEMPLATE.format(**fm), encoding="utf-8")
    return d


@pytest.fixture(autouse=True)
def _clear_cache():
    D.cache_clear()
    yield
    D.cache_clear()


def test_scan_root_basic(tmp_path):
    root = tmp_path / "plugins" / "dev" / "skills"
    for n in ("alpha", "beta", "gamma"):
        _write_entity(root, "skill", n)
    ents = D.scan_root(root, "plugin:dev", "skill")
    assert [e.id for e in ents] == ["alpha", "beta", "gamma"]
    assert all(e.type == "skill" for e in ents)
    assert all(e.source == "plugin:dev" for e in ents)


def test_scan_drop_in(tmp_path):
    root = tmp_path / "memory" / "knowledge"
    _write_entity(root, "knowledge", "foo")
    ents = D.scan_root(root, "memory", "knowledge")
    assert len(ents) == 1
    D.cache_clear()
    _write_entity(root, "knowledge", "bar")
    os.utime(root, None)
    ents2 = D.scan_root(root, "memory", "knowledge")
    assert {e.id for e in ents2} == {"foo", "bar"}


def test_scan_skip_no_descriptor(tmp_path):
    root = tmp_path / "skills"
    root.mkdir(parents=True)
    (root / "orphan").mkdir()
    _write_entity(root, "skill", "good")
    ents = D.scan_root(root, "plugin:x", "skill")
    assert [e.id for e in ents] == ["good"]


def test_scan_skip_missing_fields(tmp_path):
    root = tmp_path / "skills"
    root.mkdir(parents=True)
    d = root / "broken"
    d.mkdir()
    (d / "SKILL.md").write_text(
        "---\nid: broken\ntitle: t\n---\n", encoding="utf-8",
    )
    _write_entity(root, "skill", "good")
    ents = D.scan_root(root, "plugin:x", "skill")
    assert [e.id for e in ents] == ["good"]


def test_scan_skip_underscore(tmp_path):
    root = tmp_path / "memory" / "knowledge"
    _write_entity(root, "knowledge", "visible")
    _write_entity(root, "knowledge", "_hidden")
    ents = D.scan_root(root, "memory", "knowledge")
    assert [e.id for e in ents] == ["visible"]


def test_scan_bad_yaml(tmp_path):
    root = tmp_path / "x"
    root.mkdir()
    d = root / "bad"
    d.mkdir()
    (d / "SKILL.md").write_text("---\n::: not yaml :::\n---\nbody", encoding="utf-8")
    _write_entity(root, "skill", "ok")
    ents = D.scan_root(root, "plugin:x", "skill")
    assert [e.id for e in ents] == ["ok"]


def test_scan_type_mismatch(tmp_path):
    root = tmp_path / "knowledge"
    _write_entity(root, "knowledge", "ok")
    _write_entity(root, "knowledge", "wrong-type", id="wrong-type", type="case")
    ents = D.scan_root(root, "plugin:x", "knowledge")
    assert [e.id for e in ents] == ["ok"]


def test_scan_depth_limit(tmp_path):
    root = tmp_path / "skills"
    nested = root / "a" / "b"
    nested.mkdir(parents=True)
    (nested / "SKILL.md").write_text(
        "---\nid: b\ntitle: b\nsummary: s\ntags: [k]\n---\n",
        encoding="utf-8",
    )
    _write_entity(root, "skill", "top")
    ents = D.scan_root(root, "plugin:x", "skill")
    assert [e.id for e in ents] == ["top"]


def test_discover_all(tmp_path):
    ws = tmp_path
    p_skills = ws / ".codenook" / "plugins" / "dev" / "skills"
    m_know = ws / ".codenook" / "memory" / "knowledge"
    _write_entity(p_skills, "skill", "test-runner")
    _write_entity(m_know, "knowledge", "pytest-notes")
    ents = D.discover_all(ws)
    assert {(e.source, e.type, e.id) for e in ents} == {
        ("plugin:dev", "skill", "test-runner"),
        ("memory", "knowledge", "pytest-notes"),
    }


def test_entity_to_dict_no_frontmatter(tmp_path):
    root = tmp_path / "skills"
    _write_entity(root, "skill", "x")
    ents = D.scan_root(root, "plugin:p", "skill")
    d = ents[0].to_dict()
    assert "frontmatter" not in d
    assert d["id"] == "x"


def test_memory_collapsed_roots():
    """T-006 §2.8: memory has only knowledge + skills roots."""
    assert set(D.DISCOVERY_ROOTS["memory"]) == {"knowledge", "skill"}


def test_scan_memory_fans_out_knowledge_subtypes(tmp_path):
    """A single knowledge/ root yields case + playbook + error +
    knowledge entities based on frontmatter type."""
    ws = tmp_path
    kroot = ws / ".codenook" / "memory" / "knowledge"
    _write_entity(kroot, "case", "issue-01", type="case")
    _write_entity(kroot, "playbook", "fingerprint", type="playbook")
    _write_entity(kroot, "knowledge", "platform-notes", type="knowledge")
    sroot = ws / ".codenook" / "memory" / "skills"
    _write_entity(sroot, "skill", "baselining")
    ents = D.scan_memory(ws)
    by_type = {(e.type, e.id) for e in ents}
    assert ("case", "issue-01") in by_type
    assert ("playbook", "fingerprint") in by_type
    assert ("knowledge", "platform-notes") in by_type
    assert ("skill", "baselining") in by_type
