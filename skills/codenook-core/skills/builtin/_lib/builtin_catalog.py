"""Centralised catalog of builtin skills the M3 router can dispatch to,
plus the regex intent table that maps user phrases to those skills.

Importers:
  * router-dispatch-build/_build.py  — uses BUILTIN_SKILLS for role tagging
  * router-triage/_triage.py         — uses BUILTIN_INTENTS for matching

Centralising here prevents drift: any new builtin must be added in one
place to be both routable AND addressable as a dispatch target.
"""
from __future__ import annotations

import re

BUILTIN_SKILLS: set[str] = {"list-plugins", "show-config", "help"}

BUILTIN_INTENTS: list[tuple[str, re.Pattern[str]]] = [
    ("list-plugins", re.compile(r"\b(list|show)\b.*\bplugins?\b", re.IGNORECASE)),
    ("show-config",  re.compile(r"\b(show|print)\b.*\b(config|settings)\b", re.IGNORECASE)),
    ("help",         re.compile(r"\bhelp\b", re.IGNORECASE)),
]
