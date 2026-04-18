#!/usr/bin/env bats
# M3 Unit 2 — router-bootstrap (the first sub-agent dispatched by main session).
#
# Contract:
#   bootstrap.sh --user-input "<text>" [--workspace <dir>] [--task <T-NNN>] [--json]
#
# Reads in this order:
#   1. agents/router.md            (own profile)
#   2. core/shell.md               (main-session contract)
#   3. <ws>/.codenook/state.json   (active tasks, installed plugins)
#   4. <ws>/.codenook/plugins/<each>/plugin.yaml (entry_points, declared_subsystems, intent_patterns)
#   5. config-resolve --plugin __router__   → must resolve to tier_strong (decision #44)
#
# Output:
#   { role: "router", context: {active_tasks, installed_plugins, model}, ready: true }
#
# Exit:  0 ready / 1 bootstrap failure (lists missing files) / 2 usage.

load helpers/load
load helpers/assertions

BOOT_SH="$CORE_ROOT/skills/builtin/router/bootstrap.sh"
M3_FX="$FIXTURES_ROOT/m3"

stage_ws() {
  local src="$1" dst
  dst="$(make_scratch)/ws"
  cp -R "$src" "$dst"
  # bootstrap reads model_catalog from state.json — graft full catalog.
  python3 - "$dst" "$FIXTURES_ROOT/catalog/full.json" <<'PY'
import json, sys, pathlib
ws, cat = sys.argv[1:]
sf = pathlib.Path(ws, ".codenook/state.json")
data = json.loads(sf.read_text())
data["model_catalog"] = json.loads(open(cat).read())
sf.write_text(json.dumps(data, indent=2))
PY
  echo "$dst"
}

@test "bootstrap.sh exists and is executable" {
  assert_file_exists "$BOOT_SH"
  assert_file_executable "$BOOT_SH"
}

@test "no --user-input → exit 2 usage" {
  ws="$(stage_ws "$M3_FX/workspaces/empty")"
  run_with_stderr "\"$BOOT_SH\" --workspace \"$ws\""
  [ "$status" -eq 2 ]
}

@test "happy path: empty workspace → ready=true, role=router" {
  ws="$(stage_ws "$M3_FX/workspaces/empty")"
  run_with_stderr "\"$BOOT_SH\" --user-input 'hi' --workspace \"$ws\" --json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.role    == "router"' >/dev/null
  echo "$output" | jq -e '.ready   == true'     >/dev/null
  echo "$output" | jq -e '.context.installed_plugins == []' >/dev/null
}

@test "missing agents/router.md profile → exit 1, names file" {
  ws="$(stage_ws "$M3_FX/workspaces/empty")"
  # Point CN_CORE_ROOT at a fake core that has shell.md but no router.md.
  fake="$(make_scratch)/fakecore"
  mkdir -p "$fake/agents" "$fake/core"
  cp "$CORE_ROOT/core/shell.md" "$fake/core/shell.md"
  run_with_stderr "CN_CORE_ROOT=\"$fake\" \"$BOOT_SH\" --user-input 'hi' --workspace \"$ws\" --json"
  [ "$status" -eq 1 ]
  assert_contains "$STDERR" "router.md"
}

@test "missing core/shell.md → exit 1, names file" {
  ws="$(stage_ws "$M3_FX/workspaces/empty")"
  fake="$(make_scratch)/fakecore"
  mkdir -p "$fake/agents" "$fake/core"
  cp "$CORE_ROOT/agents/router.md" "$fake/agents/router.md"
  run_with_stderr "CN_CORE_ROOT=\"$fake\" \"$BOOT_SH\" --user-input 'hi' --workspace \"$ws\" --json"
  [ "$status" -eq 1 ]
  assert_contains "$STDERR" "shell.md"
}

@test "missing state.json → exit 1, names file" {
  ws="$(make_scratch)/ws"
  mkdir -p "$ws/.codenook"
  run_with_stderr "\"$BOOT_SH\" --user-input 'hi' --workspace \"$ws\" --json"
  [ "$status" -eq 1 ]
  assert_contains "$STDERR" "state.json"
}

@test "no plugins installed → installed_plugins is empty list (not null)" {
  ws="$(stage_ws "$M3_FX/workspaces/empty")"
  run_with_stderr "\"$BOOT_SH\" --user-input 'hi' --workspace \"$ws\" --json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.context.installed_plugins | type == "array"' >/dev/null
  echo "$output" | jq -e '.context.installed_plugins | length == 0' >/dev/null
}

@test "multiple plugins enumerated with id+version" {
  ws="$(stage_ws "$M3_FX/workspaces/full")"
  run_with_stderr "\"$BOOT_SH\" --user-input 'hi' --workspace \"$ws\" --json"
  [ "$status" -eq 0 ]
  ids=$(echo "$output" | jq -c '[.context.installed_plugins[].id] | sort')
  [ "$ids" = '["ambiguous-stub","coding-stub","writing-stub"]' ]
}

@test "invalid manifest YAML → bootstrap reports broken plugin but stays ready" {
  ws="$(stage_ws "$M3_FX/workspaces/one-plugin")"
  printf '::not yaml: [' > "$ws/.codenook/plugins/writing-stub/plugin.yaml"
  run_with_stderr "\"$BOOT_SH\" --user-input 'hi' --workspace \"$ws\" --json"
  [ "$status" -eq 0 ]
  # Broken plugin entry surfaces with _error marker
  echo "$output" | jq -e '.context.installed_plugins[] | select(.id=="writing-stub") | ._error != null' >/dev/null
}

@test "model resolves to tier_strong literal (decision #44)" {
  ws="$(stage_ws "$M3_FX/workspaces/empty")"
  run_with_stderr "\"$BOOT_SH\" --user-input 'hi' --workspace \"$ws\" --json"
  [ "$status" -eq 0 ]
  # Catalog full.json maps tier_strong → opus-4.7
  echo "$output" | jq -e '.context.model == "opus-4.7"' >/dev/null
}

@test "--task without matching state propagates as null active_task" {
  ws="$(stage_ws "$M3_FX/workspaces/empty")"
  run_with_stderr "\"$BOOT_SH\" --user-input 'hi' --workspace \"$ws\" --task T-999 --json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.context.active_task == "T-999"' >/dev/null
  # but no fail — task may not exist yet (router decides whether to create)
}

@test "JSON envelope shape is stable" {
  ws="$(stage_ws "$M3_FX/workspaces/full")"
  run_with_stderr "\"$BOOT_SH\" --user-input 'hi' --workspace \"$ws\" --json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("role") and has("context") and has("ready")' >/dev/null
  echo "$output" | jq -e '.context | has("installed_plugins") and has("active_tasks") and has("model")' >/dev/null
}
