#!/usr/bin/env bash
# CodeNook bootloader behavioural regression suite.
#
# Drives a real `claude -p` (Claude Code, non-interactive) inside a
# CodeNook workspace and asserts that the agent's first
# AskUserQuestion in each scenario matches the spec encoded in the
# rendered CLAUDE.md bootloader.
#
# WHY this exists alongside the wording-agnostic contract tests:
#   tests/python/test_claude_md_contract.py asserts that the rendered
#   markdown CONTAINS the right rules. This suite asserts that a real
#   LLM agent FOLLOWS those rules end-to-end. Both are needed: the
#   markdown can be perfect and the agent can still skip a MUST.
#
# COST + GATING:
#   Each scenario is a real `claude -p` round-trip (tens of seconds,
#   ~$0.20-$0.30). The full suite is therefore NOT run in default CI
#   and is NOT wired into run_all.sh — invoke explicitly when you
#   change the bootloader's hard rules or one of the §Pre-creation /
#   §HITL sections, or when investigating an agent regression.
#
# REQUIREMENTS:
#   - `claude` CLI v2+ on PATH (Claude Code, the non-interactive
#     `-p` flag is required).
#   - A target CodeNook workspace with the kernel installed. By
#     default this points to /Users/mingdw/Documents/nook; override
#     by exporting NOOK before invocation.
#   - A funded API account for the model claude is configured to use.
#
# USAGE:
#   bash skills/codenook-core/tests/behavioral/bootloader_behaviour.sh
#   bash skills/codenook-core/tests/behavioral/bootloader_behaviour.sh s4
#
# OUTPUT:
#   Per-scenario JSON dumps land in $OUT (default /tmp/codenook-
#   bootloader-tests/sN.json) for post-mortem inspection.
set -u
NOOK="${NOOK:-/Users/mingdw/Documents/nook}"
OUT="${OUT:-/tmp/codenook-bootloader-tests}"
mkdir -p "$OUT"

if ! command -v claude >/dev/null 2>&1; then
  echo "FATAL: 'claude' CLI not found on PATH (install Claude Code)." >&2
  exit 2
fi
if [[ ! -d "$NOOK/.codenook" ]]; then
  echo "FATAL: $NOOK is not a CodeNook workspace (no .codenook/ found)." >&2
  echo "  Set NOOK=/path/to/your/workspace and try again." >&2
  exit 2
fi

PASS=0; FAIL=0

# Inspect the agent's first AskUserQuestion (denied because -p mode
# has no human responder — the denial JSON records it for us).
run_scenario() {
  local id="$1"; local prompt="$2"; local expect_re="$3"; local expect_label="$4"
  local f="$OUT/$id.json"
  echo "=== $id: $expect_label ==="
  ( cd "$NOOK" && claude -p --output-format json "$prompt" ) > "$f" 2>&1
  local first_ask
  first_ask=$(python3 - <<PY
import json
d = json.load(open("$f"))
asks = [x for x in d.get("permission_denials", [])
        if x.get("tool_name") == "AskUserQuestion"]
if not asks:
    print("NO_ASK")
else:
    qs = asks[0].get("tool_input", {}).get("questions", [])
    labels = [(q.get("header","") + ":" + q.get("question","")[:80])
              for q in qs]
    print(" || ".join(labels))
PY
)
  echo "first ask: $first_ask"
  if [[ "$first_ask" =~ $expect_re ]]; then
    echo "PASS"
    PASS=$((PASS+1))
  else
    echo "FAIL  (expected pattern: $expect_re)"
    FAIL=$((FAIL+1))
  fi
  echo
}

# Inspect the actual file/command tool calls the agent made (via
# stream-json) and assert that an expected target appears.
run_scenario_tools() {
  local id="$1"; local prompt="$2"; local expect_re="$3"; local expect_label="$4"
  local f="$OUT/$id.jsonl"
  echo "=== $id: $expect_label ==="
  ( cd "$NOOK" && claude -p --output-format stream-json --verbose "$prompt" ) > "$f" 2>&1
  local hits
  hits=$(python3 - "$f" <<'PY'
import json, sys
seen = []
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    try: ev = json.loads(line)
    except: continue
    msg = ev.get("message", {})
    content = msg.get("content")
    if not isinstance(content, list): continue
    for block in content:
        if not isinstance(block, dict): continue
        if block.get("type") != "tool_use": continue
        inp = block.get("input", {}) or {}
        tgt = (inp.get("file_path") or inp.get("command")
               or inp.get("path") or "")
        seen.append(f"{block.get('name')}:{tgt}")
print("\n".join(seen))
PY
)
  echo "$hits" | sed 's/^/  /'
  if echo "$hits" | grep -Eq "$expect_re"; then
    echo "PASS"
    PASS=$((PASS+1))
  else
    echo "FAIL  (expected pattern: $expect_re)"
    FAIL=$((FAIL+1))
  fi
  echo
}

if [[ $# -eq 0 ]]; then
  set -- s1 s2 s3 s4 s5
fi

for id in "$@"; do
  case "$id" in
    s1) run_scenario s1 \
        "为 nook 自身写一份 README 任务。注意：开一个全新的任务，忽略任何已存在的 T-NNN。" \
        '范围|目标|scope|goal|约束|读者|受众|章节|风格|现有|interview|访谈|主题|topic|audience' \
        "baseline → first ask should be the pre-task interview" ;;
    s2) run_scenario s2 \
        "为 nook 自身写一份 README 任务。我已经回答了访谈问题：
- 范围：整个 nook 工作区
- 目标：让新人 5 分钟看懂
- 风格：简洁
- 读者：开发者

继续下一步。开新任务，不要复用已有 T-NNN，不要再问访谈问题。" \
        '执行模式|exec|sub-agent|inline' \
        "interview-done → first ask should be execution mode" ;;
    s3) run_scenario s3 \
        "为 nook 自身写一份 README 任务。开一个全新的任务，忽略任何已有的 T-NNN。

对于访谈问题，我的回答是：你自己决定。

请按 CLAUDE.md 的规则继续下一步 ask。" \
        '执行模式|exec|sub-agent|inline' \
        "user said '你自己决定' → must STILL ask exec mode (regression)" ;;
    s4) run_scenario s4 \
        "为 nook 自身写一份 README 任务。开一个全新的任务，忽略任何已有的 T-NNN。

我已经回答了访谈问题（默认值即可）。
执行模式我选：sub-agent。

请按 CLAUDE.md 的规则继续下一步 ask。" \
        '模型|model|GPT|Claude|Sonnet|Opus|Haiku|MiniMax' \
        "exec=sub-agent picked → next ask MUST be model (the historical bug)" ;;
    s5) run_scenario_tools s5 \
        "你好，请按 CodeNook 会话启动仪式读取必要的工作区清单文件。然后告诉我你读了哪些文件。" \
        'memory/index\.yaml' \
        "session-start ritual reads memory/index.yaml" ;;
    *) echo "unknown scenario: $id"; exit 1 ;;
  esac
done

echo "----"
echo "PASS=$PASS  FAIL=$FAIL"
[[ $FAIL -eq 0 ]] || exit 1
