#!/usr/bin/env bats
# M6 U2 — phases.yaml + transitions.yaml + entry-questions.yaml + hitl-gates.yaml
#
# Verifies the four core machine-readable phase descriptors of the
# development plugin parse cleanly, contain the expected 8-phase
# pipeline, and round-trip through orchestrator-tick.lookup_transition
# for every (phase, verdict) pair.

load helpers/load
load helpers/assertions

PLUGIN_DIR="$CORE_ROOT/../../plugins/development"
TICK_LIB="$CORE_ROOT/skills/builtin/orchestrator-tick/_tick.py"

py_yaml_load() {
  python3 - "$1" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    yaml.safe_load(f)
PY
}

@test "plugin dir exists" {
  [ -d "$PLUGIN_DIR" ]
}

@test "phases.yaml loads as valid YAML" {
  py_yaml_load "$PLUGIN_DIR/phases.yaml"
}

@test "phases.yaml has exactly 8 entries in expected order" {
  run python3 - "$PLUGIN_DIR/phases.yaml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
phases = doc["phases"]
ids = [p["id"] for p in phases]
expected = ["clarify","design","plan","implement","test","accept","validate","ship"]
assert ids == expected, ids
for p in phases:
    assert "role" in p and "produces" in p, p
print("ok")
PY
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "phases.yaml: implement supports iteration AND fanout" {
  run python3 - "$PLUGIN_DIR/phases.yaml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
imp = next(p for p in doc["phases"] if p["id"] == "implement")
assert imp.get("supports_iteration") is True
assert imp.get("allows_fanout") is True
assert imp.get("dual_mode_compatible") is True
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "phases.yaml: design has dual_mode_compatible" {
  run python3 - "$PLUGIN_DIR/phases.yaml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
des = next(p for p in doc["phases"] if p["id"] == "design")
assert des.get("dual_mode_compatible") is True
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "transitions.yaml loads and has all 8 phases" {
  run python3 - "$PLUGIN_DIR/transitions.yaml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
t = doc["transitions"]
assert set(t.keys()) == {"clarify","design","plan","implement","test","accept","validate","ship"}
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "transitions.yaml: every (phase, verdict) lookup resolves via lookup_transition" {
  run python3 - "$PLUGIN_DIR/transitions.yaml" "$TICK_LIB" <<'PY'
import sys, yaml, importlib.util
trans_path, tick_path = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("_tick", tick_path)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
doc = yaml.safe_load(open(trans_path))
phases = ["clarify","design","plan","implement","test","accept","validate","ship"]
verdicts = ["ok","needs_revision","blocked"]
for p in phases:
    for v in verdicts:
        nxt = mod.lookup_transition(doc, p, v)
        assert nxt is not None, f"missing transition: {p}/{v}"
        assert nxt in phases or nxt == "complete", f"bad target {p}/{v}={nxt}"
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "transitions.yaml: ship.ok terminates the task" {
  run python3 - "$PLUGIN_DIR/transitions.yaml" "$TICK_LIB" <<'PY'
import sys, yaml, importlib.util
spec = importlib.util.spec_from_file_location("_tick", sys.argv[2])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
doc = yaml.safe_load(open(sys.argv[1]))
assert mod.lookup_transition(doc, "ship", "ok") == "complete"
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "entry-questions.yaml loads and covers all 8 phases" {
  run python3 - "$PLUGIN_DIR/entry-questions.yaml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
phases = ["clarify","design","plan","implement","test","accept","validate","ship"]
for p in phases:
    assert p in doc, f"missing entry-question stanza: {p}"
    assert isinstance(doc[p].get("required", []), list)
# clarify must require dual_mode (per v5 §22.7 carry-forward)
assert "dual_mode" in doc["clarify"]["required"]
# implement must require dual_mode + max_iterations
imp = doc["implement"]["required"]
assert "dual_mode" in imp and "max_iterations" in imp and "target_dir" in imp
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "hitl-gates.yaml: every gate referenced from phases.yaml is defined" {
  run python3 - "$PLUGIN_DIR/phases.yaml" "$PLUGIN_DIR/hitl-gates.yaml" <<'PY'
import sys, yaml
phases = yaml.safe_load(open(sys.argv[1]))["phases"]
gates = yaml.safe_load(open(sys.argv[2])).get("gates", {})
referenced = {p["gate"] for p in phases if p.get("gate")}
for g in referenced:
    assert g in gates, f"phases.yaml references undefined gate: {g}"
    assert "trigger" in gates[g], g
    assert "required_reviewers" in gates[g], g
print("ok")
PY
  [ "$status" -eq 0 ]
}
