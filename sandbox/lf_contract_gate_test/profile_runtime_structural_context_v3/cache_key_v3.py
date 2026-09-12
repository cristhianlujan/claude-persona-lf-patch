#!/usr/bin/env python3
"""Deterministic cache key for OCR/structural evidence only.

The cache may store source-bound OCR observations and structural resolver output.
It must never store or reuse profile_contract_valid, semantic_utility, authorization
or downstream gate decisions.
"""
from __future__ import annotations
import hashlib, json, re

_SHA256 = re.compile(r"^[0-9a-f]{64}$")

class CacheKeyError(ValueError):
    pass

def _sha(name: str, value: str) -> str:
    value=str(value).lower()
    if not _SHA256.fullmatch(value):
        raise CacheKeyError(f"{name}_must_be_sha256")
    return value

def make_cache_key(*, image_sha: str, context_sha: str, runtime_version: str, resolver_version: str) -> str:
    image_sha=_sha("image_sha",image_sha)
    context_sha=_sha("context_sha",context_sha)
    runtime_version=str(runtime_version).strip()
    resolver_version=str(resolver_version).strip()
    if not runtime_version:
        raise CacheKeyError("runtime_version_required")
    if not resolver_version:
        raise CacheKeyError("resolver_version_required")
    payload={
        "context_sha":context_sha,
        "image_sha":image_sha,
        "resolver_version":resolver_version,
        "runtime_version":runtime_version,
        "schema":"lf-profile-runtime-structural-cache-key/v1",
    }
    canonical=json.dumps(payload,sort_keys=True,separators=(",",":"),ensure_ascii=True).encode()
    return "p0v3:"+hashlib.sha256(canonical).hexdigest()

def cacheable_payload(payload: dict) -> bool:
    forbidden={"profile_contract_valid","semantic_utility","downstream_authorized","authorization","quality_verdict"}
    return isinstance(payload,dict) and not (forbidden & set(payload))
