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

# Build WHERE clause
WHERE=""
[ -n "$ROLE" ] && WHERE="AND role='$ROLE'"
[ -n "$LAYER" ] && WHERE="$WHERE AND layer='$LAYER'"

# FTS5 search with ranking
sqlite3 -header -column "$INDEX_DB" << SQL
SELECT
  '[' || file_path || ':' || line_number || ']' AS citation,
  snippet(memory_fts, 2, '**', '**', '...', 32) AS context,
  rank
FROM memory_fts
WHERE memory_fts MATCH '${QUERY}'
${WHERE}
ORDER BY rank
LIMIT ${LIMIT};
SQL
