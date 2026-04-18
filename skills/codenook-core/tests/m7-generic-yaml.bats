#!/usr/bin/env bats
# M7 generic U2 -- phases / transitions / entry-questions / hitl-gates yaml
# validity + structural invariants for the generic fallback plugin.

load helpers/load
load helpers/assertions

PLUGIN_DIR="$CORE_ROOT/../../plugins/generic"
TICK_LIB="$CORE_ROOT/skills/builtin/orchestrator-tick/_tick.py"

@test "generic plugin dir exists" {
  [ -d "$PLUGIN_DIR" ]
}

@test "generic phases.yaml loads as valid YAML" {
  python3 -c "import yaml; yaml.safe_load(open('$PLUGIN_DIR/phases.yaml'))"
}

@test "generic phases.yaml has exactly 4 entries in expected order" {
  run python3 - "$PLUGIN_DIR/phases.yaml" <<'PY'
import sys, yaml
phases = yaml.safe_load(open(sys.argv[1]))["phases"]
ids = [p["id"] for p in phases]
expected = ["clarify","analyze","execute","deliver"]
assert ids == expected, ids
for p in phases:
    assert "role" in p and "produces" in p, p
print("ok")
PY
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "generic transitions.yaml has all 4 phases" {
  run python3 - "$PLUGIN_DIR/transitions.yaml" <<'PY'
import sys, yaml
t = yaml.safe_load(open(sys.argv[1]))["transitions"]
assert set(t.keys()) == {"clarify","analyze","execute","deliver"}, t.keys()
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "generic transitions.yaml: every (phase, verdict) lookup resolves" {
  run python3 - "$PLUGIN_DIR/transitions.yaml" "$TICK_LIB" <<'PY'
import sys, yaml, importlib.util
trans_path, tick_path = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("_tick", tick_path)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
doc = yaml.safe_load(open(trans_path))
phases = ["clarify","analyze","execute","deliver"]
for p in phases:
    for v in ("ok","needs_revision","blocked"):
        nxt = mod.lookup_transition(doc, p, v)
        assert nxt is not None, f"missing {p}/{v}"
        assert nxt in phases or nxt == "complete", f"bad target {p}/{v}={nxt}"
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "generic transitions.yaml: deliver.ok terminates the task" {
  run python3 - "$PLUGIN_DIR/transitions.yaml" "$TICK_LIB" <<'PY'
import sys, yaml, importlib.util
spec = importlib.util.spec_from_file_location("_tick", sys.argv[2])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
doc = yaml.safe_load(open(sys.argv[1]))
assert mod.lookup_transition(doc, "deliver", "ok") == "complete"
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "generic entry-questions.yaml covers all 4 phases with empty required lists" {
  run python3 - "$PLUGIN_DIR/entry-questions.yaml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
for p in ("clarify","analyze","execute","deliver"):
    assert p in doc, f"missing {p}"
    req = doc[p].get("required", [])
    assert isinstance(req, list)
    assert req == [], f"generic should require nothing at {p}: {req}"
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "generic hitl-gates.yaml: empty gates by default" {
  run python3 - "$PLUGIN_DIR/hitl-gates.yaml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
gates = doc.get("gates") or {}
assert gates == {}, gates
print("ok")
PY
  [ "$status" -eq 0 ]
}
