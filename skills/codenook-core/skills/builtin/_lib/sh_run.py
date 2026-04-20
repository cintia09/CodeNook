"""sh_run — Windows-friendly subprocess.run wrapper.

On Windows, the kernel's many .sh shell scripts cannot be exec'd directly
(no shebang handling). This helper detects .sh in cmd[0] and prepends the
bash interpreter resolved via PATH (Git Bash / MSYS), keeping POSIX behavior
on Linux/macOS untouched.
"""
from __future__ import annotations

import os
import shutil
import subprocess


def sh_run(cmd, **kwargs):
    """Drop-in replacement for subprocess.run that wraps .sh on Windows."""
    if (os.name == "nt" and isinstance(cmd, list) and cmd
            and isinstance(cmd[0], str)
            and cmd[0].lower().endswith(".sh")):
        bash = shutil.which("bash") or os.environ.get("CN_BASH", "bash")
        cmd = [bash, *cmd]
    return subprocess.run(cmd, **kwargs)
