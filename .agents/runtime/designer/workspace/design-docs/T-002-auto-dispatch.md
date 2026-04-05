# Design Document: T-002 — Phase 3: Auto-dispatch and Staleness Detection

## Goal Reference
- G1: Design auto-dispatch mechanism
- G2: Implement auto-dispatch in post-tool-use hook
- G3: Implement staleness detection script
- G4: Add staleness check to session-start hook
- G5: Update agent-switch to auto-process inbox queue

## Architecture Overview

### Auto-dispatch Flow
```
Agent A completes work → writes task-board.json (status change)
  ↓
post-tool-use hook detects task-board write
  ↓
Hook reads new task status → looks up FSM next-agent mapping
  ↓
Hook writes message to next agent's inbox.json
  ↓
Next time that agent is activated → inbox processed automatically
```

### FSM Status → Next Agent Mapping

| From Status | To Status | Next Agent | Message Type |
|-------------|-----------|------------|--------------|
| created | designing | designer | task_created |
| designing | implementing | implementer | task_update |
| implementing | reviewing | reviewer | task_update |
| reviewing (pass) | testing | tester | task_update |
| reviewing (reject) | implementing | implementer | review_result |
| testing (pass) | accepting | acceptor | test_result |
| testing (fail) | fixing | implementer | test_result |
| fixing | testing | tester | task_update |
| accepting (pass) | accepted | — | accept_result |
| accepting (fail) | designing | designer | accept_result |

## G1 + G2: Auto-dispatch Implementation

### Changes to `hooks/agent-post-tool-use.sh`

After the existing task-board write detection (line 32-36), add auto-dispatch logic:

```bash
# --- AUTO-DISPATCH ---
# When task-board.json is modified, check for status changes
# and auto-send messages to the next agent in the FSM

if [[ "$FILE_PATH" =~ task-board\.json ]]; then
  # Read the updated task board
  TASKS=$(jq -c '.tasks[]' "$AGENTS_DIR/task-board.json" 2>/dev/null)
  
  # For each task, check if status implies a message to another agent
  echo "$TASKS" | while read -r TASK; do
    TASK_ID=$(echo "$TASK" | jq -r '.id')
    STATUS=$(echo "$TASK" | jq -r '.status')
    TITLE=$(echo "$TASK" | jq -r '.title')
    
    # Map status to target agent
    case "$STATUS" in
      created|accept_fail)  TARGET="designer" ;;
      designing)            TARGET="" ;;  # designer already working
      implementing|fixing)  TARGET="" ;;  # implementer already working
      reviewing)            TARGET="reviewer" ;;
      testing)              TARGET="tester" ;;
      accepting)            TARGET="acceptor" ;;
      accepted|blocked)     TARGET="" ;;
      *)                    TARGET="" ;;
    esac
    
    [ -z "$TARGET" ] && continue
    
    # Check if message already sent (avoid duplicates)
    TARGET_INBOX="$AGENTS_DIR/runtime/$TARGET/inbox.json"
    [ -f "$TARGET_INBOX" ] || continue
    
    EXISTING=$(jq --arg tid "$TASK_ID" --arg status "$STATUS" \
      '[.messages[] | select(.task_id == $tid and .content | contains($status))] | length' \
      "$TARGET_INBOX" 2>/dev/null || echo 0)
    
    [ "$EXISTING" -gt 0 ] && continue
    
    # Generate message ID
    MSG_ID="MSG-auto-${TASK_ID}-${STATUS}"
    NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Append message to target inbox
    jq --arg id "$MSG_ID" --arg from "$ACTIVE_AGENT" --arg to "$TARGET" \
       --arg tid "$TASK_ID" --arg status "$STATUS" --arg title "$TITLE" \
       --arg ts "$NOW_ISO" \
       '.messages += [{"id":$id,"from":$from,"to":$to,"type":"task_update","task_id":$tid,"content":"Task \($tid) [\($title)] status changed to \($status). Please process.","timestamp":$ts,"read":false}]' \
       "$TARGET_INBOX" > "${TARGET_INBOX}.tmp" && mv "${TARGET_INBOX}.tmp" "$TARGET_INBOX"
    
    # Log dispatch event
    sqlite3 "$EVENTS_DB" "INSERT INTO events (timestamp, event_type, agent, task_id, detail) VALUES ($TIMESTAMP, 'auto_dispatch', '$TARGET', '$TASK_ID', '{\"from_status\":\"$STATUS\",\"from_agent\":\"$ACTIVE_AGENT\"}');"
  done
fi
```

**Key design decisions:**
1. Duplicate prevention: check if inbox already has message for same task+status
2. Only dispatch on "arrival" statuses (reviewing, testing, accepting, created)
3. Don't dispatch for "working" statuses (designing, implementing, fixing) — agent is already assigned
4. Message ID format: `MSG-auto-{task_id}-{status}` for traceability

## G3: Staleness Detection Script

New file: `hooks/agent-staleness-check.sh`

```bash
#!/bin/bash
# Checks for stale tasks and agents (inactive > threshold)
# Called from session-start hook, or standalone via cron

AGENTS_DIR="${1:-.agents}"
THRESHOLD_HOURS="${2:-24}"  # Default: 24 hours

[ -d "$AGENTS_DIR/runtime" ] || exit 0

THRESHOLD_SEC=$((THRESHOLD_HOURS * 3600))
NOW_SEC=$(date +%s)

echo "━━━ Staleness Report ━━━"

# Check agent staleness
for state_file in "$AGENTS_DIR"/runtime/*/state.json; do
  [ -f "$state_file" ] || continue
  AGENT=$(jq -r '.agent' "$state_file")
  STATUS=$(jq -r '.status' "$state_file")
  LAST=$(jq -r '.last_activity' "$state_file")
  
  # Convert ISO to epoch
  LAST_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST" +%s 2>/dev/null || echo 0)
  DIFF=$((NOW_SEC - LAST_SEC))
  
  if [ "$STATUS" = "busy" ] && [ "$DIFF" -gt "$THRESHOLD_SEC" ]; then
    HOURS=$((DIFF / 3600))
    echo "⚠️  $AGENT: busy for ${HOURS}h (task: $(jq -r '.current_task' "$state_file"))"
  fi
done

# Check task staleness
if [ -f "$AGENTS_DIR/task-board.json" ]; then
  jq -r '.tasks[] | select(.status != "accepted" and .status != "blocked") | "\(.id) \(.status) \(.updated_at)"' "$AGENTS_DIR/task-board.json" | while read -r TID TSTATUS TUPDATED; do
    TASK_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$TUPDATED" +%s 2>/dev/null || echo 0)
    DIFF=$((NOW_SEC - TASK_SEC))
    if [ "$DIFF" -gt "$THRESHOLD_SEC" ]; then
      HOURS=$((DIFF / 3600))
      echo "⚠️  Task $TID ($TSTATUS): no activity for ${HOURS}h"
    fi
  done
fi

echo "━━━━━━━━━━━━━━━━━━━━━"
```

## G4: Session-start Integration

Add to `hooks/agent-session-start.sh` before the summary section:

```bash
# Run staleness check (only warn, don't block)
STALE_OUTPUT=$("$AGENTS_DIR/../hooks/agent-staleness-check.sh" "$AGENTS_DIR" 24 2>/dev/null || true)
if echo "$STALE_OUTPUT" | grep -q "⚠️"; then
  echo "$STALE_OUTPUT" >&2
fi
```

**Note**: Since hooks can't modify output to LLM, staleness warnings go to stderr (Copilot log). The agent-switch skill should also check staleness on activation.

## G5: Agent-switch Queue Processing

Update `skills/agent-switch/SKILL.md` — add to the switch flow:

After loading the agent's skill (current step 5), add:
```
5b. **自动处理 inbox**: 读取并显示未读消息, 标记为已读
5c. **检查 task-board**: 显示分配给当前 agent 的任务
5d. **Staleness 警告**: 如果有长时间未活动的任务, 提醒用户
```

## File Impact

| File | Action | Description |
|------|--------|-------------|
| `hooks/agent-post-tool-use.sh` | MODIFY | Add auto-dispatch logic after task-board write detection |
| `hooks/agent-staleness-check.sh` | CREATE | New staleness detection script |
| `hooks/agent-session-start.sh` | MODIFY | Add staleness check call |
| `skills/agent-switch/SKILL.md` | MODIFY | Add inbox processing + staleness warning to switch flow |
| `hooks/hooks.json` | NO CHANGE | Existing hooks already cover needed triggers |

## Notes
- Auto-dispatch runs in post-tool-use hook (max 5 sec timeout) — keep it fast
- Staleness check uses macOS `date -j` — may need adaptation for Linux
- Duplicate message prevention is critical to avoid inbox spam
