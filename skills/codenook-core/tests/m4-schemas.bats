#!/usr/bin/env bats
# M4.U1 — JSON Schemas validate canonical fixture documents.

load helpers/load
load helpers/assertions

SCHEMAS_DIR="$CORE_ROOT/schemas"
FIX="$FIXTURES_ROOT/m4"
VALIDATOR="$CORE_ROOT/skills/builtin/_lib/jsonschema_lite.py"

# Run the lite validator: validator.py <schema> <doc> → exit 0 valid / 1 invalid
validate() {
  python3 "$VALIDATOR" "$1" "$2"
}

@test "schemas/ directory contains the four M4 schemas" {
  assert_file_exists "$SCHEMAS_DIR/task-state.schema.json"
  assert_file_exists "$SCHEMAS_DIR/queue-entry.schema.json"
  assert_file_exists "$SCHEMAS_DIR/hitl-entry.schema.json"
  assert_file_exists "$SCHEMAS_DIR/locks-entry.schema.json"
}

@test "every schema is draft-07 with additionalProperties:false on root" {
  for s in task-state queue-entry hitl-entry locks-entry; do
    f="$SCHEMAS_DIR/$s.schema.json"
    jq -e '."$schema" == "http://json-schema.org/draft-07/schema#"' "$f" >/dev/null
    jq -e '.additionalProperties == false' "$f" >/dev/null
  done
}

@test "jsonschema_lite supports type/required/properties/additionalProperties/enum/minimum" {
  assert_file_exists "$VALIDATOR"
  run python3 -c "
import sys; sys.path.insert(0, '$(dirname "$VALIDATOR")')
from jsonschema_lite import validate
schema = {'type':'object','required':['a'],'additionalProperties':False,
          'properties':{'a':{'type':'integer','minimum':1},
                        'b':{'enum':['x','y']}}}
validate({'a':1,'b':'x'}, schema)
try:
    validate({'a':0,'b':'x'}, schema); print('NO')
except Exception: print('OK1')
try:
    validate({'a':1,'b':'z'}, schema); print('NO')
except Exception: print('OK2')
try:
    validate({'a':1,'c':1}, schema); print('NO')
except Exception: print('OK3')
try:
    validate({'b':'x'}, schema); print('NO')
except Exception: print('OK4')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *OK1* ]]
  [[ "$output" == *OK2* ]]
  [[ "$output" == *OK3* ]]
  [[ "$output" == *OK4* ]]
}

@test "task-state.schema validates the canonical state.json fixture" {
  run validate "$SCHEMAS_DIR/task-state.schema.json" "$FIX/state-valid.json"
  [ "$status" -eq 0 ]
}

@test "task-state.schema rejects unknown top-level key" {
  tmp="$BATS_TEST_TMPDIR/bad.json"
  jq '. + {"unexpected":"x"}' "$FIX/state-valid.json" >"$tmp"
  run validate "$SCHEMAS_DIR/task-state.schema.json" "$tmp"
  [ "$status" -ne 0 ]
}

@test "task-state.schema rejects bad status enum" {
  tmp="$BATS_TEST_TMPDIR/bad.json"
  jq '.status="weird"' "$FIX/state-valid.json" >"$tmp"
  run validate "$SCHEMAS_DIR/task-state.schema.json" "$tmp"
  [ "$status" -ne 0 ]
}

@test "task-state.schema accepts phase=null (initial)" {
  tmp="$BATS_TEST_TMPDIR/init.json"
  jq '.phase=null | .iteration=0 | del(.in_flight_agent) | .history=[]' \
     "$FIX/state-valid.json" >"$tmp"
  run validate "$SCHEMAS_DIR/task-state.schema.json" "$tmp"
  [ "$status" -eq 0 ]
}

@test "queue-entry.schema validates the canonical queue.json fixture" {
  run validate "$SCHEMAS_DIR/queue-entry.schema.json" "$FIX/queue-valid.json"
  [ "$status" -eq 0 ]
}

@test "queue-entry.schema rejects negative priority" {
  tmp="$BATS_TEST_TMPDIR/bad.json"
  jq '.priority=-1' "$FIX/queue-valid.json" >"$tmp"
  run validate "$SCHEMAS_DIR/queue-entry.schema.json" "$tmp"
  [ "$status" -ne 0 ]
}

@test "hitl-entry.schema validates the canonical hitl.json fixture (decision=null)" {
  run validate "$SCHEMAS_DIR/hitl-entry.schema.json" "$FIX/hitl-valid.json"
  [ "$status" -eq 0 ]
}

@test "hitl-entry.schema accepts decided entry (approve)" {
  tmp="$BATS_TEST_TMPDIR/decided.json"
  jq '.decision="approve" | .decided_at="2026-04-18T12:00:00Z" | .reviewer="alice"' \
     "$FIX/hitl-valid.json" >"$tmp"
  run validate "$SCHEMAS_DIR/hitl-entry.schema.json" "$tmp"
  [ "$status" -eq 0 ]
}

@test "hitl-entry.schema rejects bad decision enum" {
  tmp="$BATS_TEST_TMPDIR/bad.json"
  jq '.decision="maybe"' "$FIX/hitl-valid.json" >"$tmp"
  run validate "$SCHEMAS_DIR/hitl-entry.schema.json" "$tmp"
  [ "$status" -ne 0 ]
}

@test "locks-entry.schema validates the canonical lock fixture" {
  run validate "$SCHEMAS_DIR/locks-entry.schema.json" "$FIX/lock-valid.json"
  [ "$status" -eq 0 ]
}

@test "locks-entry.schema rejects ttl_sec=0" {
  tmp="$BATS_TEST_TMPDIR/bad.json"
  jq '.ttl_sec=0' "$FIX/lock-valid.json" >"$tmp"
  run validate "$SCHEMAS_DIR/locks-entry.schema.json" "$tmp"
  [ "$status" -ne 0 ]
}
