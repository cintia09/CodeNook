# Multi-Agent Software Development Framework

## Installation Guide

When the user says "install from multi-agent-framework" or similar, **automatically execute these steps**:

> ⚠️ **Important**: Clone the repo first, then use `cp` to copy files. **Do NOT** use `cat > file << EOF` or other methods to recreate file contents — always copy from repo source to ensure consistency.

### Step 1: Clone to Temporary Directory
```bash
git clone --depth 1 git@github.com:cintia09/multi-agent-framework.git /tmp/multi-agent-framework
```

### Step 2: Copy Skills (must use cp, no heredoc)
```bash
mkdir -p ~/.claude/skills
cp -r /tmp/multi-agent-framework/skills/agent-* ~/.claude/skills/
```

### Step 3: Copy Agent Profiles (must use cp, no heredoc)
```bash
mkdir -p ~/.claude/agents
cp /tmp/multi-agent-framework/agents/*.agent.md ~/.claude/agents/
```

### Step 4: Install Hooks (must use cp, no heredoc)
```bash
mkdir -p ~/.claude/hooks
cp /tmp/multi-agent-framework/hooks/*.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/agent-*.sh
chmod +x ~/.claude/hooks/security-scan.sh
```

If `~/.claude/hooks/hooks.json` already exists, **merge** hook config rather than overwriting:
```bash
if [ -f ~/.claude/hooks/hooks.json ]; then
  echo "⚠️ hooks.json already exists — merge hooks/hooks.json manually"
else
  cp /tmp/multi-agent-framework/hooks/hooks.json ~/.claude/hooks/
fi
```

### Step 5: Append Collaboration Rules (idempotent)
```bash
# Legacy: append to CLAUDE.md
if ! grep -q "## Agent Collaboration Rules" ~/.claude/CLAUDE.md 2>/dev/null; then
  echo "" >> ~/.claude/CLAUDE.md
  cat /tmp/multi-agent-framework/docs/agent-rules.md >> ~/.claude/CLAUDE.md
fi

# Modular rules (.claude/rules/ — Claude Code native)
mkdir -p ~/.claude/rules
cp /tmp/multi-agent-framework/rules/*.md ~/.claude/rules/
```

### Step 6: Verify Installation
```bash
echo "Skills:" && ls -d ~/.claude/skills/agent-* | wc -l
echo "Agents:" && ls ~/.claude/agents/*.agent.md | wc -l
echo "Hooks:" && ls ~/.claude/hooks/*.sh | wc -l
echo "hooks.json:" && [ -f ~/.claude/hooks/hooks.json ] && echo "✅" || echo "❌"
```
Expected: 15 skill directories, 5 agent files, 13 hook scripts, hooks.json present.

### Step 7: Deep Verification (optional)
For more thorough validation (skill format, YAML frontmatter, file permissions, etc.), run the verification scripts:
```bash
# Verify installation completeness
bash /tmp/multi-agent-framework/scripts/verify-install.sh

# After running /init in a project, verify .agents/ directory structure
bash /tmp/multi-agent-framework/scripts/verify-init.sh
```
> ⚠️ Must run before Step 8 cleanup.

### Step 8: Cleanup
```bash
rm -rf /tmp/multi-agent-framework
```

### Step 9: Output Results
```
✅ Multi-Agent Framework installation complete
━━━━━━━━━━━━━━━━━━━━━━━
Skills:  15 installed to ~/.claude/skills/
Agents:  5 installed to ~/.claude/agents/
Hooks:   13 installed to ~/.claude/hooks/ (boundary + audit + lifecycle + memory + scheduling)
Rules:   Appended to ~/.claude/CLAUDE.md + ~/.claude/rules/ (modular rules)
━━━━━━━━━━━━━━━━━━━━━━━
Usage:
  /agent           → Select a role
  /agent acceptor  → Switch directly to Acceptor
  "Initialize Agent system" → Initialize .agents/ directory in a project
```
