---
name: agent-orchestrator
description: "3-Phase Orchestrator Daemon. Autonomous background process that drives the 3-Phase Engineering Closed Loop workflow. Invokes agents via Copilot CLI with step-specific prompt templates."
---

# Agent Orchestrator — 3-Phase Daemon

## Overview

The orchestrator is a background shell script that autonomously drives a task through the 3-Phase Engineering Closed Loop. It:

1. Reads the current task state from `task-board.json`
2. Determines the next step based on FSM transitions
3. Selects the correct agent and prompt template for that step
4. Invokes the agent via Copilot CLI (or compatible AI CLI)
5. Evaluates the result and advances the FSM
6. Handles parallel tracks (Phase 2) and feedback loops (Phase 3)
7. Logs all actions to the orchestrator log and events.db

The orchestrator is **generated during `agent-init`** with project-specific placeholders filled in.

## Configuration Variables

The orchestrator uses `{PLACEHOLDER}` tokens that are replaced during project initialization:

### Project Settings
| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{PROJECT_DIR}` | Absolute path to project root | `/home/user/my-project` |
| `{BUILD_CMD}` | Build command | `npm run build` |
| `{TEST_CMD}` | Test command | `npm test` |
| `{LINT_CMD}` | Lint command | `npm run lint` |

### CI System (Pluggable)
| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{CI_SYSTEM}` | CI platform identifier | `github-actions` / `jenkins` / `gitlab-ci` |
| `{CI_URL}` | CI dashboard or API URL | `https://github.com/org/repo/actions` |
| `{CI_STATUS_CMD}` | Command to check CI status | `gh run list --limit 1 --json status` |
| `{CI_TRIGGER_CMD}` | Command to trigger CI run | `gh workflow run ci.yml` |

### Code Review System (Pluggable)
| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{REVIEW_SYSTEM}` | Review platform identifier | `github-pr` / `gerrit` / `gitlab-mr` |
| `{REVIEW_CMD}` | Command to create/check review | `gh pr create` |
| `{REVIEW_STATUS_CMD}` | Command to check review status | `gh pr checks` |

### AI CLI Command
| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{CLI_COMMAND}` | AI assistant CLI command (e.g., claude, copilot, github-copilot-cli) | `claude` |

### Device / Test Environment (Pluggable)
| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{DEVICE_TYPE}` | Target environment type | `localhost` / `staging` / `hardware` |
| `{DEPLOY_CMD}` | Deployment command | `docker compose up -d` |
| `{LOG_CMD}` | Log retrieval command | `docker compose logs --tail=200` |
| `{BASELINE_CMD}` | Baseline verification command | `curl -sf http://localhost:8080/health` |

## Step → Agent Mapping

The orchestrator maps each 3-Phase step to the agent responsible for execution:

```bash
get_agent_for_step() {
  local step="$1"
  case "$step" in
    requirements)        echo "acceptor" ;;
    architecture)        echo "designer" ;;
    tdd_design)          echo "designer" ;;  # secondary: tester
    dfmea)               echo "designer" ;;
    design_review)       echo "reviewer" ;;
    implementing)        echo "implementer" ;;
    test_scripting)      echo "tester" ;;
    code_reviewing)      echo "reviewer" ;;
    ci_monitoring)       echo "implementer" ;;
    ci_fixing)           echo "implementer" ;;
    device_baseline)     echo "implementer" ;;
    deploying)           echo "implementer" ;;
    regression_testing)  echo "tester" ;;
    feature_testing)     echo "tester" ;;
    log_analysis)        echo "tester" ;;    # secondary: designer
    documentation)       echo "designer" ;;
    *)                   echo "" ;;
  esac
}
```

## Step → Prompt Template Mapping

Each step has a dedicated prompt template in `.agents/prompts/`:

```bash
get_prompt_for_step() {
  local step="$1"
  echo "{PROJECT_DIR}/.agents/prompts/phase${phase}-${step}.txt"
}
```

Prompt template files (16 total):
| Phase | File | Step |
|-------|------|------|
| 1 | `phase1-requirements.txt` | requirements |
| 1 | `phase1-architecture.txt` | architecture |
| 1 | `phase1-tdd-design.txt` | tdd_design |
| 1 | `phase1-dfmea.txt` | dfmea |
| 1 | `phase1-design-review.txt` | design_review |
| 2 | `phase2-implementing.txt` | implementing |
| 2 | `phase2-test-scripting.txt` | test_scripting |
| 2 | `phase2-code-reviewing.txt` | code_reviewing |
| 2 | `phase2-ci-monitoring.txt` | ci_monitoring |
| 2 | `phase2-ci-fixing.txt` | ci_fixing |
| 2 | `phase2-device-baseline.txt` | device_baseline |
| 3 | `phase3-deploying.txt` | deploying |
| 3 | `phase3-regression-testing.txt` | regression_testing |
| 3 | `phase3-feature-testing.txt` | feature_testing |
| 3 | `phase3-log-analysis.txt` | log_analysis |
| 3 | `phase3-documentation.txt` | documentation |

## Copilot CLI Invocation Pattern

The orchestrator invokes agents using the Copilot CLI (or compatible tool) in non-interactive mode:

```bash
invoke_agent() {
  local agent="$1"
  local prompt_file="$2"
  local task_id="$3"

  # Read prompt template and substitute task-specific variables
  local prompt
  prompt=$(sed \
    -e "s|{TASK_ID}|${task_id}|g" \
    -e "s|{PROJECT_DIR}|{PROJECT_DIR}|g" \
    < "$prompt_file")

  # Invoke via AI CLI — {CLI_COMMAND} is replaced during agent-init
  {CLI_COMMAND} \
    --agent "$agent" \
    --prompt "$prompt" \
    --project-dir "{PROJECT_DIR}" \
    --non-interactive \
    2>&1 | tee -a "{PROJECT_DIR}/.agents/orchestrator/logs/${task_id}-$(date +%Y%m%d-%H%M%S).log"

  return ${PIPESTATUS[0]}
}
```

> **Note**: `{CLI_COMMAND}` is replaced during `agent-init` with the detected AI CLI tool (e.g., `claude`, `copilot`, `github-copilot-cli`).

## Result Delivery Protocol

The orchestrator reads result fields from `task-board.json` to make branching decisions (e.g., `design_review_result`, `regression_result`). **Each prompt template must instruct the agent to write its result back to task-board.json before completing.**

### Result Fields

| Field | Values | Set By | At End Of Step |
|-------|--------|--------|----------------|
| `design_review_result` | `"pass"` \| `"fail"` | reviewer | `design_review` |
| `regression_result` | `"pass"` \| `"fail"` | tester | `regression_testing` |
| `feature_result` | `"pass"` \| `"fail"` | tester | `feature_testing` |
| `log_analysis_result` | `"clean"` \| `"anomaly"` | tester | `log_analysis` |
| `device_baseline_result` | `"pass"` \| `"fail"` | implementer | `device_baseline` |

### `write_result()` Helper

Include this in the orchestrator daemon or instruct agents to use equivalent `jq` commands:

```bash
write_result() {
  local task_id="$1" field="$2" value="$3"
  jq --arg tid "$task_id" --arg f "$field" --arg v "$value" \
    '(.tasks[] | select(.id == $tid))[$f] = $v' \
    "$AGENTS_DIR/task-board.json" > tmp.json && mv tmp.json "$AGENTS_DIR/task-board.json"
}
```

### Prompt Template Requirement

Every prompt template that produces a result **must** include this instruction:

> **Before completing, update task-board.json with your result field:**
> ```bash
> jq --arg tid "{TASK_ID}" '(.tasks[] | select(.id == $tid)).FIELD = "VALUE"' \
>   .agents/task-board.json > .agents/task-board.json.tmp \
>   && mv .agents/task-board.json.tmp .agents/task-board.json
> ```
> Replace `FIELD` with the appropriate result field name and `VALUE` with the result.

## Phase 2 Parallel Execution Strategy

Phase 2 runs three tracks concurrently:

```
design_review (PASS)
    │
    ├─── Track A: implementing     (implementer)
    ├─── Track B: test_scripting   (tester)
    └─── Track C: code_reviewing   (reviewer, starts after A/B produce first artifacts)
                │
                ▼
         Convergence Gate
                │
                ▼
         ci_monitoring → ci_fixing (loop) → device_baseline
```

The orchestrator manages this by:
1. Launching Track A and Track B in parallel (background processes)
2. Launching Track C after a configurable delay or after detecting first artifacts
3. Polling `parallel_tracks` in task-board.json for completion
4. Once all tracks report complete, advancing to `ci_monitoring`

```bash
run_phase2_parallel() {
  local task_id="$1"

  # Launch Track A (implementer)
  invoke_agent "implementer" ".agents/prompts/phase2-implementing.txt" "$task_id" &
  local pid_a=$!

  # Launch Track B (tester)
  invoke_agent "tester" ".agents/prompts/phase2-test-scripting.txt" "$task_id" &
  local pid_b=$!

  # Wait for initial artifacts before launching Track C
  sleep 30
  invoke_agent "reviewer" ".agents/prompts/phase2-code-reviewing.txt" "$task_id" &
  local pid_c=$!

  # Wait for all tracks
  wait $pid_a; local rc_a=$?
  wait $pid_b; local rc_b=$?
  wait $pid_c; local rc_c=$?

  # Update parallel track status in task-board.json
  update_parallel_tracks "$task_id" "$rc_a" "$rc_b" "$rc_c"
}
```

## Feedback Loop Management

The orchestrator tracks and enforces feedback loops:

```bash
MAX_FEEDBACK_LOOPS=10

handle_feedback() {
  local task_id="$1"
  local from_step="$2"
  local to_step="$3"
  local reason="$4"

  local count
  count=$(jq -r --arg tid "$task_id" \
    '.tasks[] | select(.id == $tid) | .feedback_loops // 0' \
    .agents/task-board.json)

  if [ "$count" -ge "$MAX_FEEDBACK_LOOPS" ]; then
    echo "⛔ SAFETY LIMIT: Task $task_id has reached $MAX_FEEDBACK_LOOPS feedback loops."
    echo "   Transitioning to BLOCKED state. Manual intervention required."
    transition_task "$task_id" "blocked" "Feedback loop safety limit reached ($count/$MAX_FEEDBACK_LOOPS)"
    return 1
  fi

  # Increment counter and record feedback
  jq --arg tid "$task_id" --arg from "$from_step" --arg to "$to_step" \
     --arg reason "$reason" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '(.tasks[] | select(.id == $tid)) |=
       (.feedback_loops = ((.feedback_loops // 0) + 1) |
        .feedback_history += [{"from": $from, "to": $to, "at": $ts, "reason": $reason}])' \
     .agents/task-board.json > .agents/task-board.json.tmp \
     && mv .agents/task-board.json.tmp .agents/task-board.json

  echo "🔄 Feedback loop $((count + 1))/$MAX_FEEDBACK_LOOPS: $from_step → $to_step ($reason)"
  transition_task "$task_id" "$to_step" "$reason"
}
```

## Generic Orchestrator Daemon Template

The following is the complete, runnable orchestrator daemon script with `{PLACEHOLDER}` tokens. During `agent-init`, these are replaced with project-specific values.

```bash
#!/usr/bin/env bash
# ============================================================
# 3-Phase Engineering Closed Loop — Orchestrator Daemon
# Generated by agent-init for: {PROJECT_DIR}
# ============================================================
set -euo pipefail

# --- Configuration (filled by agent-init) ---
PROJECT_DIR="{PROJECT_DIR}"
BUILD_CMD="{BUILD_CMD}"
TEST_CMD="{TEST_CMD}"
LINT_CMD="{LINT_CMD}"
CI_SYSTEM="{CI_SYSTEM}"
CI_URL="{CI_URL}"
CI_STATUS_CMD="{CI_STATUS_CMD}"
CI_TRIGGER_CMD="{CI_TRIGGER_CMD}"
REVIEW_SYSTEM="{REVIEW_SYSTEM}"
REVIEW_CMD="{REVIEW_CMD}"
REVIEW_STATUS_CMD="{REVIEW_STATUS_CMD}"
DEVICE_TYPE="{DEVICE_TYPE}"
DEPLOY_CMD="{DEPLOY_CMD}"
LOG_CMD="{LOG_CMD}"
BASELINE_CMD="{BASELINE_CMD}"
MAX_FEEDBACK_LOOPS=10

# --- Paths ---
AGENTS_DIR="${PROJECT_DIR}/.agents"
TASKBOARD="${AGENTS_DIR}/task-board.json"
PROMPTS_DIR="${AGENTS_DIR}/prompts"
LOG_DIR="${AGENTS_DIR}/orchestrator/logs"
PID_FILE="${AGENTS_DIR}/orchestrator/daemon.pid"
EVENTS_DB="${AGENTS_DIR}/events.db"

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${GREEN}[orch]${NC} $1"; }
warn()  { echo -e "${YELLOW}[orch]${NC} $1"; }
error() { echo -e "${RED}[orch]${NC} $1"; }
step()  { echo -e "${CYAN}[step]${NC} $1"; }

# --- Initialize ---
mkdir -p "$LOG_DIR"
echo $$ > "$PID_FILE"
info "Orchestrator daemon started (PID: $$)"
info "Project: $PROJECT_DIR"
info "CI: $CI_SYSTEM | Review: $REVIEW_SYSTEM | Device: $DEVICE_TYPE"

# --- Utility Functions ---

get_task_field() {
  local task_id="$1" field="$2"
  jq -r --arg tid "$task_id" ".tasks[] | select(.id == \$tid) | .$field // empty" "$TASKBOARD"
}

get_agent_for_step() {
  local step="$1"
  case "$step" in
    requirements)        echo "acceptor" ;;
    architecture)        echo "designer" ;;
    tdd_design)          echo "designer" ;;
    dfmea)               echo "designer" ;;
    design_review)       echo "reviewer" ;;
    implementing)        echo "implementer" ;;
    test_scripting)      echo "tester" ;;
    code_reviewing)      echo "reviewer" ;;
    ci_monitoring)       echo "implementer" ;;
    ci_fixing)           echo "implementer" ;;
    device_baseline)     echo "implementer" ;;
    deploying)           echo "implementer" ;;
    regression_testing)  echo "tester" ;;
    feature_testing)     echo "tester" ;;
    log_analysis)        echo "tester" ;;
    documentation)       echo "designer" ;;
    *)                   echo "" ;;
  esac
}

get_phase_for_step() {
  local step="$1"
  case "$step" in
    requirements|architecture|tdd_design|dfmea|design_review)
      echo "1" ;;
    implementing|test_scripting|code_reviewing|ci_monitoring|ci_fixing|device_baseline)
      echo "2" ;;
    deploying|regression_testing|feature_testing|log_analysis|documentation)
      echo "3" ;;
    *) echo "0" ;;
  esac
}

transition_task() {
  local task_id="$1" new_status="$2" note="${3:-}"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local phase
  phase=$(get_phase_for_step "$new_status")

  jq --arg tid "$task_id" --arg status "$new_status" --arg note "$note" \
     --arg ts "$ts" --arg phase "$phase" \
     '(.tasks[] | select(.id == $tid)) |=
       (.status = $status | .phase = $phase | .step = $status |
        .history += [{"to": $status, "at": $ts, "note": $note}] |
        .version = (.version + 1))' \
     "$TASKBOARD" > "${TASKBOARD}.tmp" && mv "${TASKBOARD}.tmp" "$TASKBOARD"

  step "Task $task_id → $new_status (Phase $phase)"

  # Log to events.db
  sqlite3 "$EVENTS_DB" "INSERT INTO events (timestamp, event_type, agent, task_id, detail)
    VALUES ($(date +%s), 'orchestrator_transition', 'orchestrator', '$task_id',
    '{\"to\":\"$new_status\",\"phase\":\"$phase\",\"note\":\"$note\"}');" 2>/dev/null || true
}

invoke_agent() {
  local agent="$1" prompt_file="$2" task_id="$3"
  local logfile="${LOG_DIR}/${task_id}-${agent}-$(date +%Y%m%d-%H%M%S).log"

  if [ ! -f "$prompt_file" ]; then
    error "Prompt template not found: $prompt_file"
    return 1
  fi

  local prompt
  prompt=$(sed -e "s|{TASK_ID}|${task_id}|g" \
               -e "s|{PROJECT_DIR}|${PROJECT_DIR}|g" \
               < "$prompt_file")

  info "Invoking $agent for $task_id with $(basename "$prompt_file")"

  # {CLI_COMMAND} is replaced during agent-init with the detected AI CLI tool
  {CLI_COMMAND} \
    --agent "$agent" \
    --prompt "$prompt" \
    --project-dir "$PROJECT_DIR" \
    --non-interactive \
    2>&1 | tee -a "$logfile"

  local rc=${PIPESTATUS[0]}
  if [ "$rc" -ne 0 ]; then
    warn "Agent $agent returned non-zero exit code: $rc"
  fi
  return "$rc"
}

check_convergence() {
  local task_id="$1"
  local impl test_s code_r ci_m
  impl=$(jq -r --arg tid "$task_id" '.tasks[] | select(.id == $tid) | .parallel_tracks.implementing // "pending"' "$TASKBOARD")
  test_s=$(jq -r --arg tid "$task_id" '.tasks[] | select(.id == $tid) | .parallel_tracks.test_scripting // "pending"' "$TASKBOARD")
  code_r=$(jq -r --arg tid "$task_id" '.tasks[] | select(.id == $tid) | .parallel_tracks.code_reviewing // "pending"' "$TASKBOARD")
  ci_m=$(jq -r --arg tid "$task_id" '.tasks[] | select(.id == $tid) | .parallel_tracks.ci_monitoring // "pending"' "$TASKBOARD")

  if [ "$impl" = "complete" ] && [ "$test_s" = "complete" ] && \
     [ "$code_r" = "complete" ] && [ "$ci_m" = "green" ]; then
    return 0
  fi
  return 1
}

handle_feedback() {
  local task_id="$1" from_step="$2" to_step="$3" reason="$4"
  local count
  count=$(jq -r --arg tid "$task_id" '.tasks[] | select(.id == $tid) | .feedback_loops // 0' "$TASKBOARD")

  if [ "$count" -ge "$MAX_FEEDBACK_LOOPS" ]; then
    error "SAFETY LIMIT: Task $task_id reached $MAX_FEEDBACK_LOOPS feedback loops."
    error "Transitioning to BLOCKED. Manual intervention required."
    transition_task "$task_id" "blocked" "Feedback loop safety limit reached ($count/$MAX_FEEDBACK_LOOPS)"
    sqlite3 "$EVENTS_DB" "INSERT INTO events (timestamp, event_type, agent, task_id, detail)
      VALUES ($(date +%s), 'fsm_feedback_limit', 'orchestrator', '$task_id',
      '{\"loops\":$count,\"from\":\"$from_step\",\"to\":\"$to_step\"}');" 2>/dev/null || true
    return 1
  fi

  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg tid "$task_id" --arg from "$from_step" --arg to "$to_step" \
     --arg reason "$reason" --arg ts "$ts" \
     '(.tasks[] | select(.id == $tid)) |=
       (.feedback_loops = ((.feedback_loops // 0) + 1) |
        .feedback_history += [{"from": $from, "to": $to, "at": $ts, "reason": $reason}])' \
     "$TASKBOARD" > "${TASKBOARD}.tmp" && mv "${TASKBOARD}.tmp" "$TASKBOARD"

  warn "Feedback loop $((count + 1))/$MAX_FEEDBACK_LOOPS: $from_step → $to_step ($reason)"
  transition_task "$task_id" "$to_step" "Feedback: $reason"
}

run_phase2_parallel() {
  local task_id="$1"

  info "Launching Phase 2 parallel tracks for $task_id"

  # Track A: implementing
  invoke_agent "implementer" "$PROMPTS_DIR/phase2-implementing.txt" "$task_id" &
  local pid_a=$!

  # Track B: test_scripting
  invoke_agent "tester" "$PROMPTS_DIR/phase2-test-scripting.txt" "$task_id" &
  local pid_b=$!

  # Wait for initial artifacts, then launch Track C
  sleep 30
  invoke_agent "reviewer" "$PROMPTS_DIR/phase2-code-reviewing.txt" "$task_id" &
  local pid_c=$!

  # Wait for all tracks to complete
  local rc_a=0 rc_b=0 rc_c=0
  wait $pid_a || rc_a=$?
  wait $pid_b || rc_b=$?
  wait $pid_c || rc_c=$?

  # Update parallel tracks status
  jq --arg tid "$task_id" \
     --arg impl "$([ $rc_a -eq 0 ] && echo complete || echo failed)" \
     --arg test_s "$([ $rc_b -eq 0 ] && echo complete || echo failed)" \
     --arg code_r "$([ $rc_c -eq 0 ] && echo complete || echo failed)" \
     '(.tasks[] | select(.id == $tid)) |=
       (.parallel_tracks = {"implementing": $impl, "test_scripting": $test_s, "code_reviewing": $code_r, "ci_monitoring": "pending"})' \
     "$TASKBOARD" > "${TASKBOARD}.tmp" && mv "${TASKBOARD}.tmp" "$TASKBOARD"

  info "Phase 2 parallel tracks complete: impl=$rc_a test=$rc_b review=$rc_c"
}

# --- Main Orchestration Loop ---
run_3phase() {
  local task_id="$1"

  info "Starting 3-Phase orchestration for task: $task_id"

  local status
  status=$(get_task_field "$task_id" "status")

  while [ "$status" != "accepted" ] && [ "$status" != "blocked" ]; do
    step "Current state: $status"

    case "$status" in
      created)
        transition_task "$task_id" "requirements" "Orchestrator: entering Phase 1"
        invoke_agent "acceptor" "$PROMPTS_DIR/phase1-requirements.txt" "$task_id"
        transition_task "$task_id" "architecture" "Requirements approved"
        ;;

      architecture)
        invoke_agent "designer" "$PROMPTS_DIR/phase1-architecture.txt" "$task_id"
        transition_task "$task_id" "tdd_design" "Architecture complete"
        ;;

      tdd_design)
        invoke_agent "designer" "$PROMPTS_DIR/phase1-tdd-design.txt" "$task_id"
        # Also invoke tester for TDD input
        invoke_agent "tester" "$PROMPTS_DIR/phase1-tdd-design.txt" "$task_id"
        transition_task "$task_id" "dfmea" "TDD design complete"
        ;;

      dfmea)
        invoke_agent "designer" "$PROMPTS_DIR/phase1-dfmea.txt" "$task_id"
        transition_task "$task_id" "design_review" "DFMEA complete"
        ;;

      design_review)
        invoke_agent "reviewer" "$PROMPTS_DIR/phase1-design-review.txt" "$task_id"
        local review_result
        review_result=$(get_task_field "$task_id" "design_review_result")
        if [ "$review_result" = "pass" ]; then
          transition_task "$task_id" "implementing" "Design review PASS → Phase 2"
        else
          handle_feedback "$task_id" "design_review" "architecture" "Design review FAIL"
        fi
        ;;

      implementing)
        run_phase2_parallel "$task_id"
        # After parallel tracks, move to CI monitoring
        transition_task "$task_id" "ci_monitoring" "Parallel tracks complete, checking CI"
        ;;

      ci_monitoring)
        invoke_agent "implementer" "$PROMPTS_DIR/phase2-ci-monitoring.txt" "$task_id"
        local ci_status
        ci_status=$(eval "$CI_STATUS_CMD" 2>/dev/null | head -1 || echo "unknown")
        if echo "$ci_status" | grep -qi "success\|pass\|green"; then
          jq --arg tid "$task_id" \
             '(.tasks[] | select(.id == $tid)).parallel_tracks.ci_monitoring = "green"' \
             "$TASKBOARD" > "${TASKBOARD}.tmp" && mv "${TASKBOARD}.tmp" "$TASKBOARD"
          if check_convergence "$task_id"; then
            transition_task "$task_id" "device_baseline" "CI green + all tracks converged"
          fi
        else
          transition_task "$task_id" "ci_fixing" "CI failure detected"
        fi
        ;;

      ci_fixing)
        invoke_agent "implementer" "$PROMPTS_DIR/phase2-ci-fixing.txt" "$task_id"
        transition_task "$task_id" "ci_monitoring" "CI fix applied, re-checking"
        ;;

      device_baseline)
        invoke_agent "implementer" "$PROMPTS_DIR/phase2-device-baseline.txt" "$task_id"
        local baseline_ok
        baseline_ok=$(eval "$BASELINE_CMD" 2>/dev/null && echo "pass" || echo "fail")
        if [ "$baseline_ok" = "pass" ]; then
          transition_task "$task_id" "deploying" "Baseline pass → Phase 3"
        else
          handle_feedback "$task_id" "device_baseline" "implementing" "Baseline check failed"
        fi
        ;;

      deploying)
        invoke_agent "implementer" "$PROMPTS_DIR/phase3-deploying.txt" "$task_id"
        eval "$DEPLOY_CMD" 2>&1 | tee -a "$LOG_DIR/${task_id}-deploy.log"
        transition_task "$task_id" "regression_testing" "Deployment confirmed"
        ;;

      regression_testing)
        invoke_agent "tester" "$PROMPTS_DIR/phase3-regression-testing.txt" "$task_id"
        local regression_result
        regression_result=$(get_task_field "$task_id" "regression_result")
        if [ "$regression_result" = "pass" ]; then
          transition_task "$task_id" "feature_testing" "Regression pass"
        else
          handle_feedback "$task_id" "regression_testing" "implementing" "Regression failures"
        fi
        ;;

      feature_testing)
        invoke_agent "tester" "$PROMPTS_DIR/phase3-feature-testing.txt" "$task_id"
        local feature_result
        feature_result=$(get_task_field "$task_id" "feature_result")
        if [ "$feature_result" = "pass" ]; then
          transition_task "$task_id" "log_analysis" "Feature tests pass"
        else
          handle_feedback "$task_id" "feature_testing" "tdd_design" "Feature test gap"
        fi
        ;;

      log_analysis)
        invoke_agent "tester" "$PROMPTS_DIR/phase3-log-analysis.txt" "$task_id"
        invoke_agent "designer" "$PROMPTS_DIR/phase3-log-analysis.txt" "$task_id"
        local log_result
        log_result=$(get_task_field "$task_id" "log_analysis_result")
        if [ "$log_result" = "clean" ]; then
          transition_task "$task_id" "documentation" "Logs clean"
        else
          handle_feedback "$task_id" "log_analysis" "ci_fixing" "Log anomaly detected"
        fi
        ;;

      documentation)
        invoke_agent "designer" "$PROMPTS_DIR/phase3-documentation.txt" "$task_id"
        transition_task "$task_id" "accepted" "Documentation complete — Task DONE ✅"
        ;;

      blocked)
        warn "Task $task_id is BLOCKED. Waiting for manual intervention..."
        sleep 60
        ;;

      *)
        error "Unknown state: $status"
        break
        ;;
    esac

    # Refresh status
    status=$(get_task_field "$task_id" "status")
  done

  if [ "$status" = "accepted" ]; then
    info "🎉 Task $task_id completed successfully!"
  else
    warn "Task $task_id ended in state: $status"
  fi
}

# --- Entry Point ---
usage() {
  echo "Usage: $0 <task-id> [--dry-run]"
  echo ""
  echo "Drives a 3-Phase task through the full engineering closed loop."
  echo ""
  echo "Options:"
  echo "  --dry-run    Print transitions without invoking agents"
  echo "  --status     Show current orchestrator status"
  echo "  --stop       Stop the orchestrator daemon"
}

case "${2:-}" in
  --status)
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
      info "Orchestrator running (PID: $(cat "$PID_FILE"))"
    else
      warn "Orchestrator not running"
    fi
    exit 0
    ;;
  --stop)
    if [ -f "$PID_FILE" ]; then
      kill "$(cat "$PID_FILE")" 2>/dev/null || true
      rm -f "$PID_FILE"
      info "Orchestrator stopped"
    fi
    exit 0
    ;;
esac

TASK_ID="${1:?$(usage)}"
run_3phase "$TASK_ID"

# Cleanup
rm -f "$PID_FILE"
info "Orchestrator daemon exited"
```

## Sample Prompt Templates

### `phase1-requirements.txt`

```
You are the ACCEPTOR agent working on task {TASK_ID} in a 3-Phase Engineering workflow.

PROJECT: {PROJECT_DIR}
PHASE: 1 — Design
STEP: Requirements Gathering

## Your Mission
Analyze the task description and produce a comprehensive requirements document.

## Instructions
1. Read the task from .agents/task-board.json (task ID: {TASK_ID})
2. Extract and refine all functional and non-functional requirements
3. Write requirements in user story format: "As a [role], I want [feature], so that [benefit]"
4. Identify acceptance criteria for each requirement
5. Flag any ambiguities or missing information
6. Output to: .agents/runtime/acceptor/workspace/requirements/{TASK_ID}-requirements.md

## Output Format
- Title: Requirements for {TASK_ID}
- Sections: Functional Requirements, Non-Functional Requirements, Constraints, Open Questions
- Each requirement must have: ID, description, priority (P0-P3), acceptance criteria

## Quality Gate
- All requirements must be testable
- No ambiguous language ("should", "might", "could")
- At least one acceptance criterion per requirement
```

### `phase2-tdd-dev.txt`

```
You are the IMPLEMENTER agent working on task {TASK_ID} in a 3-Phase Engineering workflow.

PROJECT: {PROJECT_DIR}
PHASE: 2 — Implementation
STEP: TDD Development (Track A)

## Your Mission
Implement the feature using strict TDD discipline.

## Context
- Design doc: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-design.md
- Test spec: .agents/runtime/designer/workspace/test-specs/{TASK_ID}-test-spec.md
- TDD plan: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-tdd-plan.md

## Instructions
1. Read the design document and TDD plan
2. For each component in the TDD plan:
   a. Write the test FIRST (RED phase)
   b. Run tests, confirm failure: {TEST_CMD}
   c. Write minimal implementation (GREEN phase)
   d. Run tests, confirm pass: {TEST_CMD}
   e. Refactor if needed (REFACTOR phase)
   f. Git commit with descriptive message
3. Run full build: {BUILD_CMD}
4. Run lint: {LINT_CMD}
5. Update goal status in task-board.json as goals are completed

## CI Integration
- CI System: {CI_SYSTEM}
- After implementation, push and monitor: {CI_URL}

## Quality Gate
- All tests passing: {TEST_CMD}
- Build succeeds: {BUILD_CMD}
- Lint clean: {LINT_CMD}
- All task goals marked as "done"
```

### `phase3-regression-test.txt`

```
You are the TESTER agent working on task {TASK_ID} in a 3-Phase Engineering workflow.

PROJECT: {PROJECT_DIR}
PHASE: 3 — Testing & Verification
STEP: Regression Testing

## Your Mission
Run the full regression test suite and report results.

## Context
- Deployment: {DEVICE_TYPE}
- Test command: {TEST_CMD}
- Logs: {LOG_CMD}

## Instructions
1. Verify deployment is healthy: {BASELINE_CMD}
2. Run the full regression test suite: {TEST_CMD}
3. For each failure:
   a. Capture the error message and stack trace
   b. Check if this is a pre-existing failure or new regression
   c. Document in .agents/runtime/tester/workspace/test-cases/{TASK_ID}-regression.md
4. Check test coverage if available
5. Update task-board.json with regression_result: "pass" or "fail"

## Failure Handling
- If ANY new regression is found: set regression_result to "fail"
  - The orchestrator will trigger a feedback loop back to implementing
- If all tests pass: set regression_result to "pass"
  - The orchestrator will advance to feature_testing

## Output
- Regression report: .agents/runtime/tester/workspace/test-cases/{TASK_ID}-regression.md
- Update task-board.json: regression_result field
```

### `phase1-architecture.txt`

```
You are the DESIGNER agent working on task {TASK_ID} in a 3-Phase Engineering workflow.

PROJECT: {PROJECT_DIR}
PHASE: 1 — Design
STEP: Architecture

## Your Mission
Read the approved requirements and produce a comprehensive architecture document.

## Context
- Requirements doc: .agents/runtime/acceptor/workspace/requirements/{TASK_ID}-requirements.md
- Task board: .agents/task-board.json (task ID: {TASK_ID})

## Instructions
1. Read the requirements document thoroughly
2. Design the system architecture:
   a. Component diagram (describe in text/Mermaid)
   b. Data model (entities, relationships, schemas)
   c. API design (endpoints, request/response formats)
   d. Technology choices with justification
3. Identify integration points and dependencies
4. Document error handling and edge cases
5. Output to: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-design.md

## Output Format
- Title: Architecture for {TASK_ID}
- Sections: Overview, Component Design, Data Model, API Design, Error Handling, Open Questions
- Each component must have: name, responsibility, interfaces, dependencies

## Quality Gate
- All requirements are addressed by at least one component
- Data model covers all entities from requirements
- API design includes error responses
- No circular dependencies
```

### `phase1-tdd-design.txt`

```
You are the DESIGNER agent (with TESTER input) working on task {TASK_ID} in a 3-Phase Engineering workflow.

PROJECT: {PROJECT_DIR}
PHASE: 1 — Design
STEP: TDD Design

## Your Mission
Create a comprehensive TDD plan based on the architecture document.

## Context
- Architecture doc: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-design.md
- Requirements doc: .agents/runtime/acceptor/workspace/requirements/{TASK_ID}-requirements.md

## Instructions
1. Read the architecture document and requirements
2. For each component, define:
   a. Unit tests (RED phase — what to test, expected behavior)
   b. Implementation strategy (GREEN phase — minimal code to pass)
   c. Refactor opportunities (REFACTOR phase — code quality improvements)
3. Define integration test scenarios
4. Define E2E test scenarios matching acceptance criteria
5. Specify test data and fixtures needed
6. Output to: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-tdd-plan.md

## Output Format
- Title: TDD Plan for {TASK_ID}
- Sections: Unit Tests, Integration Tests, E2E Tests, Test Data, Execution Order
- Each test: ID, description, input, expected output, component under test

## Quality Gate
- Every requirement has at least one test
- Tests follow Red → Green → Refactor sequence
- Test data is realistic and covers edge cases
```

### `phase1-dfmea.txt`

```
You are the DESIGNER agent working on task {TASK_ID} in a 3-Phase Engineering workflow.

PROJECT: {PROJECT_DIR}
PHASE: 1 — Design
STEP: Design FMEA (Failure Mode and Effects Analysis)

## Your Mission
Analyze potential failure modes in the design and create a risk matrix with mitigation actions.

## Context
- Architecture doc: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-design.md
- TDD plan: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-tdd-plan.md
- Requirements doc: .agents/runtime/acceptor/workspace/requirements/{TASK_ID}-requirements.md

## Instructions
1. For each component in the architecture:
   a. Identify potential failure modes (what can go wrong)
   b. Assess severity (1-10), occurrence probability (1-10), detectability (1-10)
   c. Calculate Risk Priority Number (RPN = S × O × D)
   d. Define mitigation actions for high-RPN items (RPN > 100)
2. Consider: data loss, security breaches, performance degradation, API failures, concurrency issues
3. Cross-reference with TDD plan — ensure high-risk items have tests
4. Output to: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-dfmea.md

## Output Format
- Title: DFMEA for {TASK_ID}
- Risk Matrix table: Component, Failure Mode, Effect, Severity, Occurrence, Detection, RPN, Mitigation
- Summary: Top 5 risks, recommended actions, test coverage gaps

## Quality Gate
- All architecture components analyzed
- RPN > 100 items have mitigation plans
- High-severity items (S ≥ 8) have corresponding test cases
```

### `phase1-design-review.txt`

```
You are the REVIEWER agent working on task {TASK_ID} in a 3-Phase Engineering workflow.

PROJECT: {PROJECT_DIR}
PHASE: 1 — Design
STEP: Design Review

## Your Mission
Review all Phase 1 outputs for completeness, consistency, and quality. Set design_review_result.

## Context
- Requirements: .agents/runtime/acceptor/workspace/requirements/{TASK_ID}-requirements.md
- Architecture: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-design.md
- TDD Plan: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-tdd-plan.md
- DFMEA: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-dfmea.md

## Instructions
1. Review requirements: complete, unambiguous, testable?
2. Review architecture: addresses all requirements? No gaps?
3. Review TDD plan: covers all requirements and architecture components?
4. Review DFMEA: realistic risk assessment? Mitigations adequate?
5. Check cross-document consistency (no contradictions)
6. Output review report to: .agents/runtime/reviewer/workspace/review-reports/review-{TASK_ID}-design.md

## Decision
- If all documents are complete and consistent: set design_review_result = "pass"
- If issues found: set design_review_result = "fail" with detailed reasons

## Update task-board.json
Before completing, update task-board.json with your result:
```bash
jq --arg tid "{TASK_ID}" '(.tasks[] | select(.id == $tid)).design_review_result = "pass"' \
  .agents/task-board.json > .agents/task-board.json.tmp \
  && mv .agents/task-board.json.tmp .agents/task-board.json
```

## Quality Gate
- Every requirement traced to architecture component
- Every component traced to test case
- No unmitigated high-severity risks
```

### `phase2-implementing.txt`

```
You are the IMPLEMENTER agent working on task {TASK_ID} in a 3-Phase Engineering workflow.

PROJECT: {PROJECT_DIR}
PHASE: 2 — Implementation
STEP: TDD Development (Track A)

## Your Mission
Implement the feature using strict TDD discipline.

## Context
- Design doc: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-design.md
- Test spec: .agents/runtime/designer/workspace/test-specs/{TASK_ID}-test-spec.md
- TDD plan: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-tdd-plan.md

## Instructions
1. Read the design document and TDD plan
2. For each component in the TDD plan:
   a. Write the test FIRST (RED phase)
   b. Run tests, confirm failure: {TEST_CMD}
   c. Write minimal implementation (GREEN phase)
   d. Run tests, confirm pass: {TEST_CMD}
   e. Refactor if needed (REFACTOR phase)
   f. Git commit with descriptive message
3. Run full build: {BUILD_CMD}
4. Run lint: {LINT_CMD}
5. Update goal status in task-board.json as goals are completed

## CI Integration
- CI System: {CI_SYSTEM}
- After implementation, push and monitor: {CI_URL}

## Quality Gate
- All tests passing: {TEST_CMD}
- Build succeeds: {BUILD_CMD}
- Lint clean: {LINT_CMD}
- All task goals marked as "done"
```

### `phase2-test-scripting.txt`

```
You are the TESTER agent working on task {TASK_ID} in a 3-Phase Engineering workflow.

PROJECT: {PROJECT_DIR}
PHASE: 2 — Implementation
STEP: Test Scripting (Track B)

## Your Mission
Write automated test scripts based on the TDD plan, including fixtures and test data setup.

## Context
- TDD plan: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-tdd-plan.md
- Test spec: .agents/runtime/designer/workspace/test-specs/{TASK_ID}-test-spec.md
- Architecture: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-design.md

## Instructions
1. Read the TDD plan and test specifications
2. Create test infrastructure:
   a. Set up test fixtures and factories
   b. Create mock data and test utilities
   c. Configure test environment variables
3. Write test scripts for each test case in the TDD plan:
   a. Unit tests with descriptive names
   b. Integration tests with proper setup/teardown
   c. E2E tests matching acceptance criteria
4. Verify all tests are runnable: {TEST_CMD}
5. Output test cases to: .agents/runtime/tester/workspace/test-cases/{TASK_ID}-tests.md

## Quality Gate
- All TDD plan test cases have corresponding test scripts
- Tests are isolated and repeatable
- Test fixtures cover edge cases from DFMEA
- All tests runnable with: {TEST_CMD}
```

### `phase2-code-reviewing.txt`

```
You are the REVIEWER agent working on task {TASK_ID} in a 3-Phase Engineering workflow.

PROJECT: {PROJECT_DIR}
PHASE: 2 — Implementation
STEP: Code Review (Track C)

## Your Mission
Review the implementer's code for quality, security, and adherence to design.

## Context
- Design doc: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-design.md
- Architecture: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-design.md
- DFMEA: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-dfmea.md

## Instructions
1. Review all changed files (use `git diff` to identify changes)
2. Check against design document — implementation matches architecture?
3. Security review:
   a. No hardcoded secrets or credentials
   b. Input validation on all external inputs
   c. SQL injection / XSS / CSRF prevention
   d. Proper error handling (no swallowed exceptions)
4. Code quality:
   a. Consistent style: {LINT_CMD}
   b. No dead code or commented-out blocks
   c. Clear naming and documentation
   d. Proper separation of concerns
5. Output to: .agents/runtime/reviewer/workspace/review-reports/review-{TASK_ID}-code.md

## Output Format
- Critical issues (must fix before merge)
- Warnings (should fix)
- Suggestions (nice to have)
- Overall verdict: APPROVE / REQUEST_CHANGES

## Quality Gate
- Build passes: {BUILD_CMD}
- Lint clean: {LINT_CMD}
- No critical security issues
- Implementation matches design
```

### `phase2-ci-monitoring.txt`

```
You are the IMPLEMENTER agent working on task {TASK_ID} in a 3-Phase Engineering workflow.

PROJECT: {PROJECT_DIR}
PHASE: 2 — Implementation
STEP: CI Monitoring

## Your Mission
Run the CI pipeline (build + test + lint) and report results.

## Context
- CI System: {CI_SYSTEM}
- CI URL: {CI_URL}
- Task board: .agents/task-board.json

## Instructions
1. Trigger CI pipeline: {CI_TRIGGER_CMD}
2. Monitor CI status: {CI_STATUS_CMD}
3. Run local validation:
   a. Build: {BUILD_CMD}
   b. Tests: {TEST_CMD}
   c. Lint: {LINT_CMD}
4. Compare local and CI results
5. If CI passes: update parallel_tracks.ci_monitoring = "green"
6. If CI fails: collect failure logs and report

## CI Status Check
```bash
{CI_STATUS_CMD}
```

## Output
- CI report to orchestrator log
- Update task-board.json parallel_tracks if applicable

## Quality Gate
- CI pipeline completes without errors
- All tests pass in CI environment
- Build artifacts generated successfully
```

### `phase2-ci-fixing.txt`

```
You are the IMPLEMENTER agent working on task {TASK_ID} in a 3-Phase Engineering workflow.

PROJECT: {PROJECT_DIR}
PHASE: 2 — Implementation
STEP: CI Fixing

## Your Mission
Read CI failure logs, diagnose issues, apply fixes, and re-trigger CI.

## Context
- CI System: {CI_SYSTEM}
- CI URL: {CI_URL}
- CI Logs: Check {CI_URL} or run {LOG_CMD}
- Task board: .agents/task-board.json

## Instructions
1. Read CI failure logs from the latest run
2. Categorize failures:
   a. Build failures (compilation errors, missing deps)
   b. Test failures (assertion failures, timeouts)
   c. Lint failures (style violations)
   d. Environment issues (missing config, permissions)
3. For each failure:
   a. Identify root cause
   b. Apply minimal fix
   c. Run local verification: {BUILD_CMD} && {TEST_CMD} && {LINT_CMD}
4. Commit fixes with message: "fix(ci): [description]"
5. Re-trigger CI: {CI_TRIGGER_CMD}

## Quality Gate
- All previously failing CI checks now pass locally
- Fixes are minimal and don't introduce regressions
- CI re-triggered after fixes applied
```

### `phase2-device-baseline.txt`

```
You are the IMPLEMENTER agent working on task {TASK_ID} in a 3-Phase Engineering workflow.

PROJECT: {PROJECT_DIR}
PHASE: 2 — Implementation
STEP: Device Baseline

## Your Mission
Deploy to the test environment and run baseline verification checks. Set device_baseline_result.

## Context
- Device type: {DEVICE_TYPE}
- Deploy command: {DEPLOY_CMD}
- Baseline check: {BASELINE_CMD}
- Log command: {LOG_CMD}

## Instructions
1. Deploy to test environment: {DEPLOY_CMD}
2. Wait for deployment to stabilize (health checks)
3. Run baseline verification: {BASELINE_CMD}
4. Check application logs for errors: {LOG_CMD}
5. Verify core functionality is operational
6. If baseline passes: set device_baseline_result = "pass"
7. If baseline fails: set device_baseline_result = "fail" with diagnosis

## Update task-board.json
Before completing, update task-board.json with your result:
```bash
jq --arg tid "{TASK_ID}" '(.tasks[] | select(.id == $tid)).device_baseline_result = "pass"' \
  .agents/task-board.json > .agents/task-board.json.tmp \
  && mv .agents/task-board.json.tmp .agents/task-board.json
```

## Quality Gate
- Deployment succeeds without errors
- Health check passes: {BASELINE_CMD}
- No error-level entries in logs
- Core API endpoints respond correctly
```

### `phase3-deploying.txt`

```
You are the IMPLEMENTER agent working on task {TASK_ID} in a 3-Phase Engineering workflow.

PROJECT: {PROJECT_DIR}
PHASE: 3 — Testing & Verification
STEP: Deploying

## Your Mission
Deploy the verified build to the test environment for Phase 3 testing.

## Context
- Device type: {DEVICE_TYPE}
- Deploy command: {DEPLOY_CMD}
- Baseline check: {BASELINE_CMD}
- Log command: {LOG_CMD}

## Instructions
1. Verify the build artifact is ready (from Phase 2 CI)
2. Deploy to test environment: {DEPLOY_CMD}
3. Wait for deployment to complete and stabilize
4. Run health check: {BASELINE_CMD}
5. Verify logs are clean: {LOG_CMD}
6. Confirm environment is ready for regression and feature testing

## Output
- Deployment log to: .agents/orchestrator/logs/{TASK_ID}-deploy.log
- Confirm deployment URL/endpoint is accessible

## Quality Gate
- Deployment completes without errors
- Health check passes
- Application responds to basic requests
- No error-level log entries post-deployment
```

### `phase3-feature-testing.txt`

```
You are the TESTER agent working on task {TASK_ID} in a 3-Phase Engineering workflow.

PROJECT: {PROJECT_DIR}
PHASE: 3 — Testing & Verification
STEP: Feature Testing

## Your Mission
Run tests specific to the new feature and report results. Set feature_result.

## Context
- Deployment: {DEVICE_TYPE}
- Test command: {TEST_CMD}
- TDD plan: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-tdd-plan.md
- Requirements: .agents/runtime/acceptor/workspace/requirements/{TASK_ID}-requirements.md

## Instructions
1. Identify all test cases specific to the new feature from the TDD plan
2. Run feature-specific tests: {TEST_CMD}
3. Verify each acceptance criterion from requirements is met
4. For each failure:
   a. Capture error details and screenshots if applicable
   b. Determine if it's a test gap or implementation bug
   c. Document in .agents/runtime/tester/workspace/test-cases/{TASK_ID}-feature-test.md
5. Set feature_result based on results

## Update task-board.json
Before completing, update task-board.json with your result:
```bash
jq --arg tid "{TASK_ID}" '(.tasks[] | select(.id == $tid)).feature_result = "pass"' \
  .agents/task-board.json > .agents/task-board.json.tmp \
  && mv .agents/task-board.json.tmp .agents/task-board.json
```

## Decision
- If ALL new feature tests pass: set feature_result = "pass"
- If ANY feature test fails: set feature_result = "fail"
  - The orchestrator will trigger a feedback loop back to tdd_design

## Quality Gate
- All acceptance criteria verified
- No new feature test failures
- Feature behavior matches requirements
```

### `phase3-log-analysis.txt`

```
You are the TESTER agent (with DESIGNER input) working on task {TASK_ID} in a 3-Phase Engineering workflow.

PROJECT: {PROJECT_DIR}
PHASE: 3 — Testing & Verification
STEP: Log Analysis

## Your Mission
Analyze application and system logs for anomalies. Set log_analysis_result.

## Context
- Log command: {LOG_CMD}
- Deployment: {DEVICE_TYPE}
- DFMEA: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-dfmea.md

## Instructions
1. Collect logs from the test environment: {LOG_CMD}
2. Analyze for:
   a. Error-level messages (stack traces, exceptions)
   b. Warning patterns (resource exhaustion, timeouts)
   c. Performance anomalies (slow queries, high latency)
   d. Security concerns (auth failures, suspicious access patterns)
   e. Resource usage (memory leaks, file handle leaks)
3. Cross-reference with DFMEA — are predicted risks manifesting?
4. Output analysis to: .agents/runtime/tester/workspace/test-cases/{TASK_ID}-log-analysis.md
5. Set log_analysis_result based on findings

## Update task-board.json
Before completing, update task-board.json with your result:
```bash
jq --arg tid "{TASK_ID}" '(.tasks[] | select(.id == $tid)).log_analysis_result = "clean"' \
  .agents/task-board.json > .agents/task-board.json.tmp \
  && mv .agents/task-board.json.tmp .agents/task-board.json
```

## Decision
- If no anomalies found: set log_analysis_result = "clean"
- If anomalies detected: set log_analysis_result = "anomaly"
  - The orchestrator will trigger a feedback loop to ci_fixing

## Quality Gate
- All log sources analyzed
- No unaccounted error-level messages
- Performance metrics within acceptable thresholds
- DFMEA risks cross-checked
```

### `phase3-documentation.txt`

```
You are the DESIGNER agent working on task {TASK_ID} in a 3-Phase Engineering workflow.

PROJECT: {PROJECT_DIR}
PHASE: 3 — Testing & Verification
STEP: Documentation

## Your Mission
Write release notes and update project documentation for the completed task.

## Context
- Requirements: .agents/runtime/acceptor/workspace/requirements/{TASK_ID}-requirements.md
- Architecture: .agents/runtime/designer/workspace/design-docs/{TASK_ID}-design.md
- Task board: .agents/task-board.json (task ID: {TASK_ID})
- Test results: .agents/runtime/tester/workspace/test-cases/

## Instructions
1. Summarize what was implemented (from requirements and design docs)
2. Write release notes:
   a. New features added
   b. Bug fixes (if any)
   c. Breaking changes (if any)
   d. Migration steps (if needed)
3. Update project documentation:
   a. README.md — add/update feature documentation
   b. API docs — document new endpoints or changed interfaces
   c. Configuration docs — document new settings
4. Output to: docs/{TASK_ID}-release-notes.md
5. Commit documentation changes

## Output Format
- Release Notes: version, date, summary, details, migration guide
- Updated docs with clear change markers

## Quality Gate
- All new features documented
- No undocumented breaking changes
- Release notes are user-friendly and clear
- Links and references are valid
```
