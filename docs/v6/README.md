# CodeNook v6 — Plugin Architecture Design (Draft)

These three Chinese-language documents capture the v6 plugin-architecture redesign. v6 is a design draft; the shipping product is still v5 (see `skills/codenook-v5-poc/`).

| File | Purpose | Lines |
|------|---------|-------|
| `architecture-v6.md` | Design — single-workspace plugin model, modularized memory/skills/config/history, model probe + tier symbols, 42 ratified decisions | ~1300 |
| `implementation-v6.md` | Implementation roadmap — 7 milestones (M1 kernel → M7 multi-plugin), file skeletons, v5→v6 migration map, DoD scripts | ~2000 |
| `test-plan-v6.md` | Test plan — 228 cases across 9 subsystems, risk matrix R-01..R-28, fixtures, automation strategy | ~1100 |

HTML renders are siblings (theme: `default`).

## Status

- Design: ratified (42 decisions, 0 open ambiguities)
- Implementation: not started
- Tests: planned, not authored

## Reading order

1. `architecture-v6.md` — start here
2. `implementation-v6.md` — per-milestone breakdown
3. `test-plan-v6.md` — verification matrix
