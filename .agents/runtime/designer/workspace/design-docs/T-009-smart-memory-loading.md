# T-009: Smart Memory Loading by Downstream Agent Role

## Context

Currently when `agent-switch` switches Agents, it loads the complete `T-NNN-memory.json` memory file. The problems are:
1. Different roles need different information — Implementer cares about design decisions and file structure, Reviewer cares about which files were modified and decision rationale
2. Loading the full JSON wastes tokens, and noisy information reduces Agent efficiency
3. Raw JSON format is not human-readable enough, making it difficult for Agents to parse

## Decision

Add **role-aware memory filtering and formatting** to the `agent-switch` switching logic: based on the target Agent role, extract only relevant fields and format them as a concise Markdown summary injected into the Agent context.

## Alternatives Considered

| Option | Pros | Cons | Decision |
|--------|------|------|----------|
| **A: Role-field mapping + Markdown formatting (selected)** | Precise, token-efficient, good readability | Need to maintain role-field mapping table | ✅ Selected |
| **B: Load everything + let Agent self-filter** | Simple to implement | Wastes tokens, Agent may ignore important info | ❌ Inefficient |
| **C: Separate memory file per role** | Simple to load | Need to maintain multiple files on write, data inconsistency risk | ❌ Maintenance burden |
| **D: LLM dynamic summary** | Highest summary quality | Additional LLM call cost, increased latency | ❌ Too costly |

## Design

### Architecture

```
┌────────────────────────────┐
│  User: /agent implementer  │
└─────────────┬──────────────┘
              ▼
┌─────────────────────────────────────────────┐
│  agent-switch SKILL.md logic                 │
│  ├── 1. Switch active-agent                  │
│  ├── 2. Check inbox                          │
│  ├── 3. Find current task (task-board.json)   │
│  └── 4. [New] Smart memory loading            │
│       ├── Read .agents/memory/T-NNN-memory.json│
│       ├── Filter fields by role mapping table   │
│       └── Format as Markdown summary output    │
└─────────────────────────────────────────────┘
```

### Data Model

**Role-field mapping table**:

| Transition Path | Loaded Fields | Rationale |
|----------------|---------------|-----------|
| Designer → Implementer | `decisions`, `artifacts`, `handoff_notes`, `summary` | Implementer needs to know design decisions and deliverables |
| Implementer → Reviewer | `files_modified`, `decisions`, `summary`, `issues_encountered` | Reviewer needs to know what changed and why |
| Reviewer → Tester | `files_modified`, `issues_encountered` (from review), `summary` | Tester needs to know which files to test and known issues |
| Tester → Acceptor | `summary` (all phases), `issues_encountered`, `handoff_notes` | Acceptor needs a global overview |
| Any → Designer (redesign) | `issues_encountered`, `handoff_notes`, `summary` | Designer needs to know failure reasons |

**Formatted output template**:

```markdown
## 📋 Task Memory: T-008 — Auto Memory Capture

### Previous Phase Summary
Designed a hook-based auto memory capture mechanism...

### Key Decisions
- Adopted a hybrid approach of hook detection + Agent extraction
- Memory format is compatible with existing T-NNN-memory.json

### Artifacts
- `.agents/runtime/designer/workspace/design-docs/T-008-auto-memory-capture.md`

### Handoff Notes
> Implementer should first modify the hook script, then update SKILL.md
```

### API / Interface

**New logic in agent-switch SKILL.md**:

In the "switch role" operation steps, add step 4 "Smart Memory Loading":

```markdown
### Smart Memory Loading

After switching to the target Agent, automatically execute:
1. Find the task currently assigned to this Agent from task-board.json
2. Read `.agents/memory/T-NNN-memory.json`
3. Extract relevant fields based on the role mapping table
4. Format as Markdown summary
5. Display in Agent startup information

#### Role Mapping Rules
(See mapping table above)

#### Output Format
Use concise Markdown, do not display raw JSON. Include headings, sections, lists.
```

**New section in agent-memory SKILL.md**:

```markdown
### Smart Loading

Memory can be loaded differentially based on role needs. When loading, do not display raw JSON; instead format as a readable summary.
See agent-switch SKILL.md "Smart Memory Loading" section for details.
```

### Implementation Steps

1. **Define role-field mapping table**:
   - Add "Smart Memory Loading" section in `skills/agent-switch/SKILL.md`
   - Define field lists for 5 role transition paths as a Markdown table

2. **Update agent-switch switching logic**:
   - Add memory loading step after existing "switch role" steps (after reading inbox)
   - Flow: find task → read memory file → filter by mapping → format output

3. **Define Markdown formatting template**:
   - Provide formatting template in `skills/agent-switch/SKILL.md`
   - Template includes: task title, previous phase summary, key decisions (list), artifacts (list), handoff notes (blockquote)
   - Only display fields specified in the mapping table; skip all other fields

4. **Handle edge cases**:
   - No memory file: skip loading, display "No historical memory available"
   - Empty memory file or missing fields: only display fields with values
   - No assigned task: skip loading

5. **Update `skills/agent-memory/SKILL.md`**:
   - Add "Smart Loading" section
   - Describe the role-differentiated memory loading mechanism
   - Reference specific rules in agent-switch SKILL.md

6. **Update `skills/agent-switch/SKILL.md`**:
   - In "View all Agent status" section, note automatic memory loading on switch
   - Add memory loading instructions to each role's processing logic

## Test Spec

### Unit Tests

| # | Test Scenario | Expected Result |
|---|--------------|-----------------|
| 1 | Switch to Implementer with Designer phase memory | Output contains decisions, artifacts, handoff_notes; excludes issues_encountered |
| 2 | Switch to Reviewer with Implementer phase memory | Output contains files_modified, decisions; excludes artifacts |
| 3 | Switch to Tester with Reviewer phase memory | Output contains files_modified, issues (review); excludes decisions |
| 4 | Switch to Agent with no memory file | Displays "No historical memory available", continues normally |
| 5 | Switch to Agent with no assigned task | Skips memory loading |

### Integration Tests

| # | Test Scenario | Expected Result |
|---|--------------|-----------------|
| 6 | Full flow: Designer saves memory → switch to Implementer | Implementer context contains formatted design summary |
| 7 | Memory format validation | Output is Markdown format, not JSON |
| 8 | Token efficiency test | Smart-loaded output length < 50% of full load |

### Acceptance Criteria

- [ ] G1: agent-switch automatically loads task memory on role switch
- [ ] G2: Fields filtered by role mapping table (covering at least 5 transition paths)
- [ ] G3: Output is Markdown summary format, not raw JSON
- [ ] G4: Both agent-memory and agent-switch SKILL.md are updated

## Consequences

**Positive**:
- Agents automatically receive precise context on startup, reducing token waste
- Markdown format is easier for Agents to understand and utilize than JSON
- Role mapping table is maintainable and extensible

**Negative/Risks**:
- Mapping table requires maintenance as role count grows
- Formatting template may need iterative adjustments

**Dependencies**:
- Depends on T-008's standardized memory format (memory.json produced by auto-capture)
