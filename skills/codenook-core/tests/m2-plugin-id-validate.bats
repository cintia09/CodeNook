#!/usr/bin/env bats
# M2 Unit 3 — plugin-id-validate gate (G03)
#
# Contract:
#   id-validate.sh --src <dir> [--workspace <dir>] [--upgrade] [--json]
#
# Checks:
#   - plugin.yaml.id matches ^[a-z][a-z0-9-]{2,30}$
#   - id not in reserved set: {core, builtin, generic, codenook}
#   - if --workspace given AND id already under <ws>/.codenook/plugins/<id>/
#     AND --upgrade NOT supplied → fail

load helpers/load
load helpers/assertions

GATE_SH="$CORE_ROOT/skills/builtin/plugin-id-validate/id-validate.sh"

mk_src_with_id() {
  local d id; id="$1"
  d="$(make_scratch)/p"
  mkdir -p "$d"
  printf 'id: %s\nversion: 0.1.0\n' "$id" >"$d/plugin.yaml"
  echo "$d"
}

mk_ws() {
  local d; d="$(make_scratch)/ws"
  mkdir -p "$d/.codenook/plugins"
  echo "$d"
}

@test "id-validate.sh exists and is executable" {
  assert_file_exists "$GATE_SH"
  assert_file_executable "$GATE_SH"
}

@test "missing --src → exit 2" {
  run_with_stderr "\"$GATE_SH\""
  [ "$status" -eq 2 ]
}

@test "valid id (lowercase + digits + hyphen) → exit 0" {
  d="$(mk_src_with_id "foo-bar2")"
  run_with_stderr "\"$GATE_SH\" --src \"$d\""
  [ "$status" -eq 0 ]
}

@test "id with uppercase → exit 1" {
  d="$(mk_src_with_id "FooBar")"
  run_with_stderr "\"$GATE_SH\" --src \"$d\""
  [ "$status" -eq 1 ]
  assert_contains "$STDERR" "id"
}

@test "id starting with digit → exit 1" {
  d="$(mk_src_with_id "1foo")"
  run_with_stderr "\"$GATE_SH\" --src \"$d\""
  [ "$status" -eq 1 ]
}

@test "id too short (2 chars) → exit 1" {
  d="$(mk_src_with_id "ab")"
  run_with_stderr "\"$GATE_SH\" --src \"$d\""
  [ "$status" -eq 1 ]
}

@test "id with underscore → exit 1" {
  d="$(mk_src_with_id "foo_bar")"
  run_with_stderr "\"$GATE_SH\" --src \"$d\""
  [ "$status" -eq 1 ]
}

@test "reserved id 'generic' → exit 1, reason mentions reserved" {
  d="$(mk_src_with_id "generic")"
  run_with_stderr "\"$GATE_SH\" --src \"$d\""
  [ "$status" -eq 1 ]
  assert_contains "$STDERR" "reserved"
}

@test "reserved id 'codenook' → exit 1" {
  d="$(mk_src_with_id "codenook")"
  run_with_stderr "\"$GATE_SH\" --src \"$d\""
  [ "$status" -eq 1 ]
}

@test "id already installed (no --upgrade) → exit 1, reason mentions installed" {
  d="$(mk_src_with_id "foo")"
  ws="$(mk_ws)"
  mkdir -p "$ws/.codenook/plugins/foo"
  printf 'id: foo\nversion: 0.1.0\n' >"$ws/.codenook/plugins/foo/plugin.yaml"
  run_with_stderr "\"$GATE_SH\" --src \"$d\" --workspace \"$ws\""
  [ "$status" -eq 1 ]
  assert_contains "$STDERR" "installed"
}

@test "id already installed but --upgrade → exit 0" {
  d="$(mk_src_with_id "foo")"
  ws="$(mk_ws)"
  mkdir -p "$ws/.codenook/plugins/foo"
  printf 'id: foo\nversion: 0.1.0\n' >"$ws/.codenook/plugins/foo/plugin.yaml"
  run_with_stderr "\"$GATE_SH\" --src \"$d\" --workspace \"$ws\" --upgrade"
  [ "$status" -eq 0 ]
}

@test "--json envelope on failure" {
  d="$(mk_src_with_id "BAD")"
  run "$GATE_SH" --src "$d" --json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.gate == "plugin-id-validate" and .ok == false' >/dev/null
}

@test "--json envelope: already-installed sets code=already_installed" {
  d="$(mk_src_with_id "foo")"
  ws="$(mk_ws)"
  mkdir -p "$ws/.codenook/plugins/foo"
  printf 'id: foo\nversion: 0.1.0\n' >"$ws/.codenook/plugins/foo/plugin.yaml"
  run "$GATE_SH" --src "$d" --workspace "$ws" --json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.code == "already_installed" and .ok == false' >/dev/null
}

@test "--json envelope: ordinary G03 failure has no 'already_installed' code" {
  d="$(mk_src_with_id "BAD")"
  run "$GATE_SH" --src "$d" --json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '(.code // "") != "already_installed"' >/dev/null
}
