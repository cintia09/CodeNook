#!/usr/bin/env bats
# M10.6 review-r1 lock-in tests (defense layer).
# TC-M10.6-06: cycle → both chain_root=null + walk_ancestors emits
#              chain_walk_truncated (no CycleError leak).
# TC-M10.6-07: self-parent → chain_root=null.
# TC-M10.6-08: _diag(chain_root_stale) writes exactly 1 jsonl line
#              and that line carries the `kind` field.

load helpers/load
load helpers/assertions
load helpers/m10_chain

# ---------------------------------------------------------------- TC-M10.6-06

@test "[m10.6] TC-M10.6-06 cycle → chain_root=null + chain_walk_truncated" {
  ws=$(m10_seed_workspace)
  make_task "$ws" T-A
  make_task "$ws" T-B

  # Hand-craft a real cycle (set_parent's pre-check forbids this path).
  WS="$ws" python3 - <<'PY'
import json, os, pathlib
ws = pathlib.Path(os.environ["WS"])
for tid, pid in (("T-A", "T-B"), ("T-B", "T-A")):
    p = ws / ".codenook" / "tasks" / tid / "state.json"
    state = json.loads(p.read_text())
    state["parent_id"] = pid
    p.write_text(json.dumps(state))
PY

  # Build snapshot — both members must resolve to chain_root=null.
  PYTHONPATH="$M10_LIB_DIR" WS="$ws" python3 -c \
    'import os, task_chain as tc; tc._build_snapshot(os.environ["WS"])' >/dev/null

  snap="$ws/.codenook/tasks/.chain-snapshot.json"
  ra=$(jq -r '.entries["T-A"].chain_root' "$snap")
  rb=$(jq -r '.entries["T-B"].chain_root' "$snap")
  [ "$ra" = "null" ] || { echo "T-A chain_root=$ra (expected null)"; cat "$snap"; return 1; }
  [ "$rb" = "null" ] || { echo "T-B chain_root=$rb (expected null)"; cat "$snap"; return 1; }

  # Truncate the audit log so we only count emissions from the walk.
  log="$ws/$M10_AUDIT_LOG_REL"
  mkdir -p "$(dirname "$log")"
  : >"$log"

  # walk_ancestors must NOT raise on cycle; it must emit chain_walk_truncated.
  PYTHONPATH="$M10_LIB_DIR" WS="$ws" python3 - <<'PY'
import os, task_chain as tc
chain = tc.walk_ancestors(os.environ["WS"], "T-A")
# Must terminate; size bounded by cycle members.
assert isinstance(chain, list) and 1 <= len(chain) <= 2, chain
PY

  n=$(jq -c 'select(.outcome=="chain_walk_truncated")' "$log" | wc -l | tr -d ' ')
  [ "$n" -ge 1 ] || { echo "expected chain_walk_truncated; got $n"; cat "$log"; return 1; }
  reason=$(jq -r 'select(.outcome=="chain_walk_truncated") | .reason' "$log" | head -n1)
  case "$reason" in
    *cycle*) ;;
    *) echo "expected reason mentioning 'cycle', got: $reason"; return 1 ;;
  esac
}

# ---------------------------------------------------------------- TC-M10.6-07

@test "[m10.6] TC-M10.6-07 self-parent → chain_root=null" {
  ws=$(m10_seed_workspace)
  make_task "$ws" T-S

  # Hand-craft self-parent (set_parent's pre-check forbids this).
  WS="$ws" python3 - <<'PY'
import json, os, pathlib
p = pathlib.Path(os.environ["WS"]) / ".codenook" / "tasks" / "T-S" / "state.json"
state = json.loads(p.read_text())
state["parent_id"] = "T-S"
p.write_text(json.dumps(state))
PY

  PYTHONPATH="$M10_LIB_DIR" WS="$ws" python3 -c \
    'import os, task_chain as tc; tc._build_snapshot(os.environ["WS"])' >/dev/null

  snap="$ws/.codenook/tasks/.chain-snapshot.json"
  rt=$(jq -r '.entries["T-S"].chain_root' "$snap")
  [ "$rt" = "null" ] || { echo "T-S chain_root=$rt (expected null)"; cat "$snap"; return 1; }

  pid=$(jq -r '.entries["T-S"].parent_id' "$snap")
  [ "$pid" = "T-S" ] || { echo "T-S parent_id=$pid (expected T-S)"; return 1; }
}

# ---------------------------------------------------------------- TC-M10.6-08

@test "[m10.6] TC-M10.6-08 _diag(chain_root_stale) writes exactly 1 line with kind field" {
  ws=$(m10_seed_workspace)
  make_chain "$ws" T-R T-C   # T-C.parent = T-R; snapshot built by set_parent.

  log="$ws/$M10_AUDIT_LOG_REL"
  mkdir -p "$(dirname "$log")"
  : >"$log"

  # Force a stale snapshot entry: bump T-C's state.json mtime so it
  # diverges from snapshot.entries["T-C"].state_mtime, then walk —
  # walk_ancestors emits exactly one chain_root_stale diagnostic.
  WS="$ws" python3 - <<'PY'
import os, time, pathlib
p = pathlib.Path(os.environ["WS"]) / ".codenook" / "tasks" / "T-C" / "state.json"
# Skew mtime ~5s into the future to guarantee a different ISO second.
future = time.time() + 5
os.utime(p, (future, future))
PY

  PYTHONPATH="$M10_LIB_DIR" WS="$ws" python3 -c \
    'import os, task_chain as tc; tc.walk_ancestors(os.environ["WS"], "T-C")' >/dev/null

  # Exactly one diagnostic with kind=chain_root_stale, with `kind` present.
  diag_lines=$(jq -c 'select(.outcome=="diagnostic")' "$log")
  total=$(echo "$diag_lines" | grep -c . || true)
  [ "$total" -eq 1 ] || { echo "expected 1 diagnostic line, got $total"; cat "$log"; return 1; }

  kind=$(echo "$diag_lines" | jq -r '.kind')
  [ "$kind" = "chain_root_stale" ] || { echo "expected kind=chain_root_stale, got $kind"; return 1; }

  # No diagnostic line missing the `kind` field (the dedup bug we fixed).
  bad=$(jq -c 'select(.outcome=="diagnostic" and (has("kind") | not))' "$log" | wc -l | tr -d ' ')
  [ "$bad" -eq 0 ] || { echo "found $bad kindless diagnostic line(s)"; cat "$log"; return 1; }

  # The diagnostic still carries the canonical 8 keys + kind.
  has8=$(echo "$diag_lines" | jq -r '
    [has("asset_type"), has("candidate_hash"), has("existing_path"),
     has("outcome"), has("reason"), has("source_task"),
     has("timestamp"), has("verdict"), has("kind")] | all')
  [ "$has8" = "true" ] || { echo "diagnostic missing canonical keys"; echo "$diag_lines"; return 1; }
  asset=$(echo "$diag_lines" | jq -r '.asset_type')
  [ "$asset" = "chain" ] || { echo "expected asset_type=chain, got $asset"; return 1; }
}
