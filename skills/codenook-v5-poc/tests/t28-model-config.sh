#!/usr/bin/env bash
# T28 — model-config helper (core.md §24)
set -u
TS=$(mktemp -d); trap 'rm -rf "$TS"' EXIT
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TS"
CODENOOK_DEFAULT_MODEL=claude-opus-4.7 bash "$ROOT/init.sh" >/dev/null 2>&1

PASS=0; FAIL=0
pass(){ echo "  ✅ $1"; PASS=$((PASS+1)); }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "=== T28: model-config helper ==="

# [1] config.yaml defaults to claude-opus-4.7
echo "[1] workspace defaults to claude-opus-4.7:"
v=$(bash .codenook/model-config.sh resolve T-001 clarifier 2>/dev/null)
[[ "$v" == "claude-opus-4.7" ]] && pass "no task → workspace default opus-4.7" || fail "expected opus-4.7, got: $v"

# [2] create a task with empty models, still resolves to workspace default
mkdir -p .codenook/tasks/T-001
cat > .codenook/tasks/T-001/state.json <<'JSON'
{"task_id":"T-001","status":"in_progress","models":{}}
JSON
v=$(bash .codenook/model-config.sh resolve T-001 implementer)
[[ "$v" == "claude-opus-4.7" ]] && pass "empty models block → workspace default" || fail "expected opus-4.7, got: $v"

# [3] set task-level override
bash .codenook/model-config.sh set T-001 implementer "claude-opus-4.6" >/dev/null
v=$(bash .codenook/model-config.sh resolve T-001 implementer)
[[ "$v" == "claude-opus-4.6" ]] && pass "set + resolve override" || fail "expected opus-4.6, got: $v"

# [4] subtask inherits from parent
v=$(bash .codenook/model-config.sh resolve T-001.2 implementer)
[[ "$v" == "claude-opus-4.6" ]] && pass "subtask inherits parent override" || fail "expected opus-4.6, got: $v"

# [5] role with no override falls back to workspace default
v=$(bash .codenook/model-config.sh resolve T-001 reviewer)
[[ "$v" == "claude-opus-4.7" ]] && pass "unset role → workspace default" || fail "expected opus-4.7, got: $v"

# [6] task-level default takes precedence over workspace per-role default
python3 -c "
import json
p='.codenook/tasks/T-001/state.json'
d=json.load(open(p)); d['models']['default']='gpt-5.4'; json.dump(d,open(p,'w'))
"
v=$(bash .codenook/model-config.sh resolve T-001 designer)
[[ "$v" == "gpt-5.4" ]] && pass "task default overrides workspace per-role" || fail "expected gpt-5.4, got: $v"

# [7] task per-role still wins over task default
v=$(bash .codenook/model-config.sh resolve T-001 implementer)
[[ "$v" == "claude-opus-4.6" ]] && pass "task per-role > task default" || fail "expected opus-4.6, got: $v"

# [8] unset removes override
bash .codenook/model-config.sh unset T-001 implementer >/dev/null
v=$(bash .codenook/model-config.sh resolve T-001 implementer)
[[ "$v" == "gpt-5.4" ]] && pass "unset → falls back to task default" || fail "expected gpt-5.4, got: $v"

# [9] list runs and shows all roles
out=$(bash .codenook/model-config.sh list T-001)
echo "$out" | grep -q "security-auditor" && pass "list includes security-auditor" || fail "list missing role"
echo "$out" | grep -q "session-distiller" && pass "list includes session-distiller" || fail "list missing role"

# [10] workspace per-role override (edit config.yaml) wins over default
sed -i '' 's/^  reviewer: claude-opus-4\.7$/  reviewer: claude-sonnet-4.5/' .codenook/config.yaml 2>/dev/null || \
  sed -i 's/^  reviewer: claude-opus-4\.7$/  reviewer: claude-sonnet-4.5/' .codenook/config.yaml
# remove task-default to force fallback to workspace
python3 -c "
import json
p='.codenook/tasks/T-001/state.json'
d=json.load(open(p)); d['models'].pop('default',None); json.dump(d,open(p,'w'))
"
v=$(bash .codenook/model-config.sh resolve T-001 reviewer)
[[ "$v" == "claude-sonnet-4.5" ]] && pass "workspace per-role override resolves" || fail "expected sonnet-4.5, got: $v"

# [11] platform-default sentinel — if every layer is missing, fall back gracefully
sed -i '' 's/^  acceptor: claude-opus-4\.7$/  acceptor: platform-default/' .codenook/config.yaml 2>/dev/null || \
  sed -i 's/^  acceptor: claude-opus-4\.7$/  acceptor: platform-default/' .codenook/config.yaml
v=$(bash .codenook/model-config.sh resolve T-001 acceptor)
[[ "$v" == "platform-default" ]] && pass "platform-default sentinel resolves literally" || fail "expected platform-default, got: $v"

echo
[[ $FAIL -eq 0 ]] && { echo "=== T28 PASSED ($PASS) ==="; exit 0; } || { echo "=== T28 FAILED ($FAIL) ==="; exit 1; }
