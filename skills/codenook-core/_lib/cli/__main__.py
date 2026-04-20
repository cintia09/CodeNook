"""Module entry point: ``python -m codenook_cli`` or ``python __main__.py``.

Inserts the parent ``_lib`` directory into ``sys.path`` so the ``cli``
package resolves whether the kernel was copied into a workspace
(``<ws>/.codenook/codenook-core/_lib/cli``) or run from the source
repository (``skills/codenook-core/_lib/cli``).
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

# Force UTF-8 in every spawned subprocess (CodeNook YAML / MD often holds
# CJK; on Windows the default GBK codec corrupts reads).
os.environ.setdefault("PYTHONUTF8", "1")
os.environ.setdefault("PYTHONIOENCODING", "utf-8")

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    except Exception:
        pass

_HERE = Path(__file__).resolve().parent           # .../_lib/cli
_LIB_PARENT = _HERE.parent.parent                 # .../codenook-core
sys.path.insert(0, str(_LIB_PARENT))

from _lib.cli.app import main  # noqa: E402

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
