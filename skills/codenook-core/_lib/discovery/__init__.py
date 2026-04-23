"""Unified plugin+memory sub-directory discovery (T-004).

See :mod:`_lib.discovery.scan` for the scanner implementation.
"""
from __future__ import annotations

from .scan import (  # noqa: F401
    DISCOVERY_ROOTS,
    REQUIRED_FIELDS,
    Entity,
    discover_all,
    scan_memory,
    scan_plugin,
    scan_plugins,
    scan_root,
)
