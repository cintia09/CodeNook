---
name: agent-config
description: "Agent Config Management — View/set agent model, tool permissions, platform status. Activated when user says 'configure agent', 'set model', 'configure tools', 'agent config', or '/agent-config'."
---

# Agent Config Management

Manage agent configuration for the Multi-Agent Framework. Supports model and tools dimensions, applied simultaneously across all platforms.

## Config Script

Script path: `~/.claude/skills/agent-config/config.sh` (Claude Code) or `~/.copilot/skills/agent-config/config.sh` (Copilot)

### View Config

```bash
# View all agent config (model + tools)
bash ~/.claude/skills/agent-config/config.sh list

# View single agent detailed config
bash ~/.claude/skills/agent-config/config.sh get implementer

# View detected platforms
bash ~/.claude/skills/agent-config/config.sh platforms
```

### Model Config

```bash
# View available model list
bash ~/.claude/skills/agent-config/config.sh models

# Set model for a single agent
bash ~/.claude/skills/agent-config/config.sh model set implementer claude-sonnet-4

# Set all agents to the same model
bash ~/.claude/skills/agent-config/config.sh model set-all claude-sonnet-4

# Reset a single agent to system default
bash ~/.claude/skills/agent-config/config.sh model reset implementer

# Reset all agent models
bash ~/.claude/skills/agent-config/config.sh model reset-all
```

### Tool Config

Control which tools each agent can use. In Copilot CLI, the `tools` field is enforced natively by the platform; in Claude Code it serves as a guiding constraint.

```bash
# View agent's tool list
bash ~/.claude/skills/agent-config/config.sh tools get reviewer

# Set tools (comma-separated) — restrict reviewer to read and search only
bash ~/.claude/skills/agent-config/config.sh tools set reviewer read,search,grep,glob

# Add a single tool
bash ~/.claude/skills/agent-config/config.sh tools add reviewer view

# Remove a single tool
bash ~/.claude/skills/agent-config/config.sh tools rm reviewer edit

# Reset (remove restrictions, allow all tools)
bash ~/.claude/skills/agent-config/config.sh tools reset reviewer
```

### Recommended Tool Config (Built-in Agent Reference)

| Agent | Recommended Tools | Description |
|-------|-------------------|-------------|
| acceptor | (all) | Requires full access for acceptance |
| designer | read,search,grep,glob,view | Read-only — no code changes during design |
| implementer | (all) | Requires full read/write + execute capability |
| reviewer | read,search,grep,glob,view | Read-only — review without modification |
| tester | read,search,grep,glob,view,bash | Can read and run tests, no direct src editing |

> Custom agent tool config is up to the user. Use `config.sh tools set <agent> <tools>` to configure.

## Model Resolution Priority

When an agent executes a task, the model is resolved in the following priority (high → low):

1. **Task-level** — `model_override` field in `task-board.json`
2. **Agent-level** — `model` field in `.agent.md` frontmatter (managed by this Skill)
3. **Project-level** — `default_model` in `.agents/project-agents-context/SKILL.md`
4. **System-level** — Platform default model (Claude Code or Copilot CLI global setting)

## Interactive Config

When the user requests agent configuration:

1. **Discover agents and models** — Run the following two commands:
   ```bash
   bash ~/.claude/skills/agent-config/config.sh list
   bash ~/.claude/skills/agent-config/config.sh models
   ```
   > ⚠️ Do not assume only 5 agents exist. Do not assume only a few fixed models. Always get the actual list from command output.

2. Show the user the **complete current config** (all agents + current model + tools)
3. Ask the user what to configure (model / tools / both)
4. If configuring model:
   - Show the **actual available model list** from `config.sh models`
   - Let the user choose agent and target model
5. If configuring tools:
   - Show current tool config from `config.sh list`
   - Let the user choose the agent and tool list to configure
6. Execute the corresponding command
7. Run `config.sh list` again to confirm changes

## Notes

- Agent list is **dynamically discovered** — config.sh scans all platform directories for `*.agent.md` files
- All changes are applied simultaneously to `~/.claude/agents/` and `~/.copilot/agents/`
- `model: ""` = use system default model
- `tools` field omitted = no tool restrictions (agent can use all tools)
- Copilot CLI enforces `tools` restrictions natively; Claude Code enforces via hooks
- Use the `/model` command (supported on both platforms) to view the current available model list
