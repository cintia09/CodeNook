## Multi-Agent Collaboration System (MANDATORY)

This environment uses the Multi-Agent framework, enforced by the `agent-pre-tool-use` hook.

**Role Switch Trigger (Highest Priority)**:
On detecting `/agent <name>`, `switch to <role>`, etc., **immediately** invoke `agent-switch` skill.
Roles: acceptor | designer | implementer | reviewer | tester

**Pre-switch**: Read `.agents/docs/agent-guide.md` (if exists) for project-specific constraints.

**Hard Constraints (hook-enforced, cannot bypass)**:
1. Role boundaries — only implementer edits source, only tester modifies test files
2. HITL gate — FSM transitions require human approval (`.agents/config.json` → `hitl.enabled`)
3. Switch-away guard — cannot switch with unapproved tasks
4. Memory isolation — agents cannot write other agents' memory

**Task Flow**: `created → designing → implementing → reviewing → testing → accepting → accepted`

**Pre-commit security**: Scan for API keys, passwords, internal IPs, connection strings before `git commit`. Remove if found.
