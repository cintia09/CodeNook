#!/usr/bin/env bats
# M7 generic U4 -- roles/*.md (4 role profiles)

load helpers/load
load helpers/assertions

ROLES_DIR="$CORE_ROOT/../../plugins/generic/roles"
ROLE_NAMES="clarifier analyzer executor deliverer"

@test "all 4 generic role files exist" {
  for r in $ROLE_NAMES; do
    [ -f "$ROLES_DIR/$r.md" ] || { echo "missing $r.md" >&2; return 1; }
  done
}

@test "each generic role file has at least 10 non-blank lines" {
  for r in $ROLE_NAMES; do
    n=$(grep -c '[^[:space:]]' "$ROLES_DIR/$r.md")
    [ "$n" -ge 10 ] || { echo "$r.md only $n non-blank lines" >&2; return 1; }
  done
}

@test "each generic role file has YAML frontmatter naming the role" {
  for r in $ROLE_NAMES; do
    head -10 "$ROLES_DIR/$r.md" | grep -q "^name: $r$" \
      || { echo "$r.md missing 'name: $r'" >&2; return 1; }
  done
}

@test "no generic role references v5 home-dir path" {
  for r in $ROLE_NAMES; do
    if grep -q '~/\.codenook' "$ROLES_DIR/$r.md"; then
      echo "$r.md still references ~/.codenook" >&2
      return 1
    fi
  done
}

@test "no generic role references v5 templates/ path" {
  for r in $ROLE_NAMES; do
    if grep -E "(^|[^./])templates/" "$ROLES_DIR/$r.md" >/dev/null; then
      echo "$r.md still references templates/" >&2
      return 1
    fi
  done
}

@test "every generic role file is reachable from phases.yaml" {
  PHASES="$CORE_ROOT/../../plugins/generic/phases.yaml"
  run python3 - "$PHASES" "$ROLES_DIR" <<'PY'
import sys, yaml, os
phases = yaml.safe_load(open(sys.argv[1]))["phases"]
for p in phases:
    role = p["role"]
    assert os.path.isfile(f"{sys.argv[2]}/{role}.md"), f"missing role: {role}"
print("ok")
PY
  [ "$status" -eq 0 ]
}

@test "generic manifest-templates exist with placeholders" {
  MT="$CORE_ROOT/../../plugins/generic/manifest-templates"
  for f in phase-1-clarifier.md phase-2-analyzer.md phase-3-executor.md phase-4-deliverer.md; do
    [ -f "$MT/$f" ] || { echo "missing $f" >&2; return 1; }
    grep -q '{task_id}'    "$MT/$f" || { echo "$f no {task_id}" >&2; return 1; }
    grep -q '{target_dir}' "$MT/$f" || { echo "$f no {target_dir}" >&2; return 1; }
  done
}
