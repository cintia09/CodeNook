#!/usr/bin/env bats
# M7 generic U9 -- pack tarball + install via M2 12-gate pipeline +
# verify .codenook/plugins/generic/ + idempotency.

load helpers/load
load helpers/assertions

PLUGIN_SRC="$CORE_ROOT/../../plugins/generic"
INSTALL_SH="$CORE_ROOT/skills/builtin/install-orchestrator/orchestrator.sh"

mk_workspace() {
  local ws; ws="$(make_scratch)"
  mkdir -p "$ws/.codenook"
  echo "$ws"
}

mk_tarball() {
  local out_dir="$1"
  local tgz="$out_dir/generic-0.1.0.tar.gz"
  ( cd "$PLUGIN_SRC/.." && tar -czf "$tgz" generic )
  echo "$tgz"
}

@test "generic tarball builds and installs via M2 pipeline" {
  ws="$(mk_workspace)"
  dist="$(make_scratch)/dist"
  mkdir -p "$dist"
  tgz="$(mk_tarball "$dist")"
  [ -f "$tgz" ]
  run_with_stderr "\"$INSTALL_SH\" --src \"$tgz\" --workspace \"$ws\" --json"
  if [ "$status" -ne 0 ]; then
    echo "STDERR: $STDERR" >&2
    echo "STDOUT: $output" >&2
    return 1
  fi
  echo "$output" | grep -q '"ok": *true'
  echo "$output" | grep -q '"plugin_id": *"generic"'
}

@test "installed generic tree contains expected yaml + 4 role + 4 manifest files" {
  ws="$(mk_workspace)"
  dist="$(make_scratch)/dist2"
  mkdir -p "$dist"
  tgz="$(mk_tarball "$dist")"
  run_with_stderr "\"$INSTALL_SH\" --src \"$tgz\" --workspace \"$ws\" --json"
  [ "$status" -eq 0 ]
  for f in plugin.yaml config-defaults.yaml config-schema.yaml \
           phases.yaml transitions.yaml entry-questions.yaml \
           hitl-gates.yaml README.md CHANGELOG.md; do
    [ -f "$ws/.codenook/plugins/generic/$f" ] \
      || { echo "missing $f" >&2; return 1; }
  done
  for r in clarifier analyzer executor deliverer; do
    [ -f "$ws/.codenook/plugins/generic/roles/$r.md" ] \
      || { echo "missing roles/$r.md" >&2; return 1; }
  done
  count=$(ls "$ws/.codenook/plugins/generic/manifest-templates"/phase-*.md | wc -l | tr -d ' ')
  [ "$count" -eq 4 ]
  [ -x "$ws/.codenook/plugins/generic/validators/post-execute.sh" ]
}

@test "all gate_results ok for generic install" {
  ws="$(mk_workspace)"
  dist="$(make_scratch)/dist3"
  mkdir -p "$dist"
  tgz="$(mk_tarball "$dist")"
  run_with_stderr "\"$INSTALL_SH\" --src \"$tgz\" --workspace \"$ws\" --json"
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
gates = d["gate_results"]
for g in gates:
    assert g["ok"], (g["gate"], g.get("reasons"))
assert len(gates) >= 9, len(gates)
print("ok")
' >&2
}

@test "re-install generic without --upgrade -> already_installed (exit 3)" {
  ws="$(mk_workspace)"
  dist="$(make_scratch)/dist4"
  mkdir -p "$dist"
  tgz="$(mk_tarball "$dist")"
  run_with_stderr "\"$INSTALL_SH\" --src \"$tgz\" --workspace \"$ws\" --json"
  [ "$status" -eq 0 ]
  run_with_stderr "\"$INSTALL_SH\" --src \"$tgz\" --workspace \"$ws\" --json"
  [ "$status" -eq 3 ]
  count=$(jq '[.installed_plugins[] | select(.id=="generic")] | length' \
          "$ws/.codenook/state.json")
  [ "$count" = "1" ]
}
