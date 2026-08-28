#!/usr/bin/env python3
import hashlib
import re
import subprocess
from pathlib import Path
from urllib.parse import urlparse

GITHUB_REF = re.compile(
    r"^github://(?P<repo>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)@(?P<revision>[0-9a-f]{40})/(?P<path>.+)$"
)


class ResolutionError(RuntimeError):
    def __init__(self, code, detail=""):
        super().__init__(f"{code}:{detail}" if detail else code)
        self.code = code
        self.detail = detail


def _run_git(root, args, *, text=False):
    proc = subprocess.run(
        ["git", "-C", str(root), *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=text,
    )
    if proc.returncode != 0:
        detail = proc.stderr.strip() if text else proc.stderr.decode("utf-8", "replace").strip()
        raise ResolutionError("GIT_READBACK_FAILED", detail[:240])
    return proc.stdout


def repo_root(start=None):
    start = Path(start or __file__).resolve()
    cwd = start if start.is_dir() else start.parent
    proc = subprocess.run(
        ["git", "-C", str(cwd), "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise ResolutionError("REPOSITORY_ROOT_UNRESOLVED", proc.stderr.strip()[:240])
    return Path(proc.stdout.strip()).resolve()


def _origin_slug(root):
    origin = _run_git(root, ["remote", "get-url", "origin"], text=True).strip()
    if origin.startswith("git@github.com:"):
        slug = origin.split(":", 1)[1]
    else:
        parsed = urlparse(origin)
        if parsed.hostname not in {"github.com", "www.github.com"}:
            raise ResolutionError("UNSUPPORTED_ORIGIN", origin)
        slug = parsed.path.lstrip("/")
    if slug.endswith(".git"):
        slug = slug[:-4]
    if slug.count("/") != 1:
        raise ResolutionError("ORIGIN_REPO_UNRESOLVED", slug)
    return slug


class TrustedRefResolver:
    """Resolve immutable same-repository GitHub refs from Git bytes.

    Candidate flags such as observed/read/current never create evidence. This
    resolver derives bytes, SHA-256 and currentness from the checked-out repo.
    Other providers require a separately authorized resolver and fail closed here.
    """

    def __init__(self, root=None):
        self.root = repo_root(root)
        self.repo = _origin_slug(self.root)
        self.head = _run_git(self.root, ["rev-parse", "HEAD"], text=True).strip()

    def resolve(self, ref):
        if not isinstance(ref, str):
            raise ResolutionError("REF_MISSING")
        match = GITHUB_REF.fullmatch(ref.strip())
        if not match:
            raise ResolutionError("UNSUPPORTED_REF_SCHEME", ref[:160])

        repo = match.group("repo")
        revision = match.group("revision")
        path = match.group("path")
        if repo != self.repo:
            raise ResolutionError("FOREIGN_REPO_NOT_RESOLVABLE_BY_LOCAL_TRUSTED_RESOLVER", repo)
        parts = Path(path).parts
        if path.startswith("/") or ".." in parts or not path or "\x00" in path or ":" in path:
            raise ResolutionError("UNSAFE_REPOSITORY_PATH", path[:160])

        _run_git(self.root, ["cat-file", "-e", f"{revision}^{{commit}}"])
        raw = _run_git(self.root, ["show", f"{revision}:{path}"])
        return {
            "ref": ref,
            "repo": repo,
            "revision": revision,
            "path": path,
            "sha256": hashlib.sha256(raw).hexdigest(),
            "bytes": len(raw),
            "current": revision == self.head,
            "raw": raw,
        }
