# T-SKILL-OPT: Skills Mechanism Optimization — Requirements

> **Role**: Acceptor  
> **Task ID**: T-SKILL-OPT  
> **Priority**: Medium  
> **Version**: v3.0  
> **Based on**: `skills-mechanism-report.md` deep analysis report  
> **Target Platforms**: Claude Code / GitHub Copilot CLI

---

## 1. Background

Based on Claude Code source analysis + Copilot CLI official docs + local config verification, the following key findings emerged:

1. **Both platforms share the Agent Skills open standard** (`agentskills.io`) — same `SKILL.md` format
2. **Injection mechanism is consistent**: Summary list (~1% tokens) + on-demand full-text loading (not the previously assumed "full injection at 40%")
3. **No per-agent skill isolation**: Currently the framework exposes all 18 skills to every agent, lacking role-level isolation
4. **Inaccurate documentation**: `docs/llm-message-structure.md` token distribution description does not match the actual mechanism

### Platform Skill Mechanism Comparison

| Dimension | Claude Code | GitHub Copilot CLI |
|-----------|------------|-------------------|
| **Discovery paths** | `~/.claude/skills/` + `.claude/skills/` + `.agents/skills/` | `~/.copilot/skills/` + `.github/skills/` + `.claude/skills/` + `.agents/skills/` |
| **Shared paths** | `.claude/skills/` ✅ `.agents/skills/` ✅ | `.claude/skills/` ✅ `.agents/skills/` ✅ |
| **Injection strategy** | Summary list ~1% + on-demand full text | Summary list + on-demand invocation |
| **Selective loading** | frontmatter `disable-model-invocation` / `paths:` | `/skills` command enable/disable |
| **Per-agent isolation** | Prompt soft constraint | Prompt soft constraint |
| **Hot reload** | ⚠️ Memoize cache, requires new session | `/skills reload` |

---

## 2. Requirements

### R1: Fix Token Distribution Documentation

**Priority**: HIGH  
**Type**: Documentation fix

`docs/llm-message-structure.md` token distribution chart labels Skills as ~40%; actual values should be:
- **~1%**: Skill summary list (injected into system prompt each turn)
- **~5-15%**: Invoked skill full text (appears in messages array, loaded on demand)
- Custom Instructions (`copilot-instructions.md` / `CLAUDE.md`) ≠ Skills

**Acceptance Criteria**:
- [ ] Token distribution chart (Mermaid pie chart) values accurately reflect the two-level loading mechanism
- [ ] ASCII package structure diagram marks Skills section as "Summary list ~1%" instead of "full text"
- [ ] New explanatory paragraph describing "summary discovery + on-demand loading" mechanism

### R2: Implement Per-Agent Skill Soft Constraints

**Priority**: HIGH  
**Type**: Feature enhancement

Add `skills:` declarations and prompt constraints to the 5 `.agent.md` files for role-level skill isolation.

**Skill Assignment Matrix**:

| Skill | acceptor | designer | implementer | reviewer | tester | Notes |
|-------|:--------:|:--------:|:-----------:|:--------:|:------:|-------|
| agent-orchestrator | ✅ | ✅ | ✅ | ✅ | ✅ | Global orchestration |
| agent-fsm | ✅ | ✅ | ✅ | ✅ | ✅ | State machine |
| agent-task-board | ✅ | ✅ | ✅ | ✅ | ✅ | Task board |
| agent-messaging | ✅ | ✅ | ✅ | ✅ | ✅ | Messaging |
| agent-memory | ✅ | ✅ | ✅ | ✅ | ✅ | Memory management |
| agent-switch | ✅ | ✅ | ✅ | ✅ | ✅ | Role switching |
| agent-docs | ✅ | ✅ | ✅ | ✅ | ✅ | Document pipeline |
| agent-config | ✅ | — | — | — | — | Project configuration |
| agent-init | ✅ | — | — | — | — | Project initialization |
| agent-acceptor | ✅ | — | — | — | — | Acceptance workflow |
| agent-designer | — | ✅ | — | — | — | Design workflow |
| agent-implementer | — | — | ✅ | — | — | Implementation workflow |
| agent-reviewer | — | — | — | ✅ | — | Review workflow |
| agent-tester | — | — | — | — | ✅ | Testing workflow |
| agent-events | — | — | ✅ | — | ✅ | Event logging |
| agent-hooks | — | — | ✅ | — | — | Hook development |
| agent-hypothesis | — | ✅ | ✅ | — | — | Hypothesis exploration |
| agent-teams | ✅ | — | — | — | — | Team orchestration |

**Acceptance Criteria**:
- [ ] All 5 `.agent.md` files have `skills:` list declarations
- [ ] Prompts contain explicit "may only invoke the following skills" constraint
- [ ] Prompts contain "must not invoke other roles' skills" negative constraint
- [ ] Assignment matrix matches the table above (7 shared + role-specific)

### R3: Update Skills Mechanism Architecture Documentation

**Priority**: MEDIUM  
**Type**: Documentation update

`docs/skills-mechanism.md` needs updates to reflect latest findings.

**Acceptance Criteria**:
- [ ] New "two-level loading" flowchart (Mermaid sequence diagram)
- [ ] New cross-platform skill discovery path comparison diagram
- [ ] Updated per-agent isolation description (from "full injection" to "summary + on-demand")
- [ ] Document hot-reload differences and memoize cache considerations per platform

### R4: Support Two Installation Methods

**Priority**: MEDIUM  
**Type**: Documentation + feature enhancement

#### R4-A: One-Click Install (Script-Automated)

```bash
curl -sL https://raw.githubusercontent.com/cintia09/multi-agent-framework/main/install.sh | bash
```

Existing functionality, maintained as-is. Script auto-detects platform, downloads, and installs all components.

#### R4-B: Prompt-Based Install (AI-Guided)

User tells AI assistant:
> "Follow the instructions in the cintia09/multi-agent-framework repo to install agents locally."

The AI assistant reads README and completes installation following the documentation.

**README must include sufficiently clear installation instructions**, covering:
1. Target directory structure (`~/.claude/` and `~/.copilot/`)
2. Files to copy (18 skills, 5 agents, 13 hooks, hooks.json, rules)
3. File mappings (e.g., `hooks.json` vs `hooks-copilot.json`)
4. Permission settings (`chmod +x` hook scripts)
5. Verification commands (how to confirm successful installation)

**Acceptance Criteria**:
- [ ] README "One-Click Install" section maintains `curl | bash` approach
- [ ] README adds "Prompt-Based Install" section with prompt text for AI
- [ ] README has complete manual installation steps (directory structure + file list + permissions) that AI can directly follow
- [ ] Manual install steps are consistent with `install.sh` logic
- [ ] Includes post-installation verification method (`install.sh --check`)

### R5: Add `paths:` Conditional Activation (Optional)

**Priority**: LOW  
**Type**: Feature enhancement (optional)

Add `paths:` frontmatter conditions to applicable skills:

| Skill | paths condition |
|-------|----------------|
| agent-tester | `tests/**`, `**/*.test.*`, `**/*.spec.*` |
| agent-hooks | `hooks/**`, `**/*.sh` |
| agent-implementer | `src/**`, `lib/**`, `**/*.ts`, `**/*.py` |

**Acceptance Criteria**:
- [ ] Skills with `paths:` only appear in summary list when matching files are present
- [ ] Does not affect manual `/skillname` invocation
- [ ] Does not affect Copilot CLI compatibility

---

## 3. Priority Ranking

```
R2 (HIGH)   → Per-agent skill isolation (security feature)
R1 (HIGH)   → Fix token documentation (eliminate misconceptions)
R4 (MEDIUM) → Dual-mode installation (one-click + interactive)
R3 (MEDIUM) → Architecture documentation update (knowledge capture)
R5 (LOW)    → paths: conditional activation (nice-to-have)
```

**Recommended implementation order**: R2 → R1 → R4 → R3 → R5

---

## 4. Constraints & Assumptions

1. **No platform code changes** — All optimizations at framework level (`.agent.md`, `SKILL.md`, docs, `install.sh`)
2. **Backward compatible** — `install.sh` without arguments maintains current behavior
3. **Agent Skills open standard** — All changes comply with `agentskills.io` spec
4. **Dual platform** — All changes apply to both Claude Code and Copilot CLI
5. **Prompt-based install dependency** — README docs must be clear enough for AI assistants (Claude Code/Copilot CLI) to follow directly
6. **Isolation scope** — Per-agent skill isolation **only affects project-level** 5 agent roles (designer/implementer/tester/reviewer/acceptor). Does not affect normal skill usage outside agent mode, does not affect global baoyu-* or other skills, does not affect other projects

---

## 5. Non-Functional Requirements

- **Token efficiency**: After per-agent isolation, each agent's summary list drops from 18 to ~10-12 skills
- **Auditability**: Skill constraint lists in `.agent.md` can be directly used for auditing
- **Installation experience**: Prompt-based install README instructions must be clear enough for AI assistants to execute directly
- **Documentation accuracy**: All documentation diagrams must match actual implementation
