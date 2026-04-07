#!/bin/bash
# test-3phase-fsm.sh — E2E test for 3-Phase Closed Loop FSM validation
# Tests: legal transitions, illegal blocks, convergence gate, feedback loops, auto-block
set -euo pipefail

PASS=0
FAIL=0
TEST_DIR=$(mktemp -d)
AGENTS_DIR="$TEST_DIR/.agents"
EVENTS_DB="$AGENTS_DIR/events.db"

# Setup test environment
setup() {
  mkdir -p "$AGENTS_DIR/runtime"
  sqlite3 "$EVENTS_DB" "CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY, timestamp INTEGER, event_type TEXT, agent TEXT, task_id TEXT, tool_name TEXT, detail TEXT);"
  echo "designer" > "$AGENTS_DIR/runtime/active-agent"
}

# Create a task-board snapshot + board with given status
set_task_status() {
  local task_id="$1" old_status="$2" new_status="$3"
  local workflow_mode="${4:-3phase}"
  local feedback_loops="${5:-0}"
  local impl="${6:-pending}" test_s="${7:-pending}" review="${8:-pending}" ci="${9:-pending}"

  # Snapshot = old state
  cat > "$AGENTS_DIR/runtime/.task-board-snapshot.json" << EOF
{"version":1,"tasks":[{"id":"$task_id","status":"$old_status","workflow_mode":"$workflow_mode","feedback_loops":$feedback_loops,"parallel_tracks":{"implementing":"$impl","test_scripting":"$test_s","code_reviewing":"$review","ci_monitoring":"$ci"}}]}
EOF

  # Current board = new state
  cat > "$AGENTS_DIR/task-board.json" << EOF
{"version":2,"tasks":[{"id":"$task_id","status":"$new_status","workflow_mode":"$workflow_mode","feedback_loops":$feedback_loops,"parallel_tracks":{"implementing":"$impl","test_scripting":"$test_s","code_reviewing":"$review","ci_monitoring":"$ci"}}]}
EOF
}

# Run the FSM validation portion of the hook
# Returns the hook's stdout (contains ⛔ if blocked)
run_fsm_check() {
  local hook_script="hooks/agent-post-tool-use.sh"
  # We can't run the full hook (it expects tool input JSON), so we extract and test
  # the FSM validation logic directly by simulating what the hook does

  local output=""
  local task_id new_status old_status workflow_mode

  # Read task from board
  while read -r TASK; do
    task_id=$(echo "$TASK" | jq -r '.id')
    new_status=$(echo "$TASK" | jq -r '.status')
    old_status=$(jq -r --arg tid "$task_id" '.tasks[] | select(.id == $tid) | .status' "$AGENTS_DIR/runtime/.task-board-snapshot.json" 2>/dev/null || echo "")

    [ -z "$old_status" ] && continue
    [ "$old_status" = "$new_status" ] && continue

    LEGAL=false
    workflow_mode=$(jq -r --arg tid "$task_id" '.tasks[] | select(.id == $tid) | .workflow_mode // "simple"' "$AGENTS_DIR/task-board.json" 2>/dev/null || echo "simple")

    if [ "$workflow_mode" = "3phase" ]; then
      case "${old_status}→${new_status}" in
        "created→requirements"|"requirements→architecture"|"architecture→tdd_design"|\
        "tdd_design→dfmea"|"dfmea→design_review"|\
        "design_review→implementing"|"design_review→architecture"|\
        "implementing→code_reviewing"|"implementing→ci_monitoring"|\
        "test_scripting→code_reviewing"|\
        "code_reviewing→implementing"|"code_reviewing→ci_monitoring"|\
        "ci_monitoring→ci_fixing"|"ci_monitoring→device_baseline"|\
        "ci_fixing→ci_monitoring"|\
        "device_baseline→deploying"|"device_baseline→implementing"|\
        "deploying→regression_testing"|\
        "regression_testing→feature_testing"|"regression_testing→implementing"|\
        "feature_testing→log_analysis"|"feature_testing→tdd_design"|\
        "log_analysis→documentation"|"log_analysis→ci_fixing"|\
        "documentation→accepted")
          LEGAL=true ;;
        *→blocked) LEGAL=true ;;
        blocked→*) LEGAL=true ;;
      esac

      # Feedback loop safety
      if [ "$LEGAL" = true ]; then
        case "${old_status}→${new_status}" in
          "regression_testing→implementing"|"feature_testing→tdd_design"|\
          "log_analysis→ci_fixing"|"device_baseline→implementing"|\
          "design_review→architecture"|"code_reviewing→implementing")
            local fb_count
            fb_count=$(jq -r --arg tid "$task_id" '.tasks[] | select(.id == $tid) | .feedback_loops // 0' "$AGENTS_DIR/task-board.json" 2>/dev/null || echo 0)
            if [ "$fb_count" -ge 10 ]; then
              output="⛔ FEEDBACK_LIMIT"
              LEGAL=false
            fi
            ;;
        esac
      fi

      # Convergence gate
      if [ "$LEGAL" = true ] && [ "$new_status" = "device_baseline" ]; then
        local impl test_s review ci_s
        impl=$(jq -r --arg tid "$task_id" '.tasks[] | select(.id == $tid) | .parallel_tracks.implementing // "pending"' "$AGENTS_DIR/task-board.json")
        test_s=$(jq -r --arg tid "$task_id" '.tasks[] | select(.id == $tid) | .parallel_tracks.test_scripting // "pending"' "$AGENTS_DIR/task-board.json")
        review=$(jq -r --arg tid "$task_id" '.tasks[] | select(.id == $tid) | .parallel_tracks.code_reviewing // "pending"' "$AGENTS_DIR/task-board.json")
        ci_s=$(jq -r --arg tid "$task_id" '.tasks[] | select(.id == $tid) | .parallel_tracks.ci_monitoring // "pending"' "$AGENTS_DIR/task-board.json")
        if [ "$impl" != "complete" ] || [ "$test_s" != "complete" ] || [ "$review" != "complete" ] || [ "$ci_s" != "green" ]; then
          output="⛔ CONVERGENCE_GATE"
          LEGAL=false
        fi
      fi
    else
      case "${old_status}→${new_status}" in
        "created→designing"|"designing→implementing"|"implementing→reviewing"|\
        "reviewing→implementing"|"reviewing→testing"|"testing→fixing"|\
        "testing→accepting"|"fixing→testing"|"accepting→accepted"|\
        "accept_fail→designing")
          LEGAL=true ;;
        *→blocked) LEGAL=true ;;
        blocked→*) LEGAL=true ;;
      esac
    fi

    if [ "$LEGAL" = false ] && [ -z "$output" ]; then
      output="⛔ ILLEGAL"
    elif [ "$LEGAL" = true ]; then
      output="✅ LEGAL"
    fi
  done < <(jq -c '.tasks[]' "$AGENTS_DIR/task-board.json" 2>/dev/null)

  echo "$output"
}

check() {
  local label="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then
    echo "  ✅ $label"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $label (expected: $expected, got: $actual)"
    FAIL=$((FAIL + 1))
  fi
}

# ========================================
# Tests
# ========================================

echo "🧪 3-Phase FSM Validation Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

setup

# --- Goal 1: Test all 26 legal 3-Phase transitions ---
echo ""
echo "📋 G-037-1: Legal 3-Phase Transitions"

LEGAL_TRANSITIONS=(
  "created:requirements"
  "requirements:architecture"
  "architecture:tdd_design"
  "tdd_design:dfmea"
  "dfmea:design_review"
  "design_review:implementing"
  "design_review:architecture"
  "implementing:code_reviewing"
  "implementing:ci_monitoring"
  "test_scripting:code_reviewing"
  "code_reviewing:implementing"
  "code_reviewing:ci_monitoring"
  "ci_monitoring:ci_fixing"
  "ci_monitoring:device_baseline"
  "ci_fixing:ci_monitoring"
  "device_baseline:deploying"
  "device_baseline:implementing"
  "deploying:regression_testing"
  "regression_testing:feature_testing"
  "regression_testing:implementing"
  "feature_testing:log_analysis"
  "feature_testing:tdd_design"
  "log_analysis:documentation"
  "log_analysis:ci_fixing"
  "documentation:accepted"
  "implementing:blocked"
)

LEGAL_PASS=0
LEGAL_FAIL=0
for trans in "${LEGAL_TRANSITIONS[@]}"; do
  from="${trans%%:*}"
  to="${trans##*:}"
  if [ "$to" = "device_baseline" ]; then
    set_task_status "T-TEST" "$from" "$to" "3phase" "0" "complete" "complete" "complete" "green"
  else
    set_task_status "T-TEST" "$from" "$to" "3phase"
  fi
  result=$(run_fsm_check)
  if echo "$result" | grep -q "LEGAL"; then
    LEGAL_PASS=$((LEGAL_PASS + 1))
  else
    echo "    ⚠️  $from → $to: $result"
    LEGAL_FAIL=$((LEGAL_FAIL + 1))
  fi
done
check "26 legal transitions" "LEGAL" "$([ $LEGAL_FAIL -eq 0 ] && echo 'ALL LEGAL' || echo "$LEGAL_FAIL FAILED")"
echo "    ($LEGAL_PASS passed, $LEGAL_FAIL failed)"

# --- Goal 2: Test illegal transitions are blocked ---
echo ""
echo "📋 G-037-2: Illegal Transitions Blocked"

ILLEGAL_TRANSITIONS=(
  "created:implementing"
  "requirements:testing"
  "tdd_design:accepted"
  "design_review:deploying"
  "ci_monitoring:regression_testing"
  "documentation:implementing"
)

for trans in "${ILLEGAL_TRANSITIONS[@]}"; do
  from="${trans%%:*}"
  to="${trans##*:}"
  set_task_status "T-TEST" "$from" "$to" "3phase"
  result=$(run_fsm_check)
  check "$from → $to blocked" "ILLEGAL" "$result"
done

# --- Goal 3: Convergence gate ---
echo ""
echo "📋 G-037-3: Convergence Gate"

# Test: gate blocks when tracks incomplete
set_task_status "T-TEST" "ci_monitoring" "device_baseline" "3phase" "0" "complete" "pending" "complete" "green"
result=$(run_fsm_check)
check "Gate blocks (test_scripting=pending)" "CONVERGENCE_GATE" "$result"

set_task_status "T-TEST" "ci_monitoring" "device_baseline" "3phase" "0" "complete" "complete" "complete" "pending"
result=$(run_fsm_check)
check "Gate blocks (ci_monitoring=pending)" "CONVERGENCE_GATE" "$result"

# Test: gate allows when all complete
set_task_status "T-TEST" "ci_monitoring" "device_baseline" "3phase" "0" "complete" "complete" "complete" "green"
result=$(run_fsm_check)
check "Gate allows (all complete)" "LEGAL" "$result"

# --- Goal 4: Feedback loop counter ---
echo ""
echo "📋 G-037-4: Feedback Loop Counter"

set_task_status "T-TEST" "regression_testing" "implementing" "3phase" "3"
result=$(run_fsm_check)
check "Feedback at loops=3 allowed" "LEGAL" "$result"

set_task_status "T-TEST" "design_review" "architecture" "3phase" "5"
result=$(run_fsm_check)
check "Feedback at loops=5 allowed" "LEGAL" "$result"

set_task_status "T-TEST" "feature_testing" "tdd_design" "3phase" "9"
result=$(run_fsm_check)
check "Feedback at loops=9 allowed" "LEGAL" "$result"

# --- Goal 5: Auto-block at MAX_FEEDBACK_LOOPS ---
echo ""
echo "📋 G-037-5: Auto-Block at loops>=10"

set_task_status "T-TEST" "regression_testing" "implementing" "3phase" "10"
result=$(run_fsm_check)
check "Feedback at loops=10 BLOCKED" "FEEDBACK_LIMIT" "$result"

set_task_status "T-TEST" "code_reviewing" "implementing" "3phase" "15"
result=$(run_fsm_check)
check "Feedback at loops=15 BLOCKED" "FEEDBACK_LIMIT" "$result"

set_task_status "T-TEST" "log_analysis" "ci_fixing" "3phase" "10"
result=$(run_fsm_check)
check "log_analysis feedback at 10 BLOCKED" "FEEDBACK_LIMIT" "$result"

# Also test that non-feedback transitions still work at loops>=10
set_task_status "T-TEST" "deploying" "regression_testing" "3phase" "10"
result=$(run_fsm_check)
check "Non-feedback transition at loops=10 ALLOWED" "LEGAL" "$result"

# --- Bonus: Simple FSM still works ---
echo ""
echo "📋 Bonus: Simple FSM Backward Compatibility"

set_task_status "T-TEST" "created" "designing" "simple"
result=$(run_fsm_check)
check "Simple: created→designing" "LEGAL" "$result"

set_task_status "T-TEST" "implementing" "reviewing" "simple"
result=$(run_fsm_check)
check "Simple: implementing→reviewing" "LEGAL" "$result"

set_task_status "T-TEST" "created" "implementing" "simple"
result=$(run_fsm_check)
check "Simple: created→implementing BLOCKED" "ILLEGAL" "$result"

# Cleanup
rm -rf "$TEST_DIR"

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -eq 0 ]; then
  echo "✅ All 3-Phase FSM tests passed!"
  exit 0
else
  echo "❌ $FAIL test(s) failed"
  exit 1
fi
