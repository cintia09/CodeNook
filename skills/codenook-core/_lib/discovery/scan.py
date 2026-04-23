"""Unified filesystem-scan discovery for plugins + workspace memory (T-004).

Contract
========

Every discoverable entity is a **directory** containing a required
``index.md`` whose YAML frontmatter carries at least
``id, type, title, summary, keywords``.  The scanner walks a fixed
set of roots (see :data:`DISCOVERY_ROOTS`) exactly one level deep and
yields :class:`Entity` records suitable for CLI JSON output and for
downstream search / resolution.

Semantics
---------

* Drop-in: copying a well-formed entity directory under a discovery
  root makes it visible on the *next* CLI call.  No reindex required.
* Half-copied dir without ``index.md`` is silently skipped.
* Broken YAML frontmatter: skipped with a warning (scan exit 0).
* Depth: exactly one level.  Nested ``<root>/<slug>/sub/index.md``
  is NOT discoverable.

Cache
-----

Process-scoped; keyed by ``(root_path, root_mtime)``.  Every call
``stat()``s the root and rebuilds when mtime changed.  Each CLI
invocation is a fresh process, so the cache rebuilds once per call.

This module is intentionally self-contained: pure stdlib + PyYAML.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any, Iterable, Iterator

import yaml


log = logging.getLogger(__name__)

INDEX_FILE = "index.md"
REQUIRED_FIELDS: tuple[str, ...] = ("id", "type", "title", "summary", "keywords")

DISCOVERY_ROOTS: dict[str, dict[str, str]] = {
    "plugin": {
        "skill": "skills",
        "knowledge": "knowledge",
        "role": "roles",
    },
    "memory": {
        "case": "cases",
        "playbook": "playbooks",
        "error": "errors",
        "skill": "skills",
        "knowledge": "knowledge",
    },
}


@dataclass
class Entity:
    source: str                # "plugin:<id>" | "memory"
    type: str                  # skill|knowledge|role|case|playbook|error
    id: str
    path: str                  # absolute path of the entity directory
    title: str
    summary: str
    keywords: list[str] = field(default_factory=list)
    examples: list[str] = field(default_factory=list)
    tags: list[str] = field(default_factory=list)
    provides: list[str] = field(default_factory=list)
    requires: list[str] = field(default_factory=list)
    version: str = "0.0.0"
    status: str = "active"
    frontmatter: dict[str, Any] = field(default_factory=dict)

    def to_dict(self, include_frontmatter: bool = False) -> dict[str, Any]:
        d = asdict(self)
        if not include_frontmatter:
            d.pop("frontmatter", None)
        return d


_FM_SEP = "---"


def _parse_frontmatter(text: str) -> tuple[dict[str, Any], str]:
    """Return (frontmatter, body).  Missing frontmatter → ({}, text)."""
    if not text.startswith(_FM_SEP):
        return {}, text
    # split on the next line that is exactly "---"
    lines = text.split("\n")
    if not lines or lines[0].strip() != _FM_SEP:
        return {}, text
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == _FM_SEP:
            end = i
            break
    if end is None:
        return {}, text
    fm_text = "\n".join(lines[1:end])
    body = "\n".join(lines[end + 1 :])
    try:
        fm = yaml.safe_load(fm_text) or {}
    except yaml.YAMLError as e:
        raise
    if not isinstance(fm, dict):
        fm = {}
    return fm, body


def _str_list(v: Any) -> list[str]:
    if v is None:
        return []
    if isinstance(v, str):
        return [v]
    if isinstance(v, list):
        return [str(x).strip() for x in v if str(x).strip()]
    return []


# ---------------------------------------------------------------- cache

# key: (resolved_path_str, mtime_ns) -> list[Entity]
_SCAN_CACHE: dict[tuple[str, int], list[Entity]] = {}


def _root_cache_key(root: Path) -> tuple[str, int] | None:
    try:
        st = root.stat()
    except OSError:
        return None
    return (str(root.resolve()), st.st_mtime_ns)


def cache_clear() -> None:
    """Drop all cached scans (useful for tests)."""
    _SCAN_CACHE.clear()


# ---------------------------------------------------------------- scan

def scan_root(root: Path, source: str, type_: str) -> list[Entity]:
    """Scan ``root`` one level deep for ``<slug>/index.md`` entities.

    Entities whose frontmatter's ``type`` field does not match ``type_``
    are silently skipped with a warning (a catch for author mistakes).

    Returns an empty list when ``root`` does not exist.  Results are
    sorted by ``id``.
    """
    root = Path(root)
    if not root.is_dir():
        return []
    ck = _root_cache_key(root)
    cache_key = (ck[0] + "|" + source + "|" + type_, ck[1]) if ck else None
    if cache_key is not None and cache_key in _SCAN_CACHE:
        return list(_SCAN_CACHE[cache_key])

    out: list[Entity] = []
    for child in sorted(root.iterdir(), key=lambda p: p.name):
        if not child.is_dir():
            continue
        name = child.name
        if name.startswith((".", "_")):
            continue
        idx = child / INDEX_FILE
        if not idx.is_file():
            log.debug("discovery: skip %s (no %s)", child, INDEX_FILE)
            continue
        try:
            text = idx.read_text(encoding="utf-8")
        except OSError as e:
            log.warning("discovery: skip %s: read error: %s", child, e)
            continue
        try:
            fm, body = _parse_frontmatter(text)
        except yaml.YAMLError as e:
            log.warning("discovery: skip %s: bad frontmatter: %s", child, e)
            continue
        missing = [f for f in REQUIRED_FIELDS if f not in fm]
        if missing:
            log.warning("discovery: skip %s: missing fields %s", child, missing)
            continue
        fm_type = str(fm.get("type", "")).strip()
        if fm_type and fm_type != type_:
            log.warning(
                "discovery: skip %s: type mismatch (fm=%s want=%s)",
                child, fm_type, type_,
            )
            continue
        ent = Entity(
            source=source,
            type=type_,
            id=str(fm.get("id") or name).strip(),
            path=str(child.resolve()),
            title=str(fm.get("title") or name).strip(),
            summary=str(fm.get("summary") or "").strip(),
            keywords=_str_list(fm.get("keywords")),
            examples=_str_list(fm.get("examples")),
            tags=_str_list(fm.get("tags")),
            provides=_str_list(fm.get("provides")),
            requires=_str_list(fm.get("requires")),
            version=str(fm.get("version") or "0.0.0"),
            status=str(fm.get("status") or "active"),
            frontmatter=fm,
        )
        out.append(ent)

    out.sort(key=lambda e: e.id)
    if cache_key is not None:
        _SCAN_CACHE[cache_key] = list(out)
    return out


def scan_plugin(plugin_dir: Path, plugin_id: str | None = None) -> list[Entity]:
    """Scan one plugin dir for skills/knowledge/roles."""
    plugin_dir = Path(plugin_dir)
    pid = plugin_id or plugin_dir.name
    source = f"plugin:{pid}"
    out: list[Entity] = []
    for type_, sub in DISCOVERY_ROOTS["plugin"].items():
        out.extend(scan_root(plugin_dir / sub, source, type_))
    return out


def scan_plugins(workspace: Path) -> list[Entity]:
    """Scan every installed plugin under ``<ws>/.codenook/plugins/``."""
    workspace = Path(workspace)
    plugins_root = workspace / ".codenook" / "plugins"
    if not plugins_root.is_dir():
        return []
    out: list[Entity] = []
    for pdir in sorted(plugins_root.iterdir(), key=lambda p: p.name):
        if not pdir.is_dir() or pdir.name.startswith((".", "_")):
            continue
        out.extend(scan_plugin(pdir, pdir.name))
    return out


def scan_memory(workspace: Path) -> list[Entity]:
    """Scan workspace memory topic sub-dirs."""
    workspace = Path(workspace)
    mem_root = workspace / ".codenook" / "memory"
    if not mem_root.is_dir():
        return []
    out: list[Entity] = []
    for type_, sub in DISCOVERY_ROOTS["memory"].items():
        out.extend(scan_root(mem_root / sub, "memory", type_))
    return out


def discover_all(workspace: Path) -> list[Entity]:
    """Union of plugin + memory entities."""
    return scan_plugins(workspace) + scan_memory(workspace)


# ---------------------------------------------------------------- filter / rank

def filter_entities(
    entities: Iterable[Entity],
    *,
    source_startswith: str | None = None,
    type_: str | None = None,
    id_: str | None = None,
) -> list[Entity]:
    out = []
    for e in entities:
        if source_startswith and not e.source.startswith(source_startswith):
            continue
        if type_ and e.type != type_:
            continue
        if id_ and e.id != id_:
            continue
        out.append(e)
    return out
