---
name: agent-hitl-gate
description: "Human-in-the-Loop approval gate. Each phase output must pass human review before FSM transition. Use when publishing documents for review, collecting feedback, or checking approval status."
---

# 🚪 Human-in-the-Loop Gate

## Overview

HITL Gate is a human approval checkpoint in the agent workflow. After completing a phase, an agent publishes its output document for interactive review. The FSM transition is blocked until human approval is received.

## Configuration

Project-level config in `.agents/config.json`:

```json
{
  "hitl": {
    "enabled": true,
    "platform": "local-html",
    "gates": {
      "acceptor":    { "enabled": true, "output": "requirements + acceptance-criteria" },
      "designer":    { "enabled": true, "output": "design-doc + test-spec" },
      "implementer": { "enabled": true, "output": "code-summary + dfmea" },
      "reviewer":    { "enabled": true, "output": "review-report" },
      "tester":      { "enabled": true, "output": "test-report" }
    },
    "auto_approve_timeout_hours": null
  }
}
```

**Platform Options**:
- `"local-html"` (default): Local HTTP server, opens in browser
  - Docker/headless: auto-detects, binds `0.0.0.0`, accessible via container IP
- `"terminal"`: Pure terminal interaction, no browser needed (Docker/SSH/CI)
  - Agent displays content in terminal, collects feedback via ask_user
- `"github-issue"`: Creates GitHub Issue, approval via comments/reactions
- `"confluence"`: Publishes to Confluence, approval via comments

**Recommended Platform by Environment**:

| Environment | Platform | Reason |
|-------------|----------|--------|
| Local desktop (macOS/Linux) | `local-html` | Best browser-based UX |
| Docker + port mapping | `local-html` | Auto-binds 0.0.0.0, host browser accessible |
| Docker/SSH (no browser) | `terminal` | Pure CLI, zero dependencies |
| Team collaboration | `github-issue` | Async approval with comment history |
| Enterprise | `confluence` | Integrates with existing doc systems |

If `hitl.enabled` is `false` or config is missing, HITL gates are skipped (backward compatible).

## Core Workflow

### 1. Publish Document for Review

Agent calls after completing output:

```
HITL Gate: publish(task_id, agent_role, output_doc_path)
```

**Steps:**
1. Read the output document (markdown)
2. Invoke platform adapter:
   - **local-html**: Start local HTTP server (hitl-server.py), open browser
     ```bash
     bash scripts/hitl-adapters/local-html.sh publish T-NNN <role> <doc.md>
     # → Starts http://127.0.0.1:8900 and opens browser
     ```
   - **github-issue**: Create GitHub Issue
   - **confluence**: Create Confluence page
3. Record HITL status in task-board.json:
   ```json
   {
     "hitl_status": {
       "current_gate": "designer",
       "review_url": "http://127.0.0.1:8900",
       "status": "pending_review",
       "feedback_rounds": 0,
       "published_at": "<ISO 8601>",
       "approved_at": null,
       "approved_by": null
     }
   }
   ```
4. Output: "📄 Review page published: <URL>. Please review in browser..."

### Multi-Round Feedback Loop

```
Agent publishes doc → User sees doc in browser
  ↓
User writes feedback in textarea → Clicks "Request Changes"
  ↓
Agent polls feedback JSON → Reads feedback → Revises doc → Republishes
  (Agent edits the source markdown; hitl-server auto-refreshes)
  ↓
User refreshes page → Sees revised doc → Adds more feedback or clicks "Approve"
  ↓
Agent detects approved → Stops server → Proceeds with FSM transition
```

**Local HTML Server Features**:
- Pure Python (zero dependencies), auto-selects available port (8900-8999)
- Live document refresh (reads latest file on each request)
- Full feedback history preserved (each round appended to history JSON)
- Server PID stored at `.agents/reviews/T-NNN-<role>-server.pid`
- Cleanup after approval: `bash scripts/hitl-adapters/local-html.sh stop T-NNN <role>`

### 2. Check Approval Status

Agent polls periodically or user triggers manually:

```
HITL Gate: check(task_id)
```

**Steps:**
1. Read `hitl_status` from task-board.json
2. Query platform adapter for current status
3. Return status:
   - `pending_review`: Awaiting review
   - `feedback`: Feedback received, revisions needed
   - `approved`: Approved

### 3. Collect Feedback

When status is `feedback`:

```
HITL Gate: collect_feedback(task_id)
```

**Steps:**
1. Retrieve feedback from platform adapter
2. Return feedback list: `[{section, comment, author, at}]`
3. Agent revises document based on feedback
4. Republish (feedback_rounds + 1)
5. Loop until approved

### 4. Confirm Approval

When status is `approved`:

```
HITL Gate: confirm(task_id)
```

**Steps:**
1. Record `approved_at` and `approved_by`
2. Set `hitl_status.status = "approved"`
3. Allow FSM transition

## HITL Checkpoints by Role

| Role | Trigger | Review Content | Post-Approval Transition |
|------|---------|----------------|--------------------------|
| 🎯 acceptor | Requirements complete | Requirements + acceptance criteria | created → designing |
| 🏗️ designer | Design doc complete | Design doc + test spec | designing → implementing |
| 💻 implementer | Implementation complete | Code summary + DFMEA | implementing → reviewing |
| 🔍 reviewer | Review report complete | Review verdict + change requests | reviewing → testing |
| 🧪 tester | Test report complete | Test results + issue list | testing → accepting |

## Platform Adapter Interface

Each adapter must implement:

```bash
# Publish document, return review page URL
hitl_publish(task_id, role, content_md) → review_url

# Poll approval status
hitl_poll(task_id, role) → { status: "pending"|"feedback"|"approved", comments: [] }

# Retrieve feedback content
hitl_get_feedback(task_id, role) → [{ section, comment, author, at }]
```

Adapter scripts location: `scripts/hitl-adapters/<platform>.sh`

## FSM Integration

Added to agent-fsm Guard rules:

**HITL Approval Guard**:
- Active only when `hitl.enabled == true`
- Pre-transition check: `hitl_status.status == "approved"`
- If not approved: block transition with "⛔ HITL approval required before proceeding"

**Optimistic Locking**:
- Reads `version` field from task-board.json on publish
- Validates version unchanged on write-back to prevent concurrent overwrites
- Retries on conflict (up to 3 attempts)

## Quick Approval (Shortcut)

Users can approve directly in the agent conversation:
- "approve" → Marks current HITL gate as approved
- "feedback: <content>" → Writes feedback; agent revises and republishes

This provides a fast approval path without leaving the terminal.

## Auto-Approval (Optional)

If `auto_approve_timeout_hours` is configured:
- Auto-approves after the specified hours with no feedback
- Set to `null` to disable (default)
