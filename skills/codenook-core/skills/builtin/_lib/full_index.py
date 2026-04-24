"""Build the unified ``<ws>/.codenook/memory/index.yaml``.

Two sources merge into a single document:

* **Plugin-shipped knowledge / skills** discovered under
  ``<ws>/.codenook/plugins/<id>/knowledge/`` and
  ``<ws>/.codenook/plugins/<id>/skills/<name>/SKILL.md`` — this is
  what makes the index *discoverable* even before any task has run.
  Knowledge entries are produced by
  :func:`knowledge_index.discover_knowledge` (recursive scan with
  INDEX.yaml/INDEX.md and implicit-frontmatter fallbacks; v0.21.0).

* **Memory-extracted entries** under
  ``<ws>/.codenook/memory/{knowledge,skills}/`` — the running record
  of post-phase extractor output (M9.x).

The schema is the union of fields used by both sources::

    version: 1
    generated_at: <iso8601 Z>
    skills:
      - plugin: <id|null>     # null for memory entries
        name: <str>
        path: <relative or absolute path>
        summary: <str>
        tags: [<str>...]
        status: <str>         # memory only
        sources: [<task_id>]  # memory only
    knowledge:
      - plugin: <id|null>
        title: <str>
        topic: <str>          # mirrors title for memory entries
        path: <relative or absolute path>
        summary: <str>
        tags: [<str>...]
        status: <str>         # memory only
        sources: [<task_id>]  # memory only

The writer is atomic (tempfile + ``os.replace``) and idempotent —
running ``build_full_index`` twice on an unchanged workspace yields
the same payload modulo ``generated_at``.
"""
from __future__ import annotations

import datetime as _dt
import os
import tempfile
from pathlib import Path
from typing import Any

import yaml

import knowledge_index as _ki

INDEX_YAML_NAME = "index.yaml"
INDEX_YAML_VERSION = 1


def _codenook_dir(workspace: Path | str) -> Path:
    return Path(workspace) / ".codenook"


def _memory_dir(workspace: Path | str) -> Path:
    return _codenook_dir(workspace) / "memory"


def _rel_to_workspace(workspace: Path | str, path: str) -> str:
    """Best-effort: present paths relative to the workspace root for
    portability. Falls back to the absolute string if outside."""
    if not path:
        return ""
    ws = Path(workspace).resolve()
    try:
        return str(Path(path).resolve().relative_to(ws)).replace(os.sep, "/")
    except (ValueError, OSError):
        return path


def _scan_plugin_skills(plugin_dir: Path) -> list[dict[str, Any]]:
    """Walk ``<plugin_dir>/skills/<name>/SKILL.md`` recursively."""
    sdir = plugin_dir / "skills"
    if not sdir.is_dir():
        return []
    out: list[dict[str, Any]] = []
    for entry in sorted(sdir.iterdir(), key=lambda p: p.name):
        if not entry.is_dir() or _ki._should_skip_dir(entry.name):  # type: ignore[attr-defined]
            continue
        skill_md = entry / "SKILL.md"
        if not skill_md.is_file():
            # Look one level deeper (some plugins nest by category).
            for child in sorted(entry.iterdir(), key=lambda p: p.name):
                if child.is_dir() and (child / "SKILL.md").is_file():
                    skill_md = child / "SKILL.md"
                    break
        if not skill_md.is_file():
            continue
        try:
            text = skill_md.read_text(encoding="utf-8")
        except OSError:
            continue
        fm, body = _ki._parse_frontmatter(text)  # type: ignore[attr-defined]
        name = fm.get("name") if isinstance(fm.get("name"), str) else entry.name
        summary = fm.get("summary")
        if not isinstance(summary, str) or not summary.strip():
            summary = _ki._summary_from_body(body)  # type: ignore[attr-defined]
        else:
            summary = summary.strip()
        tags = _ki._str_list(fm.get("tags"))  # type: ignore[attr-defined]
        out.append(
            {
                "name": name,
                "path": str(skill_md),
                "summary": summary,
                "tags": tags,
            }
        )
    return out


def _scan_plugins(workspace: Path) -> tuple[list[dict], list[dict]]:
    """Return ``(knowledge, skills)`` lists across every installed plugin."""
    plugins_root = _codenook_dir(workspace) / "plugins"
    knowledge: list[dict[str, Any]] = []
    skills: list[dict[str, Any]] = []
    if not plugins_root.is_dir():
        return knowledge, skills
    for pdir in sorted(plugins_root.iterdir(), key=lambda p: p.name):
        if not pdir.is_dir() or _ki._should_skip_dir(pdir.name):  # type: ignore[attr-defined]
            continue
        plugin_id = pdir.name
        for rec in _ki.discover_knowledge(pdir):
            knowledge.append(
                {
                    "plugin": plugin_id,
                    "title": rec.get("title", ""),
                    "path": _rel_to_workspace(workspace, rec.get("path", "")),
                    "summary": rec.get("summary", ""),
                    "tags": list(rec.get("tags") or []),
                }
            )
        for rec in _scan_plugin_skills(pdir):
            skills.append(
                {
                    "plugin": plugin_id,
                    "name": rec.get("name", ""),
                    "path": _rel_to_workspace(workspace, rec.get("path", "")),
                    "summary": rec.get("summary", ""),
                    "tags": list(rec.get("tags") or []),
                }
            )
    return knowledge, skills


def _scan_memory(workspace: Path) -> tuple[list[dict], list[dict]]:
    """Best-effort import of memory entries via memory_index.build_index."""
    try:
        import memory_index as mi  # type: ignore
        from memory_index import _collect_sources  # type: ignore
    except ImportError:
        return [], []
    try:
        idx = mi.build_index(workspace)
    except Exception:
        return [], []

    knowledge_out: list[dict[str, Any]] = []
    for meta in idx.get("knowledge", []):
        ap = meta.get("path", "")
        # Prefer frontmatter ``title`` (T-006 sub-directory canonical
        # form), fall back to legacy ``topic`` (extractor-promoted
        # entries), then the directory slug, then the file stem.
        title = (
            meta.get("title")
            or meta.get("topic")
            or (Path(ap).parent.name if Path(ap).name == "index.md" else Path(ap).stem)
        )
        knowledge_out.append(
            {
                "plugin": None,
                "title": title,
                "topic": title,
                "path": _rel_to_workspace(workspace, ap),
                "summary": meta.get("summary", ""),
                "tags": list(meta.get("tags") or []),
                "status": meta.get("status", ""),
                "sources": _collect_sources(meta),
            }
        )

    skills_out: list[dict[str, Any]] = []
    for meta in idx.get("skills", []):
        ap = meta.get("path", "")
        skills_out.append(
            {
                "plugin": None,
                "name": meta.get("name") or Path(ap).parent.name,
                "path": _rel_to_workspace(workspace, ap),
                "summary": meta.get("summary", ""),
                "tags": list(meta.get("tags") or []),
                "status": meta.get("status", ""),
                "sources": _collect_sources(meta),
            }
        )
    return knowledge_out, skills_out


def build_full_index(workspace: Path | str) -> dict[str, Any]:
    """Materialise the unified index payload (no I/O writes)."""
    ws = Path(workspace)
    p_know, p_skill = _scan_plugins(ws)
    m_know, m_skill = _scan_memory(ws)
    payload: dict[str, Any] = {
        "version": INDEX_YAML_VERSION,
        "generated_at": _dt.datetime.now(tz=_dt.timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "skills": p_skill + m_skill,
        "knowledge": p_know + m_know,
    }
    return payload


def write_index_yaml(workspace: Path | str, payload: dict[str, Any]) -> Path:
    """Atomically write ``<ws>/.codenook/memory/index.yaml``."""
    mem = _memory_dir(workspace)
    mem.mkdir(parents=True, exist_ok=True)
    target = mem / INDEX_YAML_NAME
    fd, tmp = tempfile.mkstemp(dir=str(mem), prefix=".tmp-index.", suffix=".yaml")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            yaml.safe_dump(payload, f, sort_keys=False, allow_unicode=True)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, target)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return target


def reindex(workspace: Path | str) -> tuple[Path, dict[str, Any]]:
    """Convenience wrapper: build payload, write file, return both."""
    payload = build_full_index(workspace)
    target = write_index_yaml(workspace, payload)
    return target, payload
