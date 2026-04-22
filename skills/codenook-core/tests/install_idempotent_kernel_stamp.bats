#!/usr/bin/env bats
# E2E-P-001 — re-install (idempotent path) must also stamp the correct
# kernel_version. v0.11.4 round-2.

load helpers/load
load helpers/assertions

ROOT_VERSION="$(cat "$REPO_ROOT/VERSION" | tr -d '[:space:]')"

@test "[v0.11.4 E2E-P-001] re-install keeps kernel_version aligned with VERSION" {
  ws="$(make_scratch)"
  codenook_install "$ws" --plugin development >/dev/null 2>&1
  codenook_install "$ws" --plugin development >/dev/null 2>&1
  kv="$(python3 -c "import json; print(json.load(open('$ws/.codenook/state.json'))['kernel_version'])")"
  [ "$kv" = "$ROOT_VERSION" ] || { echo "got=$kv want=$ROOT_VERSION"; return 1; }
}
