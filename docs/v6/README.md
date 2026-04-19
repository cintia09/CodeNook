# CodeNook v6 — Design Docs Index

The v6 plugin architecture is the design line that ships in v0.11. The kernel
lives at `skills/codenook-core/`, the canonical pipeline plugin at
`plugins/development/`, and the per-workspace runtime at `.codenook/`.

This directory is the **design + verification archive** for that line:

- 9 design documents (architecture, implementation, router-agent, memory &
  extraction, task chains, test plan, M9 / M10 test cases, M11 decisions),
- 1 requirements document (~70 FR / NFR),
- 1 acceptance test catalog (117 ATs),
- 1 acceptance execution report (100 PASS / 13 PARTIAL / 4 SKIP),
- 2 release / cleanup reports (v0.11.0 release, v0.11.1 surface cleanup).

## Reading order for new contributors

1. **`architecture-v6.md`** — start here. The 42 ratified decisions; the
   single-workspace plugin model; the modularised memory / skills / config /
   history layout; the model-tier symbol resolution.
2. **`router-agent-v6.md`** — the per-turn entry point. Spawn / render-prompt
   / draft-config contract; how the router is the *sole* domain-aware
   component on the task-creation side.
3. **`memory-and-extraction-v6.md`** — the after-phase loop. Patch-or-create
   policy, per-task caps (3 / 1 / 5), 80% water-mark, distiller promotion.
4. **`task-chains-v6.md`** — parent suggestion (Jaccard top-3) and chain
   summarisation (two-pass LLM compression, ≤8K token budget).
5. **`implementation-v6.md`** — milestone-by-milestone roadmap (M1 kernel →
   M11 spec consolidation), file skeletons, DoD scripts.
6. **`test-plan-v6.md`** — 228 cases across 9 subsystems, risk matrix
   R-01..R-28, fixtures, automation strategy.
7. **`requirements-v0.10.md`** — ~70 FR / NFR (1162 lines).
8. **`acceptance-v0.10.md`** — 117 acceptance tests (1397 lines).
9. **`acceptance-execution-report-v0.10.md`** — execution result per AT
   (100 PASS / 13 PARTIAL / 4 SKIP).
10. **`m9-test-cases.md`** / **`m10-test-cases.md`** — milestone-specific
    test catalogs.
11. **`m11-decisions.md`** — the 21-item decision list closed in v0.11.0
    (16 SPEC-PATCH + 2 CODE-FIX + 2 DELETE-DEAD-CODE + 6 DEFER-v0.12 + 1 no-op).
12. **`v011-release-report.md`** / **`v0111-cleanup-report.md`** — what
    actually shipped in v0.11.0 and v0.11.1.

## Document index

| Doc | Purpose | Status | Lines |
|-----|---------|--------|------:|
| `architecture-v6.md` | Plugin architecture design — 42 ratified decisions | **ratified · implemented** | 1633 |
| `implementation-v6.md` | Milestone roadmap (M1 → M11), file skeletons, DoD scripts | **ratified · implemented** | 2727 |
| `router-agent-v6.md` | Router-agent specification (per-turn entry point) | **ratified · implemented** | 640 |
| `memory-and-extraction-v6.md` | Memory layer + extraction policy + water-marks | **ratified · implemented** | 882 |
| `task-chains-v6.md` | Parent suggestion + chain summarisation | **ratified · implemented** | 1138 |
| `test-plan-v6.md` | 228 cases × 9 subsystems · risk matrix R-01..R-28 | **ratified · implemented** | 1140 |
| `m9-test-cases.md` | M9 (memory + extraction) test catalog | **implemented** | 1076 |
| `m10-test-cases.md` | M10 (task chains) test catalog | **implemented** | 1075 |
| `m11-decisions.md` | M11 backlog decisions (21 items) | **closed (v0.11.0)** | 91 |
| `requirements-v0.10.md` | ~70 FR / NFR + §A.1 / §A.2 reconciliation tables | **ratified** | 1162 |
| `acceptance-v0.10.md` | 117 acceptance tests | **ratified** | 1397 |
| `acceptance-execution-report-v0.10.md` | Execution result per AT (100 / 13 / 4) | **executed (v0.11.0)** | 262 |
| `v011-release-report.md` | v0.11.0 release report (Spec Consolidation & Cleanup) | **shipped** | 171 |
| `v0111-cleanup-report.md` | v0.11.1 surface cleanup report | **shipped** | 201 |

HTML renders are siblings of each `.md` (theme: `default`).

## Status snapshot (v0.11.1)

| Metric | Value |
|--------|------:|
| Bats assertions | **851 / 851** |
| Acceptance tests | **100 PASS / 13 PARTIAL / 4 SKIP** (of 117) |
| Milestones shipped | **M1 → M11** |
| Open ambiguities in design | **0** |
| Items deferred to v0.12 | **6** (A1-6, MEDIUM-04, AT-REL-1, AT-LLM-2.1, AT-COMPAT-1, AT-COMPAT-3) |

The 6 deferred items are scoped in `v011-release-report.md` §3 and tracked
against the `session-resume schema v2` epic and the multi-process orchestration
epic for v0.12.

## Relationship to top-level docs

- [`../../README.md`](../../README.md) — user-facing entry point.
- [`../../PIPELINE.md`](../../PIPELINE.md) — runtime pipeline reference (kernel
  + plugin behaviour at execution time).
- [`../../CHANGELOG.md`](../../CHANGELOG.md) — release history.
- [`../../skills/codenook-core/README.md`](../../skills/codenook-core/README.md)
  — kernel package overview (subsystems, builtin skills, init.sh).
- [`../../plugins/development/README.md`](../../plugins/development/README.md)
  — development plugin overview (8 phases, verdict contract, validators).
