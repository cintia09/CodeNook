#!/usr/bin/env bash
# HITL Adapter: Confluence
# Creates/updates Confluence pages for HITL review, polls comments for approval
# Usage:
#   hitl-confluence.sh publish <task_id> <role> <content_md_file>
#   hitl-confluence.sh poll <task_id> <role>
#   hitl-confluence.sh get_feedback <task_id> <role>
#
# Requires: CONFLUENCE_BASE_URL, CONFLUENCE_SPACE_KEY, CONFLUENCE_PARENT_PAGE_ID, CONFLUENCE_TOKEN env vars
# Or configured in .agents/config.json under hitl.confluence

set -euo pipefail

AGENTS_DIR="$(git rev-parse --show-toplevel 2>/dev/null)/.agents"
[ -d "$AGENTS_DIR" ] || AGENTS_DIR="./.agents"
REVIEWS_DIR="$AGENTS_DIR/reviews"
CONFIG_FILE="$AGENTS_DIR/config.json"
mkdir -p "$REVIEWS_DIR"

# Load config
load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    CONFLUENCE_BASE_URL="${CONFLUENCE_BASE_URL:-$(python3 -c "import json; c=json.load(open('$CONFIG_FILE')); print(c.get('hitl',{}).get('confluence',{}).get('base_url',''))" 2>/dev/null || echo "")}"
    CONFLUENCE_SPACE_KEY="${CONFLUENCE_SPACE_KEY:-$(python3 -c "import json; c=json.load(open('$CONFIG_FILE')); print(c.get('hitl',{}).get('confluence',{}).get('space_key',''))" 2>/dev/null || echo "")}"
    CONFLUENCE_PARENT_PAGE_ID="${CONFLUENCE_PARENT_PAGE_ID:-$(python3 -c "import json; c=json.load(open('$CONFIG_FILE')); print(c.get('hitl',{}).get('confluence',{}).get('parent_page_id',''))" 2>/dev/null || echo "")}"
    CONFLUENCE_TOKEN="${CONFLUENCE_TOKEN:-$(python3 -c "import json; c=json.load(open('$CONFIG_FILE')); t=c.get('hitl',{}).get('confluence',{}).get('auth',''); print(t.replace('env:',''))" 2>/dev/null || echo "")}"
    # Resolve env: prefix
    if [[ "$CONFLUENCE_TOKEN" != "" ]] && [[ "$CONFLUENCE_TOKEN" != "CONFLUENCE_TOKEN" ]]; then
      CONFLUENCE_TOKEN="${!CONFLUENCE_TOKEN:-$CONFLUENCE_TOKEN}"
    fi
  fi
}

load_config

cmd="${1:-help}"
task_id="${2:-}"
role="${3:-}"

case "$cmd" in
  publish)
    content_file="${4:-}"
    if [ -z "$task_id" ] || [ -z "$role" ] || [ -z "$content_file" ]; then
      echo "Usage: hitl-confluence.sh publish <task_id> <role> <content_md_file>"
      exit 1
    fi

    if [ -z "$CONFLUENCE_BASE_URL" ]; then
      echo "ERROR: CONFLUENCE_BASE_URL not set. Configure in .agents/config.json or env" >&2
      exit 1
    fi

    # Convert markdown to HTML
    if command -v pandoc >/dev/null 2>&1; then
      content_html=$(pandoc -f markdown -t html "$content_file" 2>/dev/null)
    else
      content_html="<pre>$(cat "$content_file" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')</pre>"
    fi

    title="HITL Review: ${task_id} - ${role}"

    # Create Confluence page
    page_data=$(cat <<EOF
{
  "type": "page",
  "title": "$title",
  "space": {"key": "$CONFLUENCE_SPACE_KEY"},
  "ancestors": [{"id": "$CONFLUENCE_PARENT_PAGE_ID"}],
  "body": {
    "storage": {
      "value": "<h2>Status: ⏳ Pending Review</h2><p>Comment <b>approved</b> to approve, or add feedback comments.</p><hr/>${content_html}",
      "representation": "storage"
    }
  }
}
EOF
)

    response=$(curl -s -X POST \
      "${CONFLUENCE_BASE_URL}/rest/api/content" \
      -H "Authorization: Bearer ${CONFLUENCE_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$page_data")

    page_id=$(echo "$response" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

    if [ -n "$page_id" ]; then
      echo "$page_id" > "$REVIEWS_DIR/${task_id}-${role}-confluence.txt"
      page_url="${CONFLUENCE_BASE_URL}/pages/viewpage.action?pageId=${page_id}"
      echo "$page_url"
    else
      echo "ERROR: Failed to create Confluence page" >&2
      echo "$response" >&2
      exit 1
    fi
    ;;

  poll)
    if [ -z "$task_id" ] || [ -z "$role" ]; then
      echo "Usage: hitl-confluence.sh poll <task_id> <role>"
      exit 1
    fi

    page_file="$REVIEWS_DIR/${task_id}-${role}-confluence.txt"
    if [ ! -f "$page_file" ]; then
      echo "pending_review"
      exit 0
    fi

    page_id=$(cat "$page_file")

    comments=$(curl -s \
      "${CONFLUENCE_BASE_URL}/rest/api/content/${page_id}/child/comment" \
      -H "Authorization: Bearer ${CONFLUENCE_TOKEN}" 2>/dev/null || echo '{"results":[]}')

    status=$(echo "$comments" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for c in data.get('results', []):
    body = c.get('body', {}).get('storage', {}).get('value', '').strip().lower()
    if 'approved' in body or 'lgtm' in body:
        print('approved')
        sys.exit(0)
    elif body:
        print('feedback')
        sys.exit(0)
print('pending_review')
" 2>/dev/null || echo "pending_review")

    echo "$status"
    ;;

  get_feedback)
    if [ -z "$task_id" ] || [ -z "$role" ]; then
      echo "Usage: hitl-confluence.sh get_feedback <task_id> <role>"
      exit 1
    fi

    page_file="$REVIEWS_DIR/${task_id}-${role}-confluence.txt"
    if [ ! -f "$page_file" ]; then
      echo '{"status":"no_page"}'
      exit 0
    fi

    page_id=$(cat "$page_file")
    curl -s \
      "${CONFLUENCE_BASE_URL}/rest/api/content/${page_id}/child/comment?expand=body.storage" \
      -H "Authorization: Bearer ${CONFLUENCE_TOKEN}" 2>/dev/null || echo '{"results":[]}'
    ;;

  *)
    echo "HITL Confluence Adapter"
    echo "Commands: publish, poll, get_feedback"
    echo "Config: .agents/config.json → hitl.confluence.{base_url, space_key, parent_page_id, auth}"
    ;;
esac
