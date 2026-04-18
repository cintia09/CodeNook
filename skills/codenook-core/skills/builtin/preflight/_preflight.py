#!/usr/bin/env python3
"""preflight/_preflight.py — sanity check logic"""
import json
import os
import sys

def main():
    task = os.environ["CN_TASK"]
    state_file = os.environ["CN_STATE_FILE"]
    workspace = os.environ["CN_WORKSPACE"]
    json_out = os.environ.get("CN_JSON", "0") == "1"
    
    reasons = []
    
    # Load state
    try:
        with open(state_file, 'r') as f:
            state = json.load(f)
    except Exception as e:
        reasons.append(f"invalid state.json: {e}")
        emit_result(task, None, reasons, json_out, exit_code=1)
        return
    
    phase = state.get("phase", "")
    total_iterations = state.get("total_iterations", 0)
    dual_mode = state.get("dual_mode")
    config_overrides = state.get("config_overrides", {})
    
    # Check 1: dual_mode required if total_iterations > 1
    if total_iterations > 1 and dual_mode is None:
        reasons.append("needs dual_mode")
    
    # Check 2: known phase
    KNOWN_PHASES = ["start", "implement", "test", "review", "distill", "accept", "done"]
    if phase not in KNOWN_PHASES:
        reasons.append(f"unknown_phase: {phase}")
    
    # Check 3: blocking HITL queue entry
    hitl_queue = os.path.join(workspace, ".codenook/queues/hitl.jsonl")
    if os.path.exists(hitl_queue):
        with open(hitl_queue, 'r') as f:
            for line in f:
                try:
                    entry = json.loads(line.strip())
                    if entry.get("task") == task and entry.get("status") == "pending":
                        reasons.append("HITL gate blocking")
                        break
                except:
                    pass
    
    # Check 4: config overrides validation (whitelist from #45)
    ALLOWED_OVERRIDE_KEYS = [
        "models.default", "models.router", "models.planner", "models.executor", 
        "models.reviewer", "models.distiller", "hitl.mode"
    ]
    for key in config_overrides.keys():
        # Check top-level or nested keys
        is_allowed = False
        for allowed in ALLOWED_OVERRIDE_KEYS:
            if key == allowed or key.startswith(allowed.split('.')[0] + '.'):
                is_allowed = True
                break
        if not is_allowed:
            reasons.append(f"invalid config override key: {key}")
    
    # Sort and dedupe reasons
    reasons = sorted(list(set(reasons)))
    
    ok = len(reasons) == 0
    exit_code = 0 if ok else 1
    
    emit_result(task, phase, reasons, json_out, exit_code)

def emit_result(task, phase, reasons, json_out, exit_code):
    if json_out:
        result = {
            "ok": exit_code == 0,
            "task": task,
            "phase": phase,
            "reasons": reasons
        }
        print(json.dumps(result, ensure_ascii=False))
    else:
        if reasons:
            for r in reasons:
                print(r, file=sys.stderr)
    
    sys.exit(exit_code)

if __name__ == "__main__":
    main()
