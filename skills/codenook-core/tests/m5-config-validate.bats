#!/usr/bin/env bats
# M5 — config-validate: typo detection + nested unknown key reporting

load helpers/load
load helpers/assertions

VALIDATE_SH="$CORE_ROOT/skills/builtin/config-validate/validate.sh"

mk_cfg_json() {
  local f="$1" body="$2"
  echo "$body" > "$f"
}

@test "m5-validate: valid effective config exits 0" {
  cfg="${BATS_TEST_TMPDIR}/cfg.json"
  cat >"$cfg" <<'EOF'
{
  "models": { "default": "opus-4.7", "reviewer": "sonnet-4.6" },
  "hitl":   { "mode": "auto" },
  "concurrency": { "max_parallel": 2 }
}
EOF
  run "$VALIDATE_SH" --config "$cfg"
  [ "$status" -eq 0 ]
}

@test "m5-validate: typo models.reviever suggests reviewer" {
  cfg="${BATS_TEST_TMPDIR}/cfg.json"
  cat >"$cfg" <<'EOF'
{
  "models": { "default": "opus-4.7", "reviever": "sonnet-4.6" }
}
EOF
  run_with_stderr "\"$VALIDATE_SH\" --config \"$cfg\""
  [ "$status" -eq 1 ]
  assert_contains "$STDERR" "models.reviever"
  assert_contains "$STDERR" "unknown key"
  assert_contains "$STDERR" "did you mean"
  assert_contains "$STDERR" "reviewer"
}

@test "m5-validate: completely novel key has no did-you-mean line" {
  cfg="${BATS_TEST_TMPDIR}/cfg.json"
  cat >"$cfg" <<'EOF'
{
  "models": { "default": "opus-4.7", "qwertyuiop": "x" }
}
EOF
  run_with_stderr "\"$VALIDATE_SH\" --config \"$cfg\""
  [ "$status" -eq 1 ]
  assert_contains "$STDERR" "models.qwertyuiop"
  assert_contains "$STDERR" "unknown key"
  assert_not_contains "$STDERR" "did you mean"
}

@test "m5-validate: nested unknown key shows full dotted path" {
  cfg="${BATS_TEST_TMPDIR}/cfg.json"
  cat >"$cfg" <<'EOF'
{
  "models": { "default": "opus-4.7" },
  "hitl":   { "modee": "auto" }
}
EOF
  run_with_stderr "\"$VALIDATE_SH\" --config \"$cfg\""
  [ "$status" -eq 1 ]
  assert_contains "$STDERR" "hitl.modee"
  assert_contains "$STDERR" "did you mean"
  assert_contains "$STDERR" "mode"
}
