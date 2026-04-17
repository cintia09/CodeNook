#!/usr/bin/env bash
# T18: Queue Runtime MVP — queue/*.json, locks/, §19 protocol, dependency
# graph parser, queue-runner.sh CLI
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SH="$POC_DIR/init.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
bash "$INIT_SH" > /tmp/t18-init.log 2>&1

FAIL=0
pass() { echo "  ✅ $1"; }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "=== T18: Queue Runtime MVP ==="
echo ""

# ----------------------------------------------------------------------
# [1] Workspace layout
# ----------------------------------------------------------------------
echo "[1] Workspace layout:"
[[ -d .codenook/queue ]]                     && pass "queue/ exists"             || fail "queue/ missing"
[[ -d .codenook/locks ]]                     && pass "locks/ exists"             || fail "locks/ missing"
[[ -f .codenook/queue/pending.json ]]        && pass "pending.json initialized"  || fail "pending.json missing"
[[ -f .codenook/queue/dispatching.json ]]    && pass "dispatching.json init'd"   || fail "dispatching.json missing"
[[ -f .codenook/queue/completed.json ]]      && pass "completed.json init'd"     || fail "completed.json missing"
[[ -f .codenook/dependency-graph-schema.md ]]&& pass "dep-graph schema copied"   || fail "schema missing"
[[ -x .codenook/queue-runner.sh ]]           && pass "queue-runner.sh executable"|| fail "queue-runner.sh not executable"
grep -q '"items"' .codenook/queue/pending.json && pass "pending.json has items[]" || fail "pending.json malformed"

# ----------------------------------------------------------------------
# [2] Schema + config
# ----------------------------------------------------------------------
echo ""
echo "[2] Schema & config:"
S=.codenook/dependency-graph-schema.md
grep -q '## Nodes'     "$S" && pass "schema documents ## Nodes section" || fail "schema missing Nodes"
grep -q '## Edges'     "$S" && pass "schema documents ## Edges section" || fail "schema missing Edges"
grep -q 'depends_on'   "$S" && pass "schema defines depends_on edge"    || fail "no depends_on"
grep -q 'Max depth'    "$S" && pass "schema bounds depth"               || fail "no depth bound"

C=.codenook/config.yaml
grep -q 'max_parallel_tasks'   "$C" && pass "config has max_parallel_tasks"   || fail "no max_parallel_tasks"
grep -q 'per_role_limit'       "$C" && pass "config has per_role_limit"       || fail "no per_role_limit"
grep -q 'stale_dispatch'       "$C" && pass "config has stale_dispatch flag"  || fail "no stale_dispatch"

# ----------------------------------------------------------------------
# [3] core.md §19
# ----------------------------------------------------------------------
echo ""
echo "[3] core.md §19:"
K=.codenook/core/codenook-core.md
s19=$(awk '/^## 19\. Queue Runtime/{on=1} on' "$K")
# awk range with no terminator picks up to EOF if no ## 20 — acceptable
[[ -n "$s19" ]] && pass "§19 present" || fail "§19 missing"
echo "$s19" | grep -q 'pending.json'          && pass "§19 references pending.json"      || fail "§19 no pending.json"
echo "$s19" | grep -q 'dispatching.json'      && pass "§19 references dispatching.json"  || fail "§19 no dispatching.json"
echo "$s19" | grep -q 'completed.json'        && pass "§19 references completed.json"    || fail "§19 no completed.json"
echo "$s19" | grep -q 'SWEEP'                 && pass "§19 documents SWEEP step"         || fail "§19 no SWEEP"
echo "$s19" | grep -q 'READY'                 && pass "§19 documents READY step"         || fail "§19 no READY"
echo "$s19" | grep -q 'DISPATCH'              && pass "§19 documents DISPATCH step"      || fail "§19 no DISPATCH"
echo "$s19" | grep -q 'agent_id'              && pass "§19 defines agent_id format"      || fail "§19 no agent_id"
echo "$s19" | grep -q 'dependency-graph'      && pass "§19 references dep graph"         || fail "§19 no dep-graph ref"
echo "$s19" | grep -q 'queue-runner.sh'       && pass "§19 references queue-runner.sh"   || fail "§19 no runner ref"
echo "$s19" | grep -q 'locks/'                && pass "§19 references locks/"            || fail "§19 no locks/"
echo "$s19" | grep -qi 'cycle'                && pass "§19 handles cycles"               || fail "§19 no cycle mention"
echo "$s19" | grep -qi 'hitl'                 && pass "§19 ties into HITL"               || fail "§19 no HITL ref"

# ----------------------------------------------------------------------
# [4] queue-runner.sh basic CLI
# ----------------------------------------------------------------------
echo ""
echo "[4] queue-runner.sh basic commands:"
R=.codenook/queue-runner.sh
status_out=$(bash "$R" status)
[[ "$status_out" == *"pending:"* ]]           && pass "status prints counts"     || fail "status broken"
[[ "$status_out" == *"pending:     0"* ]]     && pass "empty pending=0"          || fail "pending count wrong"
list_out=$(bash "$R" list pending)
[[ "$list_out" == *"empty"* ]]                && pass "list pending empty"       || fail "list empty broken"
help_out=$(bash "$R" help)
[[ "$help_out" == *"Queue Runtime helper"* ]] && pass "help prints banner"       || fail "help broken"

# ----------------------------------------------------------------------
# [5] Dependency graph parsing + ready set
# ----------------------------------------------------------------------
echo ""
echo "[5] Dependency graph parser + ready set:"
TID=T-003
mkdir -p ".codenook/tasks/$TID/decomposition"
cat > ".codenook/tasks/$TID/decomposition/dependency-graph.md" <<'GRAPH_EOF'
# Dependency Graph — T-003

## Nodes

- T-003.1: Database schema
- T-003.2: API layer
- T-003.3: Business logic
- T-003.4: E2E tests

## Edges

- T-003.2 depends_on T-003.1
- T-003.3 depends_on T-003.1
- T-003.3 depends_on T-003.2
- T-003.4 depends_on T-003.3
GRAPH_EOF

# Initial state: nothing done → only T-003.1 ready
cat > ".codenook/tasks/$TID/state.json" <<'STATE_EOF'
{
  "task_id": "T-003",
  "subtasks": [
    {"id": "T-003.1", "status": "pending", "depends_on": []},
    {"id": "T-003.2", "status": "pending", "depends_on": ["T-003.1"]},
    {"id": "T-003.3", "status": "pending", "depends_on": ["T-003.1","T-003.2"]},
    {"id": "T-003.4", "status": "pending", "depends_on": ["T-003.3"]}
  ]
}
STATE_EOF

# deps output
deps_out=$(bash "$R" deps "$TID")
printf '%s\n' "$deps_out" | grep -q $'^T-003\\.2\tT-003\\.1$' && pass "deps parses T-003.2→T-003.1" || fail "edge T-003.2 missing"
printf '%s\n' "$deps_out" | grep -q $'^T-003\\.4\tT-003\\.3$' && pass "deps parses T-003.4→T-003.3" || fail "edge T-003.4 missing"
[[ $(printf '%s\n' "$deps_out" | wc -l | tr -d ' ') == "4" ]] && pass "deps returns exactly 4 edges" || fail "edge count wrong"

# ready (initial)
if ready0=$(bash "$R" ready "$TID" 2>/tmp/t18-ready.err); then
  [[ "$(echo "$ready0" | tr -d ' \n')" == "T-003.1" ]] && pass "ready set = {T-003.1} initially" || { fail "ready set wrong: '$ready0'"; cat /tmp/t18-ready.err >&2 || true; }
else
  fail "ready command exited non-zero (python3 likely missing)"
fi

# Mark T-003.1 done, ready should be T-003.2
python3 -c '
import json
s=json.load(open(".codenook/tasks/T-003/state.json"))
s["subtasks"][0]["status"]="done"
json.dump(s,open(".codenook/tasks/T-003/state.json","w"),indent=2)
'
ready1=$(bash "$R" ready "$TID")
[[ "$(echo "$ready1" | tr -d ' \n')" == "T-003.2" ]] && pass "after T-003.1 done, ready = {T-003.2}" || fail "ready wrong after step 1: '$ready1'"

# Mark T-003.2 done too, ready should be T-003.3
python3 -c '
import json
s=json.load(open(".codenook/tasks/T-003/state.json"))
s["subtasks"][1]["status"]="done"
json.dump(s,open(".codenook/tasks/T-003/state.json","w"),indent=2)
'
ready2=$(bash "$R" ready "$TID")
[[ "$(echo "$ready2" | tr -d ' \n')" == "T-003.3" ]] && pass "after 1,2 done, ready = {T-003.3}" || fail "ready wrong after step 2: '$ready2'"

# cycles — should be acyclic
bash "$R" cycles "$TID" | grep -q acyclic && pass "acyclic graph detected as acyclic" || fail "cycles false positive"

# ----------------------------------------------------------------------
# [6] Cycle detection
# ----------------------------------------------------------------------
echo ""
echo "[6] Cycle detection:"
CID=T-666
mkdir -p ".codenook/tasks/$CID/decomposition"
cat > ".codenook/tasks/$CID/decomposition/dependency-graph.md" <<'CYCLE_EOF'
# Dependency Graph — T-666

## Nodes

- T-666.1: A
- T-666.2: B
- T-666.3: C

## Edges

- T-666.1 depends_on T-666.3
- T-666.2 depends_on T-666.1
- T-666.3 depends_on T-666.2
CYCLE_EOF
if bash "$R" cycles "$CID" 2>/dev/null; then
  fail "cycle not detected"
else
  rc=$?
  [[ $rc -eq 2 ]] && pass "cycle correctly detected (exit 2)" || fail "cycle exit code wrong: $rc"
fi

# ----------------------------------------------------------------------
# [7] File lock acquire/release
# ----------------------------------------------------------------------
echo ""
echo "[7] File lock:"
bash "$R" lock src/module.py agent-A > /dev/null && pass "lock acquire ok" || fail "lock failed"
[[ -f .codenook/locks/src-module.py.lock ]] && pass "lock file exists" || fail "no lock file"
grep -q 'holder: agent-A' .codenook/locks/src-module.py.lock && pass "lock records holder" || fail "no holder"
# Second acquire must fail
if bash "$R" lock src/module.py agent-B 2>/dev/null; then
  fail "second lock succeeded (should fail)"
else
  rc=$?
  [[ $rc -eq 2 ]] && pass "second lock rejected (exit 2)" || fail "second lock exit wrong: $rc"
fi
bash "$R" unlock src/module.py > /dev/null && [[ ! -f .codenook/locks/src-module.py.lock ]] \
  && pass "unlock removes lock file" || fail "unlock failed"

# ----------------------------------------------------------------------
# [8] Sweep behavior (dispatching → completed)
# ----------------------------------------------------------------------
echo ""
echo "[8] Sweep dispatching → completed:"
# Craft a dispatching item whose expected_output already exists
mkdir -p .codenook/tasks/T-003.1/outputs
echo "done output" > .codenook/tasks/T-003.1/outputs/phase-3-implementer.md
cat > .codenook/queue/dispatching.json <<'DISP_EOF'
{
  "items": [
    {
      "agent_id": "T-003.1-implement-1737200000",
      "agent_type": "implementer",
      "task_id": "T-003.1",
      "phase": "implement",
      "prompt_file": ".codenook/tasks/T-003.1/prompts/phase-3-implementer.md",
      "expected_output": ".codenook/tasks/T-003.1/outputs/phase-3-implementer.md",
      "dispatched_at": "2025-01-20T10:00:00Z",
      "status": "dispatching"
    }
  ]
}
DISP_EOF

bash "$R" sweep > /tmp/t18-sweep.log 2>&1
if grep -q 'swept 1' /tmp/t18-sweep.log; then
  pass "sweep moved 1 item"
else
  fail "sweep did not move item"
  cat /tmp/t18-sweep.log >&2 || true
fi
# Verify dispatching is now empty and completed has the item
python3 -c '
import json, sys
d=json.load(open(".codenook/queue/dispatching.json"))
c=json.load(open(".codenook/queue/completed.json"))
assert len(d["items"])==0, f"dispatching not drained: {d}"
assert len(c["items"])==1, f"completed count wrong: {c}"
assert c["items"][0]["agent_id"]=="T-003.1-implement-1737200000"
assert c["items"][0].get("completed_at"), "no completed_at"
' && pass "post-sweep state correct" || fail "post-sweep state wrong"

echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "=== T18 PASSED ==="
  exit 0
else
  echo "=== T18 FAILED ($FAIL issues) ==="
  exit 1
fi
