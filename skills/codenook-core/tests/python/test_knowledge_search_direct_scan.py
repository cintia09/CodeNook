"""v0.29.0 — `codenook knowledge search` walks plugin/memory dirs live.

Asserts that the new live-scan code path returns hits even when no
``memory/index.yaml`` exists on disk.
"""
from __future__ import annotations

from pathlib import Path

import yaml

import knowledge_query as kq


def _make_ws(tmp_path: Path) -> Path:
    (tmp_path / ".codenook" / "memory" / "knowledge").mkdir(parents=True)
    (tmp_path / ".codenook" / "plugins").mkdir(parents=True)
    return tmp_path


def _entry(parent: Path, slug: str, title: str, summary: str,
           tags: list[str]) -> Path:
    d = parent / slug
    d.mkdir(parents=True, exist_ok=True)
    fm = {"title": title, "summary": summary, "tags": tags}
    (d / "index.md").write_text(
        "---\n" + yaml.safe_dump(fm, sort_keys=False) + "---\n\n# " + title + "\n",
        encoding="utf-8",
    )
    return d


def test_search_returns_hits_without_index_yaml_plugin(tmp_path: Path):
    ws = _make_ws(tmp_path)
    pkdir = ws / ".codenook" / "plugins" / "demo" / "knowledge"
    _entry(pkdir, "pytest-conventions",
           title="Pytest conventions",
           summary="how we run pytest in CodeNook",
           tags=["pytest", "testing"])
    # Sanity: no index.yaml exists.
    assert not (ws / ".codenook" / "memory" / "index.yaml").exists()

    hits = kq.find_relevant(ws, "pytest")
    assert len(hits) == 1
    assert hits[0]["plugin"] == "demo"
    assert "pytest" in hits[0]["tags"]


def test_search_returns_hits_without_index_yaml_memory(tmp_path: Path):
    ws = _make_ws(tmp_path)
    mkdir = ws / ".codenook" / "memory" / "knowledge"
    _entry(mkdir, "deploy-runbook",
           title="Deploy runbook",
           summary="Steps for prod deploys.",
           tags=["deploy", "ops"])
    assert not (ws / ".codenook" / "memory" / "index.yaml").exists()

    hits = kq.find_relevant(ws, "deploy")
    assert len(hits) == 1
    # Memory entries carry plugin=None.
    assert hits[0]["plugin"] is None
    assert "deploy" in hits[0]["tags"]


def test_search_merges_plugin_and_memory_entries(tmp_path: Path):
    ws = _make_ws(tmp_path)
    _entry(ws / ".codenook" / "plugins" / "demo" / "knowledge",
           "ci-tips", "CI tips", "tips for CI runs", ["ci"])
    _entry(ws / ".codenook" / "memory" / "knowledge",
           "ci-local", "Local CI", "running CI locally", ["ci"])
    hits = kq.find_relevant(ws, "ci")
    plugins = sorted([h["plugin"] for h in hits], key=lambda s: s or "")
    assert None in plugins  # memory hit
    assert "demo" in plugins  # plugin hit
    assert len(hits) == 2


def test_reindex_is_noop_no_index_file_created(tmp_path: Path):
    """Calling cmd_knowledge.run(['reindex']) does NOT create index.yaml."""
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from _lib.cli.config import CodenookContext
    from _lib.cli import cmd_knowledge

    ws = _make_ws(tmp_path)
    state_file = ws / ".codenook" / "state.json"
    ctx = CodenookContext(
        workspace=ws,
        state_file=state_file,
        state={"kernel_version": "0.29.0"},
        kernel_dir=Path(__file__).resolve().parents[2] / "skills" / "builtin",
    )
    rc = cmd_knowledge.run(ctx, ["reindex"])
    assert rc == 0
    assert not (ws / ".codenook" / "memory" / "index.yaml").exists()
