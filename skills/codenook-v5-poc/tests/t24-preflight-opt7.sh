#!/usr/bin/env bash
# T24: Preflight + rebuild-task-board + OPT-7 + CLAUDE.md bootloader audit
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SH="$POC_DIR/init.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

FAIL=0
pass() { echo "  ✅ $1"; }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "=== T24: Preflight + board-rebuild + OPT-7 + CLAUDE.md ==="

cd "$TMP" && bash "$INIT_SH" > /tmp/t24-init.log 2>&1
PF=".codenook/preflight.sh"
RB=".codenook/rebuild-task-board.sh"

# ----------------------------------------------------------------------
# [1] Helpers installed + executable
# ----------------------------------------------------------------------
echo ""
echo "[1] Helpers installed:"
[[ -x "$PF" ]] && pass "preflight.sh +x" || fail "preflight.sh missing/not +x"
[[ -x "$RB" ]] && pass "rebuild-task-board.sh +x" || fail "rebuild missing/not +x"

# ----------------------------------------------------------------------
# [2] Preflight on fresh workspace = healthy (rc 0 or 1 with only warnings)
# ----------------------------------------------------------------------
echo ""
echo "[2] Preflight on fresh workspace:"
rc=0; out=$(bash "$PF" 2>&1) || rc=$?
if [[ $rc -le 1 ]]; then
  pass "preflight rc=$rc on fresh workspace (≤1 = errors-free)"
else
  fail "preflight rc=$rc on fresh workspace (should be ≤1):\n$out"
fi
echo "$out" | grep -q 'Workspace structure' && pass "preflight runs check [1]" || fail "check [1] missing"
echo "$out" | grep -q 'OPT-7'               && pass "preflight runs OPT-7 check"  || fail "OPT-7 check missing"

# ----------------------------------------------------------------------
# [3] Preflight catches missing core file
# ----------------------------------------------------------------------
echo ""
echo "[3] Preflight catches missing core.md:"
rm .codenook/core/codenook-core.md
rc=0; out=$(bash "$PF" 2>&1) || rc=$?
[[ $rc -eq 2 ]] && pass "rc=2 when core.md missing" || fail "rc=$rc (expected 2)"
echo "$out" | grep -q 'codenook-core.md' && pass "error names missing file" || fail "error message missing"
# Restore.
cp "$POC_DIR/templates/core/codenook-core.md" .codenook/core/codenook-core.md

# ----------------------------------------------------------------------
# [4] Preflight catches corrupted state.json
# ----------------------------------------------------------------------
echo ""
echo "[4] Preflight catches corrupted state.json:"
mkdir -p .codenook/tasks/T-001
echo 'not json {' > .codenook/tasks/T-001/state.json
rc=0; out=$(bash "$PF" 2>&1) || rc=$?
[[ $rc -eq 2 ]] && pass "rc=2 on corrupted JSON" || fail "rc=$rc (expected 2)"
echo "$out" | grep -q 'invalid JSON' && pass "flags invalid JSON" || fail "no invalid-JSON note"
rm -rf .codenook/tasks/T-001

# ----------------------------------------------------------------------
# [5] OPT-7 check flags dual_mode=null with iterations>0
# ----------------------------------------------------------------------
echo ""
echo "[5] OPT-7 catches pre-OPT-7 tasks:"
mkdir -p .codenook/tasks/T-002
cat > .codenook/tasks/T-002/state.json <<'JSON'
{
  "task_id": "T-002",
  "status": "in_progress",
  "phase": "implement",
  "dual_mode": null,
  "total_iterations": 2
}
JSON
rc=0; out=$(bash "$PF" 2>&1) || rc=$?
[[ $rc -eq 2 ]] && pass "rc=2 on OPT-7 violation" || fail "rc=$rc (expected 2)"
echo "$out" | grep -q 'OPT-7 bug' && pass "OPT-7 error names bug" || fail "OPT-7 bug not named"

# ----------------------------------------------------------------------
# [6] OPT-7 happy path: dual_mode='serial' with iterations>0 passes
# ----------------------------------------------------------------------
echo ""
echo "[6] OPT-7 passes with dual_mode set:"
cat > .codenook/tasks/T-002/state.json <<'JSON'
{
  "task_id": "T-002",
  "status": "in_progress",
  "phase": "implement",
  "dual_mode": "serial",
  "total_iterations": 2
}
JSON
rc=0; out=$(bash "$PF" 2>&1) || rc=$?
[[ $rc -le 1 ]] && pass "rc=$rc (healthy) with dual_mode set" || fail "rc=$rc (should be ≤1): $out"

# Leave T-002 and add a second task for the board rebuild test.
mkdir -p .codenook/tasks/T-003
cat > .codenook/tasks/T-003/state.json <<'JSON'
{
  "task_id": "T-003",
  "status": "pending",
  "phase": "clarify",
  "dual_mode": null,
  "subtasks": [{"id":"T-003.1","status":"pending"}, {"id":"T-003.2","status":"done"}]
}
JSON

# ----------------------------------------------------------------------
# [7] rebuild-task-board dry-run prints JSON for both tasks
# ----------------------------------------------------------------------
echo ""
echo "[7] rebuild-task-board dry-run:"
dry=$(bash "$RB" --dry-run 2>&1)
echo "$dry" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['version']==1; assert len(d['tasks'])>=2" \
  && pass "dry-run produces valid JSON with ≥2 tasks" || fail "dry-run JSON invalid: $dry"
echo "$dry" | grep -q '"T-002"' && pass "includes T-002" || fail "missing T-002"
echo "$dry" | grep -q '"T-003"' && pass "includes T-003" || fail "missing T-003"
echo "$dry" | grep -q '"subtask_count": 2' && pass "T-003 subtask_count = 2" || fail "wrong subtask count"

# ----------------------------------------------------------------------
# [8] rebuild-task-board writes file
# ----------------------------------------------------------------------
echo ""
echo "[8] rebuild-task-board writes task-board.json:"
rm -f .codenook/tasks/task-board.json
bash "$RB" > /tmp/t24-rb.log 2>&1
[[ -f .codenook/tasks/task-board.json ]] && pass "file written" || fail "file not written"
python3 -c "import json; json.load(open('.codenook/tasks/task-board.json'))" \
  && pass "valid JSON" || fail "invalid JSON"

# ----------------------------------------------------------------------
# [9] CLAUDE.md bootloader audit
# ----------------------------------------------------------------------
echo ""
echo "[9] CLAUDE.md bootloader content:"
[[ -f CLAUDE.md ]] && pass "CLAUDE.md exists at root" || fail "no CLAUDE.md"
grep -q 'codenook-core.md'    CLAUDE.md && pass "references codenook-core.md" || fail "missing core ref"
grep -qi 'pure router'        CLAUDE.md && pass "declares pure-router role" || fail "missing router directive"
grep -qi 'end of every response' CLAUDE.md && pass "has interaction rule" || fail "missing interaction rule"
grep -qi 'prompts-templates'  CLAUDE.md && pass "DO-NOT-read list mentions prompts-templates" || fail "missing do-not list"

# ----------------------------------------------------------------------
# [10] core.md §22 OPT-7 documented
# ----------------------------------------------------------------------
echo ""
echo "[10] core.md §22 OPT-7 Preflight:"
C=.codenook/core/codenook-core.md
grep -q '^## 22. Preflight Check Protocol (OPT-7)' "$C" && pass "§22 section exists" || fail "§22 missing"
s22=$(awk '/^## 22\./{p=1; print; next} p; /^## 23\.|^---$/{if(p && /^## /) p=0}' "$C")
echo "$s22" | grep -qi 'dual_mode'        && pass "§22 names dual_mode"     || fail "dual_mode not named"
echo "$s22" | grep -qi 'preflight.sh'     && pass "§22 cites preflight.sh"  || fail "preflight.sh not cited"
echo "$s22" | grep -qi 'total_iterations' && pass "§22 defines trigger"     || fail "trigger undefined"

echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "=== T24 PASSED ==="
  exit 0
else
  echo "=== T24 FAILED ($FAIL) ==="
  exit 1
fi
