# Design Criteria (v5.0 POC)

A design-phase output passes when **all** of:

## Structural (all required)

- [ ] Has an **Overview** section with ≤ 3 sentences restating the clarified goal
- [ ] Has a **Module Layout** section listing files to create/modify/delete
- [ ] Has an **Interfaces** section with at least one concrete signature
- [ ] Has a **Data Model** section (may be "no persistent data" if truly none)
- [ ] Has a **Control Flow** section with numbered steps for the primary scenario
- [ ] Has an **Error & Edge Handling** section
- [ ] Has a **Testing Strategy** section that maps back to clarify acceptance criteria
- [ ] Has a **Risks & Mitigations** section (may be empty only if explicitly "no engineering risks")

## Content Quality

- [ ] Every interface signature includes input and output shapes
- [ ] Module Layout paths are concrete (no `...` or "TBD")
- [ ] Control Flow steps are numbered and each step is a single action
- [ ] Testing Strategy names specific test types (unit/integration/smoke/static), not just "tests"
- [ ] No acceptance criterion from clarify is left without a testing strategy entry

## Verdict Gate

- `design_ready` → pass design phase, advance to implement
- `needs_user_input` → route to HITL before any implementer dispatch
- `infeasible` → HITL with strong recommendation to re-scope task

## Anti-Pattern Flags (these are failures)

- ❌ Module Layout uses vague names like `utils.py` without purpose
- ❌ Interfaces are verbs ("send email") instead of signatures (`send_email(to: str, body: str) -> MessageId`)
- ❌ Control Flow reads like prose ("then we do X") instead of numbered imperative steps
- ❌ Testing Strategy says "will be tested" without naming how
- ❌ Design silently dropped a clarify acceptance criterion
- ❌ Design introduces a dependency not listed in ENVIRONMENT.md without a Risk entry
