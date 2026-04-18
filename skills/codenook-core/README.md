# codenook-core (v6 kernel skeleton)

This package is the **v6 internal kernel** for CodeNook: shell loader, builtin
agents/skills, and the `init.sh` installer/plugin-manager dispatcher.

It is **not** a drop-in replacement for the v5 PoC (`skills/codenook-v5-poc/`).
v5 remains the working end-to-end reference until v6 reaches feature parity
(see `docs/v6/implementation-v6.md` milestones M1–M7).

## Layout (M1)

```
init.sh                     command dispatcher (--install-plugin, --refresh-models, …)
VERSION                     semver of the core skeleton
core/shell.md               main session loader (≤3K hard limit)
agents/                     builtin agent profiles (router, distiller, security-auditor, hitl-adapter, config-mutator)
skills/builtin/
  config-resolve/           4-layer deep-merge + model symbol expansion
  config-validate/          field-level type/range validation of merged configs
  model-probe/              capability discovery + tier resolution
  secrets-resolve/          ${env:...} / ${file:...} placeholder resolution
  sec-audit/                pre-tick workspace security scanner
  dispatch-audit/           redacted append-only dispatch logger (500-char cap)
  preflight/                pre-tick sanity check (dual_mode, phase, HITL queue, config overrides)
  task-config-set/          Layer-4 override writer (task-level model config)
  queue-runner/             generic FIFO queue with file locking
  orchestrator-tick/        task state machine advancement
  session-resume/           session state summary (≤1KB)
tests/                      bats-core test suites (run: `bats tests/`)
```

## Status

- M1.1 — init.sh skeleton, shell.md, config-resolve, model-probe
- M1.2 — config-validate, secrets-resolve, sec-audit, dispatch-audit
- M1.3 — preflight, task-config-set, queue-runner, orchestrator-tick, session-resume + 5 agent profiles
- M1.4 — post-review fix pass (this drop): nested-dict overrides, exact-match preflight whitelist, dual_mode threshold direction, dispatch-audit secret redaction, broadened sec-audit patterns, atomic state.json writes, expanded KNOWN_TOP_KEYS, secrets-resolve SECURITY note
- M1.5+ — pending (see implementation doc §M1)

## Running tests

```bash
cd skills/codenook-core
bats tests/
```

Requires: bash, jq, python3 (with PyYAML), bats-core ≥ 1.5.
