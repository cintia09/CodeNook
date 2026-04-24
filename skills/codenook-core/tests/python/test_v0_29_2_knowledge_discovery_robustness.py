"""Tests for v0.29.2: knowledge discovery robustness.

KO-1: discover_knowledge emits a stderr warning when a file's
frontmatter looks malformed (starts with --- but parse fails).

KO-4: top-level knowledge/README.md is filtered from discovery
(it is documentation, not a knowledge entry).
"""
from __future__ import annotations

import textwrap
from pathlib import Path

import knowledge_index as ki


def _write(path: Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(body), encoding="utf-8")


def test_top_level_readme_is_filtered(tmp_path: Path, capsys):
    pdir = tmp_path / "plugins" / "p1"
    kdir = pdir / "knowledge"
    kdir.mkdir(parents=True)
    _write(kdir / "README.md", "# Knowledge base intro\n\nNot a real entry.\n")
    _write(kdir / "real-entry" / "index.md",
           "---\nid: real-entry\ntitle: Real\ntags: [t]\n---\n# Real\nbody\n")

    entries = ki.discover_knowledge(pdir)
    titles = {e.get("title") for e in entries}
    assert "Real" in titles
    assert "Knowledge base intro" not in titles
    assert all("README" not in (e.get("path") or "") for e in entries)


def test_malformed_frontmatter_emits_warning(tmp_path: Path, capsys):
    pdir = tmp_path / "plugins" / "p1"
    kdir = pdir / "knowledge"
    kdir.mkdir(parents=True)
    # Closing --- is missing entirely - clearly meant to be frontmatter.
    _write(kdir / "broken" / "index.md",
           "---\nid: broken\ntitle: Broken\ntags: [t]\n# body without close\n")
    _write(kdir / "ok" / "index.md",
           "---\nid: ok\ntitle: Ok\ntags: [t]\n---\n# OK\n")

    ki.discover_knowledge(pdir)
    captured = capsys.readouterr()
    assert "malformed frontmatter" in captured.err
    assert "broken/index.md" in captured.err.replace("\\", "/")


def test_no_warning_for_files_without_frontmatter(tmp_path: Path, capsys):
    pdir = tmp_path / "plugins" / "p1"
    kdir = pdir / "knowledge"
    kdir.mkdir(parents=True)
    _write(kdir / "plain" / "index.md", "# Plain\n\nNo frontmatter here.\n")

    ki.discover_knowledge(pdir)
    captured = capsys.readouterr()
    assert "malformed frontmatter" not in captured.err
