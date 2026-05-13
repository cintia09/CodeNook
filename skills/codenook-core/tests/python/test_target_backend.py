from __future__ import annotations

import sys
from pathlib import Path


CORE = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(CORE / "_lib"))

from cli import target_backend  # noqa: E402


def test_parse_local_relative_target() -> None:
    spec, err = target_backend.parse_target_dir_arg("target/T-001")
    assert err is None
    assert spec is not None
    assert spec.backend == "local"
    assert spec.target_dir == "target/T-001"


def test_parse_windows_forward_slash_path_as_local() -> None:
    spec, err = target_backend.parse_target_dir_arg("C:/work/codenook-target")
    assert err is None
    assert spec is not None
    assert spec.backend == "local"
    assert spec.target_dir.replace("\\", "/") == "C:/work/codenook-target"


def test_parse_ssh_uri_target() -> None:
    spec, err = target_backend.parse_target_dir_arg(
        "ssh://mingdw@10.64.64.185:2222/home/mingdw/codenook/target/PR05448763"
    )
    assert err is None
    assert spec is not None
    assert spec.backend == "ssh"
    assert spec.user == "mingdw"
    assert spec.host == "10.64.64.185"
    assert spec.port == 2222
    assert spec.remote_path == "/home/mingdw/codenook/target/PR05448763"


def test_parse_scp_like_target() -> None:
    spec, err = target_backend.parse_target_dir_arg(
        "mingdw@10.64.64.185:/home/mingdw/codenook/target/PR05448763"
    )
    assert err is None
    assert spec is not None
    assert spec.backend == "ssh"
    assert spec.target_dir == (
        "ssh://mingdw@10.64.64.185/home/mingdw/codenook/target/PR05448763"
    )

