#!/usr/bin/env bats
# M7 writing U2 -- phases/transitions/entry-questions/hitl-gates yaml.

load helpers/load
load helpers/assertions

PLUGIN_DIR="$CORE_ROOT/../../plugins/writing"
TICK_LIB="$CORE_ROOT/skills/builtin/orchestrator-tick/_tick.py"

@test "writing plugin dir exists" {
  [ -d "$PLUGIN_DIR" ]
}

@test "writing phases.yaml has 5 entries in expected order" {
  run python3 - "$PLUGIN_DIR/phases.yaml" <<'PY'
import sys, yaml
phases = yaml.safe_load(open(sys.argv[1]))["phases"]
ids = [p["id"] for p in phases]
expected = ["outline","draft","review","revise","publish"]
assert ids == expected, ids
roles = {p["id"]: p["role"] for p in phases}
assert roles == {
    "outline": "outliner",
    "draft":   "drafter",
    "review":  "reviewer",
    "revise":  "reviser",
    "publish": "publisher",
}, roles
print("ok")
PY
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "writing phases.yaml: draft supports iteration AND dual mode" {
  run python3 - "$PLUGIN_DIR/phases.yaml" <<'PY'
import sys, yaml
phases = yaml.safe_load(open(sys.argv[1]))["phases"]
draft = next(p for p in phases if p["id"] == "draft")
assert draft.get("supports_iteration") is True
assert draft.get("dual_mode_compatible") is True
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "writing transitions.yaml: every (phase, verdict) lookup resolves" {
  run python3 - "$PLUGIN_DIR/transitions.yaml" "$TICK_LIB" <<'PY'
import sys, yaml, importlib.util
spec = importlib.util.spec_from_file_location("_tick", sys.argv[2])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
doc = yaml.safe_load(open(sys.argv[1]))
phases = ["outline","draft","review","revise","publish"]
for p in phases:
    for v in ("ok","needs_revision","blocked"):
        nxt = mod.lookup_transition(doc, p, v)
        assert nxt is not None, f"missing {p}/{v}"
        assert nxt in phases or nxt == "complete", f"bad {p}/{v}={nxt}"
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "writing transitions.yaml: publish.ok terminates the task" {
  run python3 - "$PLUGIN_DIR/transitions.yaml" "$TICK_LIB" <<'PY'
import sys, yaml, importlib.util
spec = importlib.util.spec_from_file_location("_tick", sys.argv[2])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
doc = yaml.safe_load(open(sys.argv[1]))
assert mod.lookup_transition(doc, "publish", "ok") == "complete"
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "writing entry-questions.yaml: outline requires title" {
  run python3 - "$PLUGIN_DIR/entry-questions.yaml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
for p in ("outline","draft","review","revise","publish"):
    assert p in doc, f"missing {p}"
assert "title" in doc["outline"]["required"]
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "writing hitl-gates.yaml: pre_publish defined and referenced" {
  run python3 - "$PLUGIN_DIR/phases.yaml" "$PLUGIN_DIR/hitl-gates.yaml" <<'PY'
import sys, yaml
phases = yaml.safe_load(open(sys.argv[1]))["phases"]
gates = yaml.safe_load(open(sys.argv[2]))["gates"]
referenced = {p["gate"] for p in phases if p.get("gate")}
assert "pre_publish" in referenced
assert "pre_publish" in gates
assert gates["pre_publish"]["required_reviewers"] == ["human"]
print("ok")
PY
  [ "$status" -eq 0 ]
}
