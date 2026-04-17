#!/usr/bin/env bash
# T15: Regression tests for deep-review fixes (P0/P1/P2)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SH="$POC_DIR/init.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
bash "$INIT_SH" > /tmp/t15-init.log 2>&1

FAIL=0
pass() { echo "  ✅ $1"; }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "=== T15: Deep-Review Regression Fixes ==="
echo ""

CORE=".codenook/core/codenook-core.md"
CFG=".codenook/config.yaml"

# ======================================================================
# P0-1: Tester / Acceptor / Planner read FULL clarify + design, NOT summary
# ======================================================================
echo "[P0-1] Full-file routing in tester/acceptor/planner:"

# tester.md
T=".codenook/prompts-templates/tester.md"
grep -q 'phase-1-clarify-summary.md' "$T" && fail "tester still routes clarify SUMMARY" \
                                          || pass "tester routes full clarify"
grep -q 'phase-2-design-summary.md' "$T"  && fail "tester still routes design SUMMARY" \
                                          || pass "tester routes full design"
grep -q 'phase-1-clarify.md' "$T"         && pass "tester has @phase-1-clarify.md" \
                                          || fail "tester missing full-clarify ref"
grep -q 'phase-2-design.md' "$T"          && pass "tester has @phase-2-design.md" \
                                          || fail "tester missing full-design ref"

# acceptor.md
A=".codenook/prompts-templates/acceptor.md"
grep -q 'phase-1-clarify-summary.md' "$A" && fail "acceptor still routes clarify SUMMARY" \
                                          || pass "acceptor routes full clarify"
grep -q 'phase-1-clarify.md' "$A"         && pass "acceptor has @phase-1-clarify.md" \
                                          || fail "acceptor missing full-clarify ref"

# planner.md
P=".codenook/prompts-templates/planner.md"
grep -q 'phase-1-clarify-summary.md' "$P" && fail "planner still routes clarify SUMMARY" \
                                          || pass "planner routes full clarify"
grep -q 'phase-1-clarify.md' "$P"         && pass "planner has @phase-1-clarify.md" \
                                          || fail "planner missing full-clarify ref"

# Tester / acceptor agent profiles mention FULL, not summary
TA=".codenook/agents/tester.agent.md"
AA=".codenook/agents/acceptor.agent.md"
grep -q 'FULL clarify spec' "$TA" && pass "tester agent documents FULL clarify" \
                                  || fail "tester agent still says summary"
grep -q 'FULL design spec'  "$TA" && pass "tester agent documents FULL design"  \
                                  || fail "tester agent still says summary for design"
grep -q 'FULL clarify spec' "$AA" && pass "acceptor agent documents FULL clarify" \
                                  || fail "acceptor agent still says summary"

# ======================================================================
# P0-2: Dual-agent loop exits to 'test' not 'validate'
# ======================================================================
echo ""
echo "[P0-2] Dual-agent loop exits to test phase:"
# §15 serial loop
section15=$(awk '/^## 15\./,/^## 16\./' "$CORE")
echo "$section15" | grep -q 'state.phase = "test"'    && pass "§15 sets phase=test on exit" \
                                                      || fail "§15 still exits to validate"
echo "$section15" | grep -q 'state.phase = "validate"' && fail "§15 still has phase=validate" \
                                                       || pass "§15 no leftover validate"
echo "$section15" | grep -q 'advance_phase()' && pass "§15 calls advance_phase()" \
                                              || fail "§15 no advance_phase()"
# §16 parallel loop
section16=$(awk '/^## 16\./,/^## 17\./' "$CORE")
echo "$section16" | grep -q 'state.phase = "test"'    && pass "§16 sets phase=test on exit" \
                                                      || fail "§16 still exits to validate"
echo "$section16" | grep -q 'advance_phase()' && pass "§16 calls advance_phase()" \
                                              || fail "§16 no advance_phase()"

# ======================================================================
# P0-3: Loop exhaustion without convergence escalates HITL
# ======================================================================
echo ""
echo "[P0-3] Non-converged loop exit → HITL:"
echo "$section15" | grep -q 'did not converge' && pass "§15 escalates on non-converge" \
                                               || fail "§15 silently proceeds on non-converge"
echo "$section16" | grep -q 'did not converge' && pass "§16 escalates on non-converge" \
                                               || fail "§16 silently proceeds on non-converge"

# ======================================================================
# P1-4: §8 validator is final-phase only (aligns with §5)
# ======================================================================
echo ""
echo "[P1-4] Validator gate rewrite:"
section8=$(awk '/^## 8\./,/^## 9\./' "$CORE")
echo "$section8" | grep -q 'After every worker phase'  && fail "§8 still claims per-phase" \
                                                       || pass "§8 no longer per-phase"
echo "$section8" | grep -qi 'final' && pass "§8 marks validator as final"   \
                                    || fail "§8 doesn't mark as final"
echo "$section8" | grep -q 'not_needed' && pass "§8 handles plan skip"       \
                                        || fail "§8 silent on plan skip"

# ======================================================================
# P1-5: Planner depth cap is unconditional (no escape hatch)
# ======================================================================
echo ""
echo "[P1-5] Planner depth cap unconditional:"
PA=".codenook/agents/planner.agent.md"
step6=$(awk '/^### Step 6 —/,/^### Step 7 —/' "$PA")
echo "$step6" | grep -q 'only permissible if'  && fail "planner Step 6 has escape hatch" \
                                                || pass "planner Step 6 no escape hatch"
echo "$step6" | grep -q 'unconditionally\|No exceptions' && pass "planner Step 6 hard stop" \
                                                         || fail "planner Step 6 not hard"

# ======================================================================
# P1-6: Step 2.5 forbids leaking skill name in summary/notes
# ======================================================================
echo ""
echo "[P1-6] Skill-leak guard in Step 2.5 (all 9 profiles):"
for f in .codenook/agents/*.agent.md; do
  name=$(basename "$f")
  grep -q 'Do NOT include the skill name in your returned' "$f" \
    && pass "$name: leak guard present" \
    || fail "$name: no leak guard"
done
# core §11 also warns
grep -q 'Sub-agent counterpart rule' "$CORE" && pass "core §11 has counterpart rule" \
                                              || fail "core §11 missing counterpart rule"

# ======================================================================
# P1-7: test_retry_count + conditional_retry_done in state schema + config
# ======================================================================
echo ""
echo "[P1-7] Retry bookkeeping fields declared:"
grep -q 'test_retry_count' "$CORE"        && pass "state schema: test_retry_count"   || fail "no test_retry_count in schema"
grep -q 'conditional_retry_done' "$CORE"  && pass "state schema: conditional_retry_done" || fail "no conditional_retry_done"
grep -qE '^test:' "$CFG"                  && pass "config.test block"                || fail "no test block in config"
grep -qE 'max_retries: [0-9]+' "$CFG" | head -1 > /dev/null
grep -A2 '^test:' "$CFG" | grep -q 'max_retries' && pass "config.test.max_retries"  || fail "no test.max_retries"
# §5 gate consumes them
grep -q 'state.test_retry_count' "$CORE"    && pass "§5 increments test_retry_count" || fail "§5 doesn't increment"
grep -q 'state.conditional_retry_done'   "$CORE" && pass "§5 sets conditional_retry_done" || fail "§5 doesn't set"

# ======================================================================
# P1-8: Routing table has single-impl row + path convention documented
# ======================================================================
echo ""
echo "[P1-8] Single-implementer routing + path convention:"
grep -q 'implement (single)' "$CORE"       && pass "routing table has single row"     || fail "no single row"
grep -q 'phase-3-implementer.md' "$CORE"   && pass "canonical phase-3 path documented" || fail "no phase-3 doc"
# tester/acceptor describe orchestrator selection
grep -q 'Orchestrator selects' "$T"                && pass "tester documents mode-conditional selection" || fail "tester still has OR"
grep -q 'orchestrator supplies canonical' "$A"     && pass "acceptor documents selection"                || fail "acceptor still has OR"

# ======================================================================
# P2-9: Reviewer gets clarify+design inputs
# ======================================================================
echo ""
echo "[P2-9] Reviewer inputs include clarify+design:"
R=".codenook/prompts-templates/reviewer.md"
grep -q 'clarify_output' "$R"  && pass "reviewer template: clarify_output var"  || fail "reviewer missing clarify_output"
grep -q 'design_output' "$R"   && pass "reviewer template: design_output var"   || fail "reviewer missing design_output"
# core §15 §16 manifest includes them
echo "$section15" | grep -q 'clarify_output: @../outputs/phase-1-clarify.md' && pass "§15 manifest: clarify_output" || fail "§15 missing clarify_output"
echo "$section16" | grep -q 'clarify_output: @../outputs/phase-1-clarify.md' && pass "§16 manifest: clarify_output" || fail "§16 missing clarify_output"

# ======================================================================
# P2-11: Tester budget raised to 28K
# ======================================================================
echo ""
echo "[P2-11] Tester budget adjusted:"
grep -q 'context > 28K' "$TA"  && pass "tester budget raised to 28K"  || fail "tester still 25K"

echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "=== T15 PASSED ==="
  exit 0
else
  echo "=== T15 FAILED ($FAIL issues) ==="
  exit 1
fi
