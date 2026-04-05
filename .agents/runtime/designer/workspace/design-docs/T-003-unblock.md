# Design: T-003 — /unblock Command

## G1: agent-task-board — Add unblock operation

Add a new section to `skills/agent-task-board/SKILL.md`:

```markdown
### Unblock 任务
当用户说 "unblock T-NNN" 时:
1. 读取 task-board.json, 找到 T-NNN
2. 确认 status == "blocked"
3. 读取 blocked_reason 和 previous_status (存在 tasks/T-NNN.json 中)
4. 将 status 改为 previous_status (回到 blocked 之前的状态)
5. 更新 history: { from: "blocked", to: previous_status, note: "unblocked by user" }
6. 更新 task-board.md
```

## G2: agent-fsm — Blocked state handling

Update `skills/agent-fsm/SKILL.md` transition rules:
- Add `blocked_from` field to task JSON schema (记录 block 前的状态)
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
🚫 T-003 [BLOCKED] — 等待外部 API 权限 (blocked 2h ago)
```

## Files to modify
| File | Change |
|------|--------|
| `skills/agent-task-board/SKILL.md` | Add unblock operation section |
| `skills/agent-fsm/SKILL.md` | Add blocked_from field, blocked transition rules |
| `skills/agent-switch/SKILL.md` | Add blocked task highlighting in status panel |
