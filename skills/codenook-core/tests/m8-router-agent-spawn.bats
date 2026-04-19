#!/usr/bin/env bats
# M8.2 - router-agent skill spawn.sh CLI contract.
# Verifies the deterministic context-prep + handoff envelope.
# The "subagent reply" step is mocked by tests writing directly to
# router-reply.md / draft-config.yaml between spawn.sh invocations.

load helpers/load
load helpers/assertions

SPAWN="$CORE_ROOT/skills/builtin/router-agent/spawn.sh"
LIB_DIR="$CORE_ROOT/skills/builtin/_lib"
HOLDER="$CORE_ROOT/tests/helpers/m8_lock_holder.py"

# Build a workspace with a real generic plugin so tick.sh has something
# to chew on when --confirm is exercised. Layout matches m4-e2e-tick.bats.
mk_workspace() {
  local ws
  ws="$(make_scratch)"
  mkdir -p "$ws/.codenook/tasks" "$ws/.codenook/queue" \
           "$ws/.codenook/hitl-queue" "$ws/.codenook/history" \
           "$ws/.codenook/memory/_pending" "$ws/.codenook/plugins"
  cp -R "$FIXTURES_ROOT/m4/plugins/generic" "$ws/.codenook/plugins/generic"
  echo "$ws"
}

@test "M8.2 spawn.sh is executable and reports help" {
  assert_file_executable "$SPAWN"
}

@test "M8.2 absent task -> creates initial router-context, empty draft, action=prompt" {
  ws="$(mk_workspace)"
  run bash "$SPAWN" --task-id T-001 --workspace "$ws"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  assert_contains "$output" '"action": "prompt"'
  assert_contains "$output" '"task_id": "T-001"'
  td="$ws/.codenook/tasks/T-001"
  assert_file_exists "$td/router-context.md"
  assert_file_exists "$td/draft-config.yaml"
  assert_file_exists "$td/.router-prompt.md"
  # frontmatter state is drafting; turn_count=1 (seeded turn)
  grep -q "^state: drafting" "$td/router-context.md"
  grep -q "^turn_count: 1" "$td/router-context.md"
  # draft is empty placeholder
  [ ! -s "$td/draft-config.yaml" ]
  # lock released
  [ ! -f "$td/router.lock" ]
}

@test "M8.2 --user-turn appends to router-context and prompt embeds the turn" {
  ws="$(mk_workspace)"
  bash "$SPAWN" --task-id T-002 --workspace "$ws" >/dev/null
  run bash "$SPAWN" --task-id T-002 --workspace "$ws" \
                    --user-turn "please refactor the login flow XYZUNIQ"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  assert_contains "$output" '"action": "prompt"'
  td="$ws/.codenook/tasks/T-002"
  grep -q "XYZUNIQ" "$td/router-context.md"
  grep -q "XYZUNIQ" "$td/.router-prompt.md"
  # turn_count incremented from initial 1 to 2
  grep -q "^turn_count: 2" "$td/router-context.md"
}

@test "M8.2 concurrent spawn on same task -> second emits action=busy" {
  ws="$(mk_workspace)"
  td="$ws/.codenook/tasks/T-003"
  mkdir -p "$td"
  out_file="$BATS_TEST_TMPDIR/holder.out"
  LIB_DIR="$LIB_DIR" python3 "$HOLDER" "$td" 5 >"$out_file" 2>&1 &
  holder_pid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    [ -s "$out_file" ] && break
    sleep 0.2
  done
  [ -s "$out_file" ] || { kill "$holder_pid" 2>/dev/null; cat "$out_file"; return 1; }

  run bash "$SPAWN" --task-id T-003 --workspace "$ws" --lock-timeout 0.5
  status_main="$status"; output_main="$output"
  kill "$holder_pid" 2>/dev/null; wait "$holder_pid" 2>/dev/null || true

  [ "$status_main" -eq 3 ] || { echo "exit=$status_main out=$output_main"; return 1; }
  assert_contains "$output_main" '"action": "busy"'
  assert_contains "$output_main" '"task_id": "T-003"'
}

@test "M8.2 --confirm with valid draft materialises state.json + runs first tick" {
  ws="$(mk_workspace)"
  bash "$SPAWN" --task-id T-004 --workspace "$ws" >/dev/null
  td="$ws/.codenook/tasks/T-004"
  # mock the subagent: write a complete draft + a router-reply
  cat >"$td/draft-config.yaml" <<'YAML'
_draft: true
_draft_revision: 1
_draft_updated_at: "2026-05-12T10:00:00Z"
plugin: generic
selected_plugins: [generic]
input: |
  Add a --tag filter to the xueba CLI.
max_iterations: 4
YAML
  printf 'go\n' >"$td/router-reply.md"

  run bash "$SPAWN" --task-id T-004 --workspace "$ws" --confirm
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  assert_contains "$output" '"action": "handoff"'
  assert_contains "$output" '"task_id": "T-004"'
  assert_contains "$output" '"first_tick_status"'
  assert_file_exists "$td/state.json"
  jq -e '.task_id == "T-004"' "$td/state.json" >/dev/null
  jq -e '.plugin == "generic"' "$td/state.json" >/dev/null
  # tick should have advanced phase from null to clarify
  jq -e '.phase == "clarify"' "$td/state.json" >/dev/null
  # context frontmatter flipped to confirmed
  grep -q "^state: confirmed" "$td/router-context.md"
  grep -q "^last_router_action: handoff" "$td/router-context.md"
  [ ! -f "$td/router.lock" ]
}

@test "M8.2 --confirm with invalid draft -> action=error, no state.json" {
  ws="$(mk_workspace)"
  bash "$SPAWN" --task-id T-005 --workspace "$ws" >/dev/null
  td="$ws/.codenook/tasks/T-005"
  # invalid: missing required `input` and `_draft: true`
  cat >"$td/draft-config.yaml" <<'YAML'
plugin: generic
YAML
  run bash "$SPAWN" --task-id T-005 --workspace "$ws" --confirm
  [ "$status" -eq 4 ] || { echo "exit=$status out=$output"; return 1; }
  assert_contains "$output" '"action": "error"'
  assert_contains "$output" '"code": "draft_invalid"'
  assert_contains "$output" '"errors"'
  [ ! -f "$td/state.json" ]
  # lock released even on validation failure (test #8)
  [ ! -f "$td/router.lock" ]
  # subsequent acquire must succeed immediately
  run bash "$SPAWN" --task-id T-005 --workspace "$ws" --lock-timeout 1.0
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  assert_contains "$output" '"action": "prompt"'
}

@test "M8.2 prompt template renders all required sections" {
  ws="$(mk_workspace)"
  bash "$SPAWN" --task-id T-006 --workspace "$ws" \
                --user-turn "build a CLI tag filter SENTINEL_USER" >/dev/null
  pf="$ws/.codenook/tasks/T-006/.router-prompt.md"
  assert_file_exists "$pf"
  # placeholders must all be substituted (no {{...}} left)
  ! grep -q "{{TASK_ID}}" "$pf"
  ! grep -q "{{PLUGINS_SUMMARY}}" "$pf"
  ! grep -q "{{ROLES}}" "$pf"
  ! grep -q "{{OVERLAY}}" "$pf"
  ! grep -q "{{CONTEXT_FRONTMATTER}}" "$pf"
  ! grep -q "{{CONTEXT}}" "$pf"
  ! grep -q "{{USER_TURN}}" "$pf"
  # required sections present
  grep -q "Task \`T-006\`" "$pf"
  grep -q "Available plugins" "$pf"
  grep -q "generic" "$pf"
  grep -q "Workspace user-overlay" "$pf"
  grep -q "router-context (frontmatter)" "$pf"
  grep -q "Latest user turn" "$pf"
  grep -q "SENTINEL_USER" "$pf"
}

@test "M8.2 two task ids in parallel both succeed (per-task lock isolation)" {
  ws="$(mk_workspace)"
  out_a="$BATS_TEST_TMPDIR/a.out"
  out_b="$BATS_TEST_TMPDIR/b.out"
  bash "$SPAWN" --task-id T-A1 --workspace "$ws" --user-turn "hello A" >"$out_a" 2>&1 &
  pid_a=$!
  bash "$SPAWN" --task-id T-B2 --workspace "$ws" --user-turn "hello B" >"$out_b" 2>&1 &
  pid_b=$!
  wait "$pid_a"; rc_a=$?
  wait "$pid_b"; rc_b=$?
  [ "$rc_a" -eq 0 ] || { echo "A: $(cat "$out_a")"; return 1; }
  [ "$rc_b" -eq 0 ] || { echo "B: $(cat "$out_b")"; return 1; }
  grep -q '"action": "prompt"' "$out_a"
  grep -q '"action": "prompt"' "$out_b"
  grep -q '"task_id": "T-A1"' "$out_a"
  grep -q '"task_id": "T-B2"' "$out_b"
  assert_file_exists "$ws/.codenook/tasks/T-A1/router-context.md"
  assert_file_exists "$ws/.codenook/tasks/T-B2/router-context.md"
}

@test "M8.2 bad task id rejected with usage error" {
  ws="$(mk_workspace)"
  run bash "$SPAWN" --task-id NOT-A-TASK --workspace "$ws"
  [ "$status" -eq 2 ] || { echo "exit=$status out=$output"; return 1; }
  assert_contains "$output" '"code": "bad_task_id"'
}

@test "M8.2 missing workspace rejected with usage error" {
  run bash "$SPAWN" --task-id T-099 --workspace /nonexistent/path/xyzzy
  [ "$status" -eq 2 ] || { echo "exit=$status out=$output"; return 1; }
  assert_contains "$output" '"code": "bad_workspace"'
}
