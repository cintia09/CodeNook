#!/usr/bin/env bash
set -euo pipefail
# Memory Index Engine - indexes all .md memory files into SQLite FTS5
# Usage: bash scripts/memory-index.sh [--force]

AGENTS_DIR=".agents"
INDEX_DB="$AGENTS_DIR/memory/index.sqlite"

# Ensure memory directory exists
mkdir -p "$AGENTS_DIR/memory"

# Create FTS5 table
sqlite3 "$INDEX_DB" << 'SQL'
CREATE VIRTUAL TABLE IF NOT EXISTS memory_fts USING fts5(
  file_path,
  line_number,
  content,
  role,
  layer,
  tokenize='unicode61'
);

CREATE TABLE IF NOT EXISTS memory_meta (
  file_path TEXT PRIMARY KEY,
  last_indexed TEXT,
  checksum TEXT
);
SQL

# Index all memory .md files
find "$AGENTS_DIR/memory" -name "*.md" -type f | while read -r file; do
  # Check if file changed since last index
  current_checksum=$(md5 -q "$file" 2>/dev/null || md5sum "$file" | cut -d' ' -f1)
  stored_checksum=$(sqlite3 "$INDEX_DB" "SELECT checksum FROM memory_meta WHERE file_path='$file'" 2>/dev/null)

  if [ "$current_checksum" = "$stored_checksum" ] && [ "${1:-}" != "--force" ]; then
    continue
  fi

  # Determine role and layer
  role="project"
  layer="project"
  case "$file" in
    */acceptor/*) role="acceptor" ;;
    */designer/*) role="designer" ;;
    */implementer/*) role="implementer" ;;
    */reviewer/*) role="reviewer" ;;
    */tester/*) role="tester" ;;
  esac
  case "$file" in
    */MEMORY.md) layer="long-term" ;;
    */diary/*) layer="diary" ;;
    *PROJECT_MEMORY*) layer="project" ;;
  esac

  # Remove old entries
  sqlite3 "$INDEX_DB" "DELETE FROM memory_fts WHERE file_path='$file'"

  # Index line by line
  line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    [ -z "$line" ] && continue
    escaped=$(echo "$line" | sed "s/'/''/g")
    sqlite3 "$INDEX_DB" "INSERT INTO memory_fts(file_path, line_number, content, role, layer) VALUES('$file', $line_num, '$escaped', '$role', '$layer')"
  done < "$file"

  # Update meta
  sqlite3 "$INDEX_DB" "INSERT OR REPLACE INTO memory_meta(file_path, last_indexed, checksum) VALUES('$file', datetime('now'), '$current_checksum')"
done

echo "✓ Memory index updated"
