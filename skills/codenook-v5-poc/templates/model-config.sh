#!/usr/bin/env bash
# CodeNook v5.0 — Model assignment helper (core.md §24)
#
# Subcommands:
#   resolve <task_id> <role>        Print the resolved model or "platform-default"
#   list    <task_id>               Print the resolution table for a task
#   set     <task_id> <role> <val>  Write task-level override into state.json
#   unset   <task_id> <role>        Remove a per-role override
#
# Resolution precedence (high→low):
#   tasks/<id>/state.json models[role]
#   tasks/<id>/state.json models.default
#   .codenook/config.yaml models[role]
#   .codenook/config.yaml models.default
#   "platform-default"   (sentinel: dispatch w/o --model; platform picks default)
#
# Subtasks (T-xxx.y) always resolve against parent T-xxx.

set -u

WS=".codenook"
CFG="$WS/config.yaml"
TASKS="$WS/tasks"

if [[ ! -d "$WS" ]]; then
  echo "error: not in a CodeNook workspace" >&2
  exit 2
fi

cmd="${1:-}"
[[ -z "$cmd" ]] && { sed -n '2,16p' "$0"; exit 2; }

# --- helpers ---------------------------------------------------------------
parent_task() {
  # T-001.2 → T-001 ;  T-001 → T-001
  local t="$1"; echo "${t%%.*}"
}

read_workspace_model() {
  local role="$1"
  python3 - "$CFG" "$role" <<'PY'
import sys, re
cfg, role = sys.argv[1], sys.argv[2]
try:
    txt = open(cfg).read()
except FileNotFoundError:
    print(""); sys.exit(0)
in_models = False
val_role = ""; val_default = ""
for raw in txt.splitlines():
    line = raw.rstrip()
    if not line or line.lstrip().startswith("#"):
        continue
    if re.match(r'^models:\s*$', line):
        in_models = True; continue
    if in_models and line and not line.startswith((" ", "\t")):
        in_models = False
    if in_models:
        m = re.match(r'^\s+([A-Za-z0-9_.-]+):\s*(.+?)\s*$', line)
        if m:
            k, v = m.group(1), m.group(2).strip().strip('"').strip("'")
            if k == role: val_role = v
            elif k == "default": val_default = v
print(val_role or val_default)
PY
}

read_task_model() {
  local task="$1" role="$2"
  local sj="$TASKS/$task/state.json"
  [[ -f "$sj" ]] || { echo ""; return; }
  python3 - "$sj" "$role" <<'PY'
import sys, json
sj, role = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(sj))
except Exception:
    print(""); sys.exit(0)
m = d.get("models") or {}
print(str(m.get(role) or m.get("default") or ""))
PY
}

resolve() {
  local task="$1" role="$2"
  local parent; parent=$(parent_task "$task")
  local v; v=$(read_task_model "$parent" "$role")
  [[ -n "$v" ]] && { echo "$v"; return; }
  v=$(read_workspace_model "$role")
  [[ -n "$v" ]] && { echo "$v"; return; }
  echo "platform-default"
}

# --- subcommands -----------------------------------------------------------
case "$cmd" in
  resolve)
    [[ $# -ne 3 ]] && { echo "usage: resolve <task> <role>" >&2; exit 2; }
    resolve "$2" "$3"
    ;;
  list)
    [[ $# -ne 2 ]] && { echo "usage: list <task>" >&2; exit 2; }
    task="$2"; parent=$(parent_task "$task")
    echo "Task: $task   (parent: $parent)"
    echo "Resolution table:"
    printf "  %-20s  %s\n" "ROLE" "MODEL"
    for r in default clarifier designer planner implementer reviewer reviewer_a reviewer_b synthesizer tester acceptor validator session-distiller security-auditor; do
      printf "  %-20s  %s\n" "$r" "$(resolve "$task" "$r")"
    done
    ;;
  set)
    [[ $# -ne 4 ]] && { echo "usage: set <task> <role> <value>" >&2; exit 2; }
    task="$2"; role="$3"; val="$4"
    parent=$(parent_task "$task")
    sj="$TASKS/$parent/state.json"
    [[ -f "$sj" ]] || { echo "error: $sj not found (subtasks inherit from parent)" >&2; exit 2; }
    python3 - "$sj" "$role" "$val" <<'PY'
import sys, json
sj, role, val = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(sj))
d.setdefault("models", {})[role] = val
json.dump(d, open(sj, "w"), indent=2)
PY
    echo "ok: set $parent.models.$role = $val"
    ;;
  unset)
    [[ $# -ne 3 ]] && { echo "usage: unset <task> <role>" >&2; exit 2; }
    task="$2"; role="$3"
    parent=$(parent_task "$task")
    sj="$TASKS/$parent/state.json"
    [[ -f "$sj" ]] || { echo "error: $sj not found" >&2; exit 2; }
    python3 - "$sj" "$role" <<'PY'
import sys, json
sj, role = sys.argv[1], sys.argv[2]
d = json.load(open(sj))
m = d.get("models", {})
m.pop(role, None)
d["models"] = m
json.dump(d, open(sj, "w"), indent=2)
PY
    echo "ok: unset $parent.models.$role"
    ;;
  *)
    echo "unknown subcommand: $cmd" >&2
    sed -n '2,16p' "$0" >&2
    exit 2
    ;;
esac
