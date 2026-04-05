# Test Specification: T-002 — Auto-dispatch + Staleness

## G1: Auto-dispatch Design
- [ ] FSM status→agent mapping table is complete (covers all transitions)
- [ ] Duplicate prevention mechanism documented

## G2: Auto-dispatch Implementation
- [ ] post-tool-use hook detects task-board.json writes
- [ ] On status=reviewing: message sent to reviewer inbox
- [ ] On status=testing: message sent to tester inbox
- [ ] On status=accepting: message sent to acceptor inbox
- [ ] On status=created: message sent to designer inbox
- [ ] Duplicate messages are NOT sent (same task+status)
- [ ] auto_dispatch event logged to events.db
- [ ] Hook completes within 5 seconds

## G3: Staleness Detection
- [ ] Script exists at hooks/agent-staleness-check.sh
- [ ] Detects busy agents inactive > threshold
- [ ] Detects tasks with no activity > threshold
- [ ] Configurable threshold (default 24h)
- [ ] Output includes task ID and hours inactive

## G4: Session-start Integration
- [ ] Session-start hook calls staleness check
- [ ] Stale items produce warning output
- [ ] Non-stale projects produce no extra output

## G5: Agent-switch Queue Processing
- [ ] Switch flow reads and displays unread inbox messages
- [ ] Switch flow shows assigned tasks from task-board
- [ ] Stale task warning shown on activation
