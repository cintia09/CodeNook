# T-010: ASCII Pipeline Visualization in Agent Status Panel

## Context

Currently `/agent status` only shows an Agent list and simple task info, with no visual indication of each task's position in the pipeline. Users must manually inspect `task-board.json` to understand task progress.

The core workflow of the multi-agent framework is a 5-stage pipeline: Design → Implement → Review → Test → Accept. Displaying this pipeline as ASCII art in the status panel greatly improves project visibility.

## Decision

Add an ASCII pipeline diagram to the `/agent status` output in `agent-switch`. Each active task gets its own line, using emoji and status markers to show its current position.

## Alternatives Considered

| Option | Pros | Cons | Decision |
|--------|------|------|----------|
| **A: Inline ASCII pipeline (selected)** | Good terminal compatibility, high info density | Limited width; long when many tasks | ✅ Selected |
| **B: Table format** | Clear structure | Not intuitive, no flow visualization | ❌ Lacks pipeline feel |
| **C: External HTML report** | Best visualization | Requires extra tools, leaves terminal | ❌ Adds dependency |
| **D: Text-only description** | Simplest | Low info density, not intuitive | ❌ Same as current state |

## Design

### Architecture

```
/agent status output structure (enhanced):

╔══════════════════════════════════════════╗
║  🤖 Multi-Agent Pipeline Status          ║
╠══════════════════════════════════════════╣
║                                          ║
║  T-008: Auto Memory Capture              ║
║  📐Design ──→ 🔨Implement ──→ 🔍Review   ║
║    ✅          ⏳ ◀──current   ⏸️          ║
║  ──→ 🧪Test ──→ ✅Accept                 ║
║       ⏸️          ⏸️                      ║
║                                          ║
║  T-009: Smart Memory Loading             ║
║  📐Design ──→ 🔨Implement ──→ 🔍Review   ║
║    ⏳ ◀──current ⏸️            ⏸️          ║
║  ──→ 🧪Test ──→ ✅Accept                 ║
║       ⏸️          ⏸️                      ║
║                                          ║
╚══════════════════════════════════════════╝
```

**Status icon definitions**:
- ✅ Completed (done)
- ⏳ In progress (active / current stage)
- ⏸️ Waiting (pending / not started)
- 🚫 Blocked
- ❌ Failed, needs redo (rejected)

**Stage emoji**:
- 📐 Design
- 🔨 Implement
- 🔍 Review
- 🧪 Test
- ✅ Accept

### Data Model

**Status-to-stage mapping**:

```
FSM Status      → Pipeline Stage    → Display
─────────────────────────────────────────────
created         → (pre-pipeline)    → Not in pipeline
designing       → Design            → ⏳
implementing    → Implement         → ⏳
reviewing       → Review            → ⏳
testing         → Test              → ⏳
accepting       → Accept            → ⏳
accepted        → Accept            → ✅ (all stages complete)
blocked         → (current stage)   → 🚫
```

**Stage completion inference rules**:
- If current status is `implementing`, then `Design` stage is ✅
- If current status is `reviewing`, then `Design` + `Implement` are ✅
- And so on: all stages before the current stage are marked ✅

### API / Interface

**New section in agent-switch SKILL.md**:

```markdown
### Pipeline Visualization

In `/agent status` output, display an ASCII pipeline for each active task:

#### Rendering Rules
1. Read all tasks from task-board.json that are not `accepted` or `created`
2. For each task, determine current stage from status
3. Mark current stage with ⏳ + ◀──current
4. Mark previous stages with ✅
5. Mark subsequent stages with ⏸️
6. Mark blocked status with 🚫 at the corresponding stage

#### Output Format
Each task occupies 4 lines:
- Line 1: Task ID + title
- Line 2: First 3 stages (Design → Implement → Review)
- Line 3: Corresponding status icons
- Line 4: Last 2 stages (Test → Accept) + status icons
```

**Compact mode** (auto-switches when tasks > 5):

```
T-008: Auto Memory Capture [📐✅──🔨⏳──🔍⏸️──🧪⏸️──✅⏸️]
T-009: Smart Memory Loading [📐⏳──🔨⏸️──🔍⏸️──🧪⏸️──✅⏸️]
```

### Implementation Steps

1. **Define stage constants and mapping**:
   - Define 5 stage names, emoji, and FSM status mapping in `skills/agent-switch/SKILL.md`
   - Define status icons (✅⏳⏸️🚫❌)

2. **Design rendering logic**:
   - Add "Pipeline Visualization" section to the `/agent status` instructions
   - Describe rendering algorithm: read task list → filter active tasks → compute each stage status → output ASCII

3. **Implement standard mode rendering**:
   - 4 lines per task
   - Stages connected with `──→`
   - Current stage appended with `◀──current` marker

4. **Implement compact mode rendering**:
   - Auto-switches when task count > 5
   - Single line per task: `[📐✅──🔨⏳──🔍⏸️──🧪⏸️──✅⏸️]`

5. **Handle special states**:
   - `blocked`: Show 🚫 at the corresponding stage, append blocked_reason
   - `accepted`: All ✅, marked as "completed"
   - `created`: Not shown in pipeline (or marked as "pending start")

6. **Update `skills/agent-switch/SKILL.md`**:
   - Integrate pipeline output into "View all Agent status" operation
   - Add complete rendering rules and example output

7. **Completed task display strategy**:
   - `accepted` tasks collapsed by default, showing only a one-line summary
   - Expandable via `/agent status --all`

## Test Spec

### Unit Tests

| # | Test Scenario | Expected Result |
|---|--------------|-----------------|
| 1 | Single task at `implementing` | Pipeline shows Design✅, Implement⏳, Review⏸️, Test⏸️, Accept⏸️ |
| 2 | Single task at `reviewing` | Design✅, Implement✅, Review⏳, Test⏸️, Accept⏸️ |
| 3 | Task at `blocked` (from implementing) | Design✅, Implement🚫, Review⏸️, Test⏸️, Accept⏸️ |
| 4 | Task is `accepted` | All ✅ |
| 5 | Task is `created` | Not shown in pipeline (or marked "pending start") |

### Integration Tests

| # | Test Scenario | Expected Result |
|---|--------------|-----------------|
| 6 | 3 active tasks at different stages | Independent pipeline lines for each, standard mode |
| 7 | 6 active tasks | Auto-switches to compact mode, one line per task |
| 8 | `/agent status` full output | Pipeline shown after Agent list, properly formatted |

### Acceptance Criteria

- [ ] G1: `/agent status` includes ASCII pipeline showing 5 stages and current position
- [ ] G2: Each task displays stage name, emoji, status icon (✅/⏳/⏸️)
- [ ] G3: Multiple active tasks each have independent pipeline lines
- [ ] G4: agent-switch SKILL.md contains pipeline visualization spec

## Consequences

**Positive**:
- Project progress visible at a glance, no need to inspect JSON files
- Compact mode keeps readability with many tasks
- Emoji + ASCII displays correctly across various terminals

**Negative/Risks**:
- Narrow terminal width may cause line wrapping and misalignment
- Emoji width may vary across different terminals

**Future Impact**:
- Provides data model reference for a future Web Dashboard
