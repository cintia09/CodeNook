#!/usr/bin/env bats
# M8.8 - Multi-turn end-to-end acceptance for the conversational
# router-agent. Uses real spawn.sh / tick.sh CLIs against a scratch
# workspace; the LLM-side subagent is simulated by directly mutating
# router-reply.md and draft-config.yaml between spawn invocations
# (the same trick used by m8-router-agent-spawn.bats).

load helpers/load
load helpers/assertions

SPAWN="$CORE_ROOT/skills/builtin/router-agent/spawn.sh"
TICK_SH="$CORE_ROOT/skills/builtin/orchestrator-tick/tick.sh"

# ---------------------------------------------------------------- helpers

mk_workspace() {
  local ws
  ws="$(make_scratch)"
  mkdir -p "$ws/.codenook/tasks" "$ws/.codenook/queue" \
           "$ws/.codenook/hitl-queue" "$ws/.codenook/history" \
           "$ws/.codenook/memory/_pending" "$ws/.codenook/plugins"
  cp -R "$FIXTURES_ROOT/m4/plugins/generic" "$ws/.codenook/plugins/generic"
  echo "$ws"
}

# Simulate the subagent appending a router turn + writing reply.
# Args: <task_dir> <reply_text>
sim_router_reply() {
  local td="$1" body="$2"
  printf '%s\n' "$body" >"$td/router-reply.md"
  python3 - "$td" "$body" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import os
lib = os.environ["LIB_DIR"]
sys.path.insert(0, lib)
import router_context as rc
td = Path(sys.argv[1])
body = sys.argv[2]
rc.append_turn(td, "router", body)
PY
}

# Write a draft-config.yaml under <task_dir>.
# Args: <task_dir> <yaml_body>
sim_draft() {
  local td="$1"; shift
  printf '%s' "$*" >"$td/draft-config.yaml"
}

setup() {
  export LIB_DIR="$CORE_ROOT/skills/builtin/_lib"
}

# ---------------------------------------------------------------- tests

@test "M8.8 multi-turn happy path: prompt -> clarify -> draft -> confirm -> handoff" {
  ws="$(mk_workspace)"
  td="$ws/.codenook/tasks/T-E2E1"

  # Turn 0 - initial spawn (no user turn yet, seeds router-context).
  run bash "$SPAWN" --task-id T-E2E1 --workspace "$ws"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  assert_contains "$output" '"action": "prompt"'
  assert_file_exists "$td/router-context.md"
  assert_file_exists "$td/.router-prompt.md"
  grep -q "^state: drafting" "$td/router-context.md"
  grep -q "^turn_count: 1" "$td/router-context.md"

  # Simulate subagent: ask a clarifying question.
  sim_router_reply "$td" "What language and runtime should the CLI use?"

  # Turn 1 - user answers; router proposes a draft.
  run bash "$SPAWN" --task-id T-E2E1 --workspace "$ws" \
                    --user-turn "Python CLI tool, Click-based, single command MARK_USER1"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  assert_contains "$output" '"action": "prompt"'
  grep -q "MARK_USER1" "$td/router-context.md"
  grep -q "MARK_USER1" "$td/.router-prompt.md"

  # Simulate subagent: write a complete draft + ask for confirmation.
  sim_draft "$td" '_draft: true
_draft_revision: 1
_draft_updated_at: "2026-05-12T10:00:00Z"
plugin: generic
selected_plugins: [generic]
input: |
  Build a Python Click CLI scaffold with one command.
max_iterations: 4
'
  sim_router_reply "$td" "Draft ready. Confirm to hand off?"

  # Turn 2 - user confirms.
  run bash "$SPAWN" --task-id T-E2E1 --workspace "$ws" --confirm
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  assert_contains "$output" '"action": "handoff"'
  assert_contains "$output" '"first_tick_status"'

  # state.json materialised + first tick has advanced phase to clarify.
  assert_file_exists "$td/state.json"
  jq -e '.task_id == "T-E2E1"' "$td/state.json" >/dev/null
  jq -e '.plugin == "generic"' "$td/state.json" >/dev/null
  jq -e '.selected_plugins == ["generic"]' "$td/state.json" >/dev/null
  jq -e '.phase == "clarify"' "$td/state.json" >/dev/null
  jq -e '.in_flight_agent.role == "clarifier"' "$td/state.json" >/dev/null

  # router-context flipped to confirmed.
  grep -q "^state: confirmed" "$td/router-context.md"
  grep -q "^last_router_action: handoff" "$td/router-context.md"
  [ ! -f "$td/router.lock" ]
}

@test "M8.8 parallel isolation: three task ids, no cross-talk" {
  ws="$(mk_workspace)"

  # Burst all three turn-0 spawns in parallel.
  out1="$BATS_TEST_TMPDIR/p1.out"
  out2="$BATS_TEST_TMPDIR/p2.out"
  out3="$BATS_TEST_TMPDIR/p3.out"
  bash "$SPAWN" --task-id T-PAR1 --workspace "$ws" \
                --user-turn "ALPHA payload zeta1" >"$out1" 2>&1 &
  pid1=$!
  bash "$SPAWN" --task-id T-PAR2 --workspace "$ws" \
                --user-turn "BETA payload zeta2" >"$out2" 2>&1 &
  pid2=$!
  bash "$SPAWN" --task-id T-PAR3 --workspace "$ws" \
                --user-turn "GAMMA payload zeta3" >"$out3" 2>&1 &
  pid3=$!
  wait "$pid1"; rc1=$?
  wait "$pid2"; rc2=$?
  wait "$pid3"; rc3=$?
  [ "$rc1" -eq 0 ] || { echo "1: $(cat "$out1")"; return 1; }
  [ "$rc2" -eq 0 ] || { echo "2: $(cat "$out2")"; return 1; }
  [ "$rc3" -eq 0 ] || { echo "3: $(cat "$out3")"; return 1; }
  grep -q '"task_id": "T-PAR1"' "$out1"
  grep -q '"task_id": "T-PAR2"' "$out2"
  grep -q '"task_id": "T-PAR3"' "$out3"

  # Turn-1 follow-up (sequential is fine; per-task lock isolation already
  # validated by the parallel turn-0 burst above).
  for i in 1 2 3; do
    case "$i" in
      1) tag=ALPHA;  unique=keyword_one  ;;
      2) tag=BETA;   unique=keyword_two  ;;
      3) tag=GAMMA;  unique=keyword_three;;
    esac
    td="$ws/.codenook/tasks/T-PAR$i"
    sim_router_reply "$td" "router ack $tag"
    bash "$SPAWN" --task-id "T-PAR$i" --workspace "$ws" \
                  --user-turn "follow-up $unique" >/dev/null
    sim_draft "$td" "_draft: true
_draft_revision: 1
_draft_updated_at: \"2026-05-12T10:00:00Z\"
plugin: generic
selected_plugins: [generic]
input: |
  $tag scope only.
max_iterations: 2
"
  done

  # Cross-talk assertions: each task's files reference only its own data.
  for i in 1 2 3; do
    case "$i" in
      1) self=ALPHA; other_a=BETA; other_b=GAMMA; uniq=keyword_one;;
      2) self=BETA;  other_a=ALPHA; other_b=GAMMA; uniq=keyword_two;;
      3) self=GAMMA; other_a=ALPHA; other_b=BETA;  uniq=keyword_three;;
    esac
    td="$ws/.codenook/tasks/T-PAR$i"
    grep -q "$self" "$td/router-context.md"
    grep -q "$uniq" "$td/router-context.md"
    ! grep -q "$other_a" "$td/router-context.md"
    ! grep -q "$other_b" "$td/router-context.md"
    grep -q "$self" "$td/draft-config.yaml"
    ! grep -q "$other_a" "$td/draft-config.yaml"
    ! grep -q "$other_b" "$td/draft-config.yaml"
    # Lock released per-task.
    [ ! -f "$td/router.lock" ]
  done
}

@test "M8.8 confirm with role_constraints excluded -> validator-style skip honoured" {
  ws="$(mk_workspace)"
  td="$ws/.codenook/tasks/T-EXC1"

  # Turn 0 - initial spawn.
  bash "$SPAWN" --task-id T-EXC1 --workspace "$ws" >/dev/null

  # Simulate a draft that excludes the clarifier role (the M4 generic
  # fixture has no `validator` role, so we exercise the same M8.10
  # skip contract on a role that does exist; the schema/skip code-path
  # is identical).
  sim_draft "$td" '_draft: true
_draft_revision: 1
_draft_updated_at: "2026-05-12T10:00:00Z"
plugin: generic
selected_plugins: [generic]
input: |
  Skip the clarifier; jump straight to analyzer.
max_iterations: 4
role_constraints:
  excluded:
    - {plugin: generic, role: clarifier}
'
  sim_router_reply "$td" "Confirm to hand off (clarifier excluded)."

  run bash "$SPAWN" --task-id T-EXC1 --workspace "$ws" --confirm
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  assert_contains "$output" '"action": "handoff"'
  assert_file_exists "$td/state.json"

  # role_constraints persisted in state.json.
  jq -e '.role_constraints.excluded[0].plugin == "generic"' "$td/state.json" >/dev/null
  jq -e '.role_constraints.excluded[0].role == "clarifier"' "$td/state.json" >/dev/null

  # First tick (run by spawn.sh --confirm) skipped clarify and dispatched analyzer.
  jq -e '[.history[] | select(.phase=="clarify" and .verdict=="skipped")] | length == 1' \
        "$td/state.json" >/dev/null
  jq -e '.phase == "analyze"' "$td/state.json" >/dev/null
  jq -e '.in_flight_agent.role == "analyzer"' "$td/state.json" >/dev/null

  # A second manual tick must not regress (idempotent on in-flight phase).
  run bash "$TICK_SH" --task T-EXC1 --workspace "$ws"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -e '.phase == "analyze"' "$td/state.json" >/dev/null
}

@test "M8.8 workspace overlay description is loaded into rendered prompt" {
  ws="$(mk_workspace)"
  mkdir -p "$ws/.codenook/user-overlay"
  cat >"$ws/.codenook/user-overlay/description.md" <<'EOF'
OVERLAY_MARKER_42 — this workspace targets the XueBa knowledge base.
EOF

  run bash "$SPAWN" --task-id T-OVL1 --workspace "$ws" \
                    --user-turn "use the project's domain conventions"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  assert_contains "$output" '"action": "prompt"'

  pf="$ws/.codenook/tasks/T-OVL1/.router-prompt.md"
  assert_file_exists "$pf"
  grep -q "OVERLAY_MARKER_42" "$pf"
  grep -q "XueBa knowledge base" "$pf"
  # overlay section header present and not empty placeholder
  grep -q "Workspace user-overlay" "$pf"
  ! grep -q "no workspace user-overlay present" "$pf"
}

@test "M8.8 schema-invalid confirm -> graceful error, state preserved for retry" {
  ws="$(mk_workspace)"
  td="$ws/.codenook/tasks/T-INV1"

  # Initial spawn establishes context.
  bash "$SPAWN" --task-id T-INV1 --workspace "$ws" \
                --user-turn "first user request UNIQUE_BEFORE" >/dev/null
  ctx_before="$(cat "$td/router-context.md")"

  # Pre-write a draft that fails schema (missing required `input`).
  sim_draft "$td" '_draft: true
plugin: generic
'

  run bash "$SPAWN" --task-id T-INV1 --workspace "$ws" --confirm
  [ "$status" -eq 4 ] || { echo "exit=$status out=$output"; return 1; }
  assert_contains "$output" '"action": "error"'
  assert_contains "$output" '"code": "draft_invalid"'
  [ ! -f "$td/state.json" ]
  [ ! -f "$td/router.lock" ]
  # router-context untouched on validation failure (no spurious
  # frontmatter mutation).
  grep -q "^state: drafting" "$td/router-context.md"
  grep -q "UNIQUE_BEFORE" "$td/router-context.md"

  # A subsequent non-confirm spawn must still work (state preserved,
  # lock not orphaned).
  run bash "$SPAWN" --task-id T-INV1 --workspace "$ws" \
                    --user-turn "let me retry UNIQUE_RETRY"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  assert_contains "$output" '"action": "prompt"'
  grep -q "UNIQUE_BEFORE" "$td/router-context.md"
  grep -q "UNIQUE_RETRY" "$td/router-context.md"
}
