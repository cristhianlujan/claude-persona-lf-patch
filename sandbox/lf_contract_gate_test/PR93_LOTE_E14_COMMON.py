#!/usr/bin/env python3
"""Authoritative PR #93 LOTE-E.14 evidence capture."""
from __future__ import annotations

import argparse
import ctypes
import errno
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
import PR93_LOTE_E14_SEMANTICS as semantics

SCHEMA_VERSION = "PR93_E14_RECEIPT_V1"
REPOSITORY = "cristhianlujan/claude-persona-lf-patch"
HEAD_RE = re.compile(r"^[0-9a-f]{40}$")

SOURCE_PATHS = (
    "sandbox/lf_contract_gate_test/PR93_LOTE_E10_RUNBOOK.psql",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_T1.psql",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_T2.psql",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_STATE_READBACK.sql",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E10_CORRELATION_READBACK.sql",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E11_SYSTEM_IDENTIFIER_PROBE.sql",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E8_EXECUTION_CONTEXT_READBACK.sql",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E6_DEPENDENCY_PREFLIGHT.sql",
    "sandbox/lf_contract_gate_test/PR93_LOTE_C_EVIDENCE_READBACK.sql",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E5_FINAL_INTEGRITY_READBACK.sql",
    "sandbox/lf_contract_gate_test/PR93_WRITER_V7_ADVERSARIAL_TESTS.sql",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_CAPTURE.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_CAPTURE_V2.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_VERIFY.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_VERIFY_V2.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_NEGATIVE_TESTS.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_NEGATIVE_TESTS_V2.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E14_CAPTURE.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E14_COMMON.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E14_VERIFY.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E14_VERIFY_COMMON.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E14_VERIFY_TRANSCRIPT.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E14_NEGATIVE_TESTS.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E14_SEMANTICS.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E14_GUARDS.md",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E15_GUARDS.md",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E15_1_REGRESSION_TESTS.py",
    # CA-N138: the bytecode-residue control is a mandatory artifact, therefore
    # it belongs to the binding inventory instead of being an untracked side
    # effect of the lote.
    "sandbox/lf_contract_gate_test/.gitignore",
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_json_bytes(value: Any) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        + "\n"
    ).encode("utf-8")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def run_process(
    command: list[str],
    cwd: Path,
    timeout: int,
    env: dict[str, str],
) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
        timeout=timeout,
        env=env,
    )


def git_text(repo_root: Path, args: list[str], timeout: int) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=repo_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=timeout,
    )
    if result.returncode != 0:
        raise RuntimeError(
            result.stderr.decode("utf-8", "replace").strip() or "git command failed"
        )
    return result.stdout.decode("utf-8", "strict").strip()


def assert_repository(repo_root: Path, head_sha: str, timeout: int) -> None:
    if HEAD_RE.fullmatch(head_sha) is None:
        raise ValueError("head SHA must be exactly 40 lowercase hexadecimal characters")
    actual_head = git_text(repo_root, ["rev-parse", "HEAD"], timeout)
    if actual_head != head_sha:
        raise RuntimeError(f"HEAD mismatch: expected {head_sha}, observed {actual_head}")
    status = git_text(
        repo_root,
        ["status", "--porcelain=v1", "--untracked-files=all"],
        timeout,
    )
    if status:
        raise RuntimeError("working tree must be clean before evidence capture")


def source_inventory(
    repo_root: Path, timeout: int
) -> dict[str, dict[str, str | int]]:
    inventory: dict[str, dict[str, str | int]] = {}
    for relative in SOURCE_PATHS:
        path = repo_root / relative
        if not path.is_file():
            raise RuntimeError(f"required source artifact is missing: {relative}")
        data = path.read_bytes()
        inventory[relative] = {
            "git_blob_sha1": git_text(
                repo_root, ["rev-parse", f"HEAD:{relative}"], timeout
            ),
            "sha256": sha256_bytes(data),
            "size_bytes": len(data),
        }
    return inventory


def clean_child_env(app_name: str) -> dict[str, str]:
    env = os.environ.copy()
    env.pop("DATABASE_URL", None)
    env.pop("PGDATABASE", None)
    env["PGAPPNAME"] = app_name
    return env


def psql_base(psql_bin: str, database_url: str) -> list[str]:
    return [
        psql_bin,
        "--dbname",
        database_url,
        "-X",
        "--no-psqlrc",
        "--set=ON_ERROR_STOP=1",
        "--set=VERBOSITY=terse",
    ]


def connectivity_preflight(
    psql_bin: str,
    database_url: str,
    cwd: Path,
    timeout: int,
) -> tuple[int, bytes]:
    command = [
        *psql_base(psql_bin, database_url),
        "--tuples-only",
        "--no-align",
        "--command",
        "select 1",
    ]
    result = run_process(
        command,
        cwd,
        timeout,
        clean_child_env("pr93-e14-connectivity-preflight"),
    )
    output = result.stdout
    if result.returncode != 0:
        return result.returncode, output
    if output.decode("utf-8", "strict").strip() != "1":
        return 91, output + b"\nE14_CONNECTIVITY_PREFLIGHT_UNEXPECTED_OUTPUT\n"
    return 0, output


def run_psql(
    psql_bin: str,
    database_url: str,
    script: Path,
    cwd: Path,
    timeout: int,
    head_sha: str,
) -> tuple[int, bytes]:
    command = [
        *psql_base(psql_bin, database_url),
        f"--set=E13_HEAD_SHA={head_sha}",
        "--file",
        str(script),
    ]
    result = run_process(
        command,
        cwd,
        timeout,
        clean_child_env("pr93-e14-evidence"),
    )
    return result.returncode, result.stdout


def run_state_readback(
    psql_bin: str,
    database_url: str,
    script: Path,
    cwd: Path,
    timeout: int,
) -> tuple[int, bytes, Any | None]:
    command = [
        *psql_base(psql_bin, database_url),
        "--tuples-only",
        "--no-align",
        "--file",
        str(script),
    ]
    result = run_process(
        command,
        cwd,
        timeout,
        clean_child_env("pr93-e14-state-readback"),
    )
    output = result.stdout
    if result.returncode != 0:
        return result.returncode, output, None
    try:
        value = json.loads(output.decode("utf-8", "strict").strip())
    except json.JSONDecodeError:
        return 90, output + b"\nE14_STATE_JSON_INVALID\n", None
    if not isinstance(value, dict):
        return 92, output + b"\nE14_STATE_JSON_NOT_OBJECT\n", None
    return 0, output, value



def json_output_matches(output: bytes, state: Any | None) -> bool:
    if state is None:
        return False
    try:
        parsed = json.loads(output.decode("utf-8", "strict").strip())
    except (UnicodeDecodeError, json.JSONDecodeError):
        return False
    return parsed == state

def exact_line_count(data: bytes) -> int:
    return len(data.splitlines())


def count_exact_line(data: bytes, marker: str) -> int:
    return sum(
        line == marker
        for line in data.decode("utf-8", "replace").splitlines()
    )


def count_prefixed_line(data: bytes, prefix: str) -> int:
    return sum(
        line.startswith(prefix)
        for line in data.decode("utf-8", "replace").splitlines()
    )


# --- CA-N125..N128 / CA-N133..N137 / CA-N143: durable publication ----------
#
# Bundles are assembled in exclusive staging directories and published using
# renameat2(RENAME_NOREPLACE). Cleanup is descriptor-bound: the directory is
# opened without following symlinks, its inode is verified with fstat(), its
# contents are removed relative to that descriptor, and the top-level name is
# revalidated before an atomic no-replace detach and final rmdir.

STAGING_PREFIX = ".pr93-e15-staging-"
CLEANUP_TOMBSTONE_PREFIX = ".pr93-e15-cleanup-"
AT_FDCWD = -100
RENAME_NOREPLACE = 1


class ContractError(RuntimeError):
    """Fail-closed publication or cleanup contract violation."""


def write_exclusive(path: Path, data: bytes) -> None:
    with path.open("xb") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())


def fsync_file(path: Path) -> None:
    handle = os.open(path, os.O_RDONLY | os.O_CLOEXEC)
    try:
        os.fsync(handle)
    finally:
        os.close(handle)


def fsync_directory(path: Path) -> None:
    handle = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        os.fsync(handle)
    finally:
        os.close(handle)


def path_identity(path: Path) -> tuple[int, int]:
    current = path.lstat()
    return current.st_dev, current.st_ino


def _identity_from_stat(value: os.stat_result) -> tuple[int, int]:
    return value.st_dev, value.st_ino


def _directory_open_flags() -> int:
    required = ("O_DIRECTORY", "O_NOFOLLOW")
    missing = [name for name in required if not hasattr(os, name)]
    if missing:
        raise ContractError(
            "descriptor-bound cleanup is unavailable; missing " + ",".join(missing)
        )
    return os.O_RDONLY | os.O_CLOEXEC | os.O_DIRECTORY | os.O_NOFOLLOW


def _open_directory_nofollow(
    path: str | os.PathLike[str], *, dir_fd: int | None = None
) -> int:
    """Open one directory component without following a symlink."""
    return os.open(path, _directory_open_flags(), dir_fd=dir_fd)


def _rename_noreplace_at(
    source_dir_fd: int,
    source_name: str | bytes,
    destination_dir_fd: int,
    destination_name: str | bytes,
) -> None:
    libc = ctypes.CDLL(None, use_errno=True)
    function = getattr(libc, "renameat2", None)
    if function is None:
        raise ContractError("renameat2(RENAME_NOREPLACE) is unavailable")
    function.argtypes = [
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_uint,
    ]
    function.restype = ctypes.c_int
    ctypes.set_errno(0)
    result = function(
        source_dir_fd,
        os.fsencode(source_name),
        destination_dir_fd,
        os.fsencode(destination_name),
        RENAME_NOREPLACE,
    )
    if result == 0:
        return
    error = ctypes.get_errno()
    if error in (errno.ENOSYS, errno.EINVAL, errno.EOPNOTSUPP):
        raise ContractError(
            "renameat2(RENAME_NOREPLACE) is unsupported by this kernel or filesystem"
        )
    raise OSError(error, os.strerror(error), os.fsdecode(destination_name))


def rename_noreplace(source: Path, destination: Path) -> None:
    """Linux atomic rename with no-clobber semantics; unsupported hosts fail closed."""
    _rename_noreplace_at(
        AT_FDCWD,
        os.fspath(source),
        AT_FDCWD,
        os.fspath(destination),
    )


def staging_directory(destination: Path) -> Path:
    """Create an exclusive staging directory beside the final destination."""
    parent = destination.parent
    parent.mkdir(parents=True, exist_ok=True)
    if not parent.is_dir() or parent.is_symlink():
        raise ContractError("destination parent must be a real directory")
    return Path(tempfile.mkdtemp(prefix=STAGING_PREFIX, dir=parent))


def discard_tree_contents(directory_fd: int) -> bool:
    """Remove entries only through an already-validated directory descriptor."""
    scan_fd = os.dup(directory_fd)
    with os.scandir(scan_fd) as entries:
        snapshot = list(entries)

    for entry in snapshot:
        try:
            before = entry.stat(follow_symlinks=False)
        except FileNotFoundError:
            continue

        mode = before.st_mode
        if stat.S_ISDIR(mode):
            try:
                child_fd = _open_directory_nofollow(entry.name, dir_fd=directory_fd)
            except (FileNotFoundError, NotADirectoryError, OSError):
                return False
            try:
                if _identity_from_stat(os.fstat(child_fd)) != _identity_from_stat(before):
                    return False
                if not discard_tree_contents(child_fd):
                    return False
                try:
                    current = os.stat(
                        entry.name,
                        dir_fd=directory_fd,
                        follow_symlinks=False,
                    )
                except FileNotFoundError:
                    continue
                if _identity_from_stat(current) != _identity_from_stat(before):
                    return False
                try:
                    os.rmdir(entry.name, dir_fd=directory_fd)
                except (FileNotFoundError, NotADirectoryError, OSError):
                    return False
            finally:
                os.close(child_fd)
            continue

        try:
            current = os.stat(
                entry.name,
                dir_fd=directory_fd,
                follow_symlinks=False,
            )
        except FileNotFoundError:
            continue
        if _identity_from_stat(current) != _identity_from_stat(before):
            return False
        try:
            os.unlink(entry.name, dir_fd=directory_fd)
        except (FileNotFoundError, IsADirectoryError, OSError):
            return False
    return True


def _unused_cleanup_name(parent_fd: int) -> str:
    for _ in range(128):
        candidate = CLEANUP_TOMBSTONE_PREFIX + os.urandom(12).hex()
        try:
            os.stat(candidate, dir_fd=parent_fd, follow_symlinks=False)
        except FileNotFoundError:
            return candidate
    raise ContractError("could not allocate a private cleanup name")


def discard_owned_tree(path: Path, expected_identity: tuple[int, int]) -> bool:
    """Remove only the directory inode registered by this process."""
    absolute = path.absolute()
    try:
        parent_fd = _open_directory_nofollow(absolute.parent)
    except (FileNotFoundError, NotADirectoryError, OSError):
        return False

    target_fd: int | None = None
    try:
        try:
            target_fd = _open_directory_nofollow(absolute.name, dir_fd=parent_fd)
        except FileNotFoundError:
            return True
        except (NotADirectoryError, OSError):
            return False

        if _identity_from_stat(os.fstat(target_fd)) != expected_identity:
            return False
        if not discard_tree_contents(target_fd):
            return False
        if _identity_from_stat(os.fstat(target_fd)) != expected_identity:
            return False

        try:
            current = os.stat(
                absolute.name,
                dir_fd=parent_fd,
                follow_symlinks=False,
            )
        except FileNotFoundError:
            return True
        if _identity_from_stat(current) != expected_identity:
            return False

        detached_name = _unused_cleanup_name(parent_fd)
        try:
            _rename_noreplace_at(
                parent_fd,
                absolute.name,
                parent_fd,
                detached_name,
            )
        except FileNotFoundError:
            return True
        except OSError:
            return False

        try:
            detached = os.stat(
                detached_name,
                dir_fd=parent_fd,
                follow_symlinks=False,
            )
        except FileNotFoundError:
            return False

        if _identity_from_stat(detached) != expected_identity:
            try:
                _rename_noreplace_at(
                    parent_fd,
                    detached_name,
                    parent_fd,
                    absolute.name,
                )
            except OSError:
                pass
            return False

        try:
            os.rmdir(detached_name, dir_fd=parent_fd)
        except (FileNotFoundError, NotADirectoryError, OSError):
            return False
        return True
    finally:
        if target_fd is not None:
            os.close(target_fd)
        os.close(parent_fd)


def discard_staging(
    staging: Path, expected_identity: tuple[int, int] | None = None
) -> bool:
    if expected_identity is None:
        try:
            expected_identity = path_identity(staging)
        except FileNotFoundError:
            return True
    return discard_owned_tree(staging, expected_identity)


def publish_atomically(staging: Path, destination: Path) -> None:
    """Publish complete evidence without replacing an existing destination."""
    if staging.is_symlink() or not staging.is_dir():
        raise ContractError("staging must be a real directory")
    staging_identity = path_identity(staging)
    for child in sorted(staging.iterdir(), key=lambda item: item.name):
        mode = child.lstat().st_mode
        if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
            raise ContractError(f"staging contains non-regular entry: {child.name}")
        fsync_file(child)
    fsync_directory(staging)
    rename_noreplace(staging, destination)
    try:
        fsync_directory(destination.parent)
    except BaseException:
        cleaned = discard_owned_tree(destination, staging_identity)
        if cleaned:
            try:
                fsync_directory(destination.parent)
            except OSError:
                pass
        else:
            raise ContractError(
                "parent fsync failed and published destination cleanup was not confirmed"
            )
        raise


def create_owned_output_root(root: Path) -> tuple[Path, tuple[int, int]]:
    """CA-N133: never remove or reuse a caller-provided existing path."""
    absolute = root.absolute()
    if os.path.lexists(absolute):
        raise ContractError("output root already exists; refusing to alter caller data")
    absolute.mkdir(parents=False, exist_ok=False)
    return absolute, path_identity(absolute)
