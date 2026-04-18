#!/usr/bin/env python3
"""Gate G02 — plugin-schema.

Validates <src>/plugin.yaml against the declarative schema in
plugin-schema.yaml.  Only structural checks (presence + type +
enum + non_empty); semantic constraints live in later gates.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import yaml

GATE = "plugin-schema"

PY_TYPE = {
    "string": str,
    "mapping": dict,
    "list": list,
}


def main() -> int:
    src = Path(os.environ["CN_SRC"])
    schema_path = Path(os.environ["CN_SCHEMA"])
    json_out = os.environ.get("CN_JSON", "0") == "1"
    reasons: list[str] = []

    pl_path = src / "plugin.yaml"
    if not pl_path.is_file():
        reasons.append("missing plugin.yaml at staged root")
        return _emit(json_out, reasons)

    try:
        plugin = yaml.safe_load(pl_path.read_text(encoding="utf-8"))
    except yaml.YAMLError as e:
        reasons.append(f"plugin.yaml is not valid YAML: {e}")
        return _emit(json_out, reasons)

    if not isinstance(plugin, dict):
        reasons.append("plugin.yaml top-level must be a mapping")
        return _emit(json_out, reasons)

    schema = yaml.safe_load(schema_path.read_text(encoding="utf-8"))
    for spec in schema.get("required", []):
        key = spec["key"]
        if key not in plugin:
            reasons.append(f"missing required field: {key}")
            continue
        val = plugin[key]
        expected = PY_TYPE[spec["type"]]
        if not isinstance(val, expected):
            reasons.append(
                f"field {key} must be {spec['type']}, got {type(val).__name__}"
            )
            continue
        if spec.get("non_empty") and not val:
            reasons.append(f"field {key} must be non-empty")
        if "enum" in spec and val not in spec["enum"]:
            reasons.append(
                f"field {key} must be one of {spec['enum']}, got {val!r}"
            )

    return _emit(json_out, reasons)


def _emit(json_out: bool, reasons: list[str]) -> int:
    ok = not reasons
    if json_out:
        print(json.dumps({"ok": ok, "gate": GATE, "reasons": reasons}))
    else:
        for r in reasons:
            print(f"[G02] {r}", file=sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
