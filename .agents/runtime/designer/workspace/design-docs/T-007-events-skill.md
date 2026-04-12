# Design: T-007 — Events.db Analysis Skill

## G1: Create skills/agent-events/SKILL.md

New skill for querying and analyzing events.db:

```markdown
---
name: agent-events
description: "Event Query: Analyze events.db audit log. When invoked say 'View event log', 'agent activity statistics'."
---

# Event Log Query

## Recent Events
\```bash
sqlite3 .agents/events.db "SELECT id, datetime(timestamp/1000, 'unixepoch') as time, event_type, agent, task_id, tool_name FROM events ORDER BY id DESC LIMIT 20;"
\```

## Query by Agent
\```bash
sqlite3 .agents/events.db "SELECT agent, COUNT(*) as total, MAX(datetime(timestamp/1000, 'unixepoch')) as last_active FROM events GROUP BY agent ORDER BY total DESC;"
\```

## Query by Task
\```bash
sqlite3 .agents/events.db "SELECT * FROM events WHERE task_id = 'T-NNN' ORDER BY id;"
\```

## Tool Usage Statistics
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
## Clean Up Old Events
\```bash
sqlite3 .agents/events.db "DELETE FROM events WHERE timestamp < (strftime('%s','now') - 86400 * $DAYS) * 1000;"
\```
Execute when the user says "Clean up events older than 30 days".
```

## Files
| File | Action |
|------|--------|
| `skills/agent-events/SKILL.md` | CREATE (new skill) |
| `skills/agent-switch/SKILL.md` | MODIFY (add activity summary) |
