#!/usr/bin/env python3
"""Gate G06 — plugin-deps-check."""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

import yaml

GATE = "plugin-deps-check"

SEMVER_RE = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)"
    r"(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?"
    r"(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$"
)
OPS = ("==", "!=", ">=", "<=", ">", "<", "=")


def parse(v: str):
    m = SEMVER_RE.match(v)
    if not m:
        return None
    return (int(m[1]), int(m[2]), int(m[3]), m[4])


def _pre_key(pre):
    if pre is None:
        return (1,)
    parts = []
    for p in pre.split("."):
        parts.append((0, int(p)) if p.isdigit() else (1, p))
    return (0, tuple(parts))


def cmpkey(p):
    return (p[0], p[1], p[2], _pre_key(p[3]))


def satisfies(core, op, target) -> bool:
    a, b = cmpkey(core), cmpkey(target)
    if op in ("==", "="):
        return a == b
    if op == "!=":
        return a != b
    if op == ">=":
        return a >= b
    if op == "<=":
        return a <= b
    if op == ">":
        return a > b
    if op == "<":
        return a < b
    return False


def split_constraint(c: str):
    c = c.strip()
    for op in OPS:
        if c.startswith(op):
            return op, c[len(op):].strip()
    return None, None


def main() -> int:
    src = Path(os.environ["CN_SRC"])
    core_v = os.environ.get("CN_CORE_VERSION", "")
    json_out = os.environ.get("CN_JSON", "0") == "1"
    reasons: list[str] = []

    core_parsed = parse(core_v) if core_v else None
    if core_parsed is None:
        reasons.append(f"current core VERSION {core_v!r} is not valid semver")
        return _emit(json_out, reasons)

    try:
        plugin = yaml.safe_load((src / "plugin.yaml").read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError) as e:
        reasons.append(f"cannot read plugin.yaml: {e}")
        return _emit(json_out, reasons)

    requires = plugin.get("requires") or {}
    constraint = requires.get("core_version")
    if constraint is None:
        return _emit(json_out, reasons)
    if not isinstance(constraint, str):
        reasons.append("requires.core_version must be a string")
        return _emit(json_out, reasons)

    parts = [p.strip() for p in constraint.split(",") if p.strip()]
    if not parts:
        reasons.append("requires.core_version is empty")
        return _emit(json_out, reasons)

    for part in parts:
        op, rhs = split_constraint(part)
        if op is None:
            reasons.append(f"unparseable comparator: {part!r}")
            continue
        target = parse(rhs)
        if target is None:
            reasons.append(f"comparator operand not semver: {rhs!r}")
            continue
        if not satisfies(core_parsed, op, target):
            reasons.append(
                f"core_version {core_v} fails constraint {part}"
            )

    return _emit(json_out, reasons)


def _emit(json_out: bool, reasons: list[str]) -> int:
    ok = not reasons
    if json_out:
        print(json.dumps({"ok": ok, "gate": GATE, "reasons": reasons}))
    else:
        for r in reasons:
            print(f"[G06] {r}", file=sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
