# CodeNook v6 — Plugin Architecture Design

These three Chinese-language documents capture the v6 plugin-architecture redesign. v6 has been **implemented in v0.10 / v0.11** (`skills/codenook-core/` + `plugins/`); the v5 monolithic PoC has been removed from the repo as of v0.11.1.

| File | Purpose | Lines |
|------|---------|-------|
| `architecture-v6.md` | Design — single-workspace plugin model, modularized memory/skills/config/history, model probe + tier symbols, 42 ratified decisions | ~1300 |
| `implementation-v6.md` | Implementation roadmap — 7 milestones (M1 kernel → M7 multi-plugin), file skeletons, v5→v6 migration map (historical), DoD scripts | ~2000 |
| `test-plan-v6.md` | Test plan — 228 cases across 9 subsystems, risk matrix R-01..R-28, fixtures, automation strategy | ~1100 |

HTML renders are siblings (theme: `default`).

## Status

- Design: ratified (42 decisions, 0 open ambiguities)
- Implementation: **delivered in v0.10 / v0.11** (M1–M11 shipped)
- Tests: 851 bats assertions live under `skills/codenook-core/tests/`

## Reading order

1. `architecture-v6.md` — start here
2. `implementation-v6.md` — per-milestone breakdown
3. `test-plan-v6.md` — verification matrix
