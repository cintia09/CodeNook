"""``codenook history`` — manual + auto session-history snapshots.

Subcommands:
  history save --description "<text>" [--content-file <path>]
                                      [--content "<text>"]
                Create a memory snapshot under
                ``.codenook/memory/history/<ISO>-<slug>/``.
                Body content is read from --content-file (or stdin
                when neither --content nor --content-file is given).

  history list [--scope memory|tasks|all]
                Print existing snapshots, newest first.

  history prune [--days N] [--scope memory|tasks|all] [--yes]
                Delete snapshots older than N days (default: 10).
                Refuses to act unless --yes is set OR the workspace
                is interactive (prompts via stdin).
"""
from __future__ import annotations

import sys
from pathlib import Path
from typing import Sequence

from .config import CodenookContext


USAGE = """\
codenook history — session-history snapshots

Subcommands:
  history save  --description "<text>" [--content-file P] [--content "T"]
  history list  [--scope memory|tasks|all]
  history prune [--days N] [--scope memory|tasks|all] [--yes]
"""


def _import_history():
    import history as _h  # type: ignore
    return _h


def run(ctx: CodenookContext, args: Sequence[str]) -> int:
    if not args or args[0] in ("-h", "--help", "help"):
        sys.stdout.write(USAGE)
        return 0
    sub = args[0]
    rest = list(args[1:])
    if sub == "save":
        return _cmd_save(ctx, rest)
    if sub == "list":
        return _cmd_list(ctx, rest)
    if sub == "prune":
        return _cmd_prune(ctx, rest)
    sys.stderr.write(f"codenook history: unknown subcommand: {sub}\n")
    sys.stderr.write(USAGE)
    return 2


def _cmd_save(ctx: CodenookContext, args: list[str]) -> int:
    desc: str | None = None
    content: str | None = None
    content_file: str | None = None
    it = iter(args)
    try:
        for a in it:
            if a == "--description":
                desc = next(it)
            elif a == "--content":
                content = next(it)
            elif a == "--content-file":
                content_file = next(it)
            else:
                sys.stderr.write(f"codenook history save: unknown arg: {a}\n")
                return 2
    except StopIteration:
        sys.stderr.write("codenook history save: missing value for last flag\n")
        return 2
    if not desc:
        sys.stderr.write("codenook history save: --description is required\n")
        return 2
    if content is not None and content_file:
        sys.stderr.write(
            "codenook history save: pass --content OR --content-file, not both\n")
        return 2
    if content_file:
        p = Path(content_file)
        if not p.is_file():
            sys.stderr.write(f"codenook history save: not a file: {content_file}\n")
            return 2
        try:
            content = p.read_text(encoding="utf-8")
        except OSError as e:
            sys.stderr.write(f"codenook history save: read failed: {e}\n")
            return 1
    if content is None:
        # Read stdin if available; otherwise empty body.
        if not sys.stdin.isatty():
            try:
                content = sys.stdin.read()
            except OSError:
                content = ""
        else:
            content = ""
    h = _import_history()
    snap = h.save_memory_snapshot(ctx.workspace, desc, content or "")
    sys.stdout.write(f"codenook history: saved {snap}\n")
    return 0


def _cmd_list(ctx: CodenookContext, args: list[str]) -> int:
    scope = "all"
    it = iter(args)
    try:
        for a in it:
            if a == "--scope":
                scope = next(it)
            else:
                sys.stderr.write(f"codenook history list: unknown arg: {a}\n")
                return 2
    except StopIteration:
        sys.stderr.write("codenook history list: missing value for last flag\n")
        return 2
    if scope not in ("memory", "tasks", "all"):
        sys.stderr.write(f"codenook history list: invalid --scope: {scope}\n")
        return 2
    h = _import_history()
    entries = h.list_snapshots(ctx.workspace, scope=scope)
    if not entries:
        sys.stdout.write("(no history snapshots)\n")
        return 0
    for e in entries:
        ts = e.get("timestamp", "?")
        sc = e.get("scope", "?")
        kind = e.get("kind", "?")
        slug = e.get("slug", "")
        path = e.get("path", "")
        if sc == "task":
            sys.stdout.write(
                f"  [{ts}] task={e.get('task_id','?')} phase={e.get('phase','')} "
                f"status={e.get('status','')}  {path}\n")
        else:
            desc = e.get("description") or slug
            sys.stdout.write(
                f"  [{ts}] memory ({kind}) — {desc}  {path}\n")
    return 0


def _cmd_prune(ctx: CodenookContext, args: list[str]) -> int:
    days = 10
    scope = "all"
    yes = False
    it = iter(args)
    try:
        for a in it:
            if a == "--days":
                days = int(next(it))
            elif a == "--scope":
                scope = next(it)
            elif a in ("--yes", "-y"):
                yes = True
            else:
                sys.stderr.write(f"codenook history prune: unknown arg: {a}\n")
                return 2
    except StopIteration:
        sys.stderr.write("codenook history prune: missing value for last flag\n")
        return 2
    except ValueError:
        sys.stderr.write("codenook history prune: --days must be an integer\n")
        return 2
    if scope not in ("memory", "tasks", "all"):
        sys.stderr.write(f"codenook history prune: invalid --scope: {scope}\n")
        return 2
    if days < 0:
        sys.stderr.write("codenook history prune: --days must be >= 0\n")
        return 2
    if not yes:
        sys.stderr.write(
            f"codenook history prune: refuse to delete without --yes "
            f"(would prune snapshots older than {days} days, scope={scope})\n")
        return 2
    h = _import_history()
    deleted = h.prune(ctx.workspace, days=days, scope=scope)
    sys.stdout.write(f"codenook history: pruned {len(deleted)} snapshot(s)\n")
    for p in deleted:
        sys.stdout.write(f"  deleted: {p}\n")
    return 0
