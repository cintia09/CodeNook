#!/usr/bin/env bats
# Unit 2 — core/shell.md (A-001 / A-007 / A-011 + A-012 hard limit)

load helpers/load
load helpers/assertions

@test "core/shell.md exists" {
  assert_file_exists "$SHELL_MD"
}

@test "core/shell.md size <= 3K (A-012 hard limit)" {
  assert_file_size_le "$SHELL_MD" 3072
}

@test "shell.md contains 'Chat vs Task' triage section" {
  run grep -F "Chat vs Task" "$SHELL_MD"
  [ "$status" -eq 0 ]
}

@test "shell.md contains a 'Dispatch' protocol section" {
  run grep -E "Dispatch|dispatch" "$SHELL_MD"
  [ "$status" -eq 0 ]
}

@test "shell.md states sub-agents run outside main session" {
  # Accept either the literal phrase or a clear synonym.
  run grep -E "(子.?[Aa]gent|sub-?agent).*(不在|fresh|outside|独立)" "$SHELL_MD"
  [ "$status" -eq 0 ]
}

@test "shell.md does NOT name any concrete plugin (A-007: MS plugin-blind)" {
  assert_file_exists "$SHELL_MD"
  run grep -Eiw "development|writing|generic" "$SHELL_MD"
  [ "$status" -ne 0 ]
}

@test "shell.md does NOT name plugin phases (MS does not read phases.yaml)" {
  assert_file_exists "$SHELL_MD"
  run grep -Ew "impl_plan|clarify|accept|design_doc|deliver" "$SHELL_MD"
  [ "$status" -ne 0 ]
}

@test "shell.md mentions ask_user confirmation pattern" {
  run grep -F "ask_user" "$SHELL_MD"
  [ "$status" -eq 0 ]
}
