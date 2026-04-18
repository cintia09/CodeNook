#!/usr/bin/env bash
# CodeNook v5.0 — Dispatch Audit
# Reads .codenook/history/dispatch-log.jsonl and verifies the orchestrator
# actually delegated work via Mode B sub-agent dispatches (vs. doing it
# itself in the main session). See core.md §20.
#
# Usage:
#   bash dispatch-audit.sh                                              # whole workspace
#   bash dispatch-audit.sh audit [T-003]                                # explicit audit (default subcommand)
#   bash dispatch-audit.sh emit <task_id> <phase> <role> <manifest> \
#                              <output_expected> [model]                # sanctioned writer for dispatch-log.jsonl
#
# Exit codes:
#   0 = no violations / emit succeeded
#   1 = violations found
#   2 = bad usage / missing files / emit validation failed

set -u

WS=".codenook"
LOG="$WS/history/dispatch-log.jsonl"
TASKS_DIR="$WS/tasks"

# ---------------------------------------------------------------------------
# Subcommand: emit — the only sanctioned writer for dispatch-log.jsonl
# (core §20.2, §21.3). Validates required fields, generates a deterministic
# invocation_id, appends one JSON line, echoes the id.
# ---------------------------------------------------------------------------
cmd_emit() {
  local task_id="${1:-}" phase="${2:-}" role="${3:-}" manifest="${4:-}" \
        output_expected="${5:-}" model="${6:-}"
  for f in task_id phase role manifest output_expected; do
    if [[ -z "${!f}" ]]; then
      echo "error: emit: missing required field '$f'" >&2
      echo "usage: dispatch-audit.sh emit <task_id> <phase> <role> <manifest> <output_expected> [model]" >&2
      exit 2
    fi
  done
  [[ "$task_id" =~ ^T-[A-Za-z0-9]+(\.[0-9]+)?$ ]] || {
    echo "error: emit: invalid task_id '$task_id'" >&2; exit 2; }
  [[ "$phase" =~ ^[A-Za-z0-9_-]+$ ]] || {
    echo "error: emit: invalid phase '$phase'" >&2; exit 2; }
  [[ "$role" =~ ^[A-Za-z0-9_-]+$ ]] || {
    echo "error: emit: invalid role '$role'" >&2; exit 2; }
  for p in "$manifest" "$output_expected"; do
    [[ "$p" == /* ]]    && { echo "error: emit: absolute path not allowed: $p" >&2; exit 2; }
    [[ "$p" == *..* ]]  && { echo "error: emit: traversal segment in path: $p" >&2; exit 2; }
  done

  mkdir -p "$WS/history"
  [[ -f "$LOG" ]] || : > "$LOG"

  local ts ts_unix slug invid
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  ts_unix=$(date -u +%s)
  slug=$(echo "$task_id" | tr '.' '-')
  invid="d-${ts_unix}-${role}-${slug}"

  python3 - "$LOG" "$ts" "$task_id" "$phase" "$role" "$manifest" \
                   "$output_expected" "$invid" "$model" <<'PY'
import json, sys
log, ts, tid, ph, ro, man, out, invid, model = sys.argv[1:10]
rec = {
    "ts": ts,
    "task_id": tid,
    "phase": ph,
    "role": ro,
    "manifest": man,
    "output_expected": out,
    "invocation_id": invid,
    "distiller_refreshed_at": None,  # populated by the distiller-refresh dispatch (§18, §3.4 fix)
}
if model:
    rec["model"] = model
with open(log, "a") as f:
    f.write(json.dumps(rec) + "\n")
PY
  echo "$invid"
  exit 0
}

# Subcommand dispatch. Backwards compatible: a bare `T-xxx` first arg still
# runs the audit on that task (legacy form).
SUB="${1:-}"
case "$SUB" in
  emit)  shift; cmd_emit "$@" ;;
  audit) shift; FILTER="${1:-}" ;;
  ""|T-*) FILTER="${1:-}" ;;
  -h|--help)
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  *) echo "error: unknown subcommand: $SUB" >&2; exit 2 ;;
esac

if [[ ! -d "$WS" ]]; then
  echo "error: not in a CodeNook workspace (no .codenook/)" >&2
  exit 2
fi

if [[ ! -f "$LOG" ]]; then
  echo "warn: no dispatch log yet at $LOG"
  echo "  → if you have outputs but no log, audit will report all of them as ghosts."
  touch "$LOG"
fi

# -----------------------------------------------------------------------
# Parse log into TSV: ts \t task_id \t phase \t role \t manifest \t output_expected \t invocation_id
# Tolerant of pretty-printed JSON? No — JSONL means one object per line.
# -----------------------------------------------------------------------
LOG_TSV=$(mktemp)
trap 'rm -f "$LOG_TSV"' EXIT

python3 - "$LOG" > "$LOG_TSV" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    for ln, raw in enumerate(f, 1):
        raw = raw.strip()
        if not raw:
            continue
        try:
            o = json.loads(raw)
        except Exception as e:
            print(f"__PARSE_ERROR__\t{ln}\t{e}\t\t\t\t", file=sys.stderr)
            continue
        fields = ["ts","task_id","phase","role","manifest","output_expected","invocation_id"]
        vals = [str(o.get(k,"")) for k in fields]
        print("\t".join(vals))
PY

violations=0
warnings=0
ok=0

note_v() { echo "  ❌ $1"; violations=$((violations+1)); }
note_w() { echo "  ⚠️  $1"; warnings=$((warnings+1)); }
note_o() { ok=$((ok+1)); }

# -----------------------------------------------------------------------
# Check 1: unique invocation_ids
# -----------------------------------------------------------------------
echo "[1] Unique invocation IDs:"
dups=$(awk -F'\t' 'NF>=7 && $7!=""{print $7}' "$LOG_TSV" | sort | uniq -d)
if [[ -z "$dups" ]]; then
  note_o; echo "  ✅ no duplicate invocation_ids"
else
  while IFS= read -r d; do note_v "duplicate invocation_id: $d"; done <<<"$dups"
fi

# -----------------------------------------------------------------------
# Check 2: every manifest referenced by log exists on disk
# -----------------------------------------------------------------------
echo ""
echo "[2] Manifest existence:"
miss=0
while IFS=$'\t' read -r ts task phase role manifest out invid; do
  [[ -z "${manifest:-}" ]] && continue
  if [[ -n "$FILTER" && "$task" != "$FILTER" ]]; then continue; fi
  if [[ ! -f "$manifest" ]]; then
    note_v "dangling manifest: $manifest (invid=$invid)"
    miss=$((miss+1))
  fi
done < "$LOG_TSV"
[[ $miss -eq 0 ]] && { note_o; echo "  ✅ all logged manifests exist"; }

# -----------------------------------------------------------------------
# Check 3: output coverage — every outputs/*.md must have a dispatch entry
# -----------------------------------------------------------------------
echo ""
echo "[3] Output coverage (ghost-work detection):"

if [[ -n "$FILTER" ]]; then
  out_dirs=("$TASKS_DIR/$FILTER/outputs")
else
  out_dirs=()
  if [[ -d "$TASKS_DIR" ]]; then
    while IFS= read -r d; do out_dirs+=("$d"); done < <(find "$TASKS_DIR" -type d -name outputs 2>/dev/null)
  fi
fi

# Build set of output_expected values from log
LOG_OUTS=$(mktemp); trap 'rm -f "$LOG_TSV" "$LOG_OUTS"' EXIT
awk -F'\t' '$6!=""{print $6}' "$LOG_TSV" | sort -u > "$LOG_OUTS"

ghosts=0
checked=0
for od in ${out_dirs[@]+"${out_dirs[@]}"}; do
  [[ -d "$od" ]] || continue
  while IFS= read -r f; do
    # Skip summary files (orchestrator may write summaries directly only if
    # the worker did; we audit primary outputs only)
    [[ "$f" == *-summary.md ]] && continue
    checked=$((checked+1))
    if ! grep -Fxq "$f" "$LOG_OUTS"; then
      note_v "ghost output (no dispatch entry): $f"
      ghosts=$((ghosts+1))
    fi
  done < <(find "$od" -maxdepth 1 -type f -name '*.md' 2>/dev/null)
done
echo "  audited $checked primary outputs"
[[ $ghosts -eq 0 && $checked -gt 0 ]] && { note_o; echo "  ✅ all outputs trace back to a dispatch"; }
[[ $checked -eq 0 ]] && { note_w "no outputs found yet (workspace still cold)"; }

# -----------------------------------------------------------------------
# Check 4: phase coverage — for each task, every (task,phase) appearing in
# outputs must appear in the log too.
# -----------------------------------------------------------------------
echo ""
echo "[4] Phase coverage:"

# Build (task, phase) set from log
LOG_TP=$(mktemp); trap 'rm -f "$LOG_TSV" "$LOG_OUTS" "$LOG_TP"' EXIT
awk -F'\t' '$2!="" && $3!=""{print $2"\t"$3}' "$LOG_TSV" | sort -u > "$LOG_TP"

mismatches=0
for od in ${out_dirs[@]+"${out_dirs[@]}"}; do
  [[ -d "$od" ]] || continue
  task_id=$(basename "$(dirname "$od")")
  while IFS= read -r f; do
    [[ "$f" == *-summary.md ]] && continue
    base=$(basename "$f" .md)
    # Output filenames look like 'phase-3-implementer'; the phase id in
    # state.json / log uses the action stem ('phase-3-implement'). Match
    # on the leading 'phase-N-' segment, then prefix-compare the stem.
    file_phase_num=$(echo "$base" | grep -oE '^phase-[0-9]+' || true)
    [[ -z "$file_phase_num" ]] && continue
    found=0
    while IFS=$'\t' read -r lt lp; do
      [[ "$lt" == "$task_id" ]] || continue
      log_phase_num=$(echo "$lp" | grep -oE '^phase-[0-9]+' || true)
      if [[ "$log_phase_num" == "$file_phase_num" ]]; then found=1; break; fi
    done < "$LOG_TP"
    if [[ $found -eq 0 ]]; then
      note_v "phase not in log: $task_id / $file_phase_num (file: $f)"
      mismatches=$((mismatches+1))
    fi
  done < <(find "$od" -maxdepth 1 -type f -name '*.md' 2>/dev/null)
done
[[ $mismatches -eq 0 ]] && { note_o; echo "  ✅ all observed phases were dispatched"; }

# -----------------------------------------------------------------------
# Check 5: workspace containment — manifest / output_expected paths must
# not escape the workspace or point at absolute roots. A traversal path in
# the log suggests an orchestrator attempted to have a sub-agent read or
# write outside .codenook/ — flag aggressively.
# -----------------------------------------------------------------------
echo ""
echo "[5] Workspace containment:"
escapes=0
while IFS=$'\t' read -r ts task phase role manifest out invid; do
  if [[ -n "$FILTER" && "$task" != "$FILTER" ]]; then continue; fi
  for p in "$manifest" "$out"; do
    [[ -z "$p" ]] && continue
    if [[ "$p" == /* ]]; then
      note_v "absolute path in log: $p (invid=$invid)"
      escapes=$((escapes+1))
    elif [[ "$p" == *..* ]]; then
      note_v "traversal segment '..' in log path: $p (invid=$invid)"
      escapes=$((escapes+1))
    elif [[ "$p" == _workspace/scratch/* || "$p" == _workspace/prompts/* \
         || "$p" == .codenook/_workspace/scratch/* || "$p" == .codenook/_workspace/prompts/* ]]; then
      : # sanctioned orchestrator scratch / refresh-manifest area (core §6, §18)
    elif [[ "$p" != .codenook/* && "$p" != "$WS"/* ]]; then
      note_w "path outside $WS/: $p (invid=$invid)"
    fi
  done
done < "$LOG_TSV"
[[ $escapes -eq 0 ]] && { note_o; echo "  ✅ no workspace-escape attempts in log"; }

# -----------------------------------------------------------------------
# Check 6: dual-mode iteration consistency. For tasks whose state.json
# declares dual_mode in {serial, parallel}, the iterations/ directory
# MUST exist and contain at least one iteration sub-dir per dispatched
# implement/review pair. Catches the case where dual_mode was set but
# the orchestrator forgot to create iteration scoping.
# -----------------------------------------------------------------------
echo ""
echo "[6] Dual-agent iteration consistency:"
dual_issues=0
if [[ -d "$WS/tasks" ]]; then
  while IFS= read -r sj; do
    [[ -z "$sj" ]] && continue
    tid=$(basename "$(dirname "$sj")")
    if [[ -n "$FILTER" && "$tid" != "$FILTER" ]]; then continue; fi
    dm=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('dual_mode') or '')" "$sj" 2>/dev/null || echo "")
    case "$dm" in
      serial|parallel)
        idir="$WS/tasks/$tid/iterations"
        if [[ ! -d "$idir" ]]; then
          # Only flag if we have any implement/review dispatches in the
          # log for this task — otherwise it just hasn't started yet.
          n=$(awk -F'\t' -v t="$tid" '$2==t && ($3=="implement"||$3=="review")' "$LOG_TSV" | wc -l | tr -d ' ')
          if [[ $n -gt 0 ]]; then
            note_v "$tid: dual_mode=$dm but no iterations/ dir (saw $n dispatches)"
            dual_issues=$((dual_issues+1))
          fi
        else
          # Verify each implement dispatch references an iteration path.
          while IFS=$'\t' read -r ts2 task2 phase2 role2 manifest2 out2 invid2; do
            [[ "$task2" != "$tid" ]] && continue
            [[ "$role2" != implementer && "$role2" != reviewer && "$role2" != synthesizer ]] && continue
            if [[ -n "$out2" && "$out2" != *iterations/* ]]; then
              note_w "$tid: $role2 output not in iterations/: $out2 (invid=$invid2)"
            fi
          done < "$LOG_TSV"
        fi
        ;;
      ""|off|none)
        : # nothing to verify
        ;;
      *)
        note_w "$tid: unknown dual_mode value '$dm'"
        ;;
    esac
  done < <(find "$WS/tasks" -maxdepth 2 -name state.json 2>/dev/null)
fi
[[ $dual_issues -eq 0 ]] && { note_o; echo "  ✅ dual-mode tasks have iteration scoping"; }

# -----------------------------------------------------------------------
# Check 7: distiller refresh discipline (Friction §3.4 / core §18, §5).
# After every non-distiller dispatch the orchestrator MUST dispatch the
# session-distiller before the next non-distiller dispatch. Two consecutive
# non-distiller entries (in chronological log order) are a violation.
# -----------------------------------------------------------------------
echo ""
echo "[7] Distiller refresh discipline:"
distill_issues=0
prev_role=""
prev_invid=""
while IFS=$'\t' read -r ts task phase role manifest out invid; do
  [[ -z "$role" ]] && continue
  if [[ -n "$FILTER" && "$task" != "$FILTER" && "$role" != session-distiller ]]; then
    continue
  fi
  if [[ "$role" != "session-distiller" && -n "$prev_role" && "$prev_role" != "session-distiller" ]]; then
    note_v "missing distiller refresh between $prev_invid and $invid (consecutive non-distiller dispatches)"
    distill_issues=$((distill_issues+1))
  fi
  prev_role="$role"; prev_invid="$invid"
done < "$LOG_TSV"
[[ $distill_issues -eq 0 ]] && { note_o; echo "  ✅ session-distiller refresh fired between every dispatch"; }

# -----------------------------------------------------------------------
# Check 8: subtask phase coverage (Bug §5). Every subtask must walk the
# full 6-phase pipeline starting from its declared start_phase (default
# clarify). Skipping any phase is a protocol violation.
# -----------------------------------------------------------------------
echo ""
echo "[8] Subtask phase coverage:"
subtask_issues=0
PIPELINE=(clarify design plan implement test accept validate)
if [[ -d "$WS/tasks" ]]; then
  while IFS= read -r sj; do
    [[ -z "$sj" ]] && continue
    sid=$(basename "$(dirname "$sj")")
    parent=$(echo "$sid" | awk -F'.' '{print $1}')
    if [[ -n "$FILTER" && "$parent" != "$FILTER" && "$sid" != "$FILTER" ]]; then continue; fi
    # Only inspect subtasks that have actually been worked (status != pending).
    sstatus=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('status',''))" "$sj" 2>/dev/null || echo "")
    [[ "$sstatus" == "pending" || -z "$sstatus" ]] && continue
    start_phase=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('start_phase','clarify'))" "$sj" 2>/dev/null || echo "clarify")
    # Build expected phase set from start_phase onward.
    expected=()
    seen_start=0
    for ph in "${PIPELINE[@]}"; do
      [[ "$ph" == "$start_phase" ]] && seen_start=1
      [[ $seen_start -eq 1 ]] && expected+=("$ph")
    done
    # Collect dispatched phases for this subtask from the log.
    walked=$(awk -F'\t' -v t="$sid" '$2==t {print $3}' "$LOG_TSV" \
              | sed -E 's/^phase-[0-9]+-//; s/^iter-[0-9]+-//; s/-?summary$//' \
              | sort -u)
    # Map dispatched roles back to phase names where the phase column is iter-N-implementer etc.
    walked_roles=$(awk -F'\t' -v t="$sid" '$2==t {print $4}' "$LOG_TSV" | sort -u)
    missing=()
    for ph in "${expected[@]}"; do
      hit=0
      while IFS= read -r w; do
        [[ -z "$w" ]] && continue
        case "$ph" in
          implement) [[ "$w" == implement* || "$w" == "implementer" ]] && hit=1 ;;
          *)         [[ "$w" == "$ph" || "$w" == "${ph}er" || "$w" == "${ph}or" ]] && hit=1 ;;
        esac
      done <<<"$walked"$'\n'"$walked_roles"
      [[ $hit -eq 0 ]] && missing+=("$ph")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
      note_v "$sid: subtask skipped phases (start_phase=$start_phase): ${missing[*]}"
      subtask_issues=$((subtask_issues+1))
    fi
  done < <(find "$WS/tasks" -mindepth 4 -maxdepth 4 -name state.json -path '*/subtasks/*' 2>/dev/null)
fi
[[ $subtask_issues -eq 0 ]] && { note_o; echo "  ✅ all worked subtasks walked their declared phase set"; }

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "================ Dispatch Audit Summary ================"
echo "  log entries: $(wc -l < "$LOG_TSV" | tr -d ' ')"
echo "  checks ok:   $ok"
echo "  warnings:    $warnings"
echo "  violations:  $violations"
echo "========================================================"

if [[ $violations -gt 0 ]]; then
  exit 1
fi
exit 0
