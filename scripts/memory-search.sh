#!/usr/bin/env bash
set -euo pipefail
# Memory Search - keyword search with citations
# Usage: bash scripts/memory-search.sh "query" [--role <role>] [--layer <layer>] [--limit <n>]

INDEX_DB=".agents/memory/index.sqlite"
QUERY="${1:?Usage: memory-search.sh \"query\" [--role role] [--layer layer] [--limit n]}"
ROLE=""
LAYER=""
LIMIT=6

shift
while [ $# -gt 0 ]; do
  case "$1" in
    --role) ROLE="$2"; shift 2 ;;
    --layer) LAYER="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ ! -f "$INDEX_DB" ]; then
  echo "⚠️ Memory index not found. Run: bash scripts/memory-index.sh"
  exit 1
fi

# Escape and validate inputs for SQL safety
QUERY_ESC=$(echo "$QUERY" | sed "s/'/''/g")
ROLE_ESC=$(echo "$ROLE" | sed "s/'/''/g")
LAYER_ESC=$(echo "$LAYER" | sed "s/'/''/g")
LIMIT=$(echo "$LIMIT" | grep -oE '^[0-9]+$' || echo 6)

# Build WHERE clause
WHERE=""
[ -n "$ROLE_ESC" ] && WHERE="AND role='$ROLE_ESC'"
[ -n "$LAYER_ESC" ] && WHERE="$WHERE AND layer='$LAYER_ESC'"

# FTS5 search with ranking
sqlite3 -header -column "$INDEX_DB" << SQL
SELECT
  '[' || file_path || ':' || line_number || ']' AS citation,
  snippet(memory_fts, 2, '**', '**', '...', 32) AS context,
  rank
FROM memory_fts
WHERE memory_fts MATCH '${QUERY_ESC}'
${WHERE}
ORDER BY rank
LIMIT ${LIMIT};
SQL
