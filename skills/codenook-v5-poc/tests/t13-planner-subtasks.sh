#!/usr/bin/env bash
# T13: planner role + subtask fan-out protocol static checks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SH="$POC_DIR/init.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
bash "$INIT_SH" > /tmp/t13-init.log 2>&1

FAIL=0
pass() { echo "  ✅ $1"; }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "=== T13: Planner + Subtask Fan-out Protocol ==="
echo ""

# ---- [1] planner files exist ----
echo "[1] planner assets:"
PT=".codenook/prompts-templates/planner.md"
PC=".codenook/prompts-criteria/criteria-plan.md"
PA=".codenook/agents/planner.agent.md"
[[ -f $PT ]] && pass "planner template"  || fail "planner template missing"
[[ -f $PC ]] && pass "planner criteria"  || fail "planner criteria missing"
[[ -f $PA ]] && pass "planner profile"   || fail "planner profile missing"

# ---- [2] planner template sections + verdicts ----
echo ""
echo "[2] planner template:"
for s in "Decomposition Rationale" "Subtask List" "Dependency Graph" "Integration Strategy" "Risks" "Depth Check"; do
  grep -q "$s" "$PT" && pass "section: $s" || fail "missing section: $s"
done
for v in decomposed not_needed too_complex; do
  grep -q "$v" "$PT" && pass "verdict: $v" || fail "missing verdict: $v"
done
grep -q 'Graph_to' "$PT"               && pass "Graph_to output contract" || fail "no Graph_to"
grep -qi 'depth.*2\|depth ≤ 2' "$PT"   && pass "depth cap 2 documented"   || fail "no depth cap"
grep -qi 'cycle' "$PT"                 && pass "cycle detection mentioned" || fail "no cycle check"

# ---- [3] planner criteria ----
echo ""
echo "[3] planner criteria:"
for s in Structural "Content Quality" "Verdict Gate" "Anti-Pattern"; do
  grep -q "$s" "$PC" && pass "criteria section: $s" || fail "criteria missing: $s"
done
grep -q 'dependency-graph.md' "$PC" && pass "criteria references graph file" || fail "no graph file reference"

# ---- [4] planner agent profile ----
echo ""
echo "[4] planner agent profile:"
grep -q 'Self-Bootstrap Protocol' "$PA"  && pass "self-bootstrap"           || fail "no self-bootstrap"
grep -q 'design_verdict' "$PA"           && pass "checks design_verdict"    || fail "no design_verdict check"
grep -q 'depth' "$PA"                    && pass "depth handling"           || fail "no depth handling"
grep -q 'Absolute Prohibitions' "$PA"    && pass "prohibitions"             || fail "no prohibitions"
grep -qi 'not create.*subtask director\|NEVER create subtask director' "$PA" && pass "dir creation excluded" || fail "no dir-creation guard"

# ---- [5] config.yaml routing has 'plan' phase ----
echo ""
echo "[5] config.yaml:"
CFG=".codenook/config.yaml"
grep -qE '^    - name: plan$' "$CFG" && pass "plan phase listed"         || fail "no plan phase in routing"
grep -A3 '^    - name: plan' "$CFG" | grep -q 'agent: planner'   && pass "plan → planner"  || fail "plan not routed to planner"
grep -A4 '^    - name: plan' "$CFG" | grep -q 'optional: true'   && pass "plan marked optional" || fail "plan not marked optional"
grep -qE '^  planner:' "$CFG" && pass "planner model entry" || fail "no planner model"

# ---- [6] core.md updates ----
echo ""
echo "[6] core.md:"
CORE=".codenook/core/codenook-core.md"
grep -qE '^\| plan[ ]+\|' "$CORE"       && pass "routing table: plan row"     || fail "no plan row in routing table"
grep -q 'dispatch_planner' "$CORE"      && pass "main loop dispatches planner" || fail "no dispatch_planner"
grep -q 'plan_verdict' "$CORE"          && pass "plan_verdict gate present"   || fail "no plan_verdict gate"
grep -q 'fan_out_subtasks' "$CORE"      && pass "fan_out_subtasks reference"  || fail "no fan_out_subtasks"
grep -q '## 17' "$CORE"                 && pass "§17 Subtask Fan-out present" || fail "no §17 section"
grep -q '17.1 Directory Seeding' "$CORE" && pass "§17.1 directory seeding"    || fail "no §17.1"
grep -q '17.2 Scheduling' "$CORE"       && pass "§17.2 scheduling"            || fail "no §17.2"
grep -q '17.3 Subtask Lifecycle' "$CORE" && pass "§17.3 lifecycle"            || fail "no §17.3"
grep -q '17.4 Parent-Level Integration' "$CORE" && pass "§17.4 integration"  || fail "no §17.4"
grep -q 'integration_phases' "$CORE"    && pass "integration_phases in state schema" || fail "no integration_phases"
grep -qi 'depth cap: 2\|depth.*2' "$CORE" && pass "depth cap rule in §17"     || fail "no depth cap in §17"

# ---- [7] synthetic planner manifest + dependency graph ----
echo ""
echo "[7] synthetic planner manifest + graph:"
T_DIR=".codenook/tasks/T-001"
mkdir -p "$T_DIR/prompts" "$T_DIR/outputs" "$T_DIR/decomposition"
cat > "$T_DIR/task.md" <<EOF
Build a multi-module CLI tool with storage backend, business logic, and REST API.
EOF
touch "$T_DIR/outputs/phase-1-clarify-summary.md"
touch "$T_DIR/outputs/phase-2-design.md"

cat > "$T_DIR/prompts/phase-plan-planner.md" <<EOF
Template: @../../../prompts-templates/planner.md
Variables:
  task_id: T-001
  phase: plan
  task_description: @../task.md
  clarify_output: @../outputs/phase-1-clarify-summary.md
  design_output: @../outputs/phase-2-design.md
  project_env: @../../../project/ENVIRONMENT.md
  project_conv: @../../../project/CONVENTIONS.md
  max_agent_context: 30000
Output_to: @../decomposition/plan.md
Graph_to: @../decomposition/dependency-graph.md
Summary_to: @../decomposition/plan-summary.md
EOF

validate_manifest() {
  local mf="$1"
  local errs=0
  for k in Template Variables Output_to Summary_to; do
    grep -qE "^${k}:" "$mf" || { echo "❌ missing field: $k"; errs=$((errs+1)); }
  done
  local mdir
  mdir=$(dirname "$mf")
  while IFS= read -r ref; do
    ref_path="${ref#@}"
    abs="$mdir/$ref_path"
    [[ -e $abs ]] || { echo "❌ broken @ ref: $ref → $abs"; errs=$((errs+1)); }
  done < <(grep -vE '^(Output_to|Graph_to|Summary_to):' "$mf" | grep -oE '@[A-Za-z0-9_./-]+' | sort -u)
  local size
  size=$(wc -c < "$mf" | tr -d ' ')
  [[ $size -le 2000 ]] || { echo "❌ manifest too large: $size bytes"; errs=$((errs+1)); }
  return $errs
}

output=$(validate_manifest "$T_DIR/prompts/phase-plan-planner.md" 2>&1 && echo "__OK__" || echo "__FAIL__")
if echo "$output" | grep -q '__OK__'; then
  pass "phase-plan-planner.md lints clean"
else
  fail "phase-plan-planner.md FAILED"
  echo "$output"
fi

# ---- [8] subtask directory structure mock (depth 2 cap) ----
echo ""
echo "[8] subtask directory structure (mock depth 2):"
mkdir -p "$T_DIR/subtasks/T-001.1/prompts"
mkdir -p "$T_DIR/subtasks/T-001.2/prompts"
# task_id pattern validation
SUBTASK_ID="T-001.1"
SUBSUBTASK_ID="T-001.1.1"
# Count dots to verify depth detection logic documented in planner profile
depth_of() { echo "$1" | awk -F'.' '{print NF-1}'; }
[[ $(depth_of "$SUBTASK_ID") -eq 1 ]]     && pass "T-001.1 is depth 1 (OK)"    || fail "depth calc broken"
[[ $(depth_of "$SUBSUBTASK_ID") -eq 2 ]]  && pass "T-001.1.1 is depth 2 (cap)" || fail "depth calc broken"

# Check planner profile enforces the cap
grep -q 'task_id.*contains a dot\|task_id.*contains two dots\|depth 2' "$PA" && pass "profile detects depth-2 case" || fail "profile doesn't detect depth-2"

echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "=== T13 PASSED ==="
  exit 0
else
  echo "=== T13 FAILED ($FAIL issues) ==="
  exit 1
fi
