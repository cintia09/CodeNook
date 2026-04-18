#!/usr/bin/env bash
# CodeNook v5.0 — Preflight health check
# Validates workspace integrity before the orchestrator recommends
# advancing any task. Catches missing files, corrupted state, and
# version drift between templates and workspace.
#
# Exit codes:
#   0 = workspace healthy
#   1 = warnings (non-fatal)
#   2 = errors (abort; do not advance)
set -u

WS=".codenook"
FAIL=0
WARN=0
ok()   { echo "  ✅ $1"; }
err()  { echo "  ❌ $1" >&2; FAIL=$((FAIL+1)); }
warn() { echo "  ⚠️  $1"; WARN=$((WARN+1)); }

# ---- 1. Workspace root ------------------------------------------------
echo "[1] Workspace structure:"
[[ -d "$WS" ]] || { echo "  ❌ $WS/ missing. Run init.sh." >&2; exit 2; }
ok "$WS/ present"

# Required directories. Any missing one = error (user should re-init).
REQ_DIRS=(
  core prompts-templates prompts-criteria agents project tasks
  knowledge knowledge/by-role knowledge/by-topic
  history history/sessions hitl-queue hitl-queue/pending hitl-queue/answered
  hitl-adapters queue locks
)
for d in "${REQ_DIRS[@]}"; do
  [[ -d "$WS/$d" ]] && ok "$d/" || err "missing $WS/$d/"
done

# ---- 2. Required files ------------------------------------------------
echo ""
echo "[2] Required files:"
REQ_FILES=(
  "CLAUDE.md"
  "$WS/core/codenook-core.md"
  "$WS/subtask-runner.sh"
  "$WS/queue-runner.sh"
  "$WS/dispatch-audit.sh"
  "$WS/hitl-adapters/terminal.sh"
  "$WS/history/dispatch-log.jsonl"
)
for f in "${REQ_FILES[@]}"; do
  [[ -f "$f" ]] && ok "$f" || err "missing $f"
done

# ---- 3. Bootloader content --------------------------------------------
echo ""
echo "[3] CLAUDE.md bootloader content:"
if [[ -f CLAUDE.md ]]; then
  grep -q 'codenook-core.md' CLAUDE.md && ok "points at codenook-core.md" || err "CLAUDE.md does not reference codenook-core.md"
  grep -qi 'pure router' CLAUDE.md     && ok "router discipline declared" || warn "router-discipline line missing"
  grep -qi '/clear'       CLAUDE.md || true  # optional
fi

# ---- 4. Runner executability -----------------------------------------
echo ""
echo "[4] Runners executable:"
for r in subtask-runner.sh queue-runner.sh dispatch-audit.sh hitl-adapters/terminal.sh; do
  f="$WS/$r"
  [[ -x "$f" ]] && ok "$r +x" || err "$r not executable"
done

# ---- 5. Agent profiles complete ---------------------------------------
echo ""
echo "[5] Agent profiles:"
EXPECTED_ROLES=(clarifier designer planner implementer reviewer tester acceptor validator synthesizer session-distiller security-auditor)
for role in "${EXPECTED_ROLES[@]}"; do
  p="$WS/agents/$role.agent.md"
  if [[ -f "$p" ]]; then
    # Must carry Mode B invocation block.
    if grep -q '## Invocation (Mode B)' "$p"; then
      ok "$role.agent.md (Mode B)"
    else
      err "$role.agent.md missing Mode B Invocation block"
    fi
  else
    warn "$role.agent.md not present (optional if role unused)"
  fi
done

# ---- 6. Task states parseable + schema --------------------------------
echo ""
echo "[6] Task state.json integrity:"
task_count=0
broken=0
if [[ -d "$WS/tasks" ]]; then
  while IFS= read -r sj; do
    [[ -z "$sj" ]] && continue
    task_count=$((task_count+1))
    if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$sj" 2>/dev/null; then
      err "invalid JSON: $sj"
      broken=$((broken+1))
      continue
    fi
    # Required fields.
    for k in task_id status phase; do
      python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if sys.argv[2] in d else 1)" "$sj" "$k" 2>/dev/null \
        || { err "$(basename "$(dirname "$sj")")/state.json missing field: $k"; broken=$((broken+1)); }
    done
  done < <(find "$WS/tasks" -maxdepth 2 -name state.json 2>/dev/null)
fi
[[ $task_count -eq 0 ]] && warn "no tasks yet (cold workspace)"
[[ $task_count -gt 0 && $broken -eq 0 ]] && ok "$task_count task state files healthy"

# ---- 7. OPT-7 preflight: active tasks have required creation-time answers --
echo ""
echo "[7] OPT-7 creation-time answers complete:"
incomplete=0
if [[ -d "$WS/tasks" ]]; then
  while IFS= read -r sj; do
    [[ -z "$sj" ]] && continue
    tid=$(basename "$(dirname "$sj")")
    # Expect dual_mode to be set to 'serial' | 'parallel' | 'off' (or null with
    # total_iterations==0 meaning 'not started yet'). If the task has any
    # iteration > 0 but dual_mode is null, flag it — this is the OPT-7 bug.
    out=$(python3 - "$sj" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
dm = d.get("dual_mode")
iters = d.get("total_iterations", 0)
status = d.get("status", "")
if status in ("done","cancelled"): print("SKIP"); sys.exit()
if dm is None and iters and iters > 0:
    print("MISSING_DUAL_MODE")
else:
    print("OK")
PY
)
    case "$out" in
      MISSING_DUAL_MODE) err "$tid: iteration started but dual_mode null (OPT-7 bug)"; incomplete=$((incomplete+1)) ;;
      SKIP|OK) : ;;
      *) warn "$tid: OPT-7 check returned unexpected '$out'" ;;
    esac
  done < <(find "$WS/tasks" -maxdepth 2 -name state.json 2>/dev/null)
fi
[[ $incomplete -eq 0 && $task_count -gt 0 ]] && ok "all active tasks have dual_mode or no iterations yet"

# ---- 7b. Serial dual_mode requires max_iterations ≥ 2 (Friction §3.3 / core §15) --
echo ""
echo "[7b] Serial dual_mode iteration budget:"
serial_bad=0
if [[ -d "$WS/tasks" ]]; then
  while IFS= read -r sj; do
    [[ -z "$sj" ]] && continue
    tid=$(basename "$(dirname "$sj")")
    out=$(python3 - "$sj" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
status = d.get("status","")
if status in ("done","cancelled"): print("SKIP"); sys.exit()
if d.get("dual_mode") == "serial":
    mi = d.get("max_iterations")
    if mi is None or mi < 2:
        print(f"BAD\t{mi}")
    else:
        print("OK")
else:
    print("SKIP")
PY
)
    case "$out" in
      BAD*)
        miv=${out#BAD	}
        err "$tid: serial dual_mode requires max_iterations >= 2 (got $miv) — otherwise loop degenerates to one-shot-or-HITL"
        serial_bad=$((serial_bad+1)) ;;
    esac
  done < <(find "$WS/tasks" -maxdepth 2 -name state.json 2>/dev/null)
fi
[[ $serial_bad -eq 0 && $task_count -gt 0 ]] && ok "serial-mode tasks have max_iterations >= 2"

# ---- 8. workspace state.json ------------------------------------------
echo ""
echo "[8] Workspace state.json:"
WSJ="$WS/state.json"
if [[ -f "$WSJ" ]]; then
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$WSJ" 2>/dev/null \
    && ok "valid JSON" || err "corrupted $WSJ"
else
  warn "$WSJ not yet created (no active tasks)"
fi

# ---- 9. Secret scan (delegated) ---------------------------------------
echo ""
echo "[9] Secret scan:"
if [[ -x "$WS/secret-scan.sh" ]]; then
  rc=0; out=$(bash "$WS/secret-scan.sh" 2>&1) || rc=$?
  case $rc in
    0) ok "secret-scan: no findings" ;;
    1) warn "secret-scan: findings (see report)"; echo "$out" | sed 's/^/      /' ;;
    *) err "secret-scan: scanner failure (rc=$rc)" ;;
  esac
else
  warn "secret-scan.sh not installed"
fi

# ---- 10. Keyring backend ----------------------------------------------
echo ""
echo "[10] Keyring backend:"
if [[ -x "$WS/keyring-helper.sh" ]]; then
  rc=0; out=$(bash "$WS/keyring-helper.sh" check 2>&1) || rc=$?
  case $rc in
    0) ok "keyring usable: $(echo "$out" | grep '^backend:' || echo unknown)" ;;
    3) warn "keyring not installed (pip install --user keyring)" ;;
    *) err "keyring backend broken (rc=$rc)" ;;
  esac
else
  warn "keyring-helper.sh not installed"
fi

# ---- 11. Summary -------------------------------------------------------
echo ""
echo "================ Preflight Summary ================"
echo "  errors:   $FAIL"
echo "  warnings: $WARN"
echo "==================================================="
if [[ $FAIL -gt 0 ]]; then
  exit 2
elif [[ $WARN -gt 0 ]]; then
  exit 1
else
  exit 0
fi
