#!/usr/bin/env bash
# T9: dual-agent serial-mode static checks
#   - config.yaml exposes dual_agent.default_mode = serial and max_iterations
#   - reviewer template exists and references the right variables
#   - reviewer agent profile has the 10-step self-bootstrap contract
#   - a synthetic dual-agent manifest for iter-1 reviewer passes the manifest linter
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SH="$POC_DIR/init.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"
bash "$INIT_SH" > /tmp/t9-init.log 2>&1

FAIL=0
pass() { echo "  ✅ $1"; }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

echo "=== T9: Dual-Agent Serial Mode Static Checks ==="
echo ""

# ---- [1] config.yaml dual_agent block ----
echo "[1] config.yaml dual_agent block:"
CFG=".codenook/config.yaml"
if [[ ! -f $CFG ]]; then
  fail "config.yaml missing"
else
  grep -q 'dual_agent:' "$CFG"             && pass "dual_agent: present"          || fail "dual_agent: missing"
  grep -qE 'enabled:[[:space:]]*true' "$CFG" && pass "dual_agent.enabled: true"     || fail "dual_agent.enabled not true"
  grep -qE 'default_mode:[[:space:]]*"serial"' "$CFG" && pass "default_mode: serial" || fail "default_mode not serial"
  grep -qE 'max_iterations:[[:space:]]*[0-9]+' "$CFG" && pass "max_iterations set"   || fail "max_iterations not set"
fi

# ---- [2] reviewer template ----
echo ""
echo "[2] reviewer template:"
RT=".codenook/prompts-templates/reviewer.md"
if [[ ! -f $RT ]]; then
  fail "reviewer.md missing"
else
  pass "reviewer.md present"
  for var in implementer_output implementer_summary review_criteria previous_review; do
    if grep -q "$var" "$RT"; then
      pass "var referenced: $var"
    else
      fail "var NOT referenced: $var"
    fi
  done
  grep -q 'overall_verdict' "$RT" && pass "overall_verdict defined" || fail "overall_verdict missing"
  grep -q 'issue_count' "$RT"     && pass "issue_count defined"     || fail "issue_count missing"
fi

# ---- [3] reviewer agent profile ----
echo ""
echo "[3] reviewer agent profile:"
RA=".codenook/agents/reviewer.agent.md"
if [[ ! -f $RA ]]; then
  fail "reviewer.agent.md missing"
else
  pass "reviewer.agent.md present"
  grep -q 'Self-Bootstrap Protocol' "$RA" && pass "self-bootstrap section"    || fail "no self-bootstrap section"
  grep -q 'Step 1' "$RA"                  && pass "step enumeration"           || fail "no Step 1"
  grep -q 'too_large' "$RA"               && pass "too_large contract"         || fail "no too_large contract"
  grep -q 'NEVER write code' "$RA" || grep -q 'You NEVER write code' "$RA" && pass "anti-scope declared" || fail "anti-scope missing"
fi

# ---- [4] core.md dual-agent section ----
echo ""
echo "[4] core.md dual-agent section:"
CORE=".codenook/core/codenook-core.md"
grep -q 'Dual-Agent Serial Protocol' "$CORE" && pass "§15 Dual-Agent Serial Protocol" || fail "no §15 Dual-Agent Serial Protocol"
grep -q 'max_iterations' "$CORE"             && pass "max_iterations referenced"       || fail "max_iterations not referenced"
grep -q 'looks_good' "$CORE"                 && pass "looks_good verdict handled"      || fail "looks_good not referenced"
grep -q 'fundamental_problems' "$CORE"       && pass "fundamental_problems handled"    || fail "fundamental_problems not referenced"

# ---- [5] synthetic iter-1 reviewer manifest passes lint ----
echo ""
echo "[5] synthetic iter-1 reviewer manifest lints clean:"
mkdir -p ".codenook/tasks/T-001/iterations/iter-1"
mkdir -p ".codenook/tasks/T-001/prompts"
cat > .codenook/tasks/T-001/iterations/iter-1/implement.md <<EOF
# dummy implementer output
placeholder
EOF
cat > .codenook/tasks/T-001/iterations/iter-1/implement-summary.md <<EOF
placeholder summary
EOF
cat > .codenook/tasks/T-001/prompts/iter-1-reviewer.md <<EOF
Template: @../../../prompts-templates/reviewer.md
Variables:
  task_id: T-001
  phase: review
  iteration: 1
  task_description: @../task.md
  implementer_output: @../iterations/iter-1/implement.md
  implementer_summary: @../iterations/iter-1/implement-summary.md
  project_env: @../../../project/ENVIRONMENT.md
  project_conv: @../../../project/CONVENTIONS.md
  review_criteria: @../../../prompts-criteria/criteria-review.md
Output_to: @../iterations/iter-1/review.md
Summary_to: @../iterations/iter-1/review-summary.md
EOF
touch .codenook/tasks/T-001/task.md

# reuse lint function from T8 by sourcing a minimal inline validator
validate_manifest() {
  local mf="$1"
  local errs=0
  local required=(Template Variables Output_to Summary_to)
  for k in "${required[@]}"; do
    grep -qE "^${k}:" "$mf" || { echo "❌ missing field: $k"; errs=$((errs+1)); }
  done
  # all @ refs on INPUT lines must resolve; Output_to/Summary_to are destinations (may not exist yet)
  local mdir
  mdir=$(dirname "$mf")
  while IFS= read -r ref; do
    ref_path="${ref#@}"
    abs="$mdir/$ref_path"
    if [[ ! -e $abs ]]; then
      echo "❌ broken @ ref: $ref → $abs"
      errs=$((errs+1))
    fi
  done < <(grep -vE '^(Output_to|Summary_to):' "$mf" | grep -oE '@[A-Za-z0-9_./-]+' | sort -u)
  local size
  size=$(wc -c < "$mf" | tr -d ' ')
  [[ $size -le 2000 ]] || { echo "❌ manifest too large: $size bytes"; errs=$((errs+1)); }
  return $errs
}

MANIFEST=".codenook/tasks/T-001/prompts/iter-1-reviewer.md"
output=$(validate_manifest "$MANIFEST" 2>&1 && echo "__OK__" || echo "__FAIL__")
if echo "$output" | grep -q '__OK__'; then
  pass "iter-1 reviewer manifest passes all lint checks"
else
  fail "iter-1 reviewer manifest FAILED lint"
  echo "$output"
fi

echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "=== T9 PASSED ==="
  exit 0
else
  echo "=== T9 FAILED ($FAIL issues) ==="
  exit 1
fi
