#!/usr/bin/env bats
# E2E-P-005 — implement phase with missing target_dir → entry-question
# (status=blocked, exit 2). Wrapper now defaults --target-dir to src/, so
# we explicitly clear target_dir in state.json before ticking implement.

load helpers/load
load helpers/assertions


setup() {
  ws="$(make_scratch)"
  codenook_install "$ws" --plugin development >/dev/null 2>&1
}

@test "[v0.11.4 E2E-P-005] tick into implement w/o target_dir → exit 2 + missing field" {
  tid="$("$ws/.codenook/bin/codenook" task new --title "X" --dual-mode serial)"
  # Set state directly to "ready to dispatch implement, target_dir
  # cleared". Tick should attempt implement → block with missing
  # target_dir, status=blocked, exit 2.
  #
  # NOTE: this test used to set phase=plan with the planner's
  # verdict already on disk and let tick advance through
  # plan → implement, but the plan phase later acquired a
  # `plan_signoff` HITL gate, so verdict-driven advancement now
  # pauses for HITL first. We bypass that by pre-pinning the
  # implement phase directly — what we're testing is the implement
  # entry-question, not the plan→implement transition.
  python3 - <<PY
import json
sf = "$ws/.codenook/tasks/$tid/state.json"
d = json.load(open(sf))
d["phase"] = "implement"
d["max_iterations"] = 3
d["target_dir"] = ""  # clear default src/
d["status"] = "in_progress"
d["history"] = []
d["in_flight_agent"] = None
json.dump(d, open(sf,"w"), indent=2)
PY
  set +e
  out=$("$ws/.codenook/bin/codenook" tick --task "$tid" --json)
  rc=$?
  set -e
  [ "$rc" -eq 2 ] || { echo "rc=$rc out=$out"; return 1; }
  echo "$out" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
assert d['status']=='blocked', d
assert 'target_dir' in d.get('missing',[]), d
"
  # state.phase should now be pinned to 'implement' with status=blocked
  python3 -c "
import json
d=json.load(open('$ws/.codenook/tasks/$tid/state.json'))
assert d['phase']=='implement', d
assert d['status']=='blocked', d
"
}

@test "[v0.11.4 E2E-P-005] task new defaults target_dir to src/" {
  tid="$("$ws/.codenook/bin/codenook" task new --title "Y" --dual-mode serial)"
  td="$(python3 -c "import json; print(json.load(open('$ws/.codenook/tasks/$tid/state.json')).get('target_dir'))")"
  [ "$td" = "src/" ] || { echo "got=$td"; return 1; }
}
