"""Secret scanner shared by all extractors.

Originally inlined in ``knowledge-extractor/extract.py``; lifted here so
the M9.4 skill-extractor (and future M9.5 config-extractor) reuse the
same fail-close rule set without copy-paste drift.

DR-005 (v0.11.2): coverage extended to JWT tokens, Google API keys,
Slack tokens, generic ``Authorization: Bearer`` headers, and modern
GitHub PAT prefixes (``ghp_``, ``ghs_``, ``gho_``, ``ghu_``, ``ghr_``,
``github_pat_``). Scanner is *fail-close*: anything matching is rejected
upstream by the extraction pipeline, so over-broad matches are
preferable to under-broad ones.

Public API::

    SECRET_PATTERNS                   # list[(rule_id, compiled_regex)]
    scan_secrets(text) -> (bool, rule_id|None)
    redact(text)      -> str

CLI:
    python3 secret_scan.py <file>...   # exit 1 + prints rule_id on first hit
"""

from __future__ import annotations

import re
import sys

SECRET_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("aws-access-key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("openai-key", re.compile(r"sk-[A-Za-z0-9]{20,}")),
    # GitHub PATs: classic ghp_, server ghs_, OAuth gho_, user ghu_,
    # refresh ghr_, plus fine-grained github_pat_.
    ("github-pat", re.compile(r"\b(?:ghp|ghs|gho|ghu|ghr)_[A-Za-z0-9]{20,}")),
    ("github-pat-finegrained", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}")),
    # Google API key (AIza prefix, 35-char tail).
    ("google-api-key", re.compile(r"\bAIza[0-9A-Za-z_\-]{35}\b")),
    # Slack tokens: bot/user/admin/refresh/legacy.
    ("slack-token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}")),
    # JWT (three base64url segments separated by dots, leading eyJ for the header).
    ("jwt", re.compile(r"\beyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\b")),
    # Generic Authorization: Bearer <token> header (case-insensitive on
    # the header name; token must be ≥ 20 chars to avoid trivial FPs).
    (
        "auth-bearer",
        re.compile(
            r"[Aa]uthorization\s*:\s*[Bb]earer\s+[A-Za-z0-9_\-\.=]{20,}"
        ),
    ),
    ("rsa-private-key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("internal-ip-10", re.compile(r"\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b")),
    ("internal-ip-192", re.compile(r"\b192\.168\.\d{1,3}\.\d{1,3}\b")),
    ("internal-ip-172", re.compile(r"\b172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}\b")),
    ("internal-ipv6-ula", re.compile(r"\b[fF][cdCD][0-9a-fA-F]{2}:[0-9a-fA-F:]*\b")),
    (
        "connection-string",
        re.compile(
            r"(?:postgres|postgresql|mysql|mongodb|redis)://[^\s\"']+",
            re.IGNORECASE,
        ),
    ),
]


def scan_secrets(text: str) -> tuple[bool, str | None]:
    """Return ``(hit, rule_id)`` — *hit* is True on first matching rule."""
    for rule_id, pat in SECRET_PATTERNS:
        if pat.search(text or ""):
            return True, rule_id
    return False, None


def redact(text: str) -> str:
    """Replace every match of every rule with ``***``."""
    out = text or ""
    for _rule_id, pat in SECRET_PATTERNS:
        out = pat.sub("***", out)
    return out


def _cli(argv: list[str]) -> int:
    if not argv:
        print("usage: secret_scan.py <file>...", file=sys.stderr)
        return 2
    rc = 0
    for path in argv:
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError as e:
            print(f"{path}: ERROR {e}", file=sys.stderr)
            rc = 2
            continue
        hit, rule = scan_secrets(text)
        if hit:
            print(f"{path}: HIT {rule}")
            rc = 1
        else:
            print(f"{path}: clean")
    return rc


if __name__ == "__main__":
    raise SystemExit(_cli(sys.argv[1:]))
