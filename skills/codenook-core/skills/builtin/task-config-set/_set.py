#!/usr/bin/env python3
"""task-config-set/_set.py — Layer-4 override writer + audit log (M5)."""
import datetime as dt
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "_lib"))
from atomic import atomic_write_json  # noqa: E402

ALLOWED_KEYS = [
    "models.default",
    "models.router",
    "models.planner",
    "models.executor",
    "models.reviewer",
    "models.distiller",
    "hitl.mode"
]

TIER_SYMBOLS = ["tier_strong", "tier_balanced", "tier_cheap"]


def now_iso() -> str:
    return dt.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")


def audit_append(workspace: str, entry: dict) -> None:
    if not workspace:
        return
    log_dir = Path(workspace) / ".codenook/history"
    try:
        log_dir.mkdir(parents=True, exist_ok=True)
    except OSError:
        return
    with (log_dir / "config-changes.jsonl").open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def main():
    task = os.environ["CN_TASK"]
    key = os.environ["CN_KEY"]
    value = os.environ.get("CN_VALUE", "")
    unset = os.environ.get("CN_UNSET", "0") == "1"
    state_file = os.environ["CN_STATE_FILE"]
    workspace = os.environ.get("CN_WORKSPACE", "")
    plugin = os.environ.get("CN_PLUGIN", "")

    if key not in ALLOWED_KEYS:
        print(f"set.sh: key '{key}' not in allow-list", file=sys.stderr)
        sys.exit(1)

    with open(state_file, 'r') as f:
        state = json.load(f)

    if "config_overrides" not in state:
        state["config_overrides"] = {}

    parts = key.split('.')

    # Capture old value for audit + noop detection.
    cur = state["config_overrides"]
    for p in parts:
        if isinstance(cur, dict) and p in cur:
            cur = cur[p]
        else:
            cur = None
            break
    old_value = cur

    changed = False

    if unset:
        stack = [state["config_overrides"]]
        node = state["config_overrides"]
        for p in parts[:-1]:
            if not isinstance(node, dict) or p not in node:
                node = None
                break
            node = node[p]
            stack.append(node)
        if isinstance(node, dict) and parts[-1] in node:
            del node[parts[-1]]
            changed = True
            for i in range(len(stack) - 1, 0, -1):
                child = stack[i]
                parent = stack[i - 1]
                seg = parts[i - 1]
                if isinstance(child, dict) and not child and isinstance(parent, dict) and seg in parent:
                    del parent[seg]
                else:
                    break
        # If the key was already absent, this is a no-op: no write, no audit.
        if not changed:
            sys.exit(0)
    else:
        if value not in TIER_SYMBOLS and not is_known_model(value):
            print(f"set.sh: warning: unknown model value '{value}'", file=sys.stderr)

        if old_value == value:
            sys.exit(0)

        node = state["config_overrides"]
        for p in parts[:-1]:
            existing = node.get(p)
            if not isinstance(existing, dict):
                existing = {}
                node[p] = existing
            node = existing
        node[parts[-1]] = value
        changed = True

    atomic_write_json(state_file, state)

    if changed:
        audit_append(workspace, {
            "ts": now_iso(),
            "actor": "user",
            "scope": "task",
            "task": task,
            "plugin": plugin or None,
            "path": key,
            "old": old_value,
            "new": None if unset else value,
            "mode": "clear" if unset else "set",
            "reason": "task-config-set",
        })

    sys.exit(0)

def is_known_model(value):
    """Check if value looks like a known model ID (very permissive)"""
    common_prefixes = ["gpt-", "claude-", "gemini-", "o1-", "o3-"]
    return any(value.startswith(p) for p in common_prefixes)

if __name__ == "__main__":
    main()
