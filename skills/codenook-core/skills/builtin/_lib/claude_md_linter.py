#!/usr/bin/env python3
"""CLAUDE.md domain-agnostic linter (M8.6).

Scans the root ``CLAUDE.md`` (or any "main session protocol" doc) for
domain-aware tokens that would violate the v6 layering principle
(see ``docs/v6/router-agent-v6.md`` §2). The main session is the
**Conductor** — pure protocol + UX, with zero domain awareness.

Allowed-context exceptions:

* Fenced code blocks opened with ``forbidden`` or ``forbidden-example``
  as the info-string (e.g. ``\\`\\`\\`forbidden``).
* The single line immediately following an HTML comment of the exact
  form ``<!-- linter:allow -->``.
* Anywhere inside the section whose heading text contains
  ``Hard rules (forbidden)`` — the section ends at the next ``## ``
  level-2 heading.

Tokens found inside an allowed context are still surfaced as
``warning`` findings so you can audit them; tokens elsewhere are
``error`` findings and cause non-zero CLI exit.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Any

# Pure substring tokens (path-style identifiers; case-sensitive).
_LITERAL_TOKENS: tuple[str, ...] = (
    "plugins/development",
    "plugins/writing",
    "plugins/generic",
    "applies_to",
    "domain_description",
)

# Word-boundary tokens: role names + plugin ids that are also common English
# words. Case-sensitive; matched only as standalone words.
_WORD_TOKENS: tuple[str, ...] = (
    "clarifier",
    "designer",
    "implementer",
    "tester",
    "validator",
    "acceptor",
    "reviewer",
    "development",
    "writing",
    "generic",
)

# Public surface mirrors the spec.
FORBIDDEN_TOKENS: list[str] = [
    *_LITERAL_TOKENS,
    *_WORD_TOKENS[:7],  # roles
    r"\bdevelopment\b",
    r"\bwriting\b",
    r"\bgeneric\b",
]

ALLOWED_CONTEXT_PATTERNS: list[str] = [
    "```forbidden / ```forbidden-example fenced block",
    "<!-- linter:allow --> on the immediately preceding line",
    "section whose ## heading contains 'Hard rules (forbidden)'",
]

_FENCE_RE = re.compile(r"^\s*```([A-Za-z0-9_-]*)\s*$")
_HEADING2_RE = re.compile(r"^##\s+(.*?)\s*$")
_ALLOW_COMMENT_RE = re.compile(r"^\s*<!--\s*linter:allow\s*-->\s*$")
_HARD_RULES_RE = re.compile(r"hard\s+rules\s*\(\s*forbidden\s*\)", re.IGNORECASE)


def _word_iter(line: str, token: str):
    pattern = r"\b" + re.escape(token) + r"\b"
    for m in re.finditer(pattern, line):
        yield m.start(), m.group(0)


def _literal_iter(line: str, token: str):
    start = 0
    while True:
        idx = line.find(token, start)
        if idx < 0:
            return
        yield idx, token
        start = idx + len(token)


def scan_file(path: Path) -> list[dict[str, Any]]:
    """Scan one file. Returns a list of finding dicts.

    Each finding has keys: ``file``, ``line``, ``column``, ``token``,
    ``snippet``, ``severity`` (``error`` or ``warning``).
    """
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        return [
            {
                "file": str(path),
                "line": 0,
                "column": 0,
                "token": "",
                "snippet": f"<read error: {exc}>",
                "severity": "error",
            }
        ]

    findings: list[dict[str, Any]] = []
    in_forbidden_fence = False
    in_any_fence = False
    in_hard_rules = False
    prev_was_allow = False

    for i, raw in enumerate(text.splitlines(), start=1):
        line = raw.rstrip("\n")
        fence_match = _FENCE_RE.match(line)
        if fence_match:
            tag = fence_match.group(1).lower()
            if in_any_fence:
                # closing fence
                in_any_fence = False
                in_forbidden_fence = False
            else:
                in_any_fence = True
                in_forbidden_fence = tag in ("forbidden", "forbidden-example")
            prev_was_allow = False
            continue

        # Heading tracking happens only outside fences.
        if not in_any_fence:
            heading = _HEADING2_RE.match(line)
            if heading:
                in_hard_rules = bool(_HARD_RULES_RE.search(heading.group(1)))

        if _ALLOW_COMMENT_RE.match(line):
            prev_was_allow = True
            continue

        allowed = in_forbidden_fence or in_hard_rules or prev_was_allow
        severity = "warning" if allowed else "error"

        line_findings: list[tuple[int, str]] = []
        for tok in _LITERAL_TOKENS:
            line_findings.extend(_literal_iter(line, tok))
        for tok in _WORD_TOKENS:
            line_findings.extend(_word_iter(line, tok))

        # De-dup overlapping word/literal hits at the same column+token.
        seen: set[tuple[int, str]] = set()
        for col, tok in sorted(line_findings):
            key = (col, tok)
            if key in seen:
                continue
            seen.add(key)
            findings.append(
                {
                    "file": str(path),
                    "line": i,
                    "column": col + 1,
                    "token": tok,
                    "snippet": line.strip()[:200],
                    "severity": severity,
                }
            )

        prev_was_allow = False

    return findings


def scan_files(paths: list[Path]) -> dict[str, Any]:
    errors: list[dict[str, Any]] = []
    warnings: list[dict[str, Any]] = []
    n = 0
    for p in paths:
        n += 1
        for f in scan_file(p):
            (errors if f["severity"] == "error" else warnings).append(f)
    return {"errors": errors, "warnings": warnings, "files_scanned": n}


def _format_finding(f: dict[str, Any]) -> str:
    return (
        f"{f['file']}:{f['line']}:{f['column']}: {f['severity'].upper()}: "
        f"forbidden domain token '{f['token']}' -> {f['snippet']}"
    )


def cli_main(argv: list[str]) -> int:
    if argv and argv[0] in ("-h", "--help"):
        print(
            "usage: claude_md_linter.py <FILE> [<FILE> ...]\n"
            "Scans CLAUDE.md-style files for forbidden domain tokens.\n"
            "Exit 0 if no errors, 1 otherwise. Findings printed to stderr.",
            file=sys.stderr,
        )
        return 0
    if not argv:
        print(
            "usage: claude_md_linter.py <FILE> [<FILE> ...]",
            file=sys.stderr,
        )
        return 2

    paths = [Path(a) for a in argv]
    missing = [p for p in paths if not p.exists()]
    if missing:
        for p in missing:
            print(f"ERROR: file not found: {p}", file=sys.stderr)
        return 2

    result = scan_files(paths)
    for f in result["errors"]:
        print(_format_finding(f), file=sys.stderr)
    for f in result["warnings"]:
        print(_format_finding(f), file=sys.stderr)

    print(
        f"scanned {result['files_scanned']} file(s): "
        f"{len(result['errors'])} error(s), {len(result['warnings'])} warning(s)",
        file=sys.stderr,
    )
    return 0 if not result["errors"] else 1


if __name__ == "__main__":  # pragma: no cover
    sys.exit(cli_main(sys.argv[1:]))
