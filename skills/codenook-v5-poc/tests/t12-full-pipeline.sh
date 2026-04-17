#!/usr/bin/env bash
# T12: designer + tester + acceptor full-pipeline static checks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SH="$POC_DIR/init.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
bash "$INIT_SH" > /tmp/t12-init.log 2>&1

FAIL=0
pass() { echo "  ✅ $1"; }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "=== T12: Full 6-phase Pipeline (designer + tester + acceptor) ==="
echo ""

# ---- [1] All new role files present ----
echo "[1] new role assets:"
for base in designer tester acceptor; do
  for f in ".codenook/prompts-templates/$base.md" \
           ".codenook/agents/$base.agent.md"; do
    [[ -f $f ]] && pass "$f" || fail "missing: $f"
  done
done
for phase in design test accept; do
  f=".codenook/prompts-criteria/criteria-$phase.md"
  [[ -f $f ]] && pass "$f" || fail "missing: $f"
done

# ---- [2] designer template content ----
echo ""
echo "[2] designer template:"
DT=".codenook/prompts-templates/designer.md"
for s in Overview "Module Layout" Interfaces "Data Model" "Control Flow" "Error" "Testing Strategy" "Risks"; do
  grep -q "$s" "$DT" && pass "section: $s" || fail "designer missing section: $s"
done
for v in design_ready needs_user_input infeasible; do
  grep -q "$v" "$DT" && pass "verdict: $v" || fail "designer missing verdict: $v"
done
grep -qi 'clarity_verdict != ready_to_implement\|NOT write implementation code' "$DT" && pass "anti-scope declared" || fail "designer missing anti-scope"

# ---- [3] tester template content ----
echo ""
echo "[3] tester template:"
TT=".codenook/prompts-templates/tester.md"
for s in "Test Inventory" Execution Failures "Coverage" "Environment"; do
  grep -q "$s" "$TT" && pass "section: $s" || fail "tester missing section: $s"
done
for v in all_pass has_failures blocked_by_env; do
  grep -q "$v" "$TT" && pass "verdict: $v" || fail "tester missing verdict: $v"
done
grep -qi 'NOT modify implementation\|not fix\|do NOT modify' "$TT" && pass "tester anti-fix declared" || fail "tester anti-fix missing"

# ---- [4] acceptor template content ----
echo ""
echo "[4] acceptor template:"
AT=".codenook/prompts-templates/acceptor.md"
for s in "Goal Achievement" "Criteria Checklist" Deviations "User-Visible" "Follow-up" Recommendation; do
  grep -q "$s" "$AT" && pass "section: $s" || fail "acceptor missing section: $s"
done
for v in "accept_verdict" "conditional_accept" reject; do
  grep -q "$v" "$AT" && pass "verdict: $v" || fail "acceptor missing verdict: $v"
done

# ---- [5] agent profiles have self-bootstrap ----
echo ""
echo "[5] agent profiles:"
for role in designer tester acceptor; do
  p=".codenook/agents/$role.agent.md"
  grep -q 'Self-Bootstrap Protocol' "$p" && pass "$role: self-bootstrap"  || fail "$role: no self-bootstrap"
  grep -q 'Absolute Prohibitions' "$p"   && pass "$role: prohibitions"    || fail "$role: no prohibitions"
  grep -q 'Hard Stops' "$p"              && pass "$role: hard stops"      || fail "$role: no hard stops"
  grep -q 'too_large' "$p"               && pass "$role: context budget"  || fail "$role: no too_large contract"
done

# ---- [6] config routing has all 6 phases ----
echo ""
echo "[6] config.yaml routing.phases:"
CFG=".codenook/config.yaml"
for phase in clarify design implement test accept validate; do
  grep -qE "^    - name: $phase$" "$CFG" && pass "phase listed: $phase" || fail "phase missing in config: $phase"
done
grep -A2 '^    - name: design'  "$CFG" | grep -q 'agent: designer'  && pass "design → designer"   || fail "design not routed to designer"
grep -A2 '^    - name: test'    "$CFG" | grep -q 'agent: tester'    && pass "test → tester"       || fail "test not routed to tester"
grep -A2 '^    - name: accept'  "$CFG" | grep -q 'agent: acceptor'  && pass "accept → acceptor"   || fail "accept not routed to acceptor"
for m in designer tester acceptor; do
  grep -qE "^  $m:" "$CFG" && pass "model entry: $m" || fail "no model entry: $m"
done

# ---- [7] core.md reflects full pipeline ----
echo ""
echo "[7] core.md pipeline references:"
CORE=".codenook/core/codenook-core.md"
grep -q 'dispatch_designer'  "$CORE" && pass "main loop: dispatch_designer"  || fail "core missing dispatch_designer"
grep -q 'dispatch_tester'    "$CORE" && pass "main loop: dispatch_tester"    || fail "core missing dispatch_tester"
grep -q 'dispatch_acceptor'  "$CORE" && pass "main loop: dispatch_acceptor"  || fail "core missing dispatch_acceptor"
grep -q 'test_verdict'       "$CORE" && pass "gate: test_verdict"            || fail "core missing test_verdict gate"
grep -q 'accept_verdict'     "$CORE" && pass "gate: accept_verdict"          || fail "core missing accept_verdict gate"
grep -q 'design_verdict'     "$CORE" && pass "gate: design_verdict"          || fail "core missing design_verdict gate"
grep -q 'conditional_accept' "$CORE" && pass "conditional_accept retry path" || fail "core missing conditional_accept path"
# routing table row checks
grep -qE '^\| design[ ]+\|' "$CORE"    && pass "routing table: design row"   || fail "no design row"
grep -qE '^\| test[ ]+\|' "$CORE"      && pass "routing table: test row"     || fail "no test row"
grep -qE '^\| accept[ ]+\|' "$CORE"    && pass "routing table: accept row"   || fail "no accept row"

# ---- [8] synthetic manifests lint clean for design/test/accept ----
echo ""
echo "[8] synthetic manifests for new phases:"
T_DIR=".codenook/tasks/T-001"
mkdir -p "$T_DIR/prompts" "$T_DIR/outputs" "$T_DIR/iterations/iter-1"
cat > "$T_DIR/task.md" <<EOF
Build a minimal CLI tool that prints "hello" and exits with code 0.
EOF

# simulate prior phase outputs so @ refs resolve
touch "$T_DIR/outputs/phase-1-clarify-summary.md"
touch "$T_DIR/outputs/phase-1-clarify.md"
touch "$T_DIR/outputs/phase-2-design-summary.md"
touch "$T_DIR/outputs/phase-3-implementer-summary.md"
touch "$T_DIR/outputs/phase-4-test-summary.md"

cat > "$T_DIR/prompts/phase-2-designer.md" <<EOF
Template: @../../../prompts-templates/designer.md
Variables:
  task_id: T-001
  phase: design
  task_description: @../task.md
  clarify_output: @../outputs/phase-1-clarify.md
  project_env: @../../../project/ENVIRONMENT.md
  project_conv: @../../../project/CONVENTIONS.md
  project_arch: @../../../project/ARCHITECTURE.md
Output_to: @../outputs/phase-2-design.md
Summary_to: @../outputs/phase-2-design-summary.md
EOF

cat > "$T_DIR/prompts/phase-4-tester.md" <<EOF
Template: @../../../prompts-templates/tester.md
Variables:
  task_id: T-001
  phase: test
  task_description: @../task.md
  clarify_output: @../outputs/phase-1-clarify-summary.md
  design_output: @../outputs/phase-2-design-summary.md
  impl_output: @../outputs/phase-3-implementer-summary.md
  project_env: @../../../project/ENVIRONMENT.md
  project_conv: @../../../project/CONVENTIONS.md
Output_to: @../outputs/phase-4-test.md
Summary_to: @../outputs/phase-4-test-summary.md
EOF

cat > "$T_DIR/prompts/phase-5-acceptor.md" <<EOF
Template: @../../../prompts-templates/acceptor.md
Variables:
  task_id: T-001
  phase: accept
  task_description: @../task.md
  clarify_output: @../outputs/phase-1-clarify-summary.md
  design_output: @../outputs/phase-2-design-summary.md
  impl_output: @../outputs/phase-3-implementer-summary.md
  test_output: @../outputs/phase-4-test-summary.md
  project_env: @../../../project/ENVIRONMENT.md
Output_to: @../outputs/phase-5-accept.md
Summary_to: @../outputs/phase-5-accept-summary.md
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
  done < <(grep -vE '^(Output_to|Summary_to):' "$mf" | grep -oE '@[A-Za-z0-9_./-]+' | sort -u)
  local size
  size=$(wc -c < "$mf" | tr -d ' ')
  [[ $size -le 2000 ]] || { echo "❌ manifest too large: $size bytes"; errs=$((errs+1)); }
  return $errs
}

for mf in "$T_DIR/prompts/phase-2-designer.md" \
          "$T_DIR/prompts/phase-4-tester.md" \
          "$T_DIR/prompts/phase-5-acceptor.md"; do
  name=$(basename "$mf")
  output=$(validate_manifest "$mf" 2>&1 && echo "__OK__" || echo "__FAIL__")
  if echo "$output" | grep -q '__OK__'; then
    pass "$name lints clean"
  else
    fail "$name FAILED"
    echo "$output"
  fi
done

echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "=== T12 PASSED ==="
  exit 0
else
  echo "=== T12 FAILED ($FAIL issues) ==="
  exit 1
fi
