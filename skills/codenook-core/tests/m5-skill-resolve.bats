#!/usr/bin/env bats
# M5.5 — skill-resolve: 4-tier lookup (plugin_local > plugin_shipped >
# workspace_custom > builtin)

load helpers/load
load helpers/assertions

RESOLVE_SKILL_SH="$CORE_ROOT/skills/builtin/skill-resolve/resolve-skill.sh"

mk_ws() {
  local d; d="$(make_scratch)"
  mkdir -p "$d/.codenook"
  echo "$d"
}

mk_skill_at() {
  local p="$1"
  mkdir -p "$p"
  printf '# %s\n' "$(basename "$p")" > "$p/SKILL.md"
}

@test "m5-skill-resolve: skill exists and is executable" {
  assert_file_exists "$RESOLVE_SKILL_SH"
  assert_file_executable "$RESOLVE_SKILL_SH"
}

@test "m5-skill-resolve: plugin_local (memory) wins over plugin_shipped + workspace + builtin" {
  ws="$(mk_ws)"
  mk_skill_at "$ws/.codenook/memory/development/skills/foo"
  mk_skill_at "$ws/.codenook/plugins/development/skills/foo"
  mk_skill_at "$ws/.codenook/skills/custom/foo"
  run_with_stderr "\"$RESOLVE_SKILL_SH\" --name foo --plugin development --workspace \"$ws\""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.found == true' >/dev/null
  echo "$output" | jq -e '.tier  == "plugin_local"' >/dev/null
  echo "$output" | jq -e '.path  | endswith(".codenook/memory/development/skills/foo/SKILL.md")' >/dev/null
}

@test "m5-skill-resolve: plugin_shipped wins over workspace_custom + builtin" {
  ws="$(mk_ws)"
  mk_skill_at "$ws/.codenook/plugins/development/skills/foo"
  mk_skill_at "$ws/.codenook/skills/custom/foo"
  run_with_stderr "\"$RESOLVE_SKILL_SH\" --name foo --plugin development --workspace \"$ws\""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.tier == "plugin_shipped"' >/dev/null
}

@test "m5-skill-resolve: workspace_custom wins over builtin" {
  ws="$(mk_ws)"
  mk_skill_at "$ws/.codenook/skills/custom/foo"
  run_with_stderr "\"$RESOLVE_SKILL_SH\" --name foo --plugin development --workspace \"$ws\""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.tier == "workspace_custom"' >/dev/null
}

@test "m5-skill-resolve: builtin only (config-resolve) returns builtin path" {
  ws="$(mk_ws)"
  CODENOOK_CORE_DIR="$CORE_ROOT" \
    run_with_stderr "\"$RESOLVE_SKILL_SH\" --name config-resolve --plugin development --workspace \"$ws\""
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.tier == "builtin"' >/dev/null
  echo "$output" | jq -e '.path | endswith("skills/builtin/config-resolve/SKILL.md")' >/dev/null
}

@test "m5-skill-resolve: not found exits 1 with candidates list" {
  ws="$(mk_ws)"
  CODENOOK_CORE_DIR="$CORE_ROOT" \
    run_with_stderr "\"$RESOLVE_SKILL_SH\" --name nonexistent-skill-zzz --plugin development --workspace \"$ws\""
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.found == false' >/dev/null
  echo "$output" | jq -e '.candidates | length == 4' >/dev/null
}

@test "m5-skill-resolve: path traversal in --name rejected" {
  ws="$(mk_ws)"
  run_with_stderr "\"$RESOLVE_SKILL_SH\" --name '../escape' --plugin development --workspace \"$ws\""
  [ "$status" -ne 0 ]
  assert_contains "$STDERR" "invalid"
}
