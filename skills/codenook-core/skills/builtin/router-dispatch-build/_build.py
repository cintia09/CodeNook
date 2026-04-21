#!/usr/bin/env python3
"""router-dispatch-build core. Invoked by build.sh.

Assembles a ≤500-char JSON envelope, truncates user_input to 200 chars
with an ellipsis if needed, then calls dispatch-audit emit.

Builtin-skill targets are recognised by the *absence* of a plugin
manifest at .codenook/plugins/<target>/plugin.yaml — and identified
positively by the existence of a sibling skills/builtin/<target>/
SKILL.md (or the in-package M3 hardcoded list for the small set we
ship at this milestone).
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "_lib"))
from manifest_load import load_manifest, ManifestError, plugins_dir  # noqa: E402
from builtin_catalog import BUILTIN_SKILLS  # noqa: E402

PAYLOAD_LIMIT  = 500
INPUT_HARD_CAP = 200
ELLIPSIS       = "..."


def truncate_input(s: str) -> str:
    if len(s) <= INPUT_HARD_CAP:
        return s
    return s[:INPUT_HARD_CAP] + ELLIPSIS


def envelope_size(payload: dict) -> int:
    return len(json.dumps(payload, ensure_ascii=False,
                          separators=(",", ":")).encode("utf-8"))


def main() -> int:
    target     = os.environ["CN_TARGET"]
    user_input = os.environ["CN_USER_INPUT"]
    task       = os.environ.get("CN_TASK", "")
    ws         = Path(os.environ["CN_WORKSPACE"]).resolve()
    # Legacy env var; no longer used since v0.24.0 uses in-process emit.
    # Read with a default so the .sh wrapper doesn't have to set it.
    emit_sh    = os.environ.get("CN_EMIT_SH", "")

    # Reject path-traversal in --target before any filesystem access.
    if (not target
            or "/" in target
            or "\\" in target
            or ".." in target
            or target != Path(target).name):
        print(f"build.sh: invalid target name: {target!r}", file=sys.stderr)
        return 1

    plugin_manifest_path = plugins_dir(ws) / target / "plugin.yaml"
    is_plugin = plugin_manifest_path.is_file()

    if is_plugin:
        try:
            load_manifest(ws, target)
        except ManifestError as e:
            print(f"build.sh: target manifest invalid: {e}", file=sys.stderr)
            return 1
        role = "plugin-worker"
    else:
        if target not in BUILTIN_SKILLS:
            print(f"build.sh: target not found (no plugin manifest, "
                  f"not a known builtin): {target}", file=sys.stderr)
            return 1
        role = "builtin-skill"

    # Build context.plugins — list installed plugin ids only (compact).
    pdir = plugins_dir(ws)
    installed_ids = sorted(p.name for p in pdir.iterdir()
                           if p.is_dir() and (p / "plugin.yaml").is_file()) \
                    if pdir.is_dir() else []

    payload = {
        "role":       role,
        "target":     target,
        "user_input": truncate_input(user_input),
        "context":    {"plugins": installed_ids},
    }
    if task:
        payload["task"] = task

    size = envelope_size(payload)
    if size > PAYLOAD_LIMIT:
        # Try shrinking context.plugins (drop ids one-by-one from the end).
        while installed_ids and size > PAYLOAD_LIMIT:
            installed_ids.pop()
            payload["context"]["plugins"] = installed_ids
            size = envelope_size(payload)
    if size > PAYLOAD_LIMIT:
        print(f"build.sh: payload still too large ({size} > {PAYLOAD_LIMIT})",
              file=sys.stderr)
        return 1

    out = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))

    # Audit — must succeed; surface as exit 1 if it doesn't.
    # v0.24.0: in-process call to dispatch-audit emitter (no bash subprocess).
    try:
        import sys as _sys
        from pathlib import Path as _P
        _da = _P(__file__).resolve().parent.parent / "dispatch-audit"
        if str(_da) not in _sys.path:
            _sys.path.insert(0, str(_da))
        import _emit  # type: ignore
        rc = _emit.run(role=role, payload=out, workspace=ws)
        if rc != 0:
            print(f"build.sh: dispatch-audit emit failed (rc={rc})",
                  file=sys.stderr)
            return 1
    except Exception as e:
        print(f"build.sh: cannot exec dispatch-audit: {e}", file=sys.stderr)
        return 1

    sys.stdout.write(out + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
