"""Exact read-only Git artifacts; no fetch, credentials, writes or admission.

Registered repository/source identities are trusted configuration, not caller
input. Origin/tree binding checks are integrity checks, not governance approval.
"""
from dataclasses import dataclass
import base64
import hashlib
from pathlib import Path, PurePosixPath
import re
import subprocess
from typing import Callable

HEX40 = re.compile(r"[0-9a-f]{40}")
HEX64 = re.compile(r"[0-9a-f]{64}")
REPO = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
MAX_BYTES = 1024 * 1024


class SourceReadError(ValueError):
    pass


@dataclass(frozen=True)
class Identity:
    repo: str
    commit: str
    path: str


def identity(pin):
    if not isinstance(pin, dict):
        raise SourceReadError("ARTIFACT_PIN_REQUIRED")
    repo, commit, path = (pin.get(k) for k in ("repo", "commit", "path"))
    if not isinstance(repo, str) or not REPO.fullmatch(repo) or any(x in {".", ".."} for x in repo.split("/")):
        raise SourceReadError("REPOSITORY_ID_INVALID")
    if not isinstance(commit, str) or not HEX40.fullmatch(commit):
        raise SourceReadError("EXACT_COMMIT_REQUIRED")
    if (not isinstance(path, str) or not path or "\x00" in path
            or PurePosixPath(path).is_absolute() or ".." in PurePosixPath(path).parts
            or str(PurePosixPath(path)) != path or path == "."):
        raise SourceReadError("ARTIFACT_PATH_INVALID")
    return Identity(repo, commit, path)


def blob_oid(raw):
    return hashlib.sha1(b"blob " + str(len(raw)).encode("ascii") + b"\0" + raw).hexdigest()


class LocalGitBackend:
    """Only read Git objects from explicitly registered local repositories."""
    def __init__(self, repositories: dict[str, Path], max_bytes=MAX_BYTES):
        self._repositories = {k: Path(v).resolve() for k, v in repositories.items()}
        self.max_bytes = max_bytes

    def _git(self, repo, *args, missing_ok=False):
        command = ["/usr/bin/git", "--no-pager", "--no-optional-locks",
                   "-c", "core.fsmonitor=false", "-C", str(repo), *args]
        env = {"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8",
               "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
               "GIT_OPTIONAL_LOCKS": "0", "GIT_NO_REPLACE_OBJECTS": "1",
               "GIT_NO_LAZY_FETCH": "1", "GIT_TERMINAL_PROMPT": "0"}
        result = subprocess.run(command, capture_output=True, timeout=10, env=env)
        if missing_ok and result.returncode == 1:
            return b""
        if result.returncode:
            raise SourceReadError("LOCAL_GIT_READ_FAILED")
        return result.stdout

    def read(self, subject: Identity):
        repo = self._repositories.get(subject.repo)
        if repo is None:
            raise SourceReadError("REPOSITORY_NOT_REGISTERED")
        origin = self._git(repo, "config", "--local", "--get", "remote.origin.url").decode("utf-8").strip()
        allowed = {"https://github.com/" + subject.repo,
                   "https://github.com/" + subject.repo + ".git",
                   "git@github.com:" + subject.repo + ".git"}
        if origin not in allowed:
            raise SourceReadError("REGISTERED_ORIGIN_MISMATCH")
        partial = self._git(repo, "config", "--local", "--get-regexp",
                            r"^(extensions\.partialclone|remote\..*\.promisor)$",
                            missing_ok=True)
        if partial.strip():
            raise SourceReadError("PARTIAL_CLONE_NOT_SUPPORTED")
        if self._git(repo, "cat-file", "-t", subject.commit).strip() != b"commit":
            raise SourceReadError("COMMIT_OBJECT_REQUIRED")
        rows = self._git(repo, "ls-tree", "-z", subject.commit, "--",
                         ":(literal)" + subject.path).split(b"\0")
        rows = [r for r in rows if r]
        if len(rows) != 1:
            raise SourceReadError("EXACT_FILE_NOT_FOUND")
        header, name = rows[0].split(b"\t", 1)
        mode, kind, oid = header.split(b" ")
        if name.decode("utf-8") != subject.path or kind != b"blob" or mode not in {b"100644", b"100755"}:
            raise SourceReadError("REGULAR_GIT_BLOB_REQUIRED")
        size = int(self._git(repo, "cat-file", "-s", oid.decode("ascii")).strip())
        if size > self.max_bytes:
            raise SourceReadError("ARTIFACT_TOO_LARGE")
        raw = self._git(repo, "cat-file", "blob", oid.decode("ascii"))
        return {"repo": subject.repo, "commit": subject.commit, "path": subject.path,
                "blob_sha": oid.decode("ascii"), "tree_blob_sha": oid.decode("ascii"),
                "raw": raw, "transport": "LOCAL_GIT_OBJECT_READ"}


class ConnectedReadbackBackend:
    """Read adapter for authenticated RO blob exports, registered by tree entry.

    Fetch must supply exact repo/commit/path, blob_sha, encoding and content.
    It is an injected read port; this class never opens a URL or selects an account.
    """
    def __init__(self, registered_sources: dict, fetch: Callable, max_bytes=MAX_BYTES):
        self._registered = dict(registered_sources)
        self._fetch = fetch
        self.max_bytes = max_bytes

    def read(self, subject: Identity):
        expected_blob = self._registered.get((subject.repo, subject.commit, subject.path))
        if not isinstance(expected_blob, str) or not HEX40.fullmatch(expected_blob):
            raise SourceReadError("SOURCE_NOT_REGISTERED")
        row = self._fetch(subject.repo, subject.commit, subject.path)
        if (not isinstance(row, dict)
                or (row.get("repo"), row.get("commit"), row.get("path")) != (subject.repo, subject.commit, subject.path)
                or row.get("blob_sha") != expected_blob or row.get("encoding") != "base64"
                or not isinstance(row.get("content"), str)):
            raise SourceReadError("CONNECTED_READBACK_IDENTITY_MISMATCH")
        encoded = re.sub(r"[ \t\r\n]", "", row["content"])
        if len(encoded) > 4 * ((self.max_bytes + 2) // 3):
            raise SourceReadError("ARTIFACT_TOO_LARGE")
        try:
            raw = base64.b64decode(encoded, validate=True)
        except (ValueError, TypeError) as exc:
            raise SourceReadError("CONNECTED_BASE64_INVALID") from exc
        return {"repo": subject.repo, "commit": subject.commit, "path": subject.path,
                "blob_sha": expected_blob, "tree_blob_sha": expected_blob,
                "raw": raw, "transport": "CONNECTED_RO_BLOB_READBACK"}


class ExactArtifactReader:
    """Callable compatible with validate_technical_framework's artifact reader."""
    def __init__(self, backend, max_bytes=MAX_BYTES):
        self._backend, self.max_bytes = backend, max_bytes

    def _read(self, subject):
        row = self._backend.read(subject)
        if (not isinstance(row, dict)
                or (row.get("repo"), row.get("commit"), row.get("path")) != (subject.repo, subject.commit, subject.path)
                or not isinstance(row.get("raw"), bytes)
                or not isinstance(row.get("blob_sha"), str)
                or not HEX40.fullmatch(row["blob_sha"])
                or row["blob_sha"] != row.get("tree_blob_sha")):
            raise SourceReadError("OBSERVATION_IDENTITY_INVALID")
        raw = row["raw"]
        if len(raw) > self.max_bytes:
            raise SourceReadError("ARTIFACT_TOO_LARGE")
        if blob_oid(raw) != row["blob_sha"]:
            raise SourceReadError("GIT_BLOB_DIGEST_MISMATCH")
        return raw, row

    def __call__(self, pin):
        subject = identity(pin)
        digest = pin.get("sha256")
        if not isinstance(digest, str) or not HEX64.fullmatch(digest):
            raise SourceReadError("ARTIFACT_SHA256_REQUIRED")
        raw, _ = self._read(subject)
        if hashlib.sha256(raw).hexdigest() != digest:
            raise SourceReadError("ARTIFACT_SHA256_MISMATCH")
        return raw

    def observe(self, pin, *, revision):
        """Observe an explicit commit independently of the bound expected hash.

        Returns facts, never CURRENT/ready or a replacement pin. Caller must
        compare via CURRENTNESS_AUTHORITY and preserve the original binding.
        """
        subject = identity({**pin, "commit": revision})
        raw, row = self._read(subject)
        return {"repo": subject.repo, "commit": subject.commit, "path": subject.path,
                "blob_sha": row["blob_sha"], "sha256": hashlib.sha256(raw).hexdigest(),
                "bytes": len(raw), "transport": row["transport"]}
