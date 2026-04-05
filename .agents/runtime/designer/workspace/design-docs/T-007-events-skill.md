# Design: T-007 — Events.db Analysis Skill

## G1: Create skills/agent-events/SKILL.md

New skill for querying and analyzing events.db:

```markdown
---
name: agent-events
description: "事件查询: 分析 events.db 审计日志。调用时说 '查看事件日志'、'agent 活动统计'。"
---

# 事件日志查询

## 最近事件
\```bash
sqlite3 .agents/events.db "SELECT id, datetime(timestamp/1000, 'unixepoch') as time, event_type, agent, task_id, tool_name FROM events ORDER BY id DESC LIMIT 20;"
\```

## 按 Agent 查询
\```bash
sqlite3 .agents/events.db "SELECT agent, COUNT(*) as total, MAX(datetime(timestamp/1000, 'unixepoch')) as last_active FROM events GROUP BY agent ORDER BY total DESC;"
\```

## 按任务查询
\```bash
sqlite3 .agents/events.db "SELECT * FROM events WHERE task_id = 'T-NNN' ORDER BY id;"
\```

## 工具使用统计
\```bash
sqlite3 .agents/events.db "SELECT tool_name, COUNT(*) as count FROM events WHERE event_type = 'tool_use' GROUP BY tool_name ORDER BY count DESC;"
\```
```

## G2: Agent-switch status panel enhancement

Add to agent-switch status output:
```
📊 Recent activity: acceptor(3) designer(12) implementer(25) reviewer(5) tester(8)
```

Query: `SELECT agent, COUNT(*) FROM events WHERE timestamp > (strftime('%s','now')-86400)*1000 GROUP BY agent;`

## G3: Event cleanup command

Add to agent-events skill:
```markdown
## 清理旧事件
\```bash
sqlite3 .agents/events.db "DELETE FROM events WHERE timestamp < (strftime('%s','now') - 86400 * $DAYS) * 1000;"
\```
用户说 "清理 30 天前的事件" 时执行。
```

## Files
| File | Action |
|------|--------|
| `skills/agent-events/SKILL.md` | CREATE (new skill) |
| `skills/agent-switch/SKILL.md` | MODIFY (add activity summary) |
