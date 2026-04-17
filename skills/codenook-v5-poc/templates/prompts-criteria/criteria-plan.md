# Planner Criteria (v5.0 POC)

A plan-phase output passes when **all** of:

## Structural (all required)

- [ ] Has a **Decomposition Rationale** section naming which trigger fired
- [ ] Has a **Subtask List** table with ≥ 2 and ≤ 8 subtasks
- [ ] Has a **Dependency Graph** section with per-subtask dependencies
- [ ] Has an **Integration Strategy** section
- [ ] Has a **Risks of Decomposition** section
- [ ] Has a **Depth Check** section stating current depth (1 or 2)
- [ ] Companion `dependency-graph.md` file written to `Graph_to`

## Content Quality

- [ ] Every subtask has a concrete id (`T-parent.N`), title, scope, primary_outputs, size
- [ ] Every subtask scope is independently testable (checkable precondition + postcondition)
- [ ] Every dependency references an id that exists in the subtask list
- [ ] No cycles in the dependency graph
- [ ] Max depth ≤ 2 (v5.0 POC hard cap)
- [ ] Integration Strategy names which subtask outputs feed parent integration

## Verdict Gate

- `decomposed` → orchestrator creates `subtasks/T-parent.N/` directories and runs each as a full task; parent waits for all to complete, then runs integration + tester + acceptor at parent level
- `not_needed` → orchestrator skips decomposition, dispatches single implementer pass
- `too_complex` → HITL: recommend re-clarify or re-scope before any implement

## Anti-Pattern Flags (these are failures)

- ❌ Subtask scope is a file list without behaviour ("modify utils.py" is not a scope)
- ❌ Dependency graph has cycles
- ❌ Integration Strategy absent or "TBD"
- ❌ Subtask count = 1 (that's not decomposition — return `not_needed` instead)
- ❌ Same file touched by multiple subtasks with no coordination note (write-conflict risk)
- ❌ Triggered on "context budget" but no size estimate for single-pass tokens
