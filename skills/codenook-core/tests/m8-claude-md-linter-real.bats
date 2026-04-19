#!/usr/bin/env bats
# M8.6 - real CLAUDE.md must pass the domain-agnostic linter.
# This guards the v6 layering principle going forward: any future
# edit that injects domain-aware tokens into the conductor's
# protocol doc will fail the suite.

load helpers/load
load helpers/assertions

LINTER="$CORE_ROOT/skills/builtin/_lib/claude_md_linter.py"
REPO_ROOT="$(cd "$CORE_ROOT/../.." && pwd)"
ROOT_CLAUDE_MD="$REPO_ROOT/CLAUDE.md"

@test "M8.6 root CLAUDE.md passes claude_md_linter (no domain tokens)" {
  assert_file_exists "$ROOT_CLAUDE_MD"
  run python3 "$LINTER" "$ROOT_CLAUDE_MD"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}
