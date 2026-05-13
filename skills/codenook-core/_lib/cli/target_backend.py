"""Target directory backend parsing and preparation.

The default backend is the historical local filesystem path.  Remote
targets are represented as URIs so the task state can describe where
artifacts belong without pretending every target is a local ``Path``.
"""
from __future__ import annotations

import os
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, TextIO
from urllib.parse import quote, unquote, urlparse


SUPPORTED_BACKENDS = ("local", "ssh")


@dataclass(frozen=True)
class TargetSpec:
    backend: str
    target_dir: str
    local_path: Path | None = None
    uri: str | None = None
    host: str | None = None
    user: str | None = None
    port: int | None = None
    remote_path: str | None = None


Runner = Callable[..., subprocess.CompletedProcess]


def _looks_absolute_local(raw: str) -> bool:
    """Cross-platform absolute-path check, including Windows drives."""
    s = raw.strip()
    if not s:
        return False
    if Path(s).expanduser().is_absolute():
        return True
    if s.startswith(("/", "\\")):
        return True
    return len(s) >= 3 and s[1] == ":" and s[2] in ("/", "\\")


def _normalise_local(raw: str) -> tuple[TargetSpec | None, str | None]:
    value = raw.strip()
    if not value:
        return None, "empty target directory"
    if _looks_absolute_local(value):
        local_path = Path(value).expanduser()
        return TargetSpec(
            backend="local",
            target_dir=str(local_path),
            local_path=local_path,
        ), None
    normalised = value.replace("\\", "/")
    parts = [p for p in normalised.split("/") if p]
    if not parts:
        return None, "empty target directory"
    if any(p == ".." for p in parts):
        return None, "relative target directory must not contain '..'"
    target_dir = "/".join(parts)
    return TargetSpec(backend="local", target_dir=target_dir), None


def _quote_path(path: str) -> str:
    return quote(path, safe="/._-~")


def _canonical_ssh_uri(
    *,
    host: str,
    path: str,
    user: str | None = None,
    port: int | None = None,
) -> str:
    netloc = ""
    if user:
        netloc += f"{quote(user, safe='')}@"
    if ":" in host and not (host.startswith("[") and host.endswith("]")):
        netloc += f"[{host}]"
    else:
        netloc += host
    if port is not None:
        netloc += f":{port}"
    return f"ssh://{netloc}{_quote_path(path)}"


def _parse_ssh_uri(value: str) -> tuple[TargetSpec | None, str | None]:
    try:
        parsed = urlparse(value)
        port = parsed.port
    except ValueError as exc:
        return None, str(exc)
    if parsed.scheme != "ssh":
        return None, (
            f"unsupported target backend '{parsed.scheme}' "
            f"(supported: {', '.join(SUPPORTED_BACKENDS)})"
        )
    if parsed.params or parsed.query or parsed.fragment:
        return None, "ssh target URI must not contain params, query, or fragment"
    host = parsed.hostname or ""
    if not host:
        return None, "ssh target URI requires a host"
    path = unquote(parsed.path or "")
    if not path.startswith("/"):
        return None, "ssh target URI path must be absolute"
    user = unquote(parsed.username) if parsed.username else None
    canonical = _canonical_ssh_uri(host=host, path=path, user=user, port=port)
    return TargetSpec(
        backend="ssh",
        target_dir=canonical,
        uri=canonical,
        host=host,
        user=user,
        port=port,
        remote_path=path,
    ), None


_SCP_LIKE_RE = re.compile(
    r"^(?:(?P<user>[^@\s:/\\]+)@)?(?P<host>[^:\s/\\]+):(?P<path>/.*)$"
)


def _parse_scp_like(value: str) -> TargetSpec | None:
    match = _SCP_LIKE_RE.match(value)
    if not match:
        return None
    user = match.group("user")
    host = match.group("host")
    path = match.group("path")
    uri = _canonical_ssh_uri(host=host, path=path, user=user)
    return TargetSpec(
        backend="ssh",
        target_dir=uri,
        uri=uri,
        host=host,
        user=user,
        remote_path=path,
    )


def parse_target_dir_arg(raw: str) -> tuple[TargetSpec | None, str | None]:
    """Parse ``--target-dir`` into a backend-specific target spec."""
    value = raw.strip()
    if not value:
        return None, "empty target directory"
    if "://" in value:
        return _parse_ssh_uri(value)
    if _looks_absolute_local(value):
        return _normalise_local(value)
    scp_like = _parse_scp_like(value)
    if scp_like is not None:
        return scp_like, None
    return _normalise_local(value)


def _target_dir_path(workspace: Path, spec: TargetSpec) -> Path:
    if spec.backend != "local":
        raise ValueError(f"target backend is not local: {spec.backend}")
    if spec.local_path is not None:
        return spec.local_path
    return workspace / spec.target_dir


def _scan_local_target(path: Path, limit: int = 5000) -> dict:
    summary = {
        "files": 0,
        "dirs": 0,
        "truncated": False,
        "git": (path / ".git").exists(),
        "top": [],
    }
    try:
        summary["top"] = [
            p.name + ("/" if p.is_dir() else "")
            for p in sorted(path.iterdir(), key=lambda item: item.name.lower())[:12]
        ]
    except OSError:
        summary["top"] = []
    for _root, dirnames, filenames in os.walk(path):
        summary["dirs"] += len(dirnames)
        summary["files"] += len(filenames)
        if summary["dirs"] + summary["files"] >= limit:
            summary["truncated"] = True
            break
    return summary


def _prepare_local_target(
    workspace: Path,
    spec: TargetSpec,
    *,
    label: str,
    stderr: TextIO,
) -> tuple[bool, str | None]:
    target_path = _target_dir_path(workspace, spec)
    existed = target_path.exists()
    if existed and not target_path.is_dir():
        return False, f"target directory exists but is not a directory: {target_path}"
    scan = _scan_local_target(target_path) if existed else None
    try:
        target_path.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        return False, f"failed to create target directory {target_path}: {exc}"

    stderr.write(
        f"codenook {label}: target_dir is the task working directory: "
        f"{target_path}\n"
    )
    if scan is None:
        stderr.write(
            f"codenook {label}: created target directory "
            f"{target_path}\n"
        )
    else:
        truncated = " (scan truncated)" if scan.get("truncated") else ""
        top = ", ".join(scan.get("top") or [])
        stderr.write(
            f"codenook {label}: existing target directory scanned: "
            f"{scan.get('dirs', 0)} dirs, {scan.get('files', 0)} files, "
            f"git={'yes' if scan.get('git') else 'no'}{truncated}\n"
        )
        if top:
            stderr.write(f"codenook {label}: top-level entries: {top}\n")
    return True, None


def _ssh_target(spec: TargetSpec) -> str:
    assert spec.host
    return f"{spec.user}@{spec.host}" if spec.user else spec.host


def _ssh_base_command(spec: TargetSpec) -> list[str]:
    cmd = ["ssh"]
    if spec.port is not None:
        cmd += ["-p", str(spec.port)]
    cmd.append(_ssh_target(spec))
    return cmd


def _remote_prepare_command(path: str) -> str:
    quoted = shlex.quote(path)
    return (
        f"p={quoted}; "
        'if [ -e "$p" ] && [ ! -d "$p" ]; then '
        "echo STATUS=NOT_DIR; exit 73; "
        "fi; "
        'if [ -d "$p" ]; then status=EXISTED; '
        'else mkdir -p -- "$p" && status=CREATED; fi; '
        'printf "STATUS=%s\\n" "$status"; '
        'printf "DIRS=%s\\n" "$(find "$p" -mindepth 1 -type d 2>/dev/null | wc -l | tr -d \' \')"; '
        'printf "FILES=%s\\n" "$(find "$p" -mindepth 1 -type f 2>/dev/null | wc -l | tr -d \' \')"; '
        'if [ -d "$p/.git" ]; then echo GIT=yes; else echo GIT=no; fi; '
        'find "$p" -mindepth 1 -maxdepth 1 -exec basename {} \\; 2>/dev/null '
        '| sort | head -12 | sed "s/^/TOP=/"'
    )


def _parse_remote_summary(stdout: str) -> dict[str, object]:
    summary: dict[str, object] = {"top": []}
    for line in stdout.splitlines():
        if line in ("CREATED", "EXISTED", "NOT_DIR"):
            summary["status"] = line
            continue
        if "=" not in line:
            continue
        key, val = line.split("=", 1)
        if key == "TOP":
            top = summary.setdefault("top", [])
            if isinstance(top, list):
                top.append(val)
        elif key in ("DIRS", "FILES"):
            try:
                summary[key.lower()] = int(val)
            except ValueError:
                summary[key.lower()] = 0
        elif key == "GIT":
            summary["git"] = val == "yes"
        elif key == "STATUS":
            summary["status"] = val
    return summary


def _prepare_ssh_target(
    spec: TargetSpec,
    *,
    label: str,
    runner: Runner,
    stderr: TextIO,
) -> tuple[bool, str | None]:
    if not (spec.host and spec.remote_path and spec.uri):
        return False, "ssh target is missing host or path"
    cmd = _ssh_base_command(spec) + [_remote_prepare_command(spec.remote_path)]
    try:
        cp = runner(
            cmd,
            text=True,
            capture_output=True,
            encoding="utf-8",
            errors="replace",
        )
    except FileNotFoundError:
        return False, "ssh executable not found; install OpenSSH or use a local target"
    if cp.returncode != 0:
        summary = _parse_remote_summary(cp.stdout or "")
        if cp.returncode == 73 or summary.get("status") == "NOT_DIR":
            return False, (
                "target directory exists but is not a directory: "
                f"{spec.uri}"
            )
        detail = (cp.stderr or cp.stdout or "").strip()
        if detail:
            return False, f"failed to prepare ssh target {spec.uri}: {detail}"
        return False, f"failed to prepare ssh target {spec.uri} (exit {cp.returncode})"

    summary = _parse_remote_summary(cp.stdout or "")
    status = str(summary.get("status") or "PREPARED")
    stderr.write(
        f"codenook {label}: target_dir is the task working directory: "
        f"{spec.uri}\n"
    )
    stderr.write(
        f"codenook {label}: target_backend=ssh host={spec.host} "
        f"path={spec.remote_path}\n"
    )
    if status == "CREATED":
        stderr.write(
            f"codenook {label}: created remote target directory {spec.uri}\n"
        )
    elif status == "EXISTED":
        top = ", ".join(summary.get("top") or [])
        stderr.write(
            f"codenook {label}: existing remote target directory scanned: "
            f"{summary.get('dirs', 0)} dirs, {summary.get('files', 0)} files, "
            f"git={'yes' if summary.get('git') else 'no'}\n"
        )
        if top:
            stderr.write(f"codenook {label}: top-level entries: {top}\n")
    else:
        stderr.write(f"codenook {label}: prepared remote target directory\n")
    return True, None


def prepare_target_dir(
    workspace: Path,
    spec: TargetSpec,
    *,
    label: str,
    runner: Runner = subprocess.run,
    stderr: TextIO = sys.stderr,
) -> tuple[bool, str | None]:
    if spec.backend == "local":
        return _prepare_local_target(workspace, spec, label=label, stderr=stderr)
    if spec.backend == "ssh":
        return _prepare_ssh_target(spec, label=label, runner=runner, stderr=stderr)
    return False, (
        f"unsupported target backend '{spec.backend}' "
        f"(supported: {', '.join(SUPPORTED_BACKENDS)})"
    )


def _ssh_details(spec: TargetSpec) -> dict[str, object]:
    details: dict[str, object] = {
        "host": spec.host or "",
        "path": spec.remote_path or "",
        "ssh_target": _ssh_target(spec),
        "ssh_command": " ".join(_ssh_base_command(spec)),
    }
    if spec.user:
        details["user"] = spec.user
    if spec.port is not None:
        details["port"] = spec.port
    return details


def state_fields_for_target(spec: TargetSpec) -> dict[str, object]:
    fields: dict[str, object] = {
        "target_dir": spec.target_dir,
        "target_backend": spec.backend,
    }
    if spec.uri:
        fields["target_uri"] = spec.uri
    if spec.backend == "ssh":
        fields["target_details"] = _ssh_details(spec)
    return fields


def apply_state_fields(state: dict, spec: TargetSpec) -> None:
    for key in ("target_dir", "target_backend", "target_uri", "target_details"):
        state.pop(key, None)
    state.update(state_fields_for_target(spec))


def target_instruction_from_state(state: dict) -> str:
    backend = str(state.get("target_backend") or "local")
    target_dir = str(state.get("target_dir") or "target/")
    if backend == "ssh":
        details = state.get("target_details")
        ssh_command = ""
        remote_path = target_dir
        if isinstance(details, dict):
            ssh_command = str(details.get("ssh_command") or "")
            remote_path = str(details.get("path") or target_dir)
        command_hint = f" Use `{ssh_command}` for remote operations." if ssh_command else ""
        return (
            f"Target backend is ssh. Store task scripts under "
            f"`{remote_path}/scripts`, temporary/intermediate artifacts under "
            f"`{remote_path}/tmp`, and task logs/downloads under "
            f"`{remote_path}` unless a phase says otherwise.{command_hint}"
        )
    return (
        f"Target backend is local. Store task scripts, logs, downloads, "
        f"and temporary/intermediate artifacts under `{target_dir}`."
    )


def envelope_fields_from_state(state: dict) -> dict[str, object]:
    fields: dict[str, object] = {
        "target_dir": state.get("target_dir", "target/"),
        "target_backend": state.get("target_backend") or "local",
        "target_instructions": target_instruction_from_state(state),
    }
    if state.get("target_uri"):
        fields["target_uri"] = state["target_uri"]
    if isinstance(state.get("target_details"), dict):
        fields["target_details"] = state["target_details"]
    return fields

