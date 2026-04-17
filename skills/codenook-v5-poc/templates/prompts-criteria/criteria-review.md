# Review Criteria (v5.0 POC)

Use this as a checklist when reviewing an Implementer's output.

## Critical (blocker)

- [ ] Output addresses the task description's stated goal
- [ ] Code compiles / runs without syntax errors (if applicable)
- [ ] No secrets, credentials, or internal IPs committed
- [ ] No obvious data loss, race condition, or resource leak
- [ ] External contracts (APIs, schemas) are not silently broken

## Important (major)

- [ ] Error paths are handled (not just happy path)
- [ ] Follows `CONVENTIONS.md` (naming, structure, style)
- [ ] Fits `ARCHITECTURE.md` (module boundaries, dependencies)
- [ ] Tests or validation path exists or is explicitly deferred with reason
- [ ] Public interfaces are documented at the level the project expects

## Nice-to-have (minor)

- [ ] Comments explain *why* for non-obvious decisions
- [ ] No duplicated blocks of logic
- [ ] Uses existing utilities rather than re-inventing

## Review Output Rules

- Each issue gets a stable id (R1, R2, …) per review — keep same id across iterations if the same issue persists.
- Severity: `blocker` | `major` | `minor` — only `blocker` or `major` can fail the review.
- Never list more than 10 issues per iteration; if more, consolidate or flag "fundamental_problems".

## Overall Verdict Mapping

- `looks_good` — zero blockers, zero majors (minors OK)
- `needs_fixes` — ≥ 1 major, no fundamental rethink needed
- `fundamental_problems` — approach itself is wrong; do NOT iterate further, escalate to HITL
