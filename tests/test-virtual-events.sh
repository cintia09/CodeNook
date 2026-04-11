#!/usr/bin/env bash
# Test: Virtual event validation (agentSwitch, memoryWrite, taskBoard)
set -euo pipefail

HOOK="./hooks/agent-pre-tool-use.sh"
PASS=0; FAIL=0; TOTAL=0
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

check() {
  local desc="$1" input="$2" expect="$3"
  TOTAL=$((TOTAL + 1))
  result=$(echo "$input" | bash "$HOOK" 2>/dev/null) || true
  if [ "$expect" = "allow" ]; then
    if [ -z "$result" ]; then PASS=$((PASS+1)); echo "  ✅ $desc → ALLOWED"
    else FAIL=$((FAIL+1)); echo "  ❌ $desc → DENIED (expected ALLOW): $result"; fi
  else
    if echo "$result" | grep -q '"deny"'; then PASS=$((PASS+1)); echo "  ✅ $desc → DENIED"
    else FAIL=$((FAIL+1)); echo "  ❌ $desc → ALLOWED (expected DENY)"; fi
  fi
}

cd "$PROJECT_ROOT"
mkdir -p .agents/memory .agents/runtime

# ============================================================
echo "📋 Virtual Event Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━"

# --- V-EVENT 1: agentSwitch (edit/create) ---
echo "reviewer" > .agents/runtime/active-agent
echo ""
echo "--- V-EVENT 1: agentSwitch validation (edit/create) ---"

check "valid: switch to implementer via create" \
  '{"toolName":"create","toolArgs":{"path":"'"$PROJECT_ROOT"'/.agents/runtime/active-agent","file_text":"implementer\n"},"cwd":"'"$PROJECT_ROOT"'"}' \
  "allow"

check "valid: switch to acceptor via edit" \
  '{"toolName":"edit","toolArgs":{"path":"'"$PROJECT_ROOT"'/.agents/runtime/active-agent","new_str":"acceptor"},"cwd":"'"$PROJECT_ROOT"'"}' \
  "allow"

check "invalid: switch to 'admin' role" \
  '{"toolName":"create","toolArgs":{"path":"'"$PROJECT_ROOT"'/.agents/runtime/active-agent","file_text":"admin"},"cwd":"'"$PROJECT_ROOT"'"}' \
  "deny"

check "invalid: switch to 'root' role" \
  '{"toolName":"create","toolArgs":{"path":"'"$PROJECT_ROOT"'/.agents/runtime/active-agent","file_text":"root"},"cwd":"'"$PROJECT_ROOT"'"}' \
  "deny"

check "valid: clear active-agent (empty)" \
  '{"toolName":"create","toolArgs":{"path":"'"$PROJECT_ROOT"'/.agents/runtime/active-agent","file_text":""},"cwd":"'"$PROJECT_ROOT"'"}' \
  "allow"

# --- V-EVENT 1b: agentSwitch (bash) ---
echo ""
echo "--- V-EVENT 1b: agentSwitch validation (bash) ---"
echo "tester" > .agents/runtime/active-agent

check "valid: echo implementer to active-agent" \
  '{"toolName":"bash","toolArgs":{"command":"echo implementer > .agents/runtime/active-agent"},"cwd":"'"$PROJECT_ROOT"'"}' \
  "allow"

check "valid: echo quoted designer to active-agent" \
  '{"toolName":"bash","toolArgs":{"command":"echo \"designer\" > .agents/runtime/active-agent"},"cwd":"'"$PROJECT_ROOT"'"}' \
  "allow"

check "invalid: echo 'hacker' to active-agent" \
  '{"toolName":"bash","toolArgs":{"command":"echo hacker > .agents/runtime/active-agent"},"cwd":"'"$PROJECT_ROOT"'"}' \
  "deny"

# --- V-EVENT 2: memoryWrite isolation (edit/create) ---
echo ""
echo "--- V-EVENT 2: memoryWrite isolation (edit/create) ---"
echo "implementer" > .agents/runtime/active-agent

check "allow: implementer writes own memory" \
  '{"toolName":"create","toolArgs":{"path":"'"$PROJECT_ROOT"'/.agents/memory/implementer-notes.md","file_text":"notes"},"cwd":"'"$PROJECT_ROOT"'"}' \
  "allow"

check "allow: implementer writes task memory" \
  '{"toolName":"create","toolArgs":{"path":"'"$PROJECT_ROOT"'/.agents/memory/T-042-memory.json","file_text":"{}"},"cwd":"'"$PROJECT_ROOT"'"}' \
  "allow"

check "deny: implementer writes designer memory" \
  '{"toolName":"create","toolArgs":{"path":"'"$PROJECT_ROOT"'/.agents/memory/designer-notes.md","file_text":"hijack"},"cwd":"'"$PROJECT_ROOT"'"}' \
  "deny"

check "deny: implementer writes reviewer memory" \
  '{"toolName":"create","toolArgs":{"path":"'"$PROJECT_ROOT"'/.agents/memory/reviewer-review.json","file_text":"fake"},"cwd":"'"$PROJECT_ROOT"'"}' \
  "deny"

echo "reviewer" > .agents/runtime/active-agent

check "allow: reviewer writes own memory" \
  '{"toolName":"create","toolArgs":{"path":"'"$PROJECT_ROOT"'/.agents/memory/reviewer-analysis.md","file_text":"review notes"},"cwd":"'"$PROJECT_ROOT"'"}' \
  "allow"

check "deny: reviewer writes tester memory" \
  '{"toolName":"create","toolArgs":{"path":"'"$PROJECT_ROOT"'/.agents/memory/tester-results.json","file_text":"fake"},"cwd":"'"$PROJECT_ROOT"'"}' \
  "deny"

# --- V-EVENT 2b: memoryWrite isolation (bash) ---
echo ""
echo "--- V-EVENT 2b: memoryWrite isolation (bash) ---"
echo "tester" > .agents/runtime/active-agent

check "allow: tester redirects to own memory" \
  '{"toolName":"bash","toolArgs":{"command":"echo notes >> .agents/memory/tester-log.md"},"cwd":"'"$PROJECT_ROOT"'"}' \
  "allow"

check "allow: tester redirects to task memory" \
  '{"toolName":"bash","toolArgs":{"command":"echo data >> .agents/memory/T-001-memory.json"},"cwd":"'"$PROJECT_ROOT"'"}' \
  "allow"

check "deny: tester redirects to designer memory" \
  '{"toolName":"bash","toolArgs":{"command":"echo hack >> .agents/memory/designer-notes.md"},"cwd":"'"$PROJECT_ROOT"'"}' \
  "deny"

# --- V-EVENT 3: taskBoard JSON validation ---
echo ""
echo "--- V-EVENT 3: taskBoard JSON validation ---"
echo "acceptor" > .agents/runtime/active-agent

check "allow: valid JSON to task-board" \
  '{"toolName":"create","toolArgs":{"path":"'"$PROJECT_ROOT"'/.agents/task-board.json","file_text":"{\"tasks\":[]}"},"cwd":"'"$PROJECT_ROOT"'"}' \
  "allow"

check "deny: invalid JSON to task-board" \
  '{"toolName":"create","toolArgs":{"path":"'"$PROJECT_ROOT"'/.agents/task-board.json","file_text":"{ broken json ,,}"},"cwd":"'"$PROJECT_ROOT"'"}' \
  "deny"

# --- Security: chained command bypass prevention ---
echo ""
echo "--- Security: chained command with role switch ---"
echo "tester" > .agents/runtime/active-agent

check "deny: switch + destructive chained command" \
  '{"toolName":"bash","toolArgs":{"command":"echo implementer > .agents/runtime/active-agent && rm install.sh"},"cwd":"'"$PROJECT_ROOT"'"}' \
  "deny"

# --- Reviewer can switch roles (previously bugged) ---
echo ""
echo "--- Reviewer role switch regression ---"
echo "reviewer" > .agents/runtime/active-agent

check "allow: reviewer switches to acceptor via create" \
  '{"toolName":"create","toolArgs":{"path":"'"$PROJECT_ROOT"'/.agents/runtime/active-agent","file_text":"acceptor"},"cwd":"'"$PROJECT_ROOT"'"}' \
  "allow"

# --- Cleanup ---
echo ""
echo "implementer" > .agents/runtime/active-agent
echo "━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && echo "✅ All virtual event tests passed!" || echo "❌ Some tests failed"
exit "$FAIL"
