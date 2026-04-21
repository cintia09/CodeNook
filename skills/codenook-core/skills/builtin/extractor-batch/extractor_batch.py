#!/usr/bin/env python3
"""extractor-batch/extractor_batch.py — Python entry equivalent to
``extractor-batch.sh``.

v0.24.0 — preferred on Windows hosts without bash on PATH. The .sh
wrapper is retained for Linux/Mac users; it now delegates to this script.
"""
from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from _extractor_batch import main  # noqa: E402


if __name__ == "__main__":
    sys.exit(main())
