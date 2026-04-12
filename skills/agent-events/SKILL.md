---
name: agent-events
description: "Audit log query: View agent activity history, tool usage statistics, event analysis. Use when querying events.db, checking activity history, or analyzing agent behavior."
---

# Audit Log Query (events.db)

## Prerequisites
- `.agents/events.db` exists (created by agent-init or session-start hook)

## Common Queries

### Recent Events
```bash
sqlite3 .agents/events.db "SELECT id, event_type, agent, tool_name, created_at FROM events ORDER BY id DESC LIMIT 20;"
```

### Query by Agent
```bash
sqlite3 .agents/events.db "SELECT event_type, count(*) FROM events WHERE agent='<agent_name>' GROUP BY event_type;"
```

### Query by Task
```bash
sqlite3 .agents/events.db "SELECT event_type, agent, detail, created_at FROM events WHERE task_id='<task_id>' ORDER BY id;"
```

### Tool Usage Statistics
```bash
sqlite3 .agents/events.db "SELECT tool_name, count(*) as uses FROM events WHERE event_type='tool_use' GROUP BY tool_name ORDER BY uses DESC;"
```

### Auto-dispatch History
```bash
sqlite3 .agents/events.db "SELECT agent, task_id, detail, created_at FROM events WHERE event_type='auto_dispatch' ORDER BY id DESC;"
```

### Agent Activity (Past 24 Hours)
```bash
sqlite3 .agents/events.db "SELECT agent, count(*) as actions FROM events WHERE created_at > datetime('now', '-24 hours') GROUP BY agent ORDER BY actions DESC;"
```

### State Change Timeline
```bash
sqlite3 .agents/events.db "SELECT agent, detail, created_at FROM events WHERE event_type='state_change' ORDER BY id;"
```

## Event Type Reference

| event_type | Source | Description |
|-----------|--------|-------------|
| `session_start` | session-start hook | Session started |
| `tool_use` | post-tool-use hook | Tool invocation (includes result and args) |
| `task_board_write` | post-tool-use hook | Task board modified |
| `state_change` | post-tool-use hook | Agent state.json modified |
| `auto_dispatch` | post-tool-use hook | Auto-dispatched message to downstream agent |

## Clean Up Old Events

Delete events older than N days:
```bash
sqlite3 .agents/events.db "DELETE FROM events WHERE created_at < datetime('now', '-30 days');"
```

Delete all events (reset):
```bash
sqlite3 .agents/events.db "DELETE FROM events;"
sqlite3 .agents/events.db "DELETE FROM sqlite_sequence WHERE name='events';"
```

## Export

Export as CSV:
```bash
sqlite3 -header -csv .agents/events.db "SELECT * FROM events;" > events-export.csv
```

Export as JSON Lines:
```bash
sqlite3 .agents/events.db "SELECT json_object('id',id,'type',event_type,'agent',agent,'task',task_id,'tool',tool_name,'detail',detail,'time',created_at) FROM events;" > events-export.jsonl
```
