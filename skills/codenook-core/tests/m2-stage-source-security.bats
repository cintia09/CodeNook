#!/usr/bin/env bats
# M2 — install-orchestrator stage_source security:
# tar linkname / member kind validation (Bug #2).

load helpers/load
load helpers/assertions

INSTALL_SH="$CORE_ROOT/install.sh"

mk_ws() {
  local d; d="$(make_scratch)/ws"; mkdir -p "$d/.codenook"; echo "$d"
}

mk_min_plugin_dir() {
  local d="$1"
  mkdir -p "$d/skills/x"
  cat >"$d/plugin.yaml" <<'YAML'
id: foo-plugin
version: 0.2.0
type: domain
entry_points:
  install: skills/x/run.sh
declared_subsystems:
  - skills/foo-runner
requires:
  core_version: '>=0.2.0-m2'
YAML
  cat >"$d/skills/x/run.sh" <<'SH'
#!/usr/bin/env bash
echo hi
SH
  chmod +x "$d/skills/x/run.sh"
}

# Build a tarball whose archive root is "good-minimal/" and inject an extra
# member crafted by the python helper.
mk_tarball_with_extra_member() {
  local out="$1" extra_python="$2"
  local tmp; tmp="$(make_scratch)/build"; mkdir -p "$tmp/good-minimal"
  mk_min_plugin_dir "$tmp/good-minimal"
  python3 - "$out" "$tmp" <<PY
import sys, tarfile, io, os, time
out, tmp = sys.argv[1], sys.argv[2]
with tarfile.open(out, "w:gz") as tf:
    tf.add(os.path.join(tmp, "good-minimal"), arcname="good-minimal")
${extra_python}
PY
}

@test "stage_source: hardlink with .. linkname → exit 2 (unsafe)" {
  out="$(make_scratch)/p.tar.gz"
  mk_tarball_with_extra_member "$out" "$(cat <<'PY'
    ti = tarfile.TarInfo(name="good-minimal/evil")
    ti.type = tarfile.LNKTYPE
    ti.linkname = "../../etc/hosts"
    tf.addfile(ti)
PY
)"
  ws="$(mk_ws)"
  run_with_stderr "\"$INSTALL_SH\" --src \"$out\" --workspace \"$ws\""
  [ "$status" -eq 2 ]
  assert_contains "$STDERR" "linkname"
}

@test "stage_source: symlink with absolute linkname → exit 2 (unsafe)" {
  out="$(make_scratch)/p.tar.gz"
  mk_tarball_with_extra_member "$out" "$(cat <<'PY'
    ti = tarfile.TarInfo(name="good-minimal/evil-sym")
    ti.type = tarfile.SYMTYPE
    ti.linkname = "/etc/passwd"
    tf.addfile(ti)
PY
)"
  ws="$(mk_ws)"
  run_with_stderr "\"$INSTALL_SH\" --src \"$out\" --workspace \"$ws\""
  [ "$status" -eq 2 ]
  assert_contains "$STDERR" "linkname"
}

@test "stage_source: FIFO member → exit 2 (unsafe kind)" {
  out="$(make_scratch)/p.tar.gz"
  mk_tarball_with_extra_member "$out" "$(cat <<'PY'
    ti = tarfile.TarInfo(name="good-minimal/some-fifo")
    ti.type = tarfile.FIFOTYPE
    tf.addfile(ti)
PY
)"
  ws="$(mk_ws)"
  run_with_stderr "\"$INSTALL_SH\" --src \"$out\" --workspace \"$ws\""
  [ "$status" -eq 2 ]
  assert_contains "$STDERR" "kind"
}

@test "stage_source: relative in-tree symlink linkname → accepted by stage" {
  # An in-tree relative symlink is safe at extraction time. G11
  # (path-normalize) is responsible for rejecting symlinks later;
  # this test only asserts that stage_source itself does not refuse.
  out="$(make_scratch)/p.tar.gz"
  mk_tarball_with_extra_member "$out" "$(cat <<'PY'
    ti = tarfile.TarInfo(name="good-minimal/inner-link")
    ti.type = tarfile.SYMTYPE
    ti.linkname = "./plugin.yaml"
    tf.addfile(ti)
PY
)"
  ws="$(mk_ws)"
  run_with_stderr "\"$INSTALL_SH\" --src \"$out\" --workspace \"$ws\""
  # G11 will fail; what we care about is that exit != 2 (stage didn't refuse).
  [ "$status" -ne 2 ]
}
