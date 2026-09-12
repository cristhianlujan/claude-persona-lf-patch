#!/usr/bin/env python3
"""Pure contract helpers for LF profile runtime cache/batch/fail-closed execution."""
from __future__ import annotations

import hashlib
import json
import re
import uuid
from datetime import datetime, timezone
from typing import Any

MAX_BATCH_SIZE = 3
MAX_PARALLELISM = 2
VISUAL_PROFILE_CODES = {
    "PERFIL-UI-ARCHITECT",
    "PERFIL-PRODUCT-DIRECTOR-LF",
    "PERFIL-QUALITY-PACK",
}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def _nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def build_llama_cache_key(*, runner_os: str, runner_arch: str, toolchain_fingerprint: str,
                          llama_commit: str, llama_release: str,
                          namespace: str = "lf-profile-runtime-v2") -> str:
    fields = [namespace, "llama", runner_os, runner_arch, toolchain_fingerprint, llama_commit, llama_release]
    if not all(_nonempty(v) for v in fields):
        raise ValueError("LLAMA_CACHE_KEY_FIELD_MISSING")
    return "-".join(fields)


def build_model_cache_key(*, runner_os: str, runner_arch: str, model_id: str, revision: str,
                          model_sha256: str, mmproj_sha256: str,
                          namespace: str = "lf-profile-runtime-v2") -> str:
    fields = [namespace, "model", runner_os, runner_arch, model_id, revision, model_sha256, mmproj_sha256]
    if not all(_nonempty(v) for v in fields):
        raise ValueError("MODEL_CACHE_KEY_FIELD_MISSING")
    if not SHA256_RE.fullmatch(model_sha256) or not SHA256_RE.fullmatch(mmproj_sha256):
        raise ValueError("MODEL_CACHE_KEY_SHA_INVALID")
    # Avoid unsafe/path-like cache key fragments while still binding the exact model id.
    safe_model = re.sub(r"[^A-Za-z0-9_.-]+", "_", model_id)
    return "-".join([namespace, "model", runner_os, runner_arch, safe_model, revision, model_sha256, mmproj_sha256])


def validate_batch_request_ids(request_ids: list[str]) -> list[str]:
    if not isinstance(request_ids, list) or not 1 <= len(request_ids) <= MAX_BATCH_SIZE:
        raise ValueError("BATCH_SIZE_INVALID")
    normalized: list[str] = []
    seen: set[str] = set()
    for raw in request_ids:
        if not _nonempty(raw):
            raise ValueError("BATCH_REQUEST_ID_INVALID")
        try:
            value = str(uuid.UUID(raw.strip()))
        except (ValueError, AttributeError) as exc:
            raise ValueError("BATCH_REQUEST_ID_INVALID") from exc
        if value in seen:
            raise ValueError("BATCH_REQUEST_ID_DUPLICATE")
        seen.add(value)
        normalized.append(value)
    return normalized


def effective_parallelism(batch_size: int, requested: int) -> int:
    if not isinstance(batch_size, int) or batch_size < 1 or batch_size > MAX_BATCH_SIZE:
        raise ValueError("BATCH_SIZE_INVALID")
    if not isinstance(requested, int) or requested < 1:
        raise ValueError("PARALLELISM_INVALID")
    return min(batch_size, requested, MAX_PARALLELISM)


def image_binding_complete(request: dict[str, Any]) -> bool:
    values = (
        request.get("input_image_base64"),
        request.get("input_image_media_type"),
        request.get("input_image_sha256"),
    )
    return all(_nonempty(value) for value in values)


def requires_visual_bytes(*, profile_code: str, screen_code: str | None) -> bool:
    return profile_code in VISUAL_PROFILE_CODES and _nonempty(screen_code)


def artifact_verification_decision(*, profile_code: str, screen_code: str | None,
                                   image_sha256: str | None) -> str:
    if not requires_visual_bytes(profile_code=profile_code, screen_code=screen_code):
        return "NOT_APPLICABLE"
    if not _nonempty(image_sha256) or not SHA256_RE.fullmatch(str(image_sha256)):
        return "FAIL"
    return "PASS"


def governance_cache_key(*, screen_code: str | None, adapters: list[dict[str, Any]],
                         input_literal: str) -> str:
    adapter_ids = sorted(
        str((item.get("adapter_metadata") or {}).get("canonical_adapter_id") or item.get("adapter_code") or "")
        for item in adapters
    )
    payload = {
        "screen_code": screen_code or "",
        "adapter_ids": adapter_ids,
        "input_literal_sha256": _sha256_text(input_literal),
    }
    return _sha256_text(json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")))


def governance_receipt_reusable(result: dict[str, Any], *, screen_code: str | None) -> bool:
    if not isinstance(result, dict):
        return False
    if not result.get("applicable"):
        return result.get("status") == "NOT_REQUIRED" and result.get("continuation_allowed") is True
    receipt = result.get("governance_receipt")
    return (
        result.get("status") == "READY"
        and result.get("continuation_allowed") is True
        and isinstance(receipt, dict)
        and receipt.get("decision") == "PASS"
        and receipt.get("currentness") == "LIVE_CURRENT"
        and (screen_code is None or receipt.get("screen_code") == screen_code)
        and _nonempty(receipt.get("snapshot_hash"))
    )


def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def millis_between(start: datetime, end: datetime) -> int:
    return max(0, int(round((end - start).total_seconds() * 1000)))


def build_metrics(*, queued_at: str, started_at: str, runtime_ready_at: str,
                  inference_started_at: str | None, completed_at: str,
                  runtime_prepare_ms: int, model_download_ms: int, inference_ms: int,
                  cache_hit_runtime: bool, cache_hit_model: bool, batch_size: int,
                  parallelism: int, batch_total_ms: int) -> dict[str, Any]:
    def parse(value: str) -> datetime:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))

    queue_ms = millis_between(parse(queued_at), parse(started_at))
    return {
        "queued_at": queued_at,
        "started_at": started_at,
        "runtime_ready_at": runtime_ready_at,
        "inference_started_at": inference_started_at,
        "completed_at": completed_at,
        "queue_latency_ms": queue_ms,
        "runtime_prepare_ms": max(0, int(runtime_prepare_ms)),
        "model_download_ms": max(0, int(model_download_ms)),
        "inference_ms": max(0, int(inference_ms)),
        "total_ms": millis_between(parse(started_at), parse(completed_at)),
        "cache_hit_runtime": bool(cache_hit_runtime),
        "cache_hit_model": bool(cache_hit_model),
        "batch_size": batch_size,
        "parallelism": parallelism,
        "per_profile_inference_ms": max(0, int(inference_ms)),
        "batch_total_ms": max(0, int(batch_total_ms)),
    }
