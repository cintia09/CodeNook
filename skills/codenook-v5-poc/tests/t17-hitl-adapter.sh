#!/usr/bin/env bash
# T17: HITL Adapter MVP — schema, init, §9 protocol, terminal.sh CLI
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SH="$POC_DIR/init.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
bash "$INIT_SH" > /tmp/t17-init.log 2>&1

FAIL=0
pass() { echo "  ✅ $1"; }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "=== T17: HITL Adapter MVP ==="
echo ""

# ----------------------------------------------------------------------
# [1] init.sh creates the right HITL layout
# ----------------------------------------------------------------------
echo "[1] Workspace layout:"
[[ -d .codenook/hitl-queue ]]           && pass "hitl-queue/ exists"          || fail "hitl-queue/ missing"
[[ -d .codenook/hitl-queue/pending ]]   && pass "hitl-queue/pending/ exists"  || fail "pending/ missing"
[[ -d .codenook/hitl-queue/answered ]]  && pass "hitl-queue/answered/ exists" || fail "answered/ missing"
[[ -f .codenook/hitl-queue/current.md ]]&& pass "current.md exists"           || fail "current.md missing"
[[ -d .codenook/hitl-adapters ]]        && pass "hitl-adapters/ exists"       || fail "hitl-adapters/ missing"
[[ -x .codenook/hitl-adapters/terminal.sh ]] && pass "terminal.sh is executable" || fail "terminal.sh not executable"
[[ -f .codenook/hitl-item-schema.md ]]  && pass "hitl-item-schema.md exists"  || fail "schema missing"

# ----------------------------------------------------------------------
# [2] Schema file has expected frontmatter keys
# ----------------------------------------------------------------------
echo ""
echo "[2] hitl-item-schema.md structure:"
S=.codenook/hitl-item-schema.md
for key in task_id phase queued_at reason source priority options default; do
  grep -q "^$key:" "$S" && pass "schema has key: $key" || fail "schema missing: $key"
done
grep -q 'next_action:' "$S" && pass "schema has option.next_action" || fail "schema missing next_action"

# ----------------------------------------------------------------------
# [3] state.json has HITL fields
# ----------------------------------------------------------------------
echo ""
echo "[3] state.json HITL fields:"
grep -q '"hitl_pending_count"' .codenook/state.json && pass "has hitl_pending_count" || fail "no hitl_pending_count"
grep -q '"last_hitl_seen_at"'  .codenook/state.json && pass "has last_hitl_seen_at"  || fail "no last_hitl_seen_at"

# ----------------------------------------------------------------------
# [4] core.md §9 is the new queue-based protocol
# ----------------------------------------------------------------------
echo ""
echo "[4] core.md §9 queue protocol:"
C=.codenook/core/codenook-core.md
s9=$(awk '/^## 9\. HITL Gate/,/^## 10\./' "$C")
echo "$s9" | grep -q 'Queue-Based, FIFO'  && pass "§9 declares queue-based FIFO"        || fail "§9 not queue-based"
echo "$s9" | grep -q 'pending/'           && pass "§9 references pending/"              || fail "§9 no pending/"
echo "$s9" | grep -q 'answered/'          && pass "§9 references answered/"             || fail "§9 no answered/"
echo "$s9" | grep -q 'queue_hitl'         && pass "§9 documents queue_hitl"             || fail "§9 no queue_hitl"
echo "$s9" | grep -q 'hitl_response'      && pass "§9 documents hitl_response"          || fail "§9 no hitl_response"
echo "$s9" | grep -qi 'promote'           && pass "§9 documents promotion"              || fail "§9 no promote step"
echo "$s9" | grep -q 'terminal.sh'        && pass "§9 references terminal.sh"           || fail "§9 no terminal.sh ref"
echo "$s9" | grep -q 'hitl_pending_count' && pass "§9 updates hitl_pending_count"       || fail "§9 no count update"
echo "$s9" | grep -q 'Multi-task queue'   && pass "§9 covers multi-task semantics"      || fail "§9 no multi-task section"
echo "$s9" | grep -q 'decision file\|decision-' && pass "§9 defines decision file path" || fail "§9 no decision-file path"

# ----------------------------------------------------------------------
# [5] terminal.sh CLI: help / count / list on empty queue
# ----------------------------------------------------------------------
echo ""
echo "[5] terminal.sh CLI (empty queue):"
cd "$TMP"
T=".codenook/hitl-adapters/terminal.sh"
bash "$T" help     | grep -q 'CodeNook'                && pass "help prints banner"       || fail "help broken"
bash "$T" count    | grep -q '^0$'                     && pass "count returns 0"          || fail "count != 0"
bash "$T" list     | grep -q 'no pending'              && pass "list reports empty"       || fail "list doesn't report empty"
bash "$T" show     | grep -q 'current.md is empty'     && pass "show on empty current.md" || fail "show broken"

# ----------------------------------------------------------------------
# [6] terminal.sh: end-to-end — queue an item, list, show, answer, verify
# ----------------------------------------------------------------------
echo ""
echo "[6] End-to-end queue lifecycle:"

# Set up a fake task
mkdir -p .codenook/tasks/T-001/hitl
cat > .codenook/tasks/T-001/task.md <<'TASK_EOF'
# T-001 — Build hello CLI
TASK_EOF

# Queue a pending item (simulates orchestrator's queue_hitl)
PID="T-001-clarify-20250115T120000Z"
cat > ".codenook/hitl-queue/pending/$PID.md" <<'ITEM_EOF'
---
task_id: T-001
phase: clarify
queued_at: 2025-01-15T12:00:00Z
reason: clarity_verdict:needs_user_input
source: clarifier
priority: normal
options:
  - id: A
    label: approve criteria as-is
    next_action: advance_phase
  - id: B
    label: revise criterion #3
    next_action: restart_phase
default: B
---

# HITL Decision Needed

## Task Context
- Task: T-001 — Build hello CLI
- Phase: clarify

## What Happened
Clarifier returned needs_user_input. Criterion #3 ambiguous.

## Options
- A — approve as-is
- B — revise criterion #3

## Suggested Default
B
ITEM_EOF
# Orchestrator would also copy to current.md since queue was empty
cp ".codenook/hitl-queue/pending/$PID.md" .codenook/hitl-queue/current.md

# list / count / show
[[ $(bash "$T" count) == "1" ]]                                      && pass "count=1 after enqueue" || fail "count wrong"
bash "$T" list | grep -q "$PID"                                      && pass "list shows the item"  || fail "list missed item"
bash "$T" list | grep -q 'reason=clarity_verdict:needs_user_input'   && pass "list shows reason"    || fail "list missed reason"
bash "$T" show | grep -q 'Clarifier returned'                        && pass "show prints current.md body" || fail "show body wrong"
bash "$T" show "$PID" | grep -q 'revise criterion'                   && pass "show <id> prints pending item" || fail "show id wrong"

# answer
bash "$T" answer "$PID" B "criterion #3 should specify empty-string edge case" > /tmp/t17-answer.log 2>&1
[[ $? -eq 0 ]] && pass "answer command succeeded" || fail "answer command failed"

# Verify archival
[[ ! -f ".codenook/hitl-queue/pending/$PID.md" ]] && pass "pending item removed"        || fail "pending item still there"
[[ -f   ".codenook/hitl-queue/answered/$PID.md" ]] && pass "pending item archived"       || fail "item not archived"

# Verify decision file written to task hitl dir
decision_count=$(find .codenook/tasks/T-001/hitl -name 'clarify-decision-*.md' | wc -l | tr -d ' ')
[[ $decision_count -eq 1 ]] && pass "decision file written to task hitl dir" || fail "decision file not written ($decision_count)"
df=$(find .codenook/tasks/T-001/hitl -name 'clarify-decision-*.md' | head -1)
grep -q "option_id: B" "$df"       && pass "decision records option_id=B"         || fail "option_id wrong"
grep -q "pending_id: $PID" "$df"   && pass "decision links back to pending_id"    || fail "no pending_id link"
grep -q "empty-string edge case" "$df" && pass "decision preserves user note"      || fail "note not preserved"
grep -q "answered_via: terminal-adapter" "$df" && pass "decision tagged with adapter" || fail "no adapter tag"

# Verify promotion behavior — queue now empty, current.md should be cleared
[[ ! -s .codenook/hitl-queue/current.md ]] && pass "current.md cleared when queue empty" \
                                           || fail "current.md not cleared"
[[ $(bash "$T" count) == "0" ]] && pass "count=0 after answer" || fail "count not decremented"

# ----------------------------------------------------------------------
# [7] Promotion with a second pending item
# ----------------------------------------------------------------------
echo ""
echo "[7] Promotion FIFO:"
# Queue two items, answer the first, verify second gets promoted
P1="T-002-design-20250115T130000Z"
P2="T-002-test-20250115T140000Z"
for pid in "$P1" "$P2"; do
  cat > ".codenook/hitl-queue/pending/$pid.md" <<ITEM_EOF
---
task_id: T-002
phase: ${pid##*-*-*-}
queued_at: 2025-01-15T13:00:00Z
reason: test_fifo
source: test
priority: normal
options:
  - id: A
    label: approve
    next_action: advance_phase
default: A
---
# body
ITEM_EOF
done
# Fix phase values (shell substitution above was lazy)
sed -i.bak 's/phase: .*/phase: design/' ".codenook/hitl-queue/pending/$P1.md"; rm ".codenook/hitl-queue/pending/$P1.md.bak"
sed -i.bak 's/phase: .*/phase: test/'   ".codenook/hitl-queue/pending/$P2.md"; rm ".codenook/hitl-queue/pending/$P2.md.bak"
cp ".codenook/hitl-queue/pending/$P1.md" .codenook/hitl-queue/current.md

mkdir -p .codenook/tasks/T-002/hitl
bash "$T" answer "$P1" A > /dev/null

# After P1 answered, current.md should now contain P2 content
grep -q "phase: test" .codenook/hitl-queue/current.md && pass "P2 promoted to current.md" \
                                                      || fail "P2 not promoted"
[[ $(bash "$T" count) == "1" ]] && pass "count=1 (P2 remaining)" || fail "count wrong after P1 answered"

echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "=== T17 PASSED ==="
  exit 0
else
  echo "=== T17 FAILED ($FAIL issues) ==="
  exit 1
fi
