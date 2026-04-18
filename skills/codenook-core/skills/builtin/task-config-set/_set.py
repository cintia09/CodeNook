#!/usr/bin/env python3
"""task-config-set/_set.py — Layer-4 override writer"""
import json
import os
import sys

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

def main():
    task = os.environ["CN_TASK"]
    key = os.environ["CN_KEY"]
    value = os.environ.get("CN_VALUE", "")
    unset = os.environ.get("CN_UNSET", "0") == "1"
    state_file = os.environ["CN_STATE_FILE"]
    
    # Check key is in allow-list
    if key not in ALLOWED_KEYS:
        print(f"set.sh: key '{key}' not in allow-list", file=sys.stderr)
        sys.exit(1)
    
    # Load state
    with open(state_file, 'r') as f:
        state = json.load(f)
    
    if "config_overrides" not in state:
        state["config_overrides"] = {}
    
    if unset:
        # Remove the key
        if key in state["config_overrides"]:
            del state["config_overrides"][key]
    else:
        # Warn if value is not a known tier symbol or common model
        if value not in TIER_SYMBOLS and not is_known_model(value):
            print(f"set.sh: warning: unknown model value '{value}'", file=sys.stderr)
        
        # Set the value
        state["config_overrides"][key] = value
    
    # Write back
    with open(state_file, 'w') as f:
        json.dump(state, f, indent=2, ensure_ascii=False)
        f.write('\n')
    
    sys.exit(0)

def is_known_model(value):
    """Check if value looks like a known model ID (very permissive)"""
    # Just check if it contains common patterns - we warn anyway
    common_prefixes = ["gpt-", "claude-", "gemini-", "o1-", "o3-"]
    return any(value.startswith(p) for p in common_prefixes)

if __name__ == "__main__":
    main()
