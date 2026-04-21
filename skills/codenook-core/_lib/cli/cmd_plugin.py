"""``codenook plugin info <id>`` — print profiles + phases summary for a
plugin. Helps users of `task new --interactive` discover what's
available without having to read the plugin manifests by hand.
"""
from __future__ import annotations

import sys
from typing import Sequence

from .config import CodenookContext


HELP = """\
Usage: codenook plugin info <id>

  <id>   the plugin id (must be installed under .codenook/plugins/).

Prints the plugin's declared profiles + phase catalogue summary so
end-users (and the `task new --interactive` wizard) can discover what
profile names to pass to `--profile`.
"""


def run(ctx: CodenookContext, args: Sequence[str]) -> int:
    if not args or args[0] in ("-h", "--help"):
        print(HELP)
        return 0
    if args[0] != "info":
        sys.stderr.write(f"codenook plugin: unknown subcommand: {args[0]}\n")
        sys.stderr.write(HELP)
        return 2
    if len(args) < 2:
        sys.stderr.write("codenook plugin info: <id> required\n")
        return 2
    plugin = args[1]

    pdir = ctx.workspace / ".codenook" / "plugins" / plugin
    if not pdir.is_dir():
        sys.stderr.write(
            f"codenook plugin info: plugin not installed: {plugin}\n")
        return 1

    print(f"Plugin: {plugin}")
    print(f"Path  : {pdir}")

    phases_yaml = pdir / "phases.yaml"
    if not phases_yaml.is_file():
        print("(no phases.yaml — legacy plugin)")
        return 0

    try:
        import yaml  # type: ignore[import-untyped]
        doc = yaml.safe_load(phases_yaml.read_text(encoding="utf-8")) or {}
    except Exception as exc:
        sys.stderr.write(f"codenook plugin info: read failed: {exc}\n")
        return 1

    profiles = doc.get("profiles") or {}
    if isinstance(profiles, dict) and profiles:
        print("\nProfiles:")
        for name, spec in profiles.items():
            chain = spec.get("phases") if isinstance(spec, dict) else spec
            if isinstance(chain, list):
                print(f"  {name}: {' -> '.join(str(x) for x in chain)}")
            else:
                print(f"  {name}: (no phase chain)")
    else:
        print("\nProfiles: (none — single-pipeline plugin)")

    raw = doc.get("phases", [])
    print("\nPhases:")
    if isinstance(raw, dict):
        for pid, spec in raw.items():
            role = (spec or {}).get("role", "?") if isinstance(spec, dict) else "?"
            print(f"  {pid:<12} role={role}")
    elif isinstance(raw, list):
        for p in raw:
            if isinstance(p, dict):
                print(f"  {p.get('id','?'):<12} role={p.get('role','?')}")
    return 0
