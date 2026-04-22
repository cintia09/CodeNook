#!/usr/bin/env bash
# Common test helpers for CodeNook v6 core bats suites.

# Resolve repo paths once.
CORE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_ROOT="$(cd "$CORE_ROOT/../.." && pwd)"
TESTS_ROOT="$CORE_ROOT/tests"
FIXTURES_ROOT="$TESTS_ROOT/fixtures"
INIT_SH="$CORE_ROOT/init.sh"
SHELL_MD="$CORE_ROOT/core/shell.md"
RESOLVE_SH="$CORE_ROOT/skills/builtin/config-resolve/resolve.sh"
PROBE_SH="$CORE_ROOT/skills/builtin/model-probe/probe.sh"

# Compat shim: legacy bats invoke `bash "$INSTALL_SH" --plugin <id> <ws>`,
# but the kernel installer is now `python3 install.py`. Tests that still
# point INSTALL_SH at a sh file should call codenook_install instead, or
# rely on this wrapper which re-uses the same legacy CLI shape.
codenook_install() {
  # codenook_install <workspace> [--plugin <id>] [extra-flags ...]
  local ws="$1"; shift
  python3 "$REPO_ROOT/install.py" --target "$ws" --upgrade --yes "$@"
}

export CORE_ROOT REPO_ROOT TESTS_ROOT FIXTURES_ROOT INIT_SH SHELL_MD \
       RESOLVE_SH PROBE_SH
export -f codenook_install

# Per-test scratch dir (BATS_TEST_TMPDIR is provided by bats-core 1.5+).
make_scratch() {
  local d="${BATS_TEST_TMPDIR:-${BATS_TMPDIR:-/tmp}}/scratch-$$-$RANDOM"
  mkdir -p "$d"
  echo "$d"
}

# run_with_stderr <full shell command string>
# Runs the command via bash -c so callers can quote args freely; routes
# stderr to a scratch file so $output stays JSON-clean. Exposes $STDERR
# (and $status / $output) to the calling test.
run_with_stderr() {
  STDERR_FILE="${BATS_TEST_TMPDIR:-/tmp}/cn-stderr.$$"
  run bash -c "$* 2>\"$STDERR_FILE\""
  STDERR="$(cat "$STDERR_FILE" 2>/dev/null || echo)"
  export STDERR
}
