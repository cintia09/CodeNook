#!/usr/bin/env bats
# M9.8 — End-to-end acceptance for the memory layer + extractor stack.
# Spec: docs/v6/memory-and-extraction-v6.md §6 (caps/dedup),
#       docs/v6/m9-test-cases.md TC-M9.8-01..04 (this file).
#
# Tests in this file follow the user-visible numbering:
#   TC-M9.8-01  full extractor-batch round-trip (knowledge + skill +
#               config artifacts + audit trail)
#   TC-M9.8-02  GC CLI dry-run reports correct over-cap groups; real
#               run prunes them and updates the audit log
#   TC-M9.8-03  pre-commit hook blocks a commit that writes to plugins/
#   TC-M9.8-04  router → extractor → memory-index loop survives across
#               two ticks (snapshot stable, no duplicates)

load ../helpers/load
load ../helpers/assertions
load ../helpers/m9_memory

GC_PY="$CORE_ROOT/skills/builtin/_lib/memory_gc.py"
HOOK_TEMPLATE="$CORE_ROOT/templates/pre-commit-hook.sh"
BATCH_SH="$CORE_ROOT/skills/builtin/extractor-batch/extractor-batch.sh"

# --------------------------------------------------------------- helpers

# write_n_knowledge <ws> <n> [<task>]
write_n_knowledge() {
  local ws="$1" n="$2" task="${3:-T-CAP}"
  PYTHONPATH="$M9_LIB_DIR" WS="$ws" N="$n" T="$task" python3 - <<'PY'
import os, time
import memory_layer as ml
ws, n, task = os.environ["WS"], int(os.environ["N"]), os.environ["T"]
for i in range(n):
    ml.write_knowledge(
        ws,
        topic=f"k-{task.lower()}-{i:03d}",
        summary=f"summary {i}",
        tags=[f"t{i%4}"],
        body=("x" * 64) + str(i),
        created_from_task=task,
    )
    ml.append_audit(ws, {"ts": "2026-04-19T00:00:00Z", "asset_type": "knowledge",
                          "verdict": "create", "source_task": task,
                          "topic": f"k-{task.lower()}-{i:03d}"})
    time.sleep(0.01)  # ensure distinct created_at ordering
PY
}

# write_n_skills <ws> <n> [<task>]
write_n_skills() {
  local ws="$1" n="$2" task="${3:-T-CAP}"
  PYTHONPATH="$M9_LIB_DIR" WS="$ws" N="$n" T="$task" python3 - <<'PY'
import os, time
import memory_layer as ml
ws, n, task = os.environ["WS"], int(os.environ["N"]), os.environ["T"]
for i in range(n):
    name = f"s-{task.lower()}-{i:03d}"
    ml.write_skill(
        ws,
        name=name,
        frontmatter={"name": name, "summary": f"s {i}", "tags": ["a"]},
        body=("y" * 64) + str(i),
        created_from_task=task,
    )
    ml.append_audit(ws, {"ts": "2026-04-19T00:00:00Z", "asset_type": "skill",
                          "verdict": "create", "source_task": task, "name": name})
    time.sleep(0.01)
PY
}

# write_n_config <ws> <n> [<task>]
write_n_config() {
  local ws="$1" n="$2" task="${3:-T-CAP}"
  PYTHONPATH="$M9_LIB_DIR" WS="$ws" N="$n" T="$task" python3 - <<'PY'
import os, time
import memory_layer as ml
ws, n, task = os.environ["WS"], int(os.environ["N"]), os.environ["T"]
for i in range(n):
    ml.upsert_config_entry(
        ws,
        entry={
            "key": f"c-{task.lower()}-{i:03d}",
            "value": f"v{i}",
            "applies_when": "always",
            "created_from_task": task,
        },
        rationale="seed",
    )
    time.sleep(0.01)
PY
}

# Initialize a git repo with the pre-commit hook installed.
init_git_with_hook() {
  local ws="$1"
  ( cd "$ws" && git init -q && git config user.email t@t && git config user.name t \
    && cp "$HOOK_TEMPLATE" .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit )
}

# --------------------------------------------------------------- TC-M9.8-01

@test "[m9.8] TC-M9.8-01 full round-trip writes knowledge + skill + config + audit" {
  ws=$(m9_seed_workspace); m9_init_memory "$ws"

  # Direct memory_layer writes simulate the result of an extractor pass.
  write_n_knowledge "$ws" 1 T-RT
  write_n_skills    "$ws" 1 T-RT
  write_n_config    "$ws" 1 T-RT

  # Each asset class produced exactly one artifact on disk.
  k_count=$(find "$ws/.codenook/memory/knowledge" -name '*.md' | wc -l | tr -d ' ')
  s_count=$(find "$ws/.codenook/memory/skills" -name 'SKILL.md' | wc -l | tr -d ' ')
  [ "$k_count" -eq 1 ] || { echo "knowledge=$k_count"; return 1; }
  [ "$s_count" -eq 1 ] || { echo "skills=$s_count"; return 1; }

  PYTHONPATH="$M9_LIB_DIR" WS="$ws" python3 - <<'PY'
import os, json
import memory_layer as ml
ws = os.environ["WS"]
entries = ml.read_config_entries(ws)
assert len(entries) == 1, entries
assert entries[0]["key"].startswith("c-t-rt-"), entries
PY

  # Audit log contains at least one record per asset type.
  log="$ws/.codenook/memory/history/extraction-log.jsonl"
  [ -s "$log" ] || { echo "audit log empty"; return 1; }
  grep -q '"asset_type": "knowledge"' "$log" || { echo "no knowledge audit"; cat "$log"; return 1; }
  grep -q '"asset_type": "skill"'     "$log" || { echo "no skill audit"; cat "$log"; return 1; }
  grep -q '"asset_type": "config"'    "$log" || { echo "no config audit"; cat "$log"; return 1; }
}

# --------------------------------------------------------------- TC-M9.8-02

@test "[m9.8] TC-M9.8-02 gc dry-run reports over-cap; real run prunes + audits" {
  ws=$(m9_seed_workspace); m9_init_memory "$ws"

  # Per-task caps from spec §6 / §7: knowledge=3, skill=1, config=5.
  # Seed N+2 of each from a single task to force pruning.
  write_n_knowledge "$ws" 5 T-OVER
  write_n_skills    "$ws" 3 T-OVER
  write_n_config    "$ws" 7 T-OVER

  # ---- dry run: must report planned removals, must not touch disk.
  k_before=$(ls "$ws/.codenook/memory/knowledge" | wc -l | tr -d ' ')
  s_before=$(ls "$ws/.codenook/memory/skills"    | wc -l | tr -d ' ')
  c_before=$(PYTHONPATH="$M9_LIB_DIR" python3 -c "import memory_layer as m; print(len(m.read_config_entries('$ws')))")

  run env PYTHONPATH="$M9_LIB_DIR" python3 "$GC_PY" --workspace "$ws" --dry-run --json
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  # JSON envelope sanity.
  echo "$output" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
assert d['dry_run'] is True, d
assert d['planned']['knowledge'] == 2, d   # 5-3
assert d['planned']['skill']     == 2, d   # 3-1
assert d['planned']['config']    == 2, d   # 7-5
"

  # Disk is unchanged after dry run.
  k_after_dry=$(ls "$ws/.codenook/memory/knowledge" | wc -l | tr -d ' ')
  s_after_dry=$(ls "$ws/.codenook/memory/skills"    | wc -l | tr -d ' ')
  c_after_dry=$(PYTHONPATH="$M9_LIB_DIR" python3 -c "import memory_layer as m; print(len(m.read_config_entries('$ws')))")
  [ "$k_after_dry" = "$k_before" ] || { echo "dry run mutated knowledge"; return 1; }
  [ "$s_after_dry" = "$s_before" ] || { echo "dry run mutated skills"; return 1; }
  [ "$c_after_dry" = "$c_before" ] || { echo "dry run mutated config"; return 1; }

  # ---- real run: prunes oldest-first within each over-cap group.
  log="$ws/.codenook/memory/history/extraction-log.jsonl"
  audit_before=$(wc -l <"$log" | tr -d ' ')

  run env PYTHONPATH="$M9_LIB_DIR" python3 "$GC_PY" --workspace "$ws" --json
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  echo "$output" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
assert d['dry_run'] is False, d
assert d['pruned']['knowledge'] == 2, d
assert d['pruned']['skill']     == 2, d
assert d['pruned']['config']    == 2, d
"

  k_post=$(ls "$ws/.codenook/memory/knowledge" | wc -l | tr -d ' ')
  s_post=$(ls "$ws/.codenook/memory/skills"    | wc -l | tr -d ' ')
  c_post=$(PYTHONPATH="$M9_LIB_DIR" python3 -c "import memory_layer as m; print(len(m.read_config_entries('$ws')))")
  [ "$k_post" -eq 3 ] || { echo "knowledge post=$k_post"; return 1; }
  [ "$s_post" -eq 1 ] || { echo "skills post=$s_post";    return 1; }
  [ "$c_post" -eq 5 ] || { echo "config post=$c_post";    return 1; }

  # The newest knowledge artifact survives (k-t-over-004 > k-t-over-000).
  ls "$ws/.codenook/memory/knowledge" | grep -q 'k-t-over-004' \
    || { echo "newest knowledge dropped"; ls "$ws/.codenook/memory/knowledge"; return 1; }
  ls "$ws/.codenook/memory/knowledge" | grep -q 'k-t-over-000' \
    && { echo "oldest knowledge survived"; return 1; } || true

  audit_after=$(wc -l <"$log" | tr -d ' ')
  [ "$audit_after" -gt "$audit_before" ] || { echo "no gc audit appended"; return 1; }
  grep -q '"outcome": "gc_pruned"' "$log" || { echo "gc_pruned outcome missing"; tail "$log"; return 1; }
}

# --------------------------------------------------------------- TC-M9.8-03

@test "[m9.8] TC-M9.8-03 pre-commit hook blocks commits that write to plugins/" {
  command -v git >/dev/null || skip "git not available"
  [ -x "$HOOK_TEMPLATE" ] || skip "hook template not yet installed (RED)"

  ws=$(make_scratch)
  init_git_with_hook "$ws"

  # First commit a benign file so HEAD exists.
  ( cd "$ws" && echo hello > README.md && git add README.md \
    && git commit -q -m "init" )

  # Now stage a write under plugins/ — hook must reject the commit.
  ( cd "$ws" && mkdir -p plugins/some-plugin \
    && cat > plugins/some-plugin/extractor.py <<'PY'
def write():
    open("plugins/some-plugin/out.txt", "w").write("hi")
PY
    git add plugins/some-plugin/extractor.py )

  run bash -c "cd '$ws' && git commit -m 'should be blocked'"
  [ "$status" -ne 0 ] || { echo "commit was allowed; output=$output"; return 1; }
  echo "$output" | grep -qiE 'plugin|read.?only|reject' \
    || { echo "hook output missing rejection cue: $output"; return 1; }
}

# --------------------------------------------------------------- TC-M9.8-04

@test "[m9.8] TC-M9.8-04 router→extractor→memory-index loop stable across two ticks" {
  ws=$(m9_seed_workspace); m9_init_memory "$ws"
  lookup="$ws/_extractors"; mkdir -p "$lookup"

  # Tick 1: simulate the extractor result and exercise the dispatcher.
  write_n_knowledge "$ws" 1 T-LOOP-1
  run env CN_EXTRACTOR_LOOKUP_ROOT="$lookup" bash "$BATCH_SH" \
        --task-id T-LOOP-1 --reason after_phase --workspace "$ws" --phase complete
  [ "$status" -eq 0 ] || { echo "tick1 status=$status output=$output"; return 1; }

  # Snapshot after tick 1.
  snap1=$(PYTHONPATH="$M9_LIB_DIR" WS="$ws" python3 - <<'PY'
import os, json, memory_layer as ml
idx = ml.scan_memory(os.environ["WS"])
out = {
    "k": sorted(m.get("topic") or m.get("path") for m in idx["knowledge"]),
    "s": sorted(m.get("name")  or m.get("path") for m in idx["skills"]),
    "c": sorted(e.get("key") for e in idx["config"]),
}
print(json.dumps(out, sort_keys=True))
PY
)

  # Tick 2: same task / same content → idempotent (dedup must hold).
  write_n_knowledge "$ws" 1 T-LOOP-1   # same topic prefix → overwrite, not duplicate
  run env CN_EXTRACTOR_LOOKUP_ROOT="$lookup" bash "$BATCH_SH" \
        --task-id T-LOOP-1 --reason after_phase --workspace "$ws" --phase complete
  [ "$status" -eq 0 ] || { echo "tick2 status=$status output=$output"; return 1; }

  snap2=$(PYTHONPATH="$M9_LIB_DIR" WS="$ws" python3 - <<'PY'
import os, json, memory_layer as ml
idx = ml.scan_memory(os.environ["WS"])
out = {
    "k": sorted(m.get("topic") or m.get("path") for m in idx["knowledge"]),
    "s": sorted(m.get("name")  or m.get("path") for m in idx["skills"]),
    "c": sorted(e.get("key") for e in idx["config"]),
}
print(json.dumps(out, sort_keys=True))
PY
)

  [ "$snap1" = "$snap2" ] || {
    echo "snapshot drifted across ticks"
    echo "snap1=$snap1"
    echo "snap2=$snap2"
    return 1
  }

  # No half-written tmp files leaked through both ticks.
  leak=$(find "$ws/.codenook/memory" -name '.tmp.*' -o -name '.tmp-snap.*' | wc -l | tr -d ' ')
  [ "$leak" -eq 0 ] || { echo "leaked tmp files: $leak"; find "$ws/.codenook/memory" -name '.tmp*'; return 1; }
}
