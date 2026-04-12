# Design: T-003 — /unblock Command

## G1: agent-task-board — Add unblock operation

Add a new section to `skills/agent-task-board/SKILL.md`:

```markdown
### Unblock Task
When user says "unblock T-NNN":
1. Read task-board.json, find T-NNN
2. Confirm status == "blocked"
3. Read blocked_reason and previous_status (stored in tasks/T-NNN.json)
4. Set status to previous_status (restore to the state before blocked)
5. Update history: { from: "blocked", to: previous_status, note: "unblocked by user" }
6. Update task-board.md
```

## G2: agent-fsm — Blocked state handling

Update `skills/agent-fsm/SKILL.md` transition rules:
- Add `blocked_from` field to task JSON schema (records the status before block)
- ANY → blocked: save current status to `blocked_from`, set reason
- blocked → `blocked_from` value: restore previous status

Task JSON addition:
```json
{
  "blocked_from": "implementing",
  "blocked_reason": "Waiting for external API access"
}
```

## G3: agent-switch — Highlight blocked tasks

In the status panel output, add visual indicator:
```
🚫 T-003 [BLOCKED] — Waiting for external API access (blocked 2h ago)
```

## Files to modify
| File | Change |
|------|--------|
| `skills/agent-task-board/SKILL.md` | Add unblock operation section |
| `skills/agent-fsm/SKILL.md` | Add blocked_from field, blocked transition rules |
| `skills/agent-switch/SKILL.md` | Add blocked task highlighting in status panel |
