#!/usr/bin/env bats
# M7 generic U10 -- 4-phase E2E loop with mocked role outputs (mirrors
# m6-development-e2e.bats but for the 4-phase generic fallback).

load helpers/load
load helpers/assertions

PLUGIN_SRC="$CORE_ROOT/../../plugins/generic"
INSTALL_SH="$CORE_ROOT/skills/builtin/install-orchestrator/orchestrator.sh"
TICK_SH="$CORE_ROOT/skills/builtin/orchestrator-tick/tick.sh"

setup_ws_with_plugin() {
  local ws; ws="$(make_scratch)"
  mkdir -p "$ws/.codenook"
  local dist; dist="$(make_scratch)/dist"
  mkdir -p "$dist"
  ( cd "$PLUGIN_SRC/.." && tar -czf "$dist/generic.tar.gz" generic )
  "$INSTALL_SH" --src "$dist/generic.tar.gz" --workspace "$ws" --json >/dev/null
  echo "$ws"
}

create_task() {
  local ws="$1" tid="$2"
  local d="$ws/.codenook/tasks/$tid"
  mkdir -p "$d/outputs" "$d/prompts"
  cat >"$d/state.json" <<EOF
{
  "schema_version": 1,
  "task_id": "$tid",
  "title": "M7 generic DoD task",
  "plugin": "generic",
  "phase": null,
  "iteration": 0,
  "max_iterations": 3,
  "dual_mode": "serial",
  "target_dir": "$ws/work",
  "status": "in_progress",
  "config_overrides": {},
  "history": []
}
EOF
  mkdir -p "$ws/work"
  cat >"$ws/.codenook/state.json" <<EOF
{"active_tasks":["$tid"],"current_focus":"$tid"}
EOF
}

write_role_output() {
  local ws="$1" tid="$2" expected="$3"
  local out="$ws/.codenook/tasks/$tid/$expected"
  mkdir -p "$(dirname "$out")"
  cat >"$out" <<'EOF'
---
verdict: ok
summary: mock verdict
---
mocked role body
EOF
}

@test "M7 generic DoD: 4-phase loop drives task to done within 50 ticks" {
  ws="$(setup_ws_with_plugin)"
  create_task "$ws" "T-G01"

  local i=0 status_code finished=0
  for i in $(seq 1 50); do
    out=$("$TICK_SH" --task T-G01 --workspace "$ws" --json)
    status_code=$?
    [ "$status_code" -eq 0 ] || { echo "tick failed (i=$i): $out" >&2; return 1; }

    tick_status=$(echo "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin)["status"])')

    if [ "$tick_status" = "done" ]; then
      finished=1
      break
    fi
    if [ "$tick_status" = "blocked" ] || [ "$tick_status" = "error" ]; then
      echo "$tick_status at i=$i: $out" >&2
      return 1
    fi

    expected=$(jq -r '.in_flight_agent.expected_output // empty' \
               "$ws/.codenook/tasks/T-G01/state.json")
    if [ -n "$expected" ]; then
      out_file="$ws/.codenook/tasks/T-G01/$expected"
      if [ ! -f "$out_file" ]; then
        write_role_output "$ws" "T-G01" "$expected"
      fi
    fi
  done

  [ "$finished" = "1" ] || {
    echo "did not finish within 50 ticks" >&2
    cat "$ws/.codenook/tasks/T-G01/state.json" >&2
    return 1
  }

  jq -e '.status == "done"' "$ws/.codenook/tasks/T-G01/state.json" >/dev/null

  python3 - "$ws/.codenook/tasks/T-G01/state.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
phases_seen = {h["phase"] for h in state["history"] if h.get("verdict") == "ok"}
expected = {"clarify","analyze","execute","deliver"}
missing = expected - phases_seen
assert not missing, f"phases never observed verdict=ok: {missing}"
print("ok")
PY
}
