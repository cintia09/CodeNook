# T-007 Fix Design: agent-switch Event Summary Integration + Cleanup Command

## Problem
- G2: agent-switch status panel is missing event summary (recent activity statistics per Agent)
- G3: Event cleanup command is not exposed in agent-switch

## Fix Plan

### File 1: `skills/agent-switch/SKILL.md`

#### G2 Fix: Add event summary to the status panel

At the end of the output template in the "View all Agent status (/agent status)" section, add an event summary block:

```
🤖 Agent Status Panel
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Role        Status   Current Task  Queue       Last Active
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 Acceptor  idle     —            —           10:00
🏗️ Designer  busy     T-002        —           10:30
💻 Implementer idle   —            [T-003]     09:45
🔍 Reviewer  idle     —            —           09:00
🧪 Tester    busy     T-001        —           10:15
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 Task Board Summary: 3 tasks (1 done, 1 in progress, 1 pending)

📊 Last 24h Activity (from events.db):
  💻 Implementer: 42 actions | 🔍 Reviewer: 15 actions | 🧪 Tester: 8 actions

🚨 Blocked Tasks (if any):
  ⛔ T-004: blocked — "Dependent API not ready yet"
```

Add events.db query in the implementation steps:
```bash
# Query each Agent's activity count in the last 24h
if [ -f "$AGENTS_DIR/events.db" ]; then
  sqlite3 "$AGENTS_DIR/events.db" \
    "SELECT agent, count(*) FROM events WHERE created_at > datetime('now', '-24 hours') GROUP BY agent ORDER BY count(*) DESC;"
fi
```

#### G3 Fix: Add event management commands

Add a new section at the end of SKILL.md, before the "Available Roles" table:

```markdown
## Event Management

### View Activity Summary
```bash
sqlite3 .agents/events.db "SELECT agent, count(*) as actions FROM events WHERE created_at > datetime('now', '-24 hours') GROUP BY agent ORDER BY actions DESC;"
```

### Clean Up Old Events
```bash
# Clean up events older than 30 days
sqlite3 .agents/events.db "DELETE FROM events WHERE created_at < datetime('now', '-30 days');"
# Clean up all events (reset)
sqlite3 .agents/events.db "DELETE FROM events; DELETE FROM sqlite_sequence WHERE name='events';"
```

Refer to the `agent-events` skill for more query options.
```

## Implementer Notes
- Only modify `skills/agent-switch/SKILL.md`
- The event summary is appended to the `/agent status` output, without affecting existing content
- The cleanup command is a new section, placed before the "Available Roles" table
- The events.db query needs to check if the file exists (it may not be initialized)
