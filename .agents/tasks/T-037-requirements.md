# T-037 Requirements: E2E Test for 3-Phase FSM Validation

## User Story
As a framework maintainer, I want comprehensive E2E tests for the 3-Phase FSM
so that I can verify all state transitions, gates, and safety limits work correctly.

## Functional Requirements

### FR-1: Legal Transition Validation
- Test all 26 legal 3-Phase transitions (Phase 1→2→3→accepted)
- Each transition should succeed without error
- Task status should update correctly in task-board.json
- Events should be logged to events.db

### FR-2: Illegal Transition Blocking
- Attempt illegal transitions (e.g., `requirements → implementing`, `tdd_design → accepted`)
- Verify hook returns block response
- Verify task status does NOT change

### FR-3: Convergence Gate
- Set parallel_tracks with incomplete tracks
- Attempt `ci_monitoring → device_baseline`
- Verify gate blocks transition
- Set all tracks to complete + ci_monitoring to green
- Verify gate allows transition

### FR-4: Feedback Loop Counter
- Execute a feedback transition (e.g., `regression_testing → implementing`)
- Verify feedback_loops increments by 1
- Verify feedback_history gets new entry with from/to/timestamp/reason

### FR-5: Auto-Block Safety
- Set feedback_loops to 9
- Execute one more feedback transition
- Verify feedback_loops becomes 10
- Attempt another feedback transition
- Verify task is auto-blocked (status = blocked)

## Non-Functional Requirements
- Tests must run via `bash tests/test-3phase-fsm.sh`
- Tests must be idempotent (clean up after themselves)
- Tests must use a temporary task-board.json (not the real one)
- All tests must complete in < 30 seconds

## Acceptance Criteria
- [ ] All 5 goals pass
- [ ] Test script exits 0 on success, 1 on failure
- [ ] No side effects on real project state
