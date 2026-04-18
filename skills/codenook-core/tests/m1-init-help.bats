#!/usr/bin/env bats
# Unit 1 — init.sh skeleton & --help (E-001 / E-002)

load helpers/load
load helpers/assertions

@test "init.sh file exists and is executable" {
  assert_file_exists "$INIT_SH"
  assert_file_executable "$INIT_SH"
}

@test "init.sh --help exits 0 and mentions CodeNook v6" {
  run "$INIT_SH" --help
  [ "$status" -eq 0 ]
  assert_contains "$output" "CodeNook v6"
}

@test "init.sh --help lists all M1 subcommands" {
  run "$INIT_SH" --help
  [ "$status" -eq 0 ]
  for sub in --install-plugin --scaffold-plugin --pack-plugin \
             --uninstall-plugin --upgrade-core --refresh-models --version; do
    assert_contains "$output" "$sub"
  done
}

@test "init.sh --version exits 0 and prints VERSION file content" {
  local v
  v="$(cat "$CORE_ROOT/VERSION")"
  run "$INIT_SH" --version
  [ "$status" -eq 0 ]
  assert_contains "$output" "$v"
}

@test "init.sh with unknown subcommand exits non-zero and stderr says 'unknown'" {
  run "$INIT_SH" --no-such-flag
  [ "$status" -ne 0 ]
  # bats merges stderr into $output by default; ensure 'unknown' surfaces.
  assert_contains "$output" "unknown"
}

@test "init.sh with no args exits 0 and prints help (friendly fallback)" {
  run "$INIT_SH"
  [ "$status" -eq 0 ]
  assert_contains "$output" "Usage"
  assert_contains "$output" "CodeNook v6"
}

@test "init.sh -h is alias for --help" {
  run "$INIT_SH" -h
  [ "$status" -eq 0 ]
  assert_contains "$output" "CodeNook v6"
}

@test "init.sh subcommand stubs exit 2 with TODO marker" {
  # M1 declares stubs only; non-version/help subcommands must signal not-implemented.
  # M5 wired --refresh-models — removed from the stub list.
  for sub in --install-plugin --scaffold-plugin --pack-plugin \
             --uninstall-plugin --upgrade-core; do
    run "$INIT_SH" "$sub"
    [ "$status" -eq 2 ] || { echo "expected exit 2 for $sub, got $status" >&2; return 1; }
    assert_contains "$output" "TODO"
  done
}
