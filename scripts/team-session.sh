#!/usr/bin/env bash
set -euo pipefail
# Team Session — launch multi-agent tmux session
# Usage: bash scripts/team-session.sh [--agents <roles>] [--task <T-XXX>] [--layout <layout>]
#        bash scripts/team-session.sh --worktree --tasks T-042,T-043

SESSION_NAME="agent-team"
AGENTS="acceptor,designer,implementer,reviewer,tester"
TASK_FILTER=""
LAYOUT="tiled"
WORKTREE_MODE=false
TASKS=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agents)    [ -z "${2:-}" ] && { echo "❌ Missing value for --agents"; exit 1; }; AGENTS="$2"; shift 2 ;;
    --task)      [ -z "${2:-}" ] && { echo "❌ Missing value for --task"; exit 1; }; TASK_FILTER="$2"; shift 2 ;;
    --layout)    [ -z "${2:-}" ] && { echo "❌ Missing value for --layout"; exit 1; }; LAYOUT="$2"; shift 2 ;;
    --worktree)  WORKTREE_MODE=true; shift ;;
    --tasks)     [ -z "${2:-}" ] && { echo "❌ Missing value for --tasks"; exit 1; }; TASKS="$2"; shift 2 ;;
    --help)
      echo "Usage: team-session.sh [--agents roles] [--task T-XXX] [--layout layout]"
      echo "       team-session.sh --worktree --tasks T-042,T-043"
      echo ""
      echo "Standard mode:"
      echo "  --agents  Comma-separated agent roles (default: all 5)"
      echo "  --task    Focus agents on a specific task"
      echo "  --layout  tmux layout (default: tiled)"
      echo ""
      echo "Worktree mode:"
      echo "  --worktree  Enable worktree mode (one tmux window per task)"
      echo "  --tasks     Comma-separated task IDs (required with --worktree)"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Validate worktree mode requires --tasks
if [ "$WORKTREE_MODE" = true ] && [ -z "$TASKS" ]; then
  echo "❌ --worktree requires --tasks T-042,T-043"
  exit 1
fi

# Check tmux
if ! command -v tmux &>/dev/null; then
  echo "❌ tmux is required. Install with: brew install tmux (macOS) or apt install tmux (Linux)"
  exit 1
fi

# Kill existing session if running
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

# ──────────────────────────────────────────────────
# Worktree Mode: one tmux window per task worktree
# ──────────────────────────────────────────────────
if [ "$WORKTREE_MODE" = true ]; then
  IFS=',' read -ra TASK_LIST <<< "$TASKS"
  TASK_COUNT=${#TASK_LIST[@]}
  PROJECT_NAME=$(basename "$PROJECT_DIR")

  echo "🚀 Launching Worktree Team Session"
  echo "   Tasks: ${TASKS}"
  echo "   Layout: ${LAYOUT}"
  echo ""

  # Resolve worktree paths from git
  WORKTREE_LIST=$(cd "$PROJECT_DIR" && git worktree list --porcelain 2>/dev/null || true)
  FIRST=true
  WINDOW_IDX=0

  for TASK_ID in "${TASK_LIST[@]}"; do
    # Find worktree path for this task
    WT_PATH=$(echo "$WORKTREE_LIST" | awk -v tid="$TASK_ID" '
      /^worktree / { path=$2 }
      /^branch / && path && $0 ~ "task/" tid { print path; exit }
    ')

    # Fallback: check conventional path
    if [ -z "$WT_PATH" ]; then
      CANDIDATE="$(dirname "$PROJECT_DIR")/${PROJECT_NAME}--${TASK_ID}"
      [ -d "$CANDIDATE" ] && WT_PATH="$CANDIDATE"
    fi

    if [ -z "$WT_PATH" ]; then
      echo "⚠️  No worktree found for $TASK_ID (skipping)"
      continue
    fi

    SAFE_WT=$(printf '%s' "$WT_PATH" | sed "s/'/'\\\\''/g")
    SAFE_TID=$(printf '%s' "$TASK_ID" | sed "s/'/'\\\\''/g")
    WT_CMD="cd '${SAFE_WT}' && echo '🌳 Worktree: ${SAFE_TID}' && echo '📂 $(basename "$WT_PATH")' && echo 'Branch: task/${SAFE_TID}' && echo '---'"

    if [ "$FIRST" = true ]; then
      tmux new-session -d -s "$SESSION_NAME" -x 200 -y 50 "$WT_CMD; bash"
      tmux rename-window -t "$SESSION_NAME:0" "$TASK_ID"
      FIRST=false
    else
      tmux new-window -t "$SESSION_NAME" -n "$TASK_ID" "$WT_CMD; bash"
    fi
    WINDOW_IDX=$((WINDOW_IDX + 1))
  done

  if [ "$FIRST" = true ]; then
    echo "❌ No valid worktrees found for any task"
    exit 1
  fi

  # Add dashboard window (stays in main project dir)
  SAFE_PROJECT=$(printf '%s' "$PROJECT_DIR" | sed "s/'/'\\\\''/g")
  SAFE_SCRIPT_DIR=$(printf '%s' "$SCRIPT_DIR" | sed "s/'/'\\\\''/g")
  if command -v watch &>/dev/null; then
    DASHBOARD_CMD="cd '${SAFE_PROJECT}' && watch -n 10 'bash \"${SAFE_SCRIPT_DIR}/team-dashboard.sh\" 2>/dev/null || echo \"Dashboard loading...\"'"
  else
    DASHBOARD_CMD="cd '${SAFE_PROJECT}' && while true; do clear; bash '${SAFE_SCRIPT_DIR}/team-dashboard.sh' 2>/dev/null || echo 'Dashboard loading...'; sleep 10; done"
  fi
  tmux new-window -t "$SESSION_NAME" -n "dashboard" "$DASHBOARD_CMD"

  # Select first task window
  tmux select-window -t "$SESSION_NAME:0"

  echo "✅ Worktree session created: $SESSION_NAME"
  echo "   Windows: ${WINDOW_IDX} task(s) + dashboard"
  echo ""
  echo "  Attach:       tmux attach -t $SESSION_NAME"
  echo "  Switch task:  Ctrl+B → n/p (next/prev window)"
  echo "  List windows: Ctrl+B → w"
  echo "  Kill:         tmux kill-session -t $SESSION_NAME"
  echo ""

  tmux attach -t "$SESSION_NAME"
  exit 0
fi

# ──────────────────────────────────────────────────
# Standard Mode: split panes for agents in one window
# ──────────────────────────────────────────────────
IFS=',' read -ra AGENT_LIST <<< "$AGENTS"
AGENT_COUNT=${#AGENT_LIST[@]}

if [ "$AGENT_COUNT" -lt 1 ]; then
  echo "❌ At least one agent role is required"
  exit 1
fi

echo "🚀 Launching Agent Team Session"
echo "   Agents: ${AGENTS}"
echo "   Layout: ${LAYOUT}"
[ -n "$TASK_FILTER" ] && echo "   Task: ${TASK_FILTER}"
echo ""

# Create first pane with first agent (escape single quotes for tmux)
FIRST_AGENT="${AGENT_LIST[0]}"
SAFE_PROJECT=$(printf '%s' "$PROJECT_DIR" | sed "s/'/'\\\\''/g")
SAFE_FILTER=$(printf '%s' "${TASK_FILTER:-all}" | sed "s/'/'\\\\''/g")
SAFE_FIRST=$(printf '%s' "$FIRST_AGENT" | sed "s/'/'\\\\''/g")
AGENT_CMD="cd '${SAFE_PROJECT}' && echo '🤖 Agent: ${SAFE_FIRST}' && echo 'Task: ${SAFE_FILTER}' && echo '---'"
tmux new-session -d -s "$SESSION_NAME" -x 200 -y 50 "$AGENT_CMD; bash"

# Create additional panes for remaining agents
for ((i=1; i<AGENT_COUNT; i++)); do
  AGENT="${AGENT_LIST[$i]}"
  SAFE_AGENT=$(printf '%s' "$AGENT" | sed "s/'/'\\\\''/g")
  AGENT_CMD="cd '${SAFE_PROJECT}' && echo '🤖 Agent: ${SAFE_AGENT}' && echo 'Task: ${SAFE_FILTER}' && echo '---'"
  tmux split-window -t "$SESSION_NAME" "$AGENT_CMD; bash"
  tmux select-layout -t "$SESSION_NAME" "$LAYOUT"
done

# Add dashboard pane
SAFE_SCRIPT_DIR=$(printf '%s' "$SCRIPT_DIR" | sed "s/'/'\\\\''/g")
if command -v watch &>/dev/null; then
  DASHBOARD_CMD="cd '${SAFE_PROJECT}' && watch -n 10 'bash \"${SAFE_SCRIPT_DIR}/team-dashboard.sh\" 2>/dev/null || echo \"Dashboard loading...\"'"
else
  DASHBOARD_CMD="cd '${SAFE_PROJECT}' && while true; do clear; bash '${SAFE_SCRIPT_DIR}/team-dashboard.sh' 2>/dev/null || echo 'Dashboard loading...'; sleep 10; done"
fi
tmux split-window -t "$SESSION_NAME" -l 8 "$DASHBOARD_CMD"

# Final layout
tmux select-layout -t "$SESSION_NAME" "$LAYOUT" 2>/dev/null || true

# Set pane titles
for ((i=0; i<AGENT_COUNT; i++)); do
  tmux select-pane -t "$SESSION_NAME:0.$i" -T "${AGENT_LIST[$i]}"
done
tmux select-pane -t "$SESSION_NAME:0.$AGENT_COUNT" -T "dashboard"

# Enable pane borders with titles
tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-border-format " #{pane_title} " 2>/dev/null || true

# Select first pane
tmux select-pane -t "$SESSION_NAME:0.0"

echo "✅ Team session created: $SESSION_NAME"
echo ""
echo "  Attach:     tmux attach -t $SESSION_NAME"
echo "  Navigate:   Ctrl+B → arrow keys"
echo "  Zoom pane:  Ctrl+B → z"
echo "  Kill:       tmux kill-session -t $SESSION_NAME"
echo ""

# Attach
tmux attach -t "$SESSION_NAME"
