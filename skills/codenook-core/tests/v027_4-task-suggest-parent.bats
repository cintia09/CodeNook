#!/usr/bin/env bats
# v0.27.4 — `<codenook> task suggest-parent` CLI subcommand.
# Asserts the wrapper:
#   (1) exposes --help and lists --brief / --threshold / --top-k
#   (2) returns [] when no open tasks share tokens with the brief
#   (3) ranks similar open tasks by Jaccard score, descending
#   (4) rejects a user-supplied --workspace flag (kernel pins it)

load helpers/load
load helpers/assertions

REPO_ROOT="$(cd "$CORE_ROOT/../.." && pwd)"
INSTALL_PY="$REPO_ROOT/install.py"

setup() {
  ws="$(make_scratch)"
  python3 "$INSTALL_PY" --target "$ws" --upgrade --yes >/dev/null 2>&1
  CN="$ws/.codenook/bin/codenook"
}

mk_task() {
  # mk_task <T-NNN> <title> <summary>
  local tid="$1" title="$2" summary="$3"
  local d="$ws/.codenook/tasks/$tid"
  mkdir -p "$d"
  python3 - "$d/state.json" "$tid" "$title" "$summary" <<'PY'
import json, sys
path, tid, title, summary = sys.argv[1:]
json.dump({
    "task_id": tid,
    "title": title,
    "summary": summary,
    "phase": "start",
    "iteration": 0,
    "status": "open",
}, open(path, "w"), ensure_ascii=False, indent=2)
PY
}

@test "[v0.27.4] suggest-parent --help lists --brief / --threshold / --top-k" {
  run "$CN" task suggest-parent --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--brief"* ]]
  [[ "$output" == *"--threshold"* ]]
  [[ "$output" == *"--top-k"* ]]
}

@test "[v0.27.4] suggest-parent returns [] when no candidates exist" {
  run "$CN" task suggest-parent --brief "totally unrelated brief text" --json
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "[v0.27.4] suggest-parent ranks similar tasks by Jaccard score" {
  mk_task "T-100-foo-refactor" "foo refactor pass one" "refactor the foo module"
  mk_task "T-101-foo-refactor-v2" "foo refactor v2" "second pass on the foo module refactor"
  mk_task "T-102-bar-feature" "bar feature" "implement an unrelated bar feature"
  run "$CN" task suggest-parent \
        --brief "foo refactor follow-up" \
        --threshold 0.0 --top-k 5 --json
  [ "$status" -eq 0 ]
  ids="$(printf '%s' "$output" | python3 -c \
    "import json,sys; print(' '.join(s['task_id'] for s in json.load(sys.stdin)))")"
  [[ "$ids" == "T-100-foo-refactor T-101-foo-refactor-v2"* \
     || "$ids" == "T-101-foo-refactor-v2 T-100-foo-refactor"* ]]
  [[ "$ids" != *"T-102-bar-feature"* ]] || \
    [[ "$ids" == *"T-100-foo-refactor"*"T-102-bar-feature"* \
       || "$ids" == *"T-101-foo-refactor-v2"*"T-102-bar-feature"* ]]
}

@test "[v0.27.4] suggest-parent rejects user-supplied --workspace" {
  run "$CN" task suggest-parent --brief "x" --workspace /tmp/nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"--workspace"* ]]
}
