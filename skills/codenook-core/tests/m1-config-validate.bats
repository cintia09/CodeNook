#!/usr/bin/env bats
# Unit 5 — config-validate (field-level type/range validation)

load helpers/load
load helpers/assertions

VALIDATE_SH="$CORE_ROOT/skills/builtin/config-validate/validate.sh"

write_json() {
  local path="$1"; shift
  printf '%s' "$*" >"$path"
}

@test "validate.sh exists and is executable" {
  assert_file_exists "$VALIDATE_SH"
  assert_file_executable "$VALIDATE_SH"
}

@test "missing --config flag → exit 2 + usage to stderr" {
  run_with_stderr "\"$VALIDATE_SH\""
  [ "$status" -eq 2 ]
  assert_contains "$STDERR" "--config"
}

@test "non-existent config file → exit 2" {
  run_with_stderr "\"$VALIDATE_SH\" --config /no/such/file.json"
  [ "$status" -eq 2 ]
  assert_contains "$STDERR" "not found"
}

@test "valid minimal config (models + router only) → exit 0" {
  ws="$(make_scratch)"
  write_json "$ws/cfg.json" '{"models":{"default":"opus-4.7"},"router":{"policy":"tiered"}}'
  run_with_stderr "\"$VALIDATE_SH\" --config \"$ws/cfg.json\""
  [ "$status" -eq 0 ]
}

@test "invalid: concurrency.max_parallel negative → exit 1 + field path" {
  ws="$(make_scratch)"
  write_json "$ws/cfg.json" '{"models":{"default":"opus-4.7"},"concurrency":{"max_parallel":-2}}'
  run_with_stderr "\"$VALIDATE_SH\" --config \"$ws/cfg.json\""
  [ "$status" -eq 1 ]
  assert_contains "$STDERR" "concurrency.max_parallel"
}

@test "invalid: hitl.mode unknown value → exit 1" {
  ws="$(make_scratch)"
  write_json "$ws/cfg.json" '{"models":{"default":"opus-4.7"},"hitl":{"mode":"maybe"}}'
  run_with_stderr "\"$VALIDATE_SH\" --config \"$ws/cfg.json\""
  [ "$status" -eq 1 ]
  assert_contains "$STDERR" "hitl.mode"
}

@test "invalid: models.default empty string → exit 1" {
  ws="$(make_scratch)"
  write_json "$ws/cfg.json" '{"models":{"default":""}}'
  run_with_stderr "\"$VALIDATE_SH\" --config \"$ws/cfg.json\""
  [ "$status" -eq 1 ]
  assert_contains "$STDERR" "models.default"
}

@test "deprecated key present → exit 0 with stderr warning" {
  ws="$(make_scratch)"
  write_json "$ws/cfg.json" '{"models":{"default":"opus-4.7"},"legacy_router":{"x":1}}'
  run_with_stderr "\"$VALIDATE_SH\" --config \"$ws/cfg.json\""
  [ "$status" -eq 0 ]
  assert_contains "$STDERR" "deprecated"
  assert_contains "$STDERR" "legacy_router"
}

@test "default schema path resolves to packaged config-schema.yaml" {
  ws="$(make_scratch)"
  # passing no --schema must still find defaults (exit 0 on valid cfg proves it)
  write_json "$ws/cfg.json" '{"models":{"default":"opus-4.7"}}'
  run_with_stderr "\"$VALIDATE_SH\" --config \"$ws/cfg.json\""
  [ "$status" -eq 0 ]
  # And verify the packaged schema exists
  assert_file_exists "$CORE_ROOT/skills/builtin/config-validate/config-schema.yaml"
}

@test "multiple errors reported at once (single run)" {
  ws="$(make_scratch)"
  write_json "$ws/cfg.json" '{"models":{"default":""},"hitl":{"mode":"xyz"},"concurrency":{"max_parallel":-1}}'
  run_with_stderr "\"$VALIDATE_SH\" --config \"$ws/cfg.json\""
  [ "$status" -eq 1 ]
  assert_contains "$STDERR" "models.default"
  assert_contains "$STDERR" "hitl.mode"
  assert_contains "$STDERR" "concurrency.max_parallel"
}

@test "--json flag produces structured output on failure" {
  ws="$(make_scratch)"
  write_json "$ws/cfg.json" '{"models":{"default":""}}'
  run_with_stderr "\"$VALIDATE_SH\" --config \"$ws/cfg.json\" --json"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.ok == false' >/dev/null
  echo "$output" | jq -e '.errors | length >= 1' >/dev/null
  echo "$output" | jq -e '.errors[0].path == "models.default"' >/dev/null
}

@test "--json flag produces structured output on success" {
  ws="$(make_scratch)"
  write_json "$ws/cfg.json" '{"models":{"default":"opus-4.7"}}'
  run_with_stderr "\"$VALIDATE_SH\" --config \"$ws/cfg.json\" --json"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true' >/dev/null
  echo "$output" | jq -e '.errors == []' >/dev/null
}
