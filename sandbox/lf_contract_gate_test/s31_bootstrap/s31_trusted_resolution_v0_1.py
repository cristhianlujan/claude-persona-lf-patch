#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from typing import Any, Mapping

ROOT = Path(__file__).resolve().parent
REPO_ROOT = ROOT.parents[2]
RESOLVER_PATH = REPO_ROOT / "profiles/quality_pack/validators/trusted_ref_resolver.py"
_spec = importlib.util.spec_from_file_location("lf_quality_trusted_ref_resolver", RESOLVER_PATH)
_mod = importlib.util.module_from_spec(_spec)
assert _spec.loader is not None
_spec.loader.exec_module(_mod)
TrustedRefResolver = _mod.TrustedRefResolver
ResolutionError = _mod.ResolutionError

TRUSTED_RESOLVER_ID = "QUALITY_PACK_TRUSTED_REF_RESOLVER_V1"
PASS = "PASS"
BLOCKED = "BLOCKED"


def block(code: str, **extra: Any) -> dict[str, Any]:
    return {"status": BLOCKED, "code": code, **extra}


def is_trusted_resolver(resolver: Any) -> bool:
    return type(resolver) is TrustedRefResolver


def _content_current(resolver: Any, observed: Mapping[str, Any]) -> bool:
    if observed.get("current") is True:
        return True
    try:
        head_ref = f"github://{observed['repo']}@{resolver.head}/{observed['path']}"
        head = resolver.resolve(head_ref)
    except Exception:
        return False
    return head.get("sha256") == observed.get("sha256")


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
    if require_current_content and not _content_current(resolver, observed):
        return block("BLOCK_PROVIDER_SOURCE_STALE", binding=label, ref=ref), None
    return {"status": PASS, "code": "PASS_TRUSTED_SOURCE_RESOLUTION", "binding": label}, observed


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
    if binding.get("resolver_id") != TRUSTED_RESOLVER_ID:
        return block("BLOCK_UNTRUSTED_RESOLVER_ID", binding=label), None, None
    ref = binding.get("ref")
    sha = binding.get("sha256") or binding.get("digest")
    if not isinstance(ref, str) or not ref:
        return block("BLOCK_EVIDENCE_REF_MISSING", binding=label), None, None
    if not isinstance(sha, str) or len(sha) != 64:
        return block("BLOCK_EVIDENCE_SHA256_INVALID", binding=label), None, None
    status, observed = resolve_source(
        resolver,
        ref,
        sha,
        label,
        require_current_content=require_current_content,
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
    return {"status": PASS, "code": "PASS_TRUSTED_JSON_EVIDENCE", "binding": label}, record, observed


def immutable_ref(resolver: Any, path: str, revision: str | None = None) -> str:
    if not is_trusted_resolver(resolver):
        raise TypeError("TrustedRefResolver required")
    return f"github://{resolver.repo}@{revision or resolver.head}/{path}"
