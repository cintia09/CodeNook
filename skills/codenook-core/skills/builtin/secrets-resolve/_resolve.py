#!/usr/bin/env python3
"""secrets-resolve core logic.

Placeholders:
  ${env:NAME}   -> os.environ[NAME]
  ${file:path}  -> trimmed contents of `path`

Rules:
  - Nested placeholders (${env:${env:X}}) are REJECTED (M1 design lock).
  - Multiple placeholders per string are supported.
  - On success, NEVER print resolved values to stderr — only key names
    (or nothing at all).
  - --allow-missing: env keys resolve to "" with a stderr warning naming
    the key. File placeholders always fail hard on missing file.
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

PLACEHOLDER = re.compile(r"\$\{(env|file):([^${}]+)\}")
NESTED_SIGN = re.compile(r"\$\{[^}]*\$\{")


def resolve_string(s: str, allow_missing: bool, errors: list, warnings: list) -> str:
    if NESTED_SIGN.search(s):
        errors.append({"kind": "nested", "msg": "nested placeholders are not supported"})
        return s

    def repl(m: re.Match) -> str:
        kind = m.group(1)
        arg = m.group(2).strip()
        if kind == "env":
            if arg in os.environ:
                return os.environ[arg]
            if allow_missing:
                warnings.append({"kind": "env-missing", "key": arg})
                return ""
            errors.append({"kind": "env-missing", "key": arg})
            return ""
        if kind == "file":
            p = Path(arg)
            if not p.is_file():
                errors.append({"kind": "file-missing", "path": arg})
                return ""
            try:
                return p.read_text(encoding="utf-8").strip()
            except OSError as e:
                errors.append({"kind": "file-read", "path": arg, "msg": str(e)})
                return ""
        return m.group(0)

    return PLACEHOLDER.sub(repl, s)


def walk(obj, allow_missing, errors, warnings):
    if isinstance(obj, dict):
        return {k: walk(v, allow_missing, errors, warnings) for k, v in obj.items()}
    if isinstance(obj, list):
        return [walk(v, allow_missing, errors, warnings) for v in obj]
    if isinstance(obj, str):
        return resolve_string(obj, allow_missing, errors, warnings)
    return obj


def main() -> int:
    cfg_path = Path(os.environ["CN_CONFIG"])
    allow_missing = os.environ.get("CN_ALLOW_MISSING") == "1"

    try:
        cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(f"resolve.sh: config not valid JSON: {e}", file=sys.stderr)
        return 2

    errors: list = []
    warnings: list = []
    resolved = walk(cfg, allow_missing, errors, warnings)

    for w in warnings:
        if w["kind"] == "env-missing":
            print(f"warning: env var not set (allow-missing): {w['key']}", file=sys.stderr)

    if errors:
        for e in errors:
            if e["kind"] == "nested":
                print(f"error: {e['msg']}", file=sys.stderr)
            elif e["kind"] == "env-missing":
                print(f"error: env var not set: {e['key']}", file=sys.stderr)
            elif e["kind"] == "file-missing":
                print(f"error: file not found: {e['path']}", file=sys.stderr)
            elif e["kind"] == "file-read":
                print(f"error: file read failed: {e['path']}: {e['msg']}", file=sys.stderr)
        return 1

    print(json.dumps(resolved, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
