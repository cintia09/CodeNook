#!/usr/bin/env bats
# v0.11.2 — DR-001/005/008/011 unit tests.
# Companion suites for the fix-pack landing in v0.11.2.

load helpers/load
load helpers/assertions

LIB_DIR="$CORE_ROOT/skills/builtin/_lib"

# ─────────────────────────────────────────────────────────────────────
# DR-001 — plugin_readonly.assert_writable_path with workspace_root=None
# ─────────────────────────────────────────────────────────────────────

@test "[v0.11.2] DR-001 None workspace_root falls back to CWD (write outside CWD allowed)" {
  scratch="$(make_scratch)"
  run python3 -c "
import os, sys
sys.path.insert(0, '$LIB_DIR')
import plugin_readonly
os.chdir('$scratch')
# Path lives outside CWD → should NOT raise (out of scope).
plugin_readonly.assert_writable_path('/etc/hosts')
print('ok')
"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"ok"* ]]
}

@test "[v0.11.2] DR-001 None workspace_root: write inside CWD outside plugins/ is allowed" {
  scratch="$(make_scratch)"
  mkdir -p "$scratch/.codenook/memory"
  run python3 -c "
import os, sys
sys.path.insert(0, '$LIB_DIR')
import plugin_readonly
os.chdir('$scratch')
plugin_readonly.assert_writable_path('$scratch/.codenook/memory/k.md')
print('ok')
"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"ok"* ]]
}

@test "[v0.11.2] DR-001 None workspace_root: write inside CWD/plugins/ still rejected" {
  scratch="$(make_scratch)"
  mkdir -p "$scratch/.codenook/plugins/development"
  run python3 -c "
import os, sys
sys.path.insert(0, '$LIB_DIR')
import plugin_readonly
os.chdir('$scratch')
try:
    plugin_readonly.assert_writable_path('$scratch/.codenook/plugins/development/x.md')
    print('LEAK')
except plugin_readonly.PluginReadOnlyViolation:
    print('blocked')
"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"blocked"* ]]
}

@test "[v0.11.2] DR-001 absolute path containing 'plugins' segment OUTSIDE CWD is NOT rejected" {
  # Reproduces the over-block bug: previously a write under
  # /Users/foo/plugins-monorepo/.codenook/... would fire when called with
  # workspace_root=None even though it is unrelated to our workspace.
  scratch="$(make_scratch)"
  ext="$(make_scratch)/plugins/inside/file.md"
  mkdir -p "$(dirname "$ext")"
  run python3 -c "
import os, sys
sys.path.insert(0, '$LIB_DIR')
import plugin_readonly
os.chdir('$scratch')
plugin_readonly.assert_writable_path('$ext')
print('ok')
"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"ok"* ]]
}

# ─────────────────────────────────────────────────────────────────────
# DR-005 — secret_scan extended ruleset
# ─────────────────────────────────────────────────────────────────────

scan_hit() {
  python3 -c "
import sys; sys.path.insert(0, '$LIB_DIR')
import secret_scan
hit, rule = secret_scan.scan_secrets('''$1''')
print('HIT' if hit else 'MISS', rule or '-')
"
}

@test "[v0.11.2] DR-005 JWT token detected" {
  out="$(scan_hit 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c')"
  [[ "$out" == HIT\ jwt* ]]
}

@test "[v0.11.2] DR-005 JWT-shaped clean text (just three dots) is NOT flagged" {
  out="$(scan_hit 'a.b.c is short')"
  [[ "$out" == MISS* ]]
}

@test "[v0.11.2] DR-005 Google API key (AIza prefix + 35) detected" {
  out="$(scan_hit 'GOOGLE_API_KEY=AIzaBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB')"
  [[ "$out" == HIT\ google-api-key* ]]
}

@test "[v0.11.2] DR-005 Google plain 'AIza' tag is NOT flagged" {
  out="$(scan_hit 'this is just AIza without the rest')"
  [[ "$out" == MISS* ]]
}

@test "[v0.11.2] DR-005 Slack bot token detected" {
  out="$(scan_hit 'token: xoxb-1234567890-abcdefghij')"
  [[ "$out" == HIT\ slack-token* ]]
}

@test "[v0.11.2] DR-005 generic Authorization Bearer header detected" {
  out="$(scan_hit 'Authorization: Bearer abcdef0123456789abcdef0123456789')"
  [[ "$out" == HIT\ auth-bearer* ]]
}

@test "[v0.11.2] DR-005 short Bearer token (< 20 chars) is NOT flagged" {
  out="$(scan_hit 'Authorization: Bearer short123')"
  [[ "$out" == MISS* ]]
}

@test "[v0.11.2] DR-005 GitHub server PAT (ghs_) detected" {
  out="$(scan_hit 'creds: ghs_abcdefghijklmnopqrstuvwxyz0123456789')"
  [[ "$out" == HIT\ github-pat* ]]
}

@test "[v0.11.2] DR-005 GitHub fine-grained PAT (github_pat_) detected" {
  out="$(scan_hit 'token=github_pat_11ABCDEFG0_abcdefghijklmnop')"
  [[ "$out" == HIT\ github-pat-finegrained* ]]
}

@test "[v0.11.2] DR-005 OpenAI key still detected (regression)" {
  out="$(scan_hit 'sk-abcdefghijklmnopqrstuvwxyz0123456789')"
  [[ "$out" == HIT\ openai-key* ]]
}

@test "[v0.11.2] DR-005 secret_scan CLI exits 1 on hit, 0 on clean" {
  scratch="$(make_scratch)"
  echo "Authorization: Bearer abcdef0123456789abcdef0123456789" > "$scratch/dirty.txt"
  echo "all clean here" > "$scratch/clean.txt"
  run python3 "$LIB_DIR/secret_scan.py" "$scratch/clean.txt"
  [ "$status" -eq 0 ]
  run python3 "$LIB_DIR/secret_scan.py" "$scratch/dirty.txt"
  [ "$status" -eq 1 ]
}

# ─────────────────────────────────────────────────────────────────────
# DR-008 — preflight loads phase whitelist from plugin manifest
# ─────────────────────────────────────────────────────────────────────

@test "[v0.11.2] DR-008 preflight reads phases.yaml from active plugin" {
  scratch="$(make_scratch)"
  ws="$scratch/ws"
  mkdir -p "$ws/.codenook/plugins/myplug" "$ws/.codenook/tasks/T-001"
  cat > "$ws/.codenook/plugins/myplug/phases.yaml" <<'YML'
phases:
  - id: clarify
  - id: design
  - id: implement
YML
  cat > "$ws/.codenook/state.json" <<'JSON'
{"installed_plugins":[{"id":"myplug","version":"0.1.0"}]}
JSON
  cat > "$ws/.codenook/tasks/T-001/state.json" <<'JSON'
{"phase":"design","total_iterations":2,"dual_mode":"serial"}
JSON
  CN_TASK=T-001 \
  CN_STATE_FILE="$ws/.codenook/tasks/T-001/state.json" \
  CN_WORKSPACE="$ws" \
  CN_JSON=1 \
    run python3 "$CORE_ROOT/skills/builtin/preflight/_preflight.py"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  echo "$output" | python3 -c "
import json,sys
d = json.loads(sys.stdin.read())
assert d['ok'] is True, d
assert 'unknown_phase' not in ' '.join(d['reasons']), d
"
}

@test "[v0.11.2] DR-008 preflight rejects phase NOT listed in manifest" {
  scratch="$(make_scratch)"
  ws="$scratch/ws"
  mkdir -p "$ws/.codenook/plugins/myplug" "$ws/.codenook/tasks/T-001"
  cat > "$ws/.codenook/plugins/myplug/phases.yaml" <<'YML'
phases:
  - id: clarify
  - id: design
YML
  cat > "$ws/.codenook/state.json" <<'JSON'
{"installed_plugins":[{"id":"myplug","version":"0.1.0"}]}
JSON
  cat > "$ws/.codenook/tasks/T-001/state.json" <<'JSON'
{"phase":"this-phase-does-not-exist","total_iterations":2,"dual_mode":"serial"}
JSON
  CN_TASK=T-001 \
  CN_STATE_FILE="$ws/.codenook/tasks/T-001/state.json" \
  CN_WORKSPACE="$ws" \
  CN_JSON=1 \
    run python3 "$CORE_ROOT/skills/builtin/preflight/_preflight.py"
  [ "$status" -eq 1 ]
  [[ "$output" == *unknown_phase* ]]
}

@test "[v0.11.2] DR-008 preflight legacy fallback still accepts 'implement' when no plugin" {
  scratch="$(make_scratch)"
  ws="$scratch/ws"
  mkdir -p "$ws/.codenook/tasks/T-001"
  cat > "$ws/.codenook/tasks/T-001/state.json" <<'JSON'
{"phase":"implement","total_iterations":2,"dual_mode":"serial"}
JSON
  CN_TASK=T-001 \
  CN_STATE_FILE="$ws/.codenook/tasks/T-001/state.json" \
  CN_WORKSPACE="$ws" \
  CN_JSON=1 \
    run python3 "$CORE_ROOT/skills/builtin/preflight/_preflight.py"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  echo "$output" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
assert d['ok'] is True, d
"
}

# ─────────────────────────────────────────────────────────────────────
# DR-011 — memory_index._write_snapshot cleans up its .lock file
# ─────────────────────────────────────────────────────────────────────

@test "[v0.11.2] DR-011 .lock file is removed after successful snapshot write" {
  scratch="$(make_scratch)"
  mem="$scratch/.codenook/memory"
  mkdir -p "$mem/knowledge"
  cat > "$mem/knowledge/k1.md" <<'MD'
---
title: hello
---
body
MD
  run python3 -c "
import sys; sys.path.insert(0, '$LIB_DIR')
import memory_index
memory_index.build_index('$scratch')
print('ok')
"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"ok"* ]]
  # snapshot present; .lock cleaned up
  [ -f "$mem/.index-snapshot.json" ]
  [ ! -f "$mem/.index-snapshot.json.lock" ] || { echo ".lock still present"; ls -la "$mem"; return 1; }
}
