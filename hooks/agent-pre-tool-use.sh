#!/usr/bin/env bash
# Multi-Agent Framework: Pre-Tool-Use Hook
# Enforces agent boundaries — prevents agents from doing things outside their role.
# Can output {"permissionDecision":"deny","permissionDecisionReason":"..."} to block.

set -euo pipefail
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.toolName')
TOOL_ARGS=$(echo "$INPUT" | jq -r '.toolArgs')
CWD=$(echo "$INPUT" | jq -r '.cwd')

# --- Locate project root (walk up from cwd, then try file path) ---
find_agents_dir() {
  local dir="$1"
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    [ -d "$dir/.agents/runtime" ] && echo "$dir" && return 0
    dir=$(dirname "$dir")
  done
  return 1
}

PROJECT_ROOT=""
# Strategy 1: walk up from cwd
PROJECT_ROOT=$(find_agents_dir "$CWD" 2>/dev/null) || true

# Strategy 2: if not found, try the file path from tool args (edit/create targets)
if [ -z "$PROJECT_ROOT" ]; then
  FILE_HINT=$(echo "$TOOL_ARGS" | jq -r '.path // empty' 2>/dev/null)
  if [ -n "$FILE_HINT" ]; then
    PROJECT_ROOT=$(find_agents_dir "$(dirname "$FILE_HINT")" 2>/dev/null) || true
  fi
fi

# Strategy 3: try bash command's cd target or common project paths
if [ -z "$PROJECT_ROOT" ]; then
  BASH_CMD_HINT=$(echo "$TOOL_ARGS" | jq -r '.command // empty' 2>/dev/null)
  if echo "$BASH_CMD_HINT" | grep -qo 'cd [^ ;|&]*' 2>/dev/null; then
    CD_TARGET=$(echo "$BASH_CMD_HINT" | grep -o 'cd [^ ;|&]*' | head -1 | sed 's/^cd //')
    # Expand ~ to HOME
    CD_TARGET="${CD_TARGET/#\~/$HOME}"
    [ -d "$CD_TARGET" ] && PROJECT_ROOT=$(find_agents_dir "$CD_TARGET" 2>/dev/null) || true
  fi
fi

[ -n "$PROJECT_ROOT" ] || exit 0
AGENTS_DIR="$PROJECT_ROOT/.agents"

# Only enforce if an agent is active
ACTIVE_FILE="$AGENTS_DIR/runtime/active-agent"
[ -f "$ACTIVE_FILE" ] || exit 0

ACTIVE_AGENT=$(cat "$ACTIVE_FILE")
[ -n "$ACTIVE_AGENT" ] || exit 0

# --- Boundary Rules ---
case "$TOOL_NAME" in
  edit|create)
    FILE_PATH=$(echo "$TOOL_ARGS" | jq -r '.path // empty' 2>/dev/null)
    [ -n "$FILE_PATH" ] || exit 0

    # Normalize: remove project root prefix for relative comparison
    REL_PATH="${FILE_PATH#"$PROJECT_ROOT"/}"

    case "$ACTIVE_AGENT" in
      acceptor)
        # Acceptor can only edit: .agents/ files (requirements, acceptance reports, task board)
        # Cannot edit source code
        if [[ ! "$REL_PATH" =~ ^\.agents/ ]] && [[ ! "$REL_PATH" =~ ^\.github/ ]]; then
          echo '{"permissionDecision":"deny","permissionDecisionReason":"🎯 Acceptor cannot edit source code. Use task-board to create tasks or messaging to communicate."}'
          exit 0
        fi
        ;;
      reviewer)
        # Reviewer can edit: .agents/runtime/reviewer/ (review reports), .agents/docs/ (review-report.md)
        # Cannot edit source code or other agents' files
        if [[ ! "$REL_PATH" =~ ^\.agents/runtime/reviewer/ ]] && [[ ! "$REL_PATH" =~ ^\.agents/task-board ]] && [[ ! "$REL_PATH" =~ ^\.agents/docs/ ]]; then
          echo '{"permissionDecision":"deny","permissionDecisionReason":"🔍 Reviewer cannot edit source code. Write review reports in .agents/runtime/reviewer/workspace/."}'
          exit 0
        fi
        ;;
      designer)
        # Designer can edit: .agents/ (design docs, task board) but not source code
        if [[ ! "$REL_PATH" =~ ^\.agents/ ]]; then
          echo '{"permissionDecision":"deny","permissionDecisionReason":"🏗️ Designer cannot edit source code directly. Output design docs to .agents/runtime/designer/workspace/."}'
          exit 0
        fi
        ;;
      tester)
        # Tester can edit: .agents/runtime/tester/ and test files
        # Can also run tests (bash tool) but not edit source
        if [[ ! "$REL_PATH" =~ ^\.agents/ ]] && [[ ! "$REL_PATH" =~ ^tests?/ ]] && [[ ! "$REL_PATH" =~ \.test\. ]] && [[ ! "$REL_PATH" =~ \.spec\. ]]; then
          echo '{"permissionDecision":"deny","permissionDecisionReason":"🧪 Tester cannot edit source code. Write test cases in test directories or .agents/runtime/tester/workspace/."}'
          exit 0
        fi
        ;;
      implementer)
        # Implementer has the broadest access — can edit source code
        # But cannot edit other agents' workspaces
        if [[ "$REL_PATH" =~ ^\.agents/runtime/(acceptor|designer|reviewer|tester)/ ]]; then
          echo '{"permissionDecision":"deny","permissionDecisionReason":"💻 Implementer cannot edit other agents workspaces. Use messaging to communicate."}'
          exit 0
        fi
        ;;
    esac
    ;;
  bash)
    # Enforce bash command boundaries for non-implementer roles
    BASH_CMD=$(echo "$TOOL_ARGS" | jq -r '.command // empty' 2>/dev/null)
    [ -n "$BASH_CMD" ] || exit 0
    case "$ACTIVE_AGENT" in
      acceptor|designer)
        # Read-only roles: block destructive commands and file writes
        if echo "$BASH_CMD" | grep -qE '(^|\s)(rm|mv|cp|git\s+push|git\s+commit|npm\s+publish|docker\s+run|chmod|chown)(\s|$)'; then
          AGENT_JSON_ESC=$(echo "$ACTIVE_AGENT" | sed 's/"/\\"/g')
          echo "{\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"${AGENT_JSON_ESC} cannot run write/destructive commands via bash.\"}"
          exit 0
        fi
        # Block bash file-write patterns (redirects, in-place edits) outside .agents/
        if echo "$BASH_CMD" | grep -qE '(>[^&]|>>|tee\s|sed\s+-i|patch\s|dd\s)' && \
           ! echo "$BASH_CMD" | grep -qE '\.agents/'; then
          AGENT_JSON_ESC=$(echo "$ACTIVE_AGENT" | sed 's/"/\\"/g')
          echo "{\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"${AGENT_JSON_ESC} cannot write to files via bash redirects. Use task-board or messaging instead.\"}"
          exit 0
        fi
        ;;
      reviewer)
        # Reviewer: read + git diff/log allowed, no writes
        if echo "$BASH_CMD" | grep -qE '(^|\s)(rm|mv|cp|git\s+push|git\s+commit|npm\s+publish|docker\s+run|chmod|chown)(\s|$)'; then
          echo '{"permissionDecision":"deny","permissionDecisionReason":"🔍 Reviewer cannot run write/destructive commands via bash."}'
          exit 0
        fi
        # Block bash file-write patterns outside .agents/
        if echo "$BASH_CMD" | grep -qE '(>[^&]|>>|tee\s|sed\s+-i|patch\s|dd\s)' && \
           ! echo "$BASH_CMD" | grep -qE '\.agents/'; then
          echo '{"permissionDecision":"deny","permissionDecisionReason":"🔍 Reviewer cannot write to files via bash redirects."}'
          exit 0
        fi
        ;;
      tester)
        # Tester: can run tests, read code, but not modify source or deploy
        if echo "$BASH_CMD" | grep -qE '(^|\s)(git\s+push|git\s+commit|npm\s+publish|docker\s+run|chmod|chown)(\s|$)'; then
          echo '{"permissionDecision":"deny","permissionDecisionReason":"🧪 Tester cannot run commit/publish/deploy commands. Use test runners only."}'
          exit 0
        fi
        # Block destructive commands on non-test files
        if echo "$BASH_CMD" | grep -qE '(^|\s)(rm|mv|cp)(\s)' && \
           ! echo "$BASH_CMD" | grep -qE '(tests?/|\.test\.|\.spec\.|\.agents/|/tmp/)'; then
          echo '{"permissionDecision":"deny","permissionDecisionReason":"🧪 Tester cannot modify non-test files via rm/mv/cp."}'
          exit 0
        fi
        # Block bash file-write patterns outside .agents/ and test dirs
        if echo "$BASH_CMD" | grep -qE '(>[^&]|>>|tee\s|sed\s+-i|patch\s|dd\s)' && \
           ! echo "$BASH_CMD" | grep -qE '(\.agents/|tests?/|\.test\.|\.spec\.)'; then
          echo '{"permissionDecision":"deny","permissionDecisionReason":"🧪 Tester cannot write to non-test files via bash redirects."}'
          exit 0
        fi
        ;;
      implementer)
        # Implementer: broadest access but cannot touch other agents' workspaces or deploy
        # Block editing other agents' runtime directories via redirects
        if echo "$BASH_CMD" | grep -qE '(>[^&]|>>|tee\s|sed\s+-i)' && \
           echo "$BASH_CMD" | grep -qE '\.agents/runtime/(acceptor|designer|reviewer|tester)/'; then
          echo '{"permissionDecision":"deny","permissionDecisionReason":"💻 Implementer cannot write to other agents workspaces via bash. Use messaging."}'
          exit 0
        fi
        # Block direct deploy without going through review pipeline
        if echo "$BASH_CMD" | grep -qE '(^|\s)(npm\s+publish|docker\s+push)(\s|$)'; then
          echo '{"permissionDecision":"deny","permissionDecisionReason":"💻 Implementer cannot publish/deploy directly. Code must go through review first."}'
          exit 0
        fi
        ;;
    esac
    ;;
esac

# Allow by default
