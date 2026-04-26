#!/usr/bin/env python3
"""CodeNook bootloader behavioural regression suite.

Python port of the legacy ``bootloader_behaviour.sh``.

Drives a real ``claude -p`` (Claude Code, non-interactive) inside a
CodeNook workspace and asserts that the agent's first
AskUserQuestion in each scenario matches the spec encoded in the
rendered CLAUDE.md bootloader.

WHY this exists alongside the wording-agnostic contract tests:
    tests/python/test_claude_md_contract.py asserts that the
    rendered markdown CONTAINS the right rules. This suite asserts
    that a real LLM agent FOLLOWS those rules end-to-end.

COST + GATING:
    Each scenario is a real ``claude -p`` round-trip (tens of
    seconds, ~$0.20-$0.30). The full suite is therefore NOT run
    in default CI and is NOT wired into run_all.py — invoke
    explicitly when you change the bootloader's hard rules or
    one of the §Pre-creation / §HITL sections.

REQUIREMENTS:
    - ``claude`` CLI v2+ on PATH (Claude Code; ``-p`` flag).
    - A target CodeNook workspace with the kernel installed
      (default: /Users/mingdw/Documents/nook; override with
      $NOOK).
    - A funded API account for the configured model.

USAGE:
    python3 skills/codenook-core/tests/behavioral/bootloader_behaviour.py
    python3 skills/codenook-core/tests/behavioral/bootloader_behaviour.py s4
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

NOOK = Path(os.environ.get("NOOK", "/Users/mingdw/Documents/nook"))
OUT = Path(os.environ.get("OUT", "/tmp/codenook-bootloader-tests"))


def first_ask(json_path: Path) -> str:
    """Inspect first AskUserQuestion (denied because -p has no human)."""
    try:
        d = json.loads(json_path.read_text())
    except Exception:
        return "NO_ASK"
    asks = [
        x for x in d.get("permission_denials", [])
        if x.get("tool_name") == "AskUserQuestion"
    ]
    if not asks:
        return "NO_ASK"
    qs = asks[0].get("tool_input", {}).get("questions", [])
    labels = [
        f"{q.get('header', '')}:{q.get('question', '')[:80]}"
        for q in qs
    ]
    return " || ".join(labels)


def tool_uses(jsonl_path: Path) -> str:
    """Inspect tool_use blocks from a stream-json transcript."""
    seen: list[str] = []
    try:
        text = jsonl_path.read_text()
    except OSError:
        return ""
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except Exception:
            continue
        msg = ev.get("message", {})
        content = msg.get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict):
                continue
            if block.get("type") != "tool_use":
                continue
            inp = block.get("input", {}) or {}
            tgt = inp.get("file_path") or inp.get("command") or inp.get("path") or ""
            seen.append(f"{block.get('name')}:{tgt}")
    return "\n".join(seen)


class Counters:
    def __init__(self) -> None:
        self.passed = 0
        self.failed = 0


def run_scenario(c: Counters, sid: str, prompt: str, expect_re: str, label: str) -> None:
    f = OUT / f"{sid}.json"
    print(f"=== {sid}: {label} ===")
    with open(f, "w") as fh:
        subprocess.run(
            ["claude", "-p", "--output-format", "json", prompt],
            cwd=str(NOOK), stdout=fh, stderr=subprocess.STDOUT,
        )
    fa = first_ask(f)
    print(f"first ask: {fa}")
    if re.search(expect_re, fa):
        print("PASS")
        c.passed += 1
    else:
        print(f"FAIL  (expected pattern: {expect_re})")
        c.failed += 1
    print()


def run_scenario_tools(c: Counters, sid: str, prompt: str, expect_re: str, label: str) -> None:
    f = OUT / f"{sid}.jsonl"
    print(f"=== {sid}: {label} ===")
    with open(f, "w") as fh:
        subprocess.run(
            ["claude", "-p", "--output-format", "stream-json", "--verbose", prompt],
            cwd=str(NOOK), stdout=fh, stderr=subprocess.STDOUT,
        )
    hits = tool_uses(f)
    for line in hits.splitlines():
        print(f"  {line}")
    if re.search(expect_re, hits):
        print("PASS")
        c.passed += 1
    else:
        print(f"FAIL  (expected pattern: {expect_re})")
        c.failed += 1
    print()


SCENARIOS = {
    "s1": (
        run_scenario,
        "为 nook 自身写一份 README 任务。注意：开一个全新的任务，忽略任何已存在的 T-NNN。",
        r"范围|目标|scope|goal|约束|读者|受众|章节|风格|现有|interview|访谈|主题|topic|audience",
        "baseline → first ask should be the pre-task interview",
    ),
    "s2": (
        run_scenario,
        (
            "为 nook 自身写一份 README 任务。我已经回答了访谈问题：\n"
            "- 范围：整个 nook 工作区\n"
            "- 目标：让新人 5 分钟看懂\n"
            "- 风格：简洁\n"
            "- 读者：开发者\n\n"
            "继续下一步。开新任务，不要复用已有 T-NNN，不要再问访谈问题。"
        ),
        r"执行模式|exec|sub-agent|inline",
        "interview-done → first ask should be execution mode",
    ),
    "s3": (
        run_scenario,
        (
            "为 nook 自身写一份 README 任务。开一个全新的任务，忽略任何已有的 T-NNN。\n\n"
            "对于访谈问题，我的回答是：你自己决定。\n\n"
            "请按 CLAUDE.md 的规则继续下一步 ask。"
        ),
        r"执行模式|exec|sub-agent|inline",
        "user said '你自己决定' → must STILL ask exec mode (regression)",
    ),
    "s4": (
        run_scenario,
        (
            "为 nook 自身写一份 README 任务。开一个全新的任务，忽略任何已有的 T-NNN。\n\n"
            "我已经回答了访谈问题（默认值即可）。\n"
            "执行模式我选：sub-agent。\n\n"
            "请按 CLAUDE.md 的规则继续下一步 ask。"
        ),
        r"模型|model|GPT|Claude|Sonnet|Opus|Haiku|MiniMax",
        "exec=sub-agent picked → next ask MUST be model (the historical bug)",
    ),
    "s5": (
        run_scenario_tools,
        "你好，请按 CodeNook 会话启动仪式读取必要的工作区清单文件。然后告诉我你读了哪些文件。",
        r"memory/index\.yaml",
        "session-start ritual reads memory/index.yaml (explicit prompt)",
    ),
    "s6": (
        run_scenario_tools,
        "我想给 nook 自身写个 README，你帮我组织一下。",
        r"memory/index\.yaml",
        "natural prompt → boot ritual must STILL read memory/index.yaml (regression)",
    ),
    "s7": (
        run_scenario_tools,
        (
            "我想给 InferX 项目做一次代码重构，帮我开个新任务跟踪。\n"
            "我的访谈回答：范围=全项目；目标=可维护性；约束=不引入新依赖；优先级=normal。\n"
            "执行模式选 sub-agent，模型用默认。"
        ),
        r"task suggest-parent|suggest_parents|parent_suggester",
        "duplicate-detection → must call task suggest-parent before task new",
    ),
}


def main(argv: list[str]) -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    if shutil.which("claude") is None:
        sys.stderr.write("FATAL: 'claude' CLI not found on PATH (install Claude Code).\n")
        return 2
    if not (NOOK / ".codenook").is_dir():
        sys.stderr.write(f"FATAL: {NOOK} is not a CodeNook workspace (no .codenook/ found).\n")
        sys.stderr.write("  Set NOOK=/path/to/your/workspace and try again.\n")
        return 2

    selected = argv if argv else list(SCENARIOS.keys())
    c = Counters()
    for sid in selected:
        if sid not in SCENARIOS:
            sys.stderr.write(f"unknown scenario: {sid}\n")
            return 1
        runner, prompt, expect_re, label = SCENARIOS[sid]
        runner(c, sid, prompt, expect_re, label)

    print("----")
    print(f"PASS={c.passed}  FAIL={c.failed}")
    return 0 if c.failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
