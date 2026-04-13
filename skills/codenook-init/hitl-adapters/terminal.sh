#!/usr/bin/env bash
# HITL Terminal Adapter — Pure CLI review for headless/Docker environments
# No browser needed. Fully self-contained — no dependency on ask_user or any LLM tool.
#
# Usage:
#   terminal.sh publish          <task_id> <role> <content_file>
#   terminal.sh record_feedback  <task_id> <role> <decision> [<comment>]
#   terminal.sh poll             <task_id> <role>
#   terminal.sh get_feedback     <task_id> <role>
#
# Flow: publish → (orchestrator collects user response) → record_feedback → poll/get_feedback

set -euo pipefail

# Dependency check
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required for HITL terminal adapter but not found" >&2
  exit 1
fi

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# Detect platform root: .github/codenook/ or .claude/codenook/
if [ -d "$PROJECT_ROOT/.github/codenook" ]; then
  CODENOOK_DIR="$PROJECT_ROOT/.github/codenook"
elif [ -d "$PROJECT_ROOT/.claude/codenook" ]; then
  CODENOOK_DIR="$PROJECT_ROOT/.claude/codenook"
else
  CODENOOK_DIR="$PROJECT_ROOT/.github/codenook"
fi
REVIEWS_DIR="$CODENOOK_DIR/reviews"
mkdir -p "$REVIEWS_DIR"

command="${1:-}"
task_id="${2:-}"
role="${3:-}"
content_file="${4:-}"

# Validate task_id and role (path traversal protection)
if [ -n "$task_id" ] && ! echo "$task_id" | grep -qE '^T-[0-9]+$'; then
  echo "ERROR: Invalid task_id format. Expected T-NNN" >&2
  exit 1
fi
if [ -n "$role" ] && ! echo "$role" | grep -qE '^(acceptor|designer|implementer|reviewer|tester)$'; then
  echo "ERROR: Invalid role. Expected one of: acceptor designer implementer reviewer tester" >&2
  exit 1
fi

case "$command" in
  publish)
    if [ -z "$task_id" ] || [ -z "$role" ] || [ -z "$content_file" ]; then
      echo "Usage: terminal.sh publish <task_id> <role> <content_file>"
      exit 1
    fi

    if [ ! -f "$content_file" ]; then
      echo "ERROR: Content file not found: $content_file" >&2
      exit 1
    fi

    # Clear any previous feedback
    rm -f "$REVIEWS_DIR/${task_id}-${role}-feedback.json"

    # Copy content for reference
    cp "$content_file" "$REVIEWS_DIR/${task_id}-${role}-content.md"

    # Write status
    cat > "$REVIEWS_DIR/${task_id}-${role}-terminal-status.json" <<EOF
{
  "task_id": "$task_id",
  "role": "$role",
  "status": "pending_review",
  "content_file": "$content_file",
  "published_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 HITL Review: $task_id ($role)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📄 Document: $content_file"
    echo ""
    echo "--- Document Content ---"
    cat "$content_file"
    echo ""
    echo "--- End of Document ---"
    echo ""
    echo "📌 To record your decision, use:"
    echo "   terminal.sh record_feedback ${task_id} ${role} approve"
    echo "   terminal.sh record_feedback ${task_id} ${role} changes \"your feedback\""
    echo ""
    echo "terminal://${task_id}/${role}"
    ;;

  record_feedback)
    if [ -z "$task_id" ] || [ -z "$role" ] || [ -z "$content_file" ]; then
      echo "Usage: terminal.sh record_feedback <task_id> <role> <approve|changes> [comment]"
      exit 1
    fi

    decision="$content_file"  # positional $4 reused
    comment="${5:-}"

    if [ "$decision" != "approve" ] && [ "$decision" != "changes" ]; then
      echo "ERROR: decision must be 'approve' or 'changes'" >&2
      exit 1
    fi

    feedback_file="$REVIEWS_DIR/${task_id}-${role}-feedback.json"
    python3 -c "
import json, sys
fb = {
    'task_id': sys.argv[1],
    'role': sys.argv[2],
    'decision': sys.argv[3],
    'feedback': sys.argv[4] if len(sys.argv) > 4 else '',
    'recorded_at': __import__('datetime').datetime.now(__import__('datetime').timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
}
with open(sys.argv[5], 'w') as f:
    json.dump(fb, f, indent=2)
" "$task_id" "$role" "$decision" "$comment" "$feedback_file"

    echo "✅ Feedback recorded: $decision"
    [ -n "$comment" ] && echo "   Comment: $comment"
    ;;

  poll)
    if [ -z "$task_id" ] || [ -z "$role" ]; then
      echo "Usage: terminal.sh poll <task_id> <role>"
      exit 1
    fi

    feedback_file="$REVIEWS_DIR/${task_id}-${role}-feedback.json"
    if [ -f "$feedback_file" ]; then
      decision=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('decision','pending'))" "$feedback_file" 2>/dev/null || echo "pending")
      echo "$decision"
    else
      echo "pending_review"
    fi
    ;;

  get_feedback)
    if [ -z "$task_id" ] || [ -z "$role" ]; then
      echo "Usage: terminal.sh get_feedback <task_id> <role>"
      exit 1
    fi

    feedback_file="$REVIEWS_DIR/${task_id}-${role}-feedback.json"
    if [ -f "$feedback_file" ]; then
      cat "$feedback_file"
    else
      echo '{"decision":"pending_review","feedback":""}'
    fi
    ;;

  *)
    echo "Usage: terminal.sh <publish|record_feedback|poll|get_feedback> <task_id> <role> [content_file|decision] [comment]"
    exit 1
    ;;
esac
