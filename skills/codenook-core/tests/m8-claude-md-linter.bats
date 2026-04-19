#!/usr/bin/env bats
# M8.6 - claude_md_linter.py: domain-agnostic linter for CLAUDE.md.
# Verifies the linter behaviour around forbidden tokens, allowed
# contexts (forbidden code fences, <!-- linter:allow --> comments,
# the "Hard rules (forbidden)" section), aggregation, and CLI exit.

load helpers/load
load helpers/assertions

LINTER="$CORE_ROOT/skills/builtin/_lib/claude_md_linter.py"

mk_md() {
  local p="$1"; shift
  printf '%s\n' "$@" > "$p"
}

@test "M8.6 linter is executable" {
  assert_file_executable "$LINTER"
}

@test "M8.6 clean CLAUDE.md (no domain tokens) -> 0 errors" {
  ws="$(make_scratch)"
  f="$ws/CLAUDE.md"
  mk_md "$f" \
    "# CodeNook" \
    "" \
    "## Section A" \
    "" \
    "Main session is a pure protocol conductor. It only relays" \
    "router replies verbatim and drives an opaque tick loop." \
    "" \
    '```bash' \
    'spawn.sh --task-id T-001 --workspace ./proj' \
    '```'
  run python3 "$LINTER" "$f"
  [ "$status" -eq 0 ] || { echo "$output"; echo "STDERR>>>"; cat "$ws/.stderr" 2>/dev/null; return 1; }
}

@test "M8.6 bare role mention in normative paragraph -> error with line + token" {
  ws="$(make_scratch)"
  f="$ws/CLAUDE.md"
  mk_md "$f" \
    "# CodeNook" \
    "" \
    "## Protocol" \
    "" \
    "The main session may invoke the clarifier directly when it sees fit."
  run_with_stderr "python3 '$LINTER' '$f'"
  [ "$status" -eq 1 ] || { echo "stdout: $output"; echo "stderr: $STDERR"; return 1; }
  assert_contains "$STDERR" "clarifier"
  assert_contains "$STDERR" ":5:"
  assert_contains "$STDERR" "ERROR"
}

@test "M8.6 token inside forbidden fenced block -> no error" {
  ws="$(make_scratch)"
  f="$ws/CLAUDE.md"
  mk_md "$f" \
    "# CodeNook" \
    "" \
    "## Protocol" \
    "" \
    "Anti-pattern (do NOT do this):" \
    '```forbidden' \
    "Inspect plugins/development/plugin.yaml and pick the implementer role." \
    '```'
  run python3 "$LINTER" "$f"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "M8.6 token after '<!-- linter:allow -->' line -> no error" {
  ws="$(make_scratch)"
  f="$ws/CLAUDE.md"
  mk_md "$f" \
    "# CodeNook" \
    "" \
    "## Notes" \
    "" \
    "<!-- linter:allow -->" \
    "Historically we used the term clarifier here, but no longer."
  run python3 "$LINTER" "$f"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "M8.6 token inside 'Hard rules (forbidden)' section -> no error" {
  ws="$(make_scratch)"
  f="$ws/CLAUDE.md"
  mk_md "$f" \
    "# CodeNook" \
    "" \
    "## Hard rules (forbidden)" \
    "" \
    "Main session MUST NOT spawn phase agents (clarifier, designer, etc.)" \
    "Main session MUST NOT read plugins/development or plugins/writing." \
    "Main session MUST NOT inspect applies_to or domain_description." \
    "" \
    "## Next section" \
    "" \
    "Just normal prose without forbidden tokens."
  run python3 "$LINTER" "$f"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "M8.6 hard-rules section ends at next ## heading" {
  ws="$(make_scratch)"
  f="$ws/CLAUDE.md"
  mk_md "$f" \
    "# CodeNook" \
    "" \
    "## Hard rules (forbidden)" \
    "" \
    "MUST NOT spawn clarifier directly." \
    "" \
    "## Other section" \
    "" \
    "And here we mention the implementer outside hard rules - this is bad."
  run_with_stderr "python3 '$LINTER' '$f'"
  [ "$status" -eq 1 ] || { echo "$output"; echo "$STDERR"; return 1; }
  assert_contains "$STDERR" "implementer"
  assert_contains "$STDERR" ":9:"
}

@test "M8.6 multiple tokens / multiple files aggregated correctly" {
  ws="$(make_scratch)"
  f1="$ws/A.md"
  f2="$ws/B.md"
  mk_md "$f1" \
    "# A" \
    "" \
    "## Body" \
    "" \
    "The clarifier runs first, then the designer."
  mk_md "$f2" \
    "# B" \
    "" \
    "## Body" \
    "" \
    "Inspect plugins/development to find the implementer."
  run_with_stderr "python3 '$LINTER' '$f1' '$f2'"
  [ "$status" -eq 1 ] || { echo "$output"; echo "$STDERR"; return 1; }
  assert_contains "$STDERR" "clarifier"
  assert_contains "$STDERR" "designer"
  assert_contains "$STDERR" "plugins/development"
  assert_contains "$STDERR" "implementer"
  assert_contains "$STDERR" "scanned 2 file(s)"
}

@test "M8.6 CLI exit 0 on clean, exit 1 on errors" {
  ws="$(make_scratch)"
  clean="$ws/clean.md"
  dirty="$ws/dirty.md"
  mk_md "$clean" "# clean" "" "Pure protocol conductor."
  mk_md "$dirty" "# dirty" "" "## body" "" "Spawn the implementer."
  run python3 "$LINTER" "$clean"
  [ "$status" -eq 0 ]
  run python3 "$LINTER" "$dirty"
  [ "$status" -eq 1 ]
}

@test "M8.6 missing file exits 2" {
  run python3 "$LINTER" "/nonexistent/path/CLAUDE.md.zzz"
  [ "$status" -eq 2 ]
}

@test "M8.6 help flag exits 0" {
  run python3 "$LINTER" --help
  [ "$status" -eq 0 ]
}
