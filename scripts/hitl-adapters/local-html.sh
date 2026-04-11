#!/usr/bin/env bash
# HITL Adapter: Local HTML
# Generates a local HTML review page from markdown content
# Usage:
#   hitl-local-html.sh publish <task_id> <role> <content_md_file>
#   hitl-local-html.sh poll <task_id> <role>
#   hitl-local-html.sh get_feedback <task_id> <role>

set -euo pipefail

AGENTS_DIR="$(git rev-parse --show-toplevel 2>/dev/null)/.agents"
[ -d "$AGENTS_DIR" ] || AGENTS_DIR="./.agents"
REVIEWS_DIR="$AGENTS_DIR/reviews"
TEMPLATE="$AGENTS_DIR/templates/review-page.html"

ROLE_EMOJI_MAP='{"acceptor":"🎯","designer":"🏗️","implementer":"💻","reviewer":"🔍","tester":"🧪"}'

mkdir -p "$REVIEWS_DIR"

cmd="${1:-help}"
task_id="${2:-}"
role="${3:-}"

case "$cmd" in
  publish)
    content_file="${4:-}"
    if [ -z "$task_id" ] || [ -z "$role" ] || [ -z "$content_file" ]; then
      echo "Usage: hitl-local-html.sh publish <task_id> <role> <content_md_file>"
      exit 1
    fi

    # Convert markdown to HTML (basic conversion)
    content_html=""
    if command -v pandoc >/dev/null 2>&1; then
      content_html=$(pandoc -f markdown -t html "$content_file" 2>/dev/null)
    else
      # Fallback: wrap in <pre> tag
      content_html="<pre>$(cat "$content_file" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')</pre>"
    fi

    # Get role emoji
    role_emoji=$(echo "$ROLE_EMOJI_MAP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('$role','📋'))" 2>/dev/null || echo "📋")

    # Generate HTML from template
    output_file="$REVIEWS_DIR/${task_id}-${role}.html"
    feedback_path="$REVIEWS_DIR/${task_id}-${role}-feedback.json"

    sed \
      -e "s|{{TASK_ID}}|${task_id}|g" \
      -e "s|{{ROLE}}|${role}|g" \
      -e "s|{{ROLE_EMOJI}}|${role_emoji}|g" \
      -e "s|{{FEEDBACK_PATH}}|${feedback_path}|g" \
      "$TEMPLATE" > "$output_file.tmp"

    # Insert content (sed can't handle multiline well, use python)
    python3 -c "
import sys
template = open('${output_file}.tmp').read()
content = '''${content_html}'''
result = template.replace('{{CONTENT}}', content)
with open('${output_file}', 'w') as f:
    f.write(result)
" 2>/dev/null || {
      # Fallback if python fails
      sed "s|{{CONTENT}}|<p>See source document: ${content_file}</p>|g" "$output_file.tmp" > "$output_file"
    }
    rm -f "$output_file.tmp"

    # Open in browser
    if [ "$(uname)" = "Darwin" ]; then
      open "$output_file" 2>/dev/null || true
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$output_file" 2>/dev/null || true
    fi

    echo "file://$output_file"
    ;;

  poll)
    if [ -z "$task_id" ] || [ -z "$role" ]; then
      echo "Usage: hitl-local-html.sh poll <task_id> <role>"
      exit 1
    fi

    feedback_file="$REVIEWS_DIR/${task_id}-${role}-feedback.json"
    if [ -f "$feedback_file" ]; then
      decision=$(python3 -c "import json; d=json.load(open('$feedback_file')); print(d.get('decision','pending'))" 2>/dev/null || echo "pending")
      echo "$decision"
    else
      echo "pending_review"
    fi
    ;;

  get_feedback)
    if [ -z "$task_id" ] || [ -z "$role" ]; then
      echo "Usage: hitl-local-html.sh get_feedback <task_id> <role>"
      exit 1
    fi

    feedback_file="$REVIEWS_DIR/${task_id}-${role}-feedback.json"
    if [ -f "$feedback_file" ]; then
      cat "$feedback_file"
    else
      echo '{"status":"no_feedback"}'
    fi
    ;;

  *)
    echo "HITL Local HTML Adapter"
    echo "Commands: publish, poll, get_feedback"
    ;;
esac
