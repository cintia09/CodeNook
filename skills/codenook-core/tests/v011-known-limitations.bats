#!/usr/bin/env bats
# v0.11 lock-ins for two M10 known-limitations fixes:
#   - MINOR-04 (M11.4) — `chain_render_residual_slot` diagnostic when a
#                         rendered prompt still contains a `{{SLOT}}` token.
#   - MINOR-06 (M11.4) — `chain_parent_stale` diagnostic at cmd_confirm
#                         when the picked parent transitioned to
#                         done/cancelled between prepare and confirm.

load helpers/load
load helpers/assertions
load helpers/m10_chain

# ---------------------------------------------------------------- MINOR-04

@test "[v0.11] MINOR-04 residual {{SLOT}} after substitution → chain_render_residual_slot diag" {
  ws=$(m10_seed_workspace)
  make_task "$ws" T-PARENT
  make_task "$ws" T-CHILD
  PYTHONPATH="$M10_LIB_DIR" WS="$ws" python3 - <<'PY'
import os, task_chain as tc
tc.set_parent(os.environ["WS"], "T-CHILD", "T-PARENT")
PY

  # Inject a {{TASK_CHAIN}} literal into a slot value path: poison the
  # USER_TURN with a {{ROGUE_SLOT}} marker. Single-pass substitution
  # leaves it intact; the post-render guard should fire the diagnostic.
  run m10_router_render T-CHILD "$ws" --user-turn "hello {{ROGUE_SLOT}} world"
  [ "$status" -eq 0 ] || { echo "stdout=$output"; return 1; }

  # Diagnostic emitted (kind=chain_render_residual_slot, outcome=diagnostic).
  log="$ws/$M10_AUDIT_LOG_REL"
  [ -f "$log" ] || { echo "audit log missing"; return 1; }
  count=$(jq -c 'select(.kind=="chain_render_residual_slot")' "$log" | wc -l | tr -d ' ')
  [ "$count" -ge 1 ] || { echo "expected ≥1 chain_render_residual_slot record, got $count"; cat "$log"; return 1; }
}

@test "[v0.11] MINOR-04 clean prompt → no residual diag emitted" {
  ws=$(m10_seed_workspace)
  make_task "$ws" T-CHILD2

  run m10_router_render T-CHILD2 "$ws" --user-turn "ordinary turn no template token"
  [ "$status" -eq 0 ] || { echo "stdout=$output"; return 1; }

  log="$ws/$M10_AUDIT_LOG_REL"
  if [ -f "$log" ]; then
    count=$(jq -c 'select(.kind=="chain_render_residual_slot")' "$log" | wc -l | tr -d ' ')
    [ "$count" -eq 0 ] || { echo "unexpected residual diag (count=$count)"; cat "$log"; return 1; }
  fi
}

# ---------------------------------------------------------------- MINOR-06

@test "[v0.11] MINOR-06 confirm with stale (done) parent → chain_parent_stale diag, attach proceeds" {
  ws=$(m10_seed_workspace)
  # T-DONE is a perfectly attachable parent that became done after prepare.
  make_task "$ws" T-DONE
  # Mutate status → done (simulating the prepare→confirm window).
  PYTHONPATH="$M10_LIB_DIR" WS="$ws" python3 - <<'PY'
import json, os, pathlib
p = pathlib.Path(os.environ["WS"]) / ".codenook/tasks/T-DONE/state.json"
d = json.loads(p.read_text())
d["status"] = "done"
p.write_text(json.dumps(d, indent=2))
PY

  # Seed prepare so router-context.md exists.
  run m10_router_render T-NEW "$ws" --user-turn "child task"
  [ "$status" -eq 0 ] || { echo "prepare: $output"; return 1; }

  # Write a confirmable draft that picks the stale parent.
  cat >"$ws/.codenook/tasks/T-NEW/draft-config.yaml" <<YAML
_draft: true
plugin: development
input: "child task"
selected_plugins: ["development"]
parent_id: "T-DONE"
YAML

  run m10_router_render T-NEW "$ws" --confirm
  # Attach is permitted (set_parent does not refuse done parents);
  # diag MUST be emitted before the attach.
  [ "$status" -eq 0 ] || { echo "confirm: status=$status output=$output"; return 1; }

  log="$ws/$M10_AUDIT_LOG_REL"
  [ -f "$log" ] || { echo "audit log missing"; return 1; }
  count=$(jq -c 'select(.kind=="chain_parent_stale")' "$log" | wc -l | tr -d ' ')
  [ "$count" -eq 1 ] || {
    echo "expected exactly 1 chain_parent_stale record, got $count"
    cat "$log"
    return 1
  }
  # And the parent attach itself succeeded.
  parent_now=$(jq -r '.parent_id' "$ws/.codenook/tasks/T-NEW/state.json")
  [ "$parent_now" = "T-DONE" ] || { echo "attach didn't happen: parent_id=$parent_now"; return 1; }
}

@test "[v0.11] MINOR-06 confirm with active parent → no stale diag" {
  ws=$(m10_seed_workspace)
  make_task "$ws" T-ACTIVE   # status=in_progress per make_task default

  run m10_router_render T-NEW2 "$ws" --user-turn "child task two"
  [ "$status" -eq 0 ] || { echo "prepare: $output"; return 1; }

  cat >"$ws/.codenook/tasks/T-NEW2/draft-config.yaml" <<YAML
_draft: true
plugin: development
input: "child task two"
selected_plugins: ["development"]
parent_id: "T-ACTIVE"
YAML

  run m10_router_render T-NEW2 "$ws" --confirm
  [ "$status" -eq 0 ] || { echo "confirm: $output"; return 1; }

  log="$ws/$M10_AUDIT_LOG_REL"
  if [ -f "$log" ]; then
    count=$(jq -c 'select(.kind=="chain_parent_stale")' "$log" | wc -l | tr -d ' ')
    [ "$count" -eq 0 ] || { echo "unexpected stale diag (count=$count)"; cat "$log"; return 1; }
  fi
}
