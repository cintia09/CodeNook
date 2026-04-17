#!/usr/bin/env bash
# T19: Mode B dispatch invariants — core §7 and every agent profile assert
# that sub-agents are launched via general-purpose runners and must read
# their own profile (no platform preload).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SH="$POC_DIR/init.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
bash "$INIT_SH" > /tmp/t19-init.log 2>&1

FAIL=0
pass() { echo "  ✅ $1"; }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "=== T19: Mode B dispatch invariants ==="
echo ""

# ----------------------------------------------------------------------
# [1] core.md §7 declares Mode B
# ----------------------------------------------------------------------
echo "[1] core.md §7 Mode B protocol:"
C=.codenook/core/codenook-core.md
s7=$(awk '/^## 7\. Sub-Agent Dispatch Protocol/,/^## 8\./' "$C")
echo "$s7" | grep -qi 'Mode B'                      && pass "§7 labels Mode B"                   || fail "§7 no Mode B label"
echo "$s7" | grep -qi 'general-purpose'             && pass "§7 references general-purpose"       || fail "§7 no general-purpose"
echo "$s7" | grep -qi 'workspace-first'             && pass "§7 justifies with workspace-first"   || fail "§7 no workspace-first"
echo "$s7" | grep -q  'portable\|Portable'          && pass "§7 cites portability"                || fail "§7 no portability"
echo "$s7" | grep -qi 'Load your profile FIRST'     && pass "§7 documents 'Load profile FIRST'"   || fail "§7 no load-first directive"
echo "$s7" | grep -q  '.codenook/agents/<role>'     && pass "§7 shows profile path template"      || fail "§7 no profile path"
echo "$s7" | grep -qi 'ignore'                      && pass "§7 tells orchestrator to ignore named subagents" || fail "§7 no ignore-named rule"
echo "$s7" | grep -q  'status.*summary.*output_path' && pass "§7 defines return contract"         || fail "§7 no return contract"

# ----------------------------------------------------------------------
# [2] All agent profiles have the Invocation (Mode B) block
# ----------------------------------------------------------------------
echo ""
echo "[2] Agent profiles declare Mode B invocation:"
ROLES="acceptor clarifier designer implementer planner reviewer session-distiller synthesizer tester validator"
for role in $ROLES; do
  f=".codenook/agents/$role.agent.md"
  [[ -f "$f" ]] || { fail "missing profile: $f"; continue; }
  if grep -q '^## Invocation (Mode B)' "$f"; then
    pass "$role has ## Invocation (Mode B)"
  else
    fail "$role missing ## Invocation (Mode B)"
  fi
done

# ----------------------------------------------------------------------
# [3] Each Mode B block contains the three required assertions
# ----------------------------------------------------------------------
echo ""
echo "[3] Mode B block content invariants:"
for role in $ROLES; do
  f=".codenook/agents/$role.agent.md"
  [[ -f "$f" ]] || continue
  block=$(awk '/^## Invocation \(Mode B\)/,/^## Self-Bootstrap Protocol/' "$f")
  # 3a: role name baked in
  echo "$block" | grep -q "Your role is \*\*$role\*\*" \
    && pass "$role: role name baked in" || fail "$role: role not self-identified"
  # 3b: no-preload assertion
  echo "$block" | grep -qi 'did NOT pre-load\|not pre-load\|never pre-load' \
    && pass "$role: asserts no-preload" || fail "$role: missing no-preload assertion"
  # 3c: generic runner reference
  echo "$block" | grep -qi 'general-purpose\|generic task runner' \
    && pass "$role: cites generic runner" || fail "$role: no generic-runner cite"
done

# ----------------------------------------------------------------------
# [4] Step 1 still instructs reading the manifest (self-bootstrap intact)
# ----------------------------------------------------------------------
echo ""
echo "[4] Self-Bootstrap Step 1 preserved:"
for role in $ROLES; do
  f=".codenook/agents/$role.agent.md"
  [[ -f "$f" ]] || continue
  if awk '/^## Self-Bootstrap Protocol/,/^## [^S]/' "$f" | grep -qE '^### Step 1'; then
    pass "$role has Step 1"
  else
    fail "$role: Step 1 missing or mis-labeled"
  fi
done

# ----------------------------------------------------------------------
# [5] §7 dispatch template is parseable
# ----------------------------------------------------------------------
echo ""
echo "[5] Dispatch template concrete shape:"
template=$(echo "$s7" | awk '/^```$/{c++; next} c==1 && c<2')
# The first fenced block in §7 should be the dispatch prompt template.
first_block=$(echo "$s7" | awk 'BEGIN{inb=0; n=0} /^```/{n++; if(n==1){inb=1; next} else if(n==2){inb=0}} inb')
echo "$first_block" | grep -qi 'CodeNook <role> sub-agent'     && pass "template says 'CodeNook <role> sub-agent'" || fail "template missing role prefix"
echo "$first_block" | grep -q  '.codenook/agents/<role>.agent.md' && pass "template references profile path"       || fail "template missing profile path"
echo "$first_block" | grep -qi 'Manifest:'                     && pass "template cites Manifest:"                 || fail "template no Manifest"
echo "$first_block" | grep -qi 'Return ONLY'                   && pass "template demands structured return"       || fail "template no Return ONLY"

echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "=== T19 PASSED ==="
  exit 0
else
  echo "=== T19 FAILED ($FAIL issues) ==="
  exit 1
fi
