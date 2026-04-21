"""sh_run — Windows-friendly subprocess.run wrapper.

On Windows, the kernel's many .sh shell scripts cannot be exec'd directly
(no shebang handling). This helper detects .sh in cmd[0] and prepends the
bash interpreter resolved via :func:`find_bash`, keeping POSIX behavior
on Linux/macOS untouched.

``find_bash()`` is also exposed so other modules (e.g. orchestrator-tick's
extractor-batch hop) can avoid hardcoding the literal ``"bash"`` string,
which fails on Windows hosts where bash is installed but not on PATH
(typical PortableGit / Git for Windows / MSYS2 setups).
"""
from __future__ import annotations

import glob
import os
import shutil
import subprocess
from typing import Optional

# Well-known Windows install locations searched, in order, when neither
# ``CN_BASH`` nor ``shutil.which("bash")`` resolves an interpreter.
_WELL_KNOWN_PATHS: tuple[str, ...] = (
    r"C:\openclaw-pro\PortableGit\bin\bash.exe",
    r"C:\Program Files\Git\bin\bash.exe",
    r"C:\Program Files (x86)\Git\bin\bash.exe",
    r"C:\Program Files\Git\usr\bin\bash.exe",
    r"C:\msys64\usr\bin\bash.exe",
    r"C:\cygwin64\bin\bash.exe",
    r"C:\Windows\System32\bash.exe",
)

# Per-user Git installs (globbed once per process, then cached).
_WELL_KNOWN_GLOBS: tuple[str, ...] = (
    r"C:\Users\*\AppData\Local\Programs\Git\bin\bash.exe",
)

_BASH_CACHE: Optional[str] = None
_BASH_RESOLVED: bool = False


def _scan_well_known() -> Optional[str]:
    for p in _WELL_KNOWN_PATHS:
        if os.path.isfile(p):
            return p
    for pattern in _WELL_KNOWN_GLOBS:
        for hit in glob.glob(pattern):
            if os.path.isfile(hit):
                return hit
    return None


def find_bash() -> Optional[str]:
    """Return an absolute path to a usable bash interpreter, or ``None``.

    Resolution order (cached after first call):

    1. ``$CN_BASH`` if set and the path exists.
    2. ``shutil.which("bash")``.
    3. Scan :data:`_WELL_KNOWN_PATHS` and :data:`_WELL_KNOWN_GLOBS`
       (Windows-typical install locations).

    Callers that absolutely require bash should raise a clear error when
    this returns ``None``; callers where bash is best-effort (e.g.
    extractor-batch dispatch) should log and skip.
    """
    global _BASH_CACHE, _BASH_RESOLVED
    if _BASH_RESOLVED:
        return _BASH_CACHE

    cn_bash = os.environ.get("CN_BASH")
    if cn_bash and os.path.isfile(cn_bash):
        _BASH_CACHE = cn_bash
        _BASH_RESOLVED = True
        return _BASH_CACHE

    which = shutil.which("bash")
    if which:
        _BASH_CACHE = which
        _BASH_RESOLVED = True
        return _BASH_CACHE

    if os.name == "nt":
        scanned = _scan_well_known()
        if scanned:
            _BASH_CACHE = scanned
            _BASH_RESOLVED = True
            return _BASH_CACHE

    _BASH_CACHE = None
    _BASH_RESOLVED = True
    return None


def _reset_cache_for_tests() -> None:
    """Test-only hook: clear the memoised bash path."""
    global _BASH_CACHE, _BASH_RESOLVED
    _BASH_CACHE = None
    _BASH_RESOLVED = False


def sh_run(cmd, **kwargs):
    """Drop-in replacement for subprocess.run that wraps .sh on Windows."""
    if (os.name == "nt" and isinstance(cmd, list) and cmd
            and isinstance(cmd[0], str)
            and cmd[0].lower().endswith(".sh")):
        bash = find_bash()
        if bash is None:
            tried = [
                "$CN_BASH",
                "shutil.which('bash')",
                *(_WELL_KNOWN_PATHS),
                *(_WELL_KNOWN_GLOBS),
            ]
            raise RuntimeError(
                "sh_run: no bash interpreter found on this Windows host.\n"
                "Tried (in order):\n  - " + "\n  - ".join(tried) + "\n"
                "Install Git for Windows (https://git-scm.com/download/win) "
                "or set the CN_BASH environment variable to a bash.exe path."
            )
        cmd = [bash, *cmd]
    return subprocess.run(cmd, **kwargs)
