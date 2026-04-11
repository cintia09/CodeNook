#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ERRORS=0

EXPECTED_HOOKS=(
    "agent-session-start.sh"
    "agent-pre-tool-use.sh"
    "agent-post-tool-use.sh"
    "agent-staleness-check.sh"
    "agent-before-switch.sh"
    "agent-after-switch.sh"
    "agent-before-task-create.sh"
    "agent-after-task-status.sh"
    "agent-before-memory-write.sh"
    "agent-after-memory-write.sh"
    "agent-before-compaction.sh"
    "agent-on-goal-verified.sh"
    "security-scan.sh"
)

for hook in "${EXPECTED_HOOKS[@]}"; do
    hook_file="${REPO_DIR}/hooks/${hook}"
    
    if [ ! -f "$hook_file" ]; then
        echo "  ❌ ${hook}: not found"
        ERRORS=$((ERRORS + 1))
        continue
    fi
    
    # Check executable
    if [ ! -x "$hook_file" ]; then
        echo "  ❌ ${hook}: not executable"
        ERRORS=$((ERRORS + 1))
        continue
    fi
    
    # Check shebang
    if ! head -1 "$hook_file" | grep -q "^#!/usr/bin/env bash"; then
        echo "  ❌ ${hook}: shebang not #!/usr/bin/env bash"
        ERRORS=$((ERRORS + 1))
        continue
    fi
    
    # Check set -euo pipefail (within first 10 lines)
    if ! head -10 "$hook_file" | grep -q "set -euo pipefail"; then
        echo "  ❌ ${hook}: missing set -euo pipefail"
        ERRORS=$((ERRORS + 1))
        continue
    fi
done

# Check hooks.json exists and is valid JSON
if [ ! -f "${REPO_DIR}/hooks/hooks.json" ]; then
    echo "  ❌ hooks.json: not found"
    ERRORS=$((ERRORS + 1))
elif ! jq empty "${REPO_DIR}/hooks/hooks.json" 2>/dev/null; then
    echo "  ❌ hooks.json: invalid JSON"
    ERRORS=$((ERRORS + 1))
fi

# Check hooks-copilot.json exists and is valid JSON
if [ ! -f "${REPO_DIR}/hooks/hooks-copilot.json" ]; then
    echo "  ❌ hooks-copilot.json: not found"
    ERRORS=$((ERRORS + 1))
elif ! jq empty "${REPO_DIR}/hooks/hooks-copilot.json" 2>/dev/null; then
    echo "  ❌ hooks-copilot.json: invalid JSON"
    ERRORS=$((ERRORS + 1))
fi

# Check both JSON files have valid structure
# Note: Copilot CLI only supports 3 events (sessionStart, preToolUse, postToolUse)
# while Claude Code supports 9 events (includes custom events: agentSwitch, taskCreate, etc.)
if [ -f "${REPO_DIR}/hooks/hooks.json" ] && [ -f "${REPO_DIR}/hooks/hooks-copilot.json" ]; then
    CLAUDE_EVENTS=$(jq '.hooks | keys | length' "${REPO_DIR}/hooks/hooks.json")
    COPILOT_EVENTS=$(jq '.hooks | keys | length' "${REPO_DIR}/hooks/hooks-copilot.json")
    # Copilot must have at least sessionStart + preToolUse + postToolUse
    if [ "$COPILOT_EVENTS" -lt 3 ]; then
        echo "  ❌ hooks-copilot.json has only ${COPILOT_EVENTS} events (minimum 3 required)"
        ERRORS=$((ERRORS + 1))
    fi
    # Copilot events must be a subset of Claude events
    if [ "$COPILOT_EVENTS" -gt "$CLAUDE_EVENTS" ]; then
        echo "  ❌ hooks-copilot.json has more events (${COPILOT_EVENTS}) than hooks.json (${CLAUDE_EVENTS})"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Check rules/ directory
EXPECTED_RULES=("agent-workflow.md" "security.md" "commit-standards.md")
for rule in "${EXPECTED_RULES[@]}"; do
    if [ ! -f "${REPO_DIR}/rules/${rule}" ]; then
        echo "  ❌ rules/${rule}: not found"
        ERRORS=$((ERRORS + 1))
    fi
done

exit $ERRORS
