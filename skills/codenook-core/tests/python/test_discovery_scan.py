"""Unit tests for T-004 unified sub-directory discovery scanner."""
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


INDEX_TEMPLATE = """---
id: {id}
type: {type}
title: "{title}"
summary: "{summary}"
keywords: [{keywords}]
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
        "keywords": overrides.get("keywords", "kw1, kw2"),
        "body": overrides.get("body", f"body for {slug}"),
    }
    (d / "index.md").write_text(INDEX_TEMPLATE.format(**fm), encoding="utf-8")
    return d


@pytest.fixture(autouse=True)
def _clear_cache():
    D.cache_clear()
    yield
    D.cache_clear()


def test_scan_root_basic(tmp_path):
    # 3 skills
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
    # bump mtime just in case mtime_ns resolution is too coarse
    os.utime(root, None)
    ents2 = D.scan_root(root, "memory", "knowledge")
    assert {e.id for e in ents2} == {"foo", "bar"}


def test_scan_skip_no_index(tmp_path):
    root = tmp_path / "skills"
    root.mkdir(parents=True)
    (root / "orphan").mkdir()  # no index.md
    _write_entity(root, "skill", "good")
    ents = D.scan_root(root, "plugin:x", "skill")
    assert [e.id for e in ents] == ["good"]


def test_scan_skip_missing_fields(tmp_path):
    root = tmp_path / "skills"
    root.mkdir(parents=True)
    d = root / "broken"
    d.mkdir()
    (d / "index.md").write_text(
        "---\nid: broken\ntype: skill\ntitle: t\n---\n", encoding="utf-8",
    )  # missing summary + keywords
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
    (d / "index.md").write_text("---\n::: not yaml :::\n---\nbody", encoding="utf-8")
    _write_entity(root, "skill", "ok")
    ents = D.scan_root(root, "plugin:x", "skill")
    assert [e.id for e in ents] == ["ok"]


def test_scan_type_mismatch(tmp_path):
    root = tmp_path / "skills"
    _write_entity(root, "skill", "ok")
    _write_entity(root, "knowledge", "wrong", id="wrong", type="knowledge")
    ents = D.scan_root(root, "plugin:x", "skill")
    assert [e.id for e in ents] == ["ok"]


def test_scan_depth_limit(tmp_path):
    root = tmp_path / "skills"
    nested = root / "a" / "b"
    nested.mkdir(parents=True)
    (nested / "index.md").write_text(
        "---\nid: b\ntype: skill\ntitle: b\nsummary: s\nkeywords: [k]\n---\n",
        encoding="utf-8",
    )
    # and a top-level one
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
