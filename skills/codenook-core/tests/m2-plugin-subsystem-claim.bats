#!/usr/bin/env bats
# M2 Unit 9 — plugin-subsystem-claim (G07)
#
# Contract:
#   subsystem-claim.sh --src <dir> [--workspace <dir>] [--upgrade] [--json]
#
# Each installed plugin declares a list of subsystem extension claims
# in plugin.yaml.declared_subsystems (free-form strings, e.g.
# "skills/test-runner", "agents/router"). Two plugins may not claim
# the same string. On --upgrade, the plugin being installed is
# allowed to keep its own previously-claimed strings.

load helpers/load
load helpers/assertions

GATE_SH="$CORE_ROOT/skills/builtin/plugin-subsystem-claim/subsystem-claim.sh"

mk_src() {
  local id claims d
  id="$1"; claims="$2"
  d="$(make_scratch)/p"; mkdir -p "$d"
  {
    printf 'id: %s\nversion: 0.1.0\ndeclared_subsystems:\n' "$id"
    printf '%b' "$claims"
  } >"$d/plugin.yaml"
  echo "$d"
}

mk_ws() {
  local d; d="$(make_scratch)/ws"
  mkdir -p "$d/.codenook/plugins"
  echo "$d"
}

install_into_ws() {
  local ws id claims; ws="$1"; id="$2"; claims="$3"
  mkdir -p "$ws/.codenook/plugins/$id"
  {
    printf 'id: %s\nversion: 0.1.0\ndeclared_subsystems:\n' "$id"
    printf '%b' "$claims"
  } >"$ws/.codenook/plugins/$id/plugin.yaml"
}

@test "subsystem-claim.sh exists and executable" {
  assert_file_exists "$GATE_SH"
  assert_file_executable "$GATE_SH"
}

@test "no workspace given → exit 0 (no peers to collide with)" {
  d="$(mk_src "foo" "  - skills/test-runner\n")"
  run_with_stderr "\"$GATE_SH\" --src \"$d\""
  [ "$status" -eq 0 ]
}

@test "empty plugins dir → exit 0" {
  d="$(mk_src "foo" "  - skills/test-runner\n")"
  ws="$(mk_ws)"
  run_with_stderr "\"$GATE_SH\" --src \"$d\" --workspace \"$ws\""
  [ "$status" -eq 0 ]
}

@test "non-conflicting peer → exit 0" {
  d="$(mk_src "foo" "  - skills/test-runner\n")"
  ws="$(mk_ws)"
  install_into_ws "$ws" "bar" "  - agents/router\n"
  run_with_stderr "\"$GATE_SH\" --src \"$d\" --workspace \"$ws\""
  [ "$status" -eq 0 ]
}

@test "conflicting peer claim → exit 1" {
  d="$(mk_src "foo" "  - skills/test-runner\n")"
  ws="$(mk_ws)"
  install_into_ws "$ws" "bar" "  - skills/test-runner\n"
  run_with_stderr "\"$GATE_SH\" --src \"$d\" --workspace \"$ws\""
  [ "$status" -eq 1 ]
  assert_contains "$STDERR" "skills/test-runner"
  assert_contains "$STDERR" "bar"
}

@test "self-collision under --upgrade is allowed" {
  d="$(mk_src "foo" "  - skills/test-runner\n")"
  ws="$(mk_ws)"
  install_into_ws "$ws" "foo" "  - skills/test-runner\n"
  run_with_stderr "\"$GATE_SH\" --src \"$d\" --workspace \"$ws\" --upgrade"
  [ "$status" -eq 0 ]
}

@test "self-collision WITHOUT --upgrade still fails" {
  d="$(mk_src "foo" "  - skills/test-runner\n")"
  ws="$(mk_ws)"
  install_into_ws "$ws" "foo" "  - skills/test-runner\n"
  run_with_stderr "\"$GATE_SH\" --src \"$d\" --workspace \"$ws\""
  [ "$status" -eq 1 ]
}

@test "--json envelope on conflict" {
  d="$(mk_src "foo" "  - skills/x\n")"
  ws="$(mk_ws)"
  install_into_ws "$ws" "bar" "  - skills/x\n"
  run "$GATE_SH" --src "$d" --workspace "$ws" --json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.gate == "plugin-subsystem-claim" and .ok == false' >/dev/null
}
