---
name: agent-messaging
description: "Inter-agent messaging: Send messages to other Agents or view inbox. Invoke by saying 'send message to tester' or 'view inbox'."
---

# Inter-Agent Messaging

## Inbox Format
File: `<project>/.agents/runtime/<agent>/inbox.json`

```json
{
  "messages": [
    {
      "id": "msg-001",
      "from": "implementer",
      "to": "tester",
      "type": "task_update",
      "task_id": "T-001",
      "content": "T-001 fix completed, please re-verify",
      "timestamp": "2026-04-05T10:00:00Z",
      "read": false
    }
  ]
}
```

## Message Types (Auto-Dispatch)

> The following types are used for **auto-dispatch generated** messages. For manually sent messages, use the "Bidirectional Message Types" below.

| type | Description | Trigger Scenario |
|------|-------------|-----------------|
| `task_created` | New task published | Acceptor creates task |
| `task_update` | Task status changed | Any state transition |
| `review_result` | Review result | Reviewer completes review |
| `test_result` | Test result | Tester completes testing |
| `accept_result` | Acceptance result | Acceptor completes acceptance |
| `info` | General notification | Any scenario requiring notification |
| `blocked` | Blocked notification | Agent encounters unresolvable problem |

## Operations

### Send Message
1. Read target Agent's inbox.json
2. Generate message ID: `msg-{timestamp-ms}`
3. Append new message to messages array
4. Write inbox.json

### View Inbox
1. Read current Agent's inbox.json
2. List unread messages (read: false)
3. Formatted output:
```
📬 Inbox (3 unread)
[msg-001] From implementer (10:00): T-001 fix completed, please re-verify
[msg-002] From acceptor (11:00): New task T-003: Theme System
[msg-003] From reviewer (11:30): T-002 review passed
```

### Mark as Read
Set the specified message's read to true.

### Clean Up Old Messages
Messages are retained for 30 days by default. Agent can clean up read messages older than 30 days on startup.

---

## Structured Message Schema

All inter-agent messages **must** follow this structured schema. This ensures messages are semantically clear, machine-parsable, and traceable.

### Full Message Structure

```json
{
  "id": "msg-1717600000000",
  "from": "implementer",
  "to": "reviewer",
  "task_id": "T-001",
  "timestamp": "2026-04-05T10:00:00Z",
  "read": false,

  "type": "request | response | notification | escalation | broadcast",
  "severity": "critical | high | medium | low",
  "priority": "urgent | normal | info",

  "thread_id": "msg-1717599000000",
  "reply_to": "msg-1717599500000",

  "context": {
    "file": "src/auth/jwt.ts",
    "line": 42,
    "function": "validateToken"
  },

  "content": "Token validation logic has a race condition, please review the validateToken function",
  "references": ["msg-1717599000000"]
}
```

### Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | ✅ | `msg-{timestamp-ms}` format |
| `from` | string | ✅ | Sender role |
| `to` | string | ✅ | Receiver role |
| `task_id` | string | ✅ | Associated task ID |
| `timestamp` | ISO 8601 | ✅ | Send time |
| `read` | boolean | ✅ | Whether read |
| `type` | enum | ✅ | Message type (see table below) |
| `severity` | enum | ✅ | Severity level |
| `priority` | enum | ✅ | Priority level |
| `context` | object | ❌ | Code location context (fill when code-related) |
| `context.file` | string | ❌ | Related file path |
| `context.line` | number | ❌ | Related line number |
| `context.function` | string | ❌ | Related function/method name |
| `content` | string | ✅ | Message body |
| `thread_id` | string | ❌ | Conversation thread ID (first message's id) |
| `reply_to` | string | ❌ | ID of message being replied to |
| `references` | string[] | ❌ | List of related message IDs |

### Bidirectional Message Types (type)

> Used when Agents manually send messages. These do not conflict with the "auto-dispatch types" above.

| type | Description | Typical Scenario |
|------|-------------|-----------------|
| `request` | Request the other party to perform an action | implementer → reviewer: "Please review T-001" |
| `response` | Reply to a request | reviewer → implementer: "Review complete, 3 issues" |
| `notification` | One-way notification, no reply needed | acceptor → all: "New task T-005 created" |
| `escalation` | Escalate/report a problem | tester → acceptor: "T-001 tests keep failing, intervention needed" |
| `broadcast` | Broadcast to all Agents | acceptor → all: "T-001 priority elevated to critical" |

### Severity Levels

| severity | Description | Example |
|----------|-------------|---------|
| `critical` | Blocks pipeline, requires immediate attention | Build failure, security vulnerability, data loss risk |
| `high` | Serious issue, must be resolved in current phase | Logic error, unhandled boundary condition |
| `medium` | Needs attention but non-blocking | Code style issues, missing unit tests |
| `low` | Advisory information | Optimization suggestions, documentation improvements |

### Priority Levels

| priority | Description | Handling Rule |
|----------|-------------|---------------|
| `urgent` | Blocks pipeline | **Handle immediately** — First thing after Agent switch; shown in red on status panel 🔴 |
| `normal` | Standard process | Handle in order — Process by time order after current task completes |
| `info` | FYI only | No reply needed — Mark as read; does not appear in pending queue |

### Priority Handling Rules

When Agent views inbox, sort in this order:
1. **urgent** messages pinned to top (🔴 marker)
2. **normal** messages sorted by time
3. **info** messages collapsed (show count only, expand to view)

```
📬 Inbox (5 unread)
🔴 [msg-001] URGENT From tester (10:00): T-001 all tests failed, build blocked
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[msg-002] From reviewer (11:00): T-003 review complete, 2 medium issues
[msg-003] From acceptor (11:30): Please implement T-005
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ️ 2 info messages (expand: /inbox --info)
```

---

## Message Routing Rules

### Who Sends What Type to Whom

Message routing follows the SDLC pipeline order. Each Agent only sends messages to **direct upstream/downstream** and **acceptor (escalation channel)**.

```
   acceptor ←──── All Agents can escalate
      │
      ▼ notification (task_created)
   designer
      │
      ▼ request (request implementation)
   implementer
      │
      ▼ request (request review)
   reviewer ────► implementer (response: rejected for fix)
      │
      ▼ request (request testing)
   tester ──────► implementer (response: rejected for fix)
      │
      ▼ request (request acceptance)
   acceptor
```

### Routing Matrix

| Sender → Receiver | type | severity | priority | Trigger Scenario |
|-------------------|------|----------|----------|-----------------|
| acceptor → designer | notification | medium | normal | New task created, assigned for design |
| acceptor → any | notification | high | urgent | Acceptance failed, task rejected |
| designer → implementer | request | medium | normal | Design complete, request implementation |
| implementer → reviewer | request | medium | normal | Implementation complete, request review |
| reviewer → implementer | response | high/medium | normal | Review feedback (passed/rejected) |
| reviewer → tester | request | medium | normal | Review passed, request testing |
| tester → implementer | response | high | normal | Test failed, rejected for fix |
| tester → acceptor | request | medium | normal | Tests passed, request acceptance |
| any → acceptor | escalation | critical/high | urgent | Encountered unresolvable blocking issue |
| any → any | notification | low | info | General information sharing (FYI) |

### Routing Rules

1. **Direct notification**: On state transition, automatically send `request` type message to downstream Agent
2. **Rejection notification**: When reviewer/tester rejects, send `response` type message to implementer, severity at least `high`
3. **Escalation channel**: Any Agent encountering a blocking issue sends `escalation` to acceptor, priority = `urgent`
4. **Broadcast message**: When `type: broadcast`, write message to **all 5** Agents' inbox.json (`to` set to `"all"`)
5. **Conversation thread**: When replying, set `reply_to` to original message ID, `thread_id` to first message ID in thread
6. **Reference links**: If message is a reply to another message, fill `references` field with original message ID

---

## Message Replay

### Description

View the complete collaboration timeline for a task — all messages sent by all Agents for that task, sorted chronologically.

### Trigger

Execute when user says `/inbox --history T-NNN` or "view T-NNN message history".

### Implementation Steps

1. Scan **all Agents'** inbox.json:
   ```bash
   AGENTS_DIR="$(git rev-parse --show-toplevel 2>/dev/null)/.agents"
   for agent in acceptor designer implementer reviewer tester; do
     cat "$AGENTS_DIR/runtime/$agent/inbox.json"
   done
   ```
2. Filter messages where `task_id == T-NNN`
3. Sort by `timestamp` ascending
4. Format and output the complete timeline

### Output Format

```
📜 Message History — T-001: User Authentication System
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

08:00  🎯 acceptor → 🏗️ designer  [notification/medium/normal]
       "New task T-001: User Authentication System, please start designing"

10:00  🏗️ designer → 💻 implementer  [request/medium/normal]
       "T-001 design complete, please implement per design-docs/T-001-design.md"

14:00  💻 implementer → 🔍 reviewer  [request/medium/normal]
       "T-001 implementation complete, please review src/auth/*.ts"
       📎 context: src/auth/jwt.ts

14:30  🔍 reviewer → 💻 implementer  [response/high/normal]
       "T-001 review found 2 issues: token refresh race condition + missing error handling"
       📎 context: src/auth/jwt.ts:42 validateToken()

15:00  💻 implementer → 🔍 reviewer  [request/medium/normal]
       "T-001 fix complete, please re-review"

15:30  🔍 reviewer → 🧪 tester  [request/medium/normal]
       "T-001 review passed, please execute tests"

16:00  🧪 tester → 🎯 acceptor  [request/medium/normal]
       "T-001 all tests passed (12/12), please accept"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total 7 messages | Time span: 08:00 → 16:00 (8h)
```

### Replay Filter Options

| Command | Description |
|---------|-------------|
| `/inbox --history T-001` | View T-001 complete message history |
| `/inbox --history T-001 --type escalation` | View only escalation messages |
| `/inbox --history T-001 --from reviewer` | View only messages from reviewer |
| `/inbox --history T-001 --severity critical,high` | View only high-severity messages |
| `/inbox --history T-001 --priority urgent` | View only urgent messages |

### Notes
- Replay only reads existing messages, does not modify read status
- If an Agent's inbox.json does not exist, skip (no error)
- Message context info is displayed with 📎 marker in the timeline
