#!/usr/bin/env bash
# Common test helpers for CodeNook v6 core bats suites.

# Resolve repo paths once.
CORE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TESTS_ROOT="$CORE_ROOT/tests"
FIXTURES_ROOT="$TESTS_ROOT/fixtures"
INIT_SH="$CORE_ROOT/init.sh"
SHELL_MD="$CORE_ROOT/core/shell.md"
RESOLVE_SH="$CORE_ROOT/skills/builtin/config-resolve/resolve.sh"
PROBE_SH="$CORE_ROOT/skills/builtin/model-probe/probe.sh"

export CORE_ROOT TESTS_ROOT FIXTURES_ROOT INIT_SH SHELL_MD RESOLVE_SH PROBE_SH

# Per-test scratch dir (BATS_TEST_TMPDIR is provided by bats-core 1.5+).
make_scratch() {
  local d="${BATS_TEST_TMPDIR:-${BATS_TMPDIR:-/tmp}}/scratch-$$-$RANDOM"
  mkdir -p "$d"
  echo "$d"
}
