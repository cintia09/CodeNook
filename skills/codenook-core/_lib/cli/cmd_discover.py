"""``codenook discover`` — unified plugin+memory sub-directory discovery.

Surface::

    codenook discover plugins [--plugin <id>] [--type skill|knowledge|role] [--json]
    codenook discover memory  [--type case|playbook|error|skill|knowledge] [--json]
    codenook discover --all   [--json]

Output formats
--------------
Human: one entity per line ``[source] type id — title``.
JSON:  list of ``Entity.to_dict()`` records.

This command is always live: it scans the filesystem on each call,
no reindex required.  See :mod:`_lib.discovery.scan` for semantics.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Sequence

from .config import CodenookContext


USAGE = """\
codenook discover — unified plugin+memory discovery

Subcommands:
  discover plugins [--plugin <id>] [--type <t>] [--json]
  discover memory  [--type <t>] [--json]
  discover --all   [--json]

Types (plugin):  skill | knowledge | role
Types (memory):  case | playbook | error | skill | knowledge
"""


def _import():
    # package-relative (when run via `python -m _lib.cli.app`)
    from .. import discovery  # noqa: WPS433
    return discovery


def run(ctx: CodenookContext, args: Sequence[str]) -> int:
    if not args or args[0] in ("-h", "--help", "help"):
        sys.stdout.write(USAGE)
        return 0

    # flags
    json_out = False
    type_filter: str | None = None
    plugin_filter: str | None = None
    want_all = False
    sub: str | None = None

    rest = list(args)
    while rest:
        a = rest.pop(0)
        if a == "--json":
            json_out = True
        elif a == "--type":
            if not rest:
                sys.stderr.write("codenook discover: --type needs a value\n")
                return 2
            type_filter = rest.pop(0)
        elif a == "--plugin":
            if not rest:
                sys.stderr.write("codenook discover: --plugin needs a value\n")
                return 2
            plugin_filter = rest.pop(0)
        elif a == "--all":
            want_all = True
        elif a in ("plugins", "memory"):
            if sub is not None:
                sys.stderr.write(f"codenook discover: unexpected arg: {a}\n")
                return 2
            sub = a
        else:
            sys.stderr.write(f"codenook discover: unknown arg: {a}\n")
            sys.stderr.write(USAGE)
            return 2

    discovery = _import()
    workspace = Path(ctx.workspace)

    if want_all:
        entities = discovery.discover_all(workspace)
    elif sub == "plugins":
        entities = discovery.scan_plugins(workspace)
        if plugin_filter:
            entities = [
                e for e in entities if e.source == f"plugin:{plugin_filter}"
            ]
    elif sub == "memory":
        entities = discovery.scan_memory(workspace)
    else:
        sys.stderr.write("codenook discover: need `plugins`, `memory`, or `--all`\n")
        sys.stderr.write(USAGE)
        return 2

    if type_filter:
        # Validate against the appropriate DISCOVERY_ROOTS slice so that
        # typos (e.g. `roles` vs `role`) fail loudly instead of silently
        # producing zero entities.
        roots = discovery.DISCOVERY_ROOTS  # type: ignore[attr-defined]
        if want_all:
            allowed = set(roots["plugin"]) | set(roots["memory"])
            ctx_label = "plugins+memory"
        elif sub == "plugins":
            allowed = set(roots["plugin"])
            ctx_label = "plugins"
        else:  # memory
            allowed = set(roots["memory"])
            ctx_label = "memory"
        if type_filter not in allowed:
            sys.stderr.write(
                f"codenook discover: --type {type_filter!r} is not valid for "
                f"{ctx_label}.  valid types: {', '.join(sorted(allowed))}\n"
            )
            return 2
        entities = [e for e in entities if e.type == type_filter]

    if json_out:
        sys.stdout.write(
            json.dumps(
                [e.to_dict() for e in entities],
                ensure_ascii=False, indent=2,
            ) + "\n"
        )
        return 0

    if not entities:
        sys.stdout.write("(no entities discovered)\n")
        return 0

    for e in entities:
        sys.stdout.write(f"[{e.source}] {e.type:<9} {e.id}\n")
        if e.title and e.title != e.id:
            sys.stdout.write(f"    title:   {e.title}\n")
        if e.summary:
            sys.stdout.write(f"    summary: {e.summary}\n")
        if e.keywords:
            sys.stdout.write(f"    keywords: {', '.join(e.keywords)}\n")
    return 0
