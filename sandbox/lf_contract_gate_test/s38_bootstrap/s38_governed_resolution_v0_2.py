#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Mapping

GITHUB_REF = re.compile(
    r"^github://(?P<repo>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)@(?P<revision>[0-9a-f]{40})/(?P<path>.+)$"
)
ROOT = Path(__file__).resolve().parent
REPO_ROOT = ROOT.parents[2]
POLICY_PATH = ROOT / "s38_governed_trust_policy_v0_1.json"
LEGACY_RESOLVER_ID = "QUALITY_PACK_TRUSTED_REF_RESOLVER_V1"
PASS = "PASS"
BLOCKED = "BLOCKED"


class ResolutionError(RuntimeError):
    def __init__(self, code: str, detail: str = ""):
        super().__init__(f"{code}:{detail}" if detail else code)
        self.code = code
        self.detail = detail


def _git(root: Path, args: list[str], *, text: bool = False) -> bytes | str:
    p = subprocess.run(
        ["git", "-C", str(root), *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=text,
    )
    if p.returncode != 0:
        err = p.stderr.strip() if text else p.stderr.decode("utf-8", "replace").strip()
        raise ResolutionError("GIT_READBACK_FAILED", err[:240])
    return p.stdout


def _repo_root(start: Path) -> Path:
    p = subprocess.run(
        ["git", "-C", str(start), "rev-parse", "--show-toplevel"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if p.returncode != 0:
        raise ResolutionError("GOVERNED_ARTIFACT_ROOT_UNRESOLVED", p.stderr.strip()[:240])
    return Path(p.stdout.strip()).resolve()


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


class S38GovernedRefResolver:
    """Resolver whose authority is bound to canonical remote bytes, not caller root.

    The caller cannot choose a repository root. The module checkout HEAD, this
    resolver module and its trust policy are verified byte-for-byte against the
    canonical GitHub repository before any evidence is accepted. Every referenced
    revision is fetched from that canonical remote into an isolated object cache.
    """

    def __init__(self) -> None:
        self.root = _repo_root(ROOT)
        self.policy = json.loads(POLICY_PATH.read_text(encoding="utf-8"))
        repo = self.policy.get("canonical_repository") or {}
        self.repo = str(repo.get("slug") or "")
        self.remote_url = str(repo.get("remote_url") or "")
        self.resolver_id = str(self.policy.get("resolver_id") or "")
        if not self.repo or not self.remote_url or not self.resolver_id:
            raise ResolutionError("GOVERNED_TRUST_POLICY_INVALID")
        if repo.get("caller_supplied_root_authoritative") is not False:
            raise ResolutionError("CALLER_ROOT_AUTHORITY_NOT_DISABLED")
        if repo.get("resolved_bytes_must_come_from_canonical_remote") is not True:
            raise ResolutionError("CANONICAL_REMOTE_BYTE_AUTHORITY_NOT_REQUIRED")

        self.artifact_head = str(_git(self.root, ["rev-parse", "HEAD"], text=True)).strip()
        self.head = self.artifact_head
        self._tmp = tempfile.TemporaryDirectory(prefix="s38-governed-resolver-")
        self.cache = Path(self._tmp.name) / "objects.git"
        subprocess.run(["git", "init", "--bare", "-q", str(self.cache)], check=True)
        try:
            self._fetch_commit(self.artifact_head)
        except ResolutionError as exc:
            raise ResolutionError("BLOCK_GOVERNED_ARTIFACT_HEAD_UNPUBLISHED", exc.detail or exc.code) from exc

        self._verify_local_against_canonical(Path(__file__).resolve())
        self._verify_local_against_canonical(POLICY_PATH.resolve())
        self.verified = True

    def close(self) -> None:
        tmp = getattr(self, "_tmp", None)
        if tmp is not None:
            tmp.cleanup()
            self._tmp = None

    def __del__(self) -> None:
        try:
            self.close()
        except Exception:
            pass

    def _fetch_commit(self, revision: str) -> None:
        p = subprocess.run(
            ["git", "-C", str(self.cache), "cat-file", "-e", f"{revision}^{{commit}}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if p.returncode == 0:
            return
        p = subprocess.run(
            ["git", "-C", str(self.cache), "fetch", "-q", "--depth=1", self.remote_url, revision],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if p.returncode != 0:
            raise ResolutionError(
                "CANONICAL_REMOTE_REVISION_UNRESOLVED",
                p.stderr.decode("utf-8", "replace").strip()[:240],
            )
        fetched = str(_git(self.cache, ["rev-parse", "FETCH_HEAD"], text=True)).strip()
        if fetched != revision:
            raise ResolutionError("CANONICAL_REMOTE_REVISION_MISMATCH", f"expected={revision} observed={fetched}")

    def _raw(self, revision: str, path: str) -> bytes:
        self._fetch_commit(revision)
        try:
            return bytes(_git(self.cache, ["show", f"{revision}:{path}"]))
        except ResolutionError as exc:
            raise ResolutionError("CANONICAL_REMOTE_PATH_UNRESOLVED", f"{revision}:{path}") from exc

    def _verify_local_against_canonical(self, local_path: Path) -> None:
        try:
            rel = local_path.relative_to(self.root).as_posix()
        except ValueError as exc:
            raise ResolutionError("GOVERNED_ARTIFACT_OUTSIDE_REPOSITORY", str(local_path)) from exc
        canonical = self._raw(self.artifact_head, rel)
        local = local_path.read_bytes()
        if _sha256(canonical) != _sha256(local):
            raise ResolutionError("BLOCK_GOVERNED_ARTIFACT_BYTE_MISMATCH", rel)

    def resolve(self, ref: str) -> dict[str, Any]:
        if not isinstance(ref, str):
            raise ResolutionError("REF_MISSING")
        m = GITHUB_REF.fullmatch(ref.strip())
        if not m:
            raise ResolutionError("UNSUPPORTED_REF_SCHEME", str(ref)[:160])
        repo = m.group("repo")
        revision = m.group("revision")
        path = m.group("path")
        if repo != self.repo:
            raise ResolutionError("FOREIGN_REPO_NOT_RESOLVABLE_BY_GOVERNED_RESOLVER", repo)
        parts = Path(path).parts
        if path.startswith("/") or ".." in parts or not path or "\x00" in path or ":" in path:
            raise ResolutionError("UNSAFE_REPOSITORY_PATH", path[:160])
        raw = self._raw(revision, path)
        return {
            "ref": ref,
            "repo": repo,
            "revision": revision,
            "path": path,
            "sha256": _sha256(raw),
            "bytes": len(raw),
            "raw": raw,
        }

    def content_current(self, observed: Mapping[str, Any]) -> bool:
        try:
            current_raw = self._raw(self.artifact_head, str(observed["path"]))
            if _sha256(current_raw) == observed.get("sha256"):
                return True
        except ResolutionError:
            pass
        currentness = self.policy.get("currentness") or {}
        for entry in currentness.get("archival_registry") or []:
            if not isinstance(entry, Mapping) or entry.get("status") != "CURRENT":
                continue
            refs = []
            if isinstance(entry.get("historical_ref"), str):
                refs.append(entry["historical_ref"])
            refs.extend([r for r in entry.get("historical_refs") or [] if isinstance(r, str)])
            if observed.get("ref") in refs and observed.get("sha256") == entry.get("sha256"):
                return True
        return False


def is_trusted_resolver(resolver: Any) -> bool:
    return type(resolver) is S38GovernedRefResolver and resolver.verified is True


def block(code: str, **extra: Any) -> dict[str, Any]:
    return {"status": BLOCKED, "code": code, **extra}


def resolve_source(
    resolver: Any,
    ref: str,
    expected_sha256: str,
    label: str,
    *,
    require_current_content: bool = True,
) -> tuple[dict[str, Any], Mapping[str, Any] | None]:
    if not is_trusted_resolver(resolver):
        return block("BLOCK_UNTRUSTED_RESOLVER_TYPE", binding=label), None
    try:
        observed = resolver.resolve(ref)
    except ResolutionError as exc:
        return block("BLOCK_TRUSTED_REF_RESOLUTION_FAILED", binding=label, resolver_code=exc.code), None
    except Exception as exc:
        return block("BLOCK_TRUSTED_REF_RESOLUTION_FAILED", binding=label, error=type(exc).__name__), None
    if observed.get("sha256") != expected_sha256:
        return block(
            "BLOCK_PROVIDER_BYTE_DIGEST_MISMATCH",
            binding=label,
            expected=expected_sha256,
            observed=observed.get("sha256"),
        ), None
    if require_current_content and not resolver.content_current(observed):
        return block("BLOCK_PROVIDER_SOURCE_STALE", binding=label, ref=ref), None
    return {"status": PASS, "code": "PASS_GOVERNED_SOURCE_RESOLUTION", "binding": label}, observed


def resolve_json_binding(
    resolver: Any,
    binding: Mapping[str, Any] | None,
    expected_type: str,
    label: str,
    *,
    require_current_content: bool = True,
) -> tuple[dict[str, Any], Mapping[str, Any] | None, Mapping[str, Any] | None]:
    if not isinstance(binding, Mapping):
        return block("BLOCK_EVIDENCE_BINDING_MISSING", binding=label), None, None
    if not is_trusted_resolver(resolver):
        return block("BLOCK_UNTRUSTED_RESOLVER_TYPE", binding=label), None, None
    accepted_ids = {resolver.resolver_id, LEGACY_RESOLVER_ID}
    if binding.get("resolver_id") not in accepted_ids:
        return block("BLOCK_UNTRUSTED_RESOLVER_ID", binding=label), None, None
    ref = binding.get("ref")
    sha = binding.get("sha256") or binding.get("digest")
    if not isinstance(ref, str) or not ref:
        return block("BLOCK_EVIDENCE_REF_MISSING", binding=label), None, None
    if not isinstance(sha, str) or len(sha) != 64:
        return block("BLOCK_EVIDENCE_SHA256_INVALID", binding=label), None, None
    status, observed = resolve_source(
        resolver, ref, sha, label, require_current_content=require_current_content
    )
    if status.get("status") != PASS:
        return status, None, observed
    try:
        record = json.loads(observed["raw"].decode("utf-8"))
    except Exception:
        return block("BLOCK_RESOLVED_EVIDENCE_NOT_JSON", binding=label), None, observed
    if not isinstance(record, Mapping):
        return block("BLOCK_RESOLVED_EVIDENCE_NOT_OBJECT", binding=label), None, observed
    if record.get("evidence_type") != expected_type:
        return block(
            "BLOCK_EVIDENCE_TYPE_MISMATCH",
            binding=label,
            expected=expected_type,
            observed=record.get("evidence_type"),
        ), None, observed
    if record.get("status") != PASS:
        return block("BLOCK_RESOLVED_EVIDENCE_NOT_PASS", binding=label, observed=record.get("status")), None, observed
    return {"status": PASS, "code": "PASS_GOVERNED_JSON_EVIDENCE", "binding": label}, record, observed


def immutable_ref(resolver: Any, path: str, revision: str | None = None) -> str:
    if not is_trusted_resolver(resolver):
        raise TypeError("S38GovernedRefResolver required")
    return f"github://{resolver.repo}@{revision or resolver.artifact_head}/{path}"
