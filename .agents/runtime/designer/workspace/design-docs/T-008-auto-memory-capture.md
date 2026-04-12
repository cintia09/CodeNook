# T-008: Auto Capture Memory on Phase Transition

## Context

In the current multi-agent framework, saving memory requires the Agent to manually invoke the "save memory" operation of the `agent-memory` skill. This leads to two problems:
1. Agents often forget to save memory, causing critical context to be lost during handoff
2. Manually saved memories vary in quality and lack standardized structure

FSM state transitions (e.g., designing → implementing) are natural trigger points for saving memory — at that point the Agent has completed its phase work and all key information is in context.

## Decision

Add FSM state transition detection logic in the `agent-post-tool-use.sh` hook: when a task status change is detected in `task-board.json`, automatically trigger a memory snapshot save. Memory content is automatically extracted from the current Agent context and written in the standardized `T-NNN-memory.json` format.

## Alternatives Considered

| Option | Pros | Cons | Decision |
|--------|------|------|----------|
| **A: Hook detection + auto save (selected)** | Fully automatic, no Agent cooperation needed | Hook script complexity increases | ✅ Selected |
| **B: Require manual save in SKILL.md** | Simple to implement | Relies on Agent compliance, easy to miss | ❌ Unreliable |
| **C: Periodic auto save** | Not dependent on state transitions | May save meaningless intermediate states, wasting storage | ❌ Wrong granularity |
| **D: Save on Agent-switch** | Clear timing | Only covers switch scenarios, not intra-Agent state changes | ❌ Incomplete coverage |

## Design

### Architecture

```
┌─────────────────────────────────────────────────────┐
│  Agent executes tool (edit/bash/write)               │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│  agent-post-tool-use.sh                             │
│  ├── Existing: log to events.db                     │
│  ├── Existing: AUTO-DISPATCH (detect change→message)│
│  └── New: AUTO-MEMORY-CAPTURE                       │
│       ├── Compare task-board.json before/after state │
│       ├── If state changed → generate memory extract │
│       └── Write to .agents/memory/T-NNN-memory.json  │
└─────────────────────────────────────────────────────┘
```

**Trigger mechanism**:
1. `agent-post-tool-use.sh` already has logic to detect `task-board.json` writes (for AUTO-DISPATCH)
2. At the same detection point, add: when a status field change is detected, output memory capture instructions

**Memory extraction strategy**:
- Hook scripts cannot directly access Agent context (they are shell scripts)
- Option: Hook outputs a JSON instruction to stdout, Copilot framework reads it and executes memory extraction
- Or: Define an "auto capture" trigger convention in `agent-memory SKILL.md`, having the Agent extract memory immediately after executing a state transition

**Practical feasible approach**: Since hooks are shell scripts and cannot directly manipulate LLM context, a **hybrid approach** is used:
1. Hook detects state change, records a `memory_capture_needed` event in `events.db`
2. Hook's stdout returns a prompt message telling the Agent "please save memory immediately"
3. `agent-memory SKILL.md` adds an "Auto-Capture" section defining a standardized extraction template
4. Agent extracts and saves per the template — the entire process is transparent to the user, no manual invocation needed

### Data Model

**Memory snapshot format** (extends existing `T-NNN-memory.json`):

```json
{
  "task_id": "T-008",
  "version": 2,
  "auto_captured": true,
  "capture_trigger": "designing → implementing",
  "captured_at": "2026-04-06T15:00:00Z",
  "captured_by": "designer",
  "stages": {
    "designing": {
      "summary": "Designed an auto memory capture mechanism...",
      "decisions": [
        "Adopted a hybrid approach of hook detection + Agent extraction",
        "Memory format is compatible with existing T-NNN-memory.json"
      ],
      "artifacts": [
        ".agents/runtime/designer/workspace/design-docs/T-008-auto-memory-capture.md"
      ],
      "files_modified": [
        "hooks/agent-post-tool-use.sh",
        "skills/agent-memory/SKILL.md"
      ],
      "issues_encountered": [
        "Hook is a shell script and cannot directly access LLM context"
      ],
      "handoff_notes": "Implementer should first modify the hook script, then update SKILL.md"
    }
  }
}
```

**New event type in events.db**:
```sql
INSERT INTO events (type, agent, task_id, detail, timestamp)
VALUES ('memory_capture_needed', 'designer', 'T-008', 
        '{"from_status":"designing","to_status":"implementing"}', 
        datetime('now'));
```

### API / Interface

**Hook output (new)**:

When a state change is detected, hook outputs a prompt on stderr:
```
[AUTO-MEMORY] Task T-008 state changed: designing → implementing
[AUTO-MEMORY] Please save memory per the agent-memory SKILL.md "Auto-Capture" template
```

**New section in agent-memory SKILL.md**:

```markdown
### Auto-Capture

After you complete your phase work and transition the FSM state, you **must immediately** perform the following memory save:

#### Extraction Template
Extract the following fields from the current working context:
- **summary**: One-sentence summary of work completed in this phase
- **decisions**: Key technical decisions made in this phase (list)
- **artifacts**: File paths of artifacts produced in this phase (list)
- **files_modified**: File paths modified in this phase (list)
- **issues_encountered**: Problems encountered and solutions (list)
- **handoff_notes**: Key handoff points for the downstream Agent

#### Save Operation
Write the extracted content to `.agents/memory/T-NNN-memory.json`, setting `auto_captured: true`.
```

### Implementation Steps

1. **Modify `hooks/agent-post-tool-use.sh`**:
   - In the existing `task-board.json` write detection logic (around lines 40-60), add before/after state comparison
   - When a `status` field change is detected, record a `memory_capture_needed` event to `events.db`
   - Output `[AUTO-MEMORY]` prompt to stderr

2. **Create memory directory**:
   - Ensure `.agents/memory/` directory exists (create if not present)

3. **Update `skills/agent-memory/SKILL.md`**:
   - Add an "Auto-Capture" section after the existing operation list
   - Include extraction template (6 fields)
   - Include save operation instructions
   - Explicitly state: Agent must automatically execute this operation after state transition, no user trigger needed

4. **Cache previous task-board.json state in hook**:
   - Hook reads current `task-board.json` on execution, compares with previous cache
   - Cache location: `.agents/runtime/.task-board-cache.json`
   - On first run with no cache, skip detection

5. **Verify compatibility of auto-dispatch and auto-memory**:
   - Both trigger on state changes, ensure correct execution order
   - First auto-memory (save current Agent memory), then auto-dispatch (notify downstream Agent)

6. **Update `.gitignore`**:
   - Add `.agents/runtime/.task-board-cache.json` (temporary cache should not be committed)

## Test Spec

### Unit Tests

| # | Test Scenario | Expected Result |
|---|--------------|-----------------|
| 1 | Modify task status in task-board.json from designing → implementing | Hook outputs `[AUTO-MEMORY]` prompt, events.db records `memory_capture_needed` |
| 2 | Modify non-status field in task-board.json (e.g., priority) | Does not trigger auto-memory |
| 3 | First run (no cache file) | Does not trigger auto-memory, creates cache |
| 4 | Write with same status unchanged (e.g., implementing → implementing) | Does not trigger auto-memory |

### Integration Tests

| # | Test Scenario | Expected Result |
|---|--------------|-----------------|
| 5 | Full flow: Agent completes design → updates status → auto saves memory | `.agents/memory/T-NNN-memory.json` contains `auto_captured: true` |
| 6 | Auto-memory + Auto-dispatch both trigger | Memory saved first, then dispatch message sent, no conflicts |
| 7 | agent-memory SKILL.md format validation | Contains "Auto-Capture" section, template contains 6 required fields |

### Acceptance Criteria

- [ ] G1: Hook detects FSM state transition and triggers memory save
- [ ] G2: Memory snapshot contains summary, decisions, files_modified, issues_encountered, handoff_notes
- [ ] G3: agent-memory SKILL.md contains "Auto-Capture" section
- [ ] G4: Entire process requires no manual "save memory" invocation

## Consequences

**Positive**:
- Agent handoffs always have context available, no more losing critical information
- Standardized memory format, downstream Agents can reliably parse
- Synergizes with existing auto-dispatch mechanism, forming a complete automated handoff flow

**Negative/Risks**:
- Hook script complexity increases, cache file needs maintenance
- Memory extraction relies on Agent following SKILL.md conventions (but much better than pure manual approach)
- Cache file needs to be added to `.gitignore`

**Downstream Impact**:
- T-009 (Smart Memory Loading) directly depends on the standardized memory format produced by this task
