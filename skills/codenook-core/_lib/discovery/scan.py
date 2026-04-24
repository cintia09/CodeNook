"""Unified filesystem-scan discovery for plugins + workspace memory (T-006).

Contract
========

Every discoverable entity is a **directory** containing exactly one of:

* ``index.md`` for *knowledge* entries (``knowledge/<slug>/index.md``);
  the ``type`` frontmatter field selects ``case|playbook|error|knowledge``.
* ``SKILL.md`` for *skill* entries (``skills/<slug>/SKILL.md``); the
  filename is the type — ``type:`` in frontmatter is optional and
  validated as ``skill`` when present.

Required frontmatter fields: ``id, title, tags, summary`` (T-006 §2.4
dropped ``keywords:`` in favour of ``tags:``).  Knowledge entries
additionally require ``type``; skill entries do not (their type is the
filename).

Roots
-----

::

    DISCOVERY_ROOTS = {
        "plugin": {"skill": "skills", "knowledge": "knowledge", "role": "roles"},
        "memory": {"knowledge": "knowledge", "skill": "skills"},
    }

The ``--type case|playbook|error`` selectors fan out to the same
``knowledge`` root and filter on the ``type:`` frontmatter field.

Semantics
---------

* Drop-in: copying a well-formed entity directory under a discovery
  root makes it visible on the *next* CLI call.  No reindex required.
* Half-copied dir without an ``index.md`` / ``SKILL.md`` is silently
  skipped.
* Broken YAML frontmatter: skipped with a warning (scan exit 0).
* Depth: exactly one level.

Cache
-----

Process-scoped; keyed by ``(root_path, root_mtime, source, type_)``.

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
SKILL_FILE = "SKILL.md"

# T-006 §2.4 contract — keywords dropped in favour of tags.
REQUIRED_FIELDS_KNOWLEDGE: tuple[str, ...] = ("id", "type", "title", "summary", "tags")
REQUIRED_FIELDS_SKILL: tuple[str, ...] = ("id", "title", "summary", "tags")

# Back-compat alias for callers that haven't moved off the legacy name.
REQUIRED_FIELDS: tuple[str, ...] = REQUIRED_FIELDS_KNOWLEDGE

KNOWLEDGE_TYPES: frozenset[str] = frozenset(
    {"case", "playbook", "error", "knowledge"}
)

DISCOVERY_ROOTS: dict[str, dict[str, str]] = {
    "plugin": {
        "skill": "skills",
        "knowledge": "knowledge",
        "role": "roles",
    },
    # T-006 §2.8: memory collapses 5 roots → 2.  The cases/playbooks/errors
    # legacy roots were folded into knowledge/ with frontmatter ``type:``
    # carrying the original kind (see T-006 §2.7 migration table).
    "memory": {
        "knowledge": "knowledge",
        "skill": "skills",
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
    """Scan ``root`` one level deep for ``<slug>/{index.md,SKILL.md}`` entities.

    For ``type_ == "skill"`` the descriptor file is ``SKILL.md`` (the
    filename is the type) and ``type:`` in frontmatter is optional.
    For all other ``type_`` values the descriptor is ``index.md`` and
    the frontmatter ``type`` MUST equal ``type_`` (knowledge entries
    fan-out: ``case|playbook|error|knowledge`` all live under
    ``knowledge/`` with their kind in frontmatter).

    Entities whose required fields are missing are skipped with a
    warning.  Returns an empty list when ``root`` does not exist.
    Results are sorted by ``id``.
    """
    root = Path(root)
    if not root.is_dir():
        return []
    is_skill = (type_ == "skill")
    descriptor = SKILL_FILE if is_skill else INDEX_FILE
    required = REQUIRED_FIELDS_SKILL if is_skill else REQUIRED_FIELDS_KNOWLEDGE

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
        idx = child / descriptor
        if not idx.is_file():
            log.debug("discovery: skip %s (no %s)", child, descriptor)
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
        missing = [f for f in required if f not in fm]
        if missing:
            log.warning("discovery: skip %s: missing fields %s", child, missing)
            continue
        fm_type = str(fm.get("type", "")).strip()
        if is_skill:
            if fm_type and fm_type != "skill":
                log.warning(
                    "discovery: skip %s: SKILL.md frontmatter type=%s "
                    "(expected absent or 'skill')",
                    child, fm_type,
                )
                continue
            entity_type = "skill"
        else:
            # Knowledge fan-out: scan_root is invoked once per requested
            # kind (case|playbook|error|knowledge).  When ``type_`` is
            # the catch-all "knowledge" we still gate on the requested
            # frontmatter value so callers always get back what they
            # asked for; the CLI fans out separately for each kind.
            if fm_type and fm_type != type_:
                # During knowledge fan-out a single entry will appear
                # 3 times in the "wrong type" branch (once per other
                # sub-type).  That's not a problem worth warning about
                # — keep it at debug level.
                if fm_type in KNOWLEDGE_TYPES:
                    log.debug(
                        "discovery: skip %s: type mismatch (fm=%s want=%s)",
                        child, fm_type, type_,
                    )
                else:
                    log.warning(
                        "discovery: skip %s: unknown knowledge type %r "
                        "(want=%s)",
                        child, fm_type, type_,
                    )
                continue
            entity_type = type_
        ent = Entity(
            source=source,
            type=entity_type,
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


def scan_memory(workspace: Path) -> list[Entity]:
    """Scan workspace memory under the T-006 flat layout.

    Walks ``memory/knowledge/`` once per knowledge sub-type
    (``case|playbook|error|knowledge``) so the returned entities carry
    accurate ``type`` values, plus ``memory/skills/`` for SKILL.md
    entries.  ``DISCOVERY_ROOTS["memory"]`` is the authoritative root
    map and intentionally only declares ``knowledge`` + ``skill``
    (T-006 §2.8 collapse).
    """
    workspace = Path(workspace)
    mem_root = workspace / ".codenook" / "memory"
    if not mem_root.is_dir():
        return []
    out: list[Entity] = []
    knowledge_root = mem_root / DISCOVERY_ROOTS["memory"]["knowledge"]
    for kt in sorted(KNOWLEDGE_TYPES):
        out.extend(scan_root(knowledge_root, "memory", kt))
    skills_root = mem_root / DISCOVERY_ROOTS["memory"]["skill"]
    out.extend(scan_root(skills_root, "memory", "skill"))
    return out


def scan_plugin(plugin_dir: Path, plugin_id: str | None = None) -> list[Entity]:
    """Scan one plugin dir for skills/knowledge/roles."""
    plugin_dir = Path(plugin_dir)
    pid = plugin_id or plugin_dir.name
    source = f"plugin:{pid}"
    out: list[Entity] = []
    knowledge_root = plugin_dir / DISCOVERY_ROOTS["plugin"]["knowledge"]
    for kt in sorted(KNOWLEDGE_TYPES):
        out.extend(scan_root(knowledge_root, source, kt))
    skills_root = plugin_dir / DISCOVERY_ROOTS["plugin"]["skill"]
    out.extend(scan_root(skills_root, source, "skill"))
    roles_root = plugin_dir / DISCOVERY_ROOTS["plugin"]["role"]
    out.extend(scan_root(roles_root, source, "role"))
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
