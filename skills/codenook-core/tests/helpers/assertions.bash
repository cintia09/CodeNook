#!/usr/bin/env bash
# Minimal assertion helpers (avoid bats-assert dependency).

assert_file_exists() {
  local p="$1"
  [ -e "$p" ] || { echo "expected file to exist: $p" >&2; return 1; }
}

assert_file_executable() {
  local p="$1"
  [ -x "$p" ] || { echo "expected file to be executable: $p" >&2; return 1; }
}

assert_file_size_le() {
  local p="$1" max="$2"
  local n
  n=$(wc -c <"$p" | tr -d ' ')
  [ "$n" -le "$max" ] || { echo "file $p is $n bytes, expected <= $max" >&2; return 1; }
}

assert_contains() {
  local haystack="$1" needle="$2"
  case "$haystack" in
    *"$needle"*) return 0 ;;
    *) echo "expected output to contain: $needle" >&2
       echo "got: $haystack" >&2
       return 1 ;;
  esac
}

assert_not_contains() {
  local haystack="$1" needle="$2"
  case "$haystack" in
    *"$needle"*) echo "expected output NOT to contain: $needle" >&2; return 1 ;;
    *) return 0 ;;
  esac
}

assert_jq() {
  local file="$1" expr="$2"
  jq -e "$expr" "$file" >/dev/null \
    || { echo "jq expr failed: $expr on $file" >&2; jq . "$file" >&2 || cat "$file" >&2; return 1; }
}
