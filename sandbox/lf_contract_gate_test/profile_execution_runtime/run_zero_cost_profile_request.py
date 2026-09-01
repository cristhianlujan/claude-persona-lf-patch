#!/usr/bin/env python3
"""Execute one private queued LF profile request on a zero-cost GitHub standard runner."""

from __future__ import annotations

import argparse
import base64
import binascii
import json
import sys
import tempfile
from pathlib import Path
from typing import Any

from github_actions_local_runtime import (
    GitHubHostedLlamaCppAdapter,
    GitHubHostedLlamaCppVerifier,
    MAX_IMAGE_BYTES,
    _sha256_bytes,
)
from profile_runtime_runner import RuntimeExecutionBlocked, execute_profile_runtime

RESULT_SCHEMA = "LF_PROFILE_RUNTIME_QUEUE_RESULT_V1"
MAX_LF_ADAPTERS = 4


def _load_request(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeExecutionBlocked("QUEUE_REQUEST_JSON_INVALID", type(exc).__name__) from exc
    if not isinstance(payload, dict):
        raise RuntimeExecutionBlocked("QUEUE_REQUEST_NOT_OBJECT")
    return payload


def _nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _safe_source_paths(profile_slug: str, value: Any) -> list[str]:
    if not isinstance(value, list) or not value:
        raise RuntimeExecutionBlocked("QUEUE_SOURCE_PATHS_MISSING")
    prefix = f"profiles/{profile_slug}/"
    result: list[str] = []
    seen: set[str] = set()
    for item in value:
        if not _nonempty(item):
            raise RuntimeExecutionBlocked("QUEUE_SOURCE_PATH_INVALID")
        normalized = str(Path(item).as_posix())
        if normalized.startswith("/") or ".." in Path(normalized).parts or not normalized.startswith(prefix):
            raise RuntimeExecutionBlocked("QUEUE_SOURCE_PATH_OUT_OF_SCOPE", normalized)
        if normalized in seen:
            raise RuntimeExecutionBlocked("QUEUE_SOURCE_PATH_DUPLICATE", normalized)
        seen.add(normalized)
        result.append(normalized)
    return sorted(result)


def _capsule_scalar(content: str, key: str) -> str | None:
    prefix = f"{key}:"
    for raw in content.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith(prefix):
            value = line[len(prefix):].strip().strip('"\'')
            return value or None
    return None


def _safe_adapter_sources(request: dict[str, Any], repo_root: Path) -> list[dict[str, Any]]:
    bindings = request.get("lf_adapter_bindings", [])
    if bindings is None:
        bindings = []
    if not isinstance(bindings, list):
        raise RuntimeExecutionBlocked("QUEUE_LF_ADAPTER_BINDINGS_NOT_ARRAY")
    if len(bindings) > MAX_LF_ADAPTERS:
        raise RuntimeExecutionBlocked("QUEUE_LF_ADAPTER_BINDING_COUNT_EXCEEDED", str(len(bindings)))
    sources: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in bindings:
        if not isinstance(item, dict):
            raise RuntimeExecutionBlocked("QUEUE_LF_ADAPTER_BINDING_INVALID")
        canonical_id = item.get("canonical_adapter_id")
        current_path = item.get("current_path")
        binding_ref = item.get("binding_ref")
        governance_required = item.get("input_governance_receipt_required")
        if not all(_nonempty(value) for value in (canonical_id, current_path, binding_ref)):
            raise RuntimeExecutionBlocked("QUEUE_LF_ADAPTER_BINDING_INCOMPLETE")
        if not isinstance(governance_required, bool):
            raise RuntimeExecutionBlocked("QUEUE_LF_ADAPTER_GOVERNANCE_FLAG_INVALID", str(canonical_id))
        if canonical_id in seen:
            raise RuntimeExecutionBlocked("BLOCK_DUPLICATE_ADAPTER_INVOCATION", canonical_id)
        seen.add(canonical_id)
        normalized_current = str(Path(current_path).as_posix())
        current_parts = Path(normalized_current).parts
        if normalized_current.startswith("/") or ".." in current_parts or not normalized_current.startswith("adapters/") or Path(normalized_current).name != "ADAPTER.md":
            raise RuntimeExecutionBlocked("QUEUE_LF_ADAPTER_CURRENT_PATH_INVALID", normalized_current)
        capsule_relative = str((Path(normalized_current).parent / "runtime" / "runtime_capsule.yaml").as_posix())
        capsule_path = repo_root / capsule_relative
        if not capsule_path.is_file():
            raise RuntimeExecutionBlocked("QUEUE_LF_ADAPTER_CAPSULE_MISSING", capsule_relative)
        try:
            content = capsule_path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            raise RuntimeExecutionBlocked("QUEUE_LF_ADAPTER_CAPSULE_READ_FAILED", capsule_relative) from exc
        if not content:
            raise RuntimeExecutionBlocked("QUEUE_LF_ADAPTER_CAPSULE_EMPTY", capsule_relative)
        declared_adapter = _capsule_scalar(content, "adapter")
        assurance_revision = _capsule_scalar(content, "assurance_revision")
        activation = _capsule_scalar(content, "activation")
        if declared_adapter != canonical_id:
            raise RuntimeExecutionBlocked("QUEUE_LF_ADAPTER_CAPSULE_ID_MISMATCH", canonical_id)
        if not _nonempty(assurance_revision):
            raise RuntimeExecutionBlocked("QUEUE_LF_ADAPTER_ASSURANCE_REVISION_MISSING", canonical_id)
        if activation != "ROUTER_BOUND_ONLY":
            raise RuntimeExecutionBlocked("BLOCK_UNBOUND_ADAPTER_INVOCATION", canonical_id)
        sources.append({
            "adapter_code": canonical_id,
            "assurance_revision": assurance_revision,
            "activation_source": "ROUTER",
            "binding_ref": binding_ref,
            "target_ref": request["profile_code"],
            "ref": capsule_relative,
            "content": content,
            "input_governance_receipt_required": governance_required,
            "input_governance_continuation_policy": item.get("input_governance_continuation_policy"),
            "input_governance_contract_resolution": item.get("input_governance_contract_resolution"),
            "input_governance_authority_contract": item.get("input_governance_authority_contract"),
        })
    return sorted(sources, key=lambda item: item["adapter_code"])


def _materialize_image(request: dict[str, Any], work_dir: Path) -> tuple[Path | None, str | None]:
    encoded = request.get("input_image_base64")
    media_type = request.get("input_image_media_type")
    claimed_sha = request.get("input_image_sha256")
    if encoded is None and media_type is None and claimed_sha is None:
        return None, None
    if not all(_nonempty(value) for value in (encoded, media_type, claimed_sha)):
        raise RuntimeExecutionBlocked("QUEUE_IMAGE_BINDING_INCOMPLETE")
    extension = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp"}.get(media_type)
    if extension is None:
        raise RuntimeExecutionBlocked("QUEUE_IMAGE_MEDIA_TYPE_INVALID", str(media_type))
    try:
        raw = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise RuntimeExecutionBlocked("QUEUE_IMAGE_BASE64_INVALID") from exc
    if not raw or len(raw) > MAX_IMAGE_BYTES:
        raise RuntimeExecutionBlocked("QUEUE_IMAGE_SIZE_INVALID", str(len(raw)))
    actual_sha = _sha256_bytes(raw)
    if actual_sha != claimed_sha:
        raise RuntimeExecutionBlocked("QUEUE_IMAGE_SHA256_MISMATCH")
    image_path = work_dir / f"input{extension}"
    image_path.write_bytes(raw)
    return image_path, actual_sha


def _materialize_runtime_output_schema(profile_slug: str, repo_root: Path, work_dir: Path) -> Path | None:
    if not profile_slug or "/" in profile_slug or "\\" in profile_slug or profile_slug in {".", ".."}:
        raise RuntimeExecutionBlocked("QUEUE_RUNTIME_SCHEMA_PROFILE_SLUG_INVALID")
    profiles_root = (repo_root / "profiles").resolve()
    profile_root = (profiles_root / profile_slug).resolve()
    try:
        profile_root.relative_to(profiles_root)
    except ValueError as exc:
        raise RuntimeExecutionBlocked("QUEUE_RUNTIME_SCHEMA_PATH_ESCAPE") from exc
    source = (profile_root / "schemas" / "runtime_output.schema.json").resolve()
    try:
        source.relative_to(profile_root / "schemas")
    except ValueError as exc:
        raise RuntimeExecutionBlocked("QUEUE_RUNTIME_SCHEMA_PATH_ESCAPE") from exc
    if not source.exists():
        return None
    if not source.is_file():
        raise RuntimeExecutionBlocked("QUEUE_RUNTIME_SCHEMA_INVALID")
    try:
        raw = source.read_bytes()
        payload = json.loads(raw.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeExecutionBlocked("QUEUE_RUNTIME_SCHEMA_INVALID_JSON") from exc
    if not isinstance(payload, dict):
        raise RuntimeExecutionBlocked("QUEUE_RUNTIME_SCHEMA_INVALID")
    destination = work_dir / "profiles" / profile_slug / "schemas" / "runtime_output.schema.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(raw)
    if _sha256_bytes(destination.read_bytes()) != _sha256_bytes(raw):
        raise RuntimeExecutionBlocked("QUEUE_RUNTIME_SCHEMA_COPY_MISMATCH")
    return destination


def execute_request(request: dict[str, Any], *, repo_root: Path, work_dir: Path) -> dict[str, Any]:
    required = ("request_id", "operation_code", "profile_code", "profile_slug", "input_literal")
    for key in required:
        if not _nonempty(request.get(key)):
            raise RuntimeExecutionBlocked("QUEUE_REQUEST_FIELD_MISSING", key)
    if request["operation_code"] != "EJECUCION_PERFIL_LF":
        raise RuntimeExecutionBlocked("QUEUE_OPERATION_CODE_INVALID")

    profile_slug = request["profile_slug"]
    source_paths = _safe_source_paths(profile_slug, request.get("profile_source_paths"))
    sources: list[dict[str, str]] = []
    for relative in source_paths:
        path = repo_root / relative
        if not path.is_file():
            raise RuntimeExecutionBlocked("QUEUE_PROFILE_SOURCE_MISSING", relative)
        try:
            content = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            raise RuntimeExecutionBlocked("QUEUE_PROFILE_SOURCE_READ_FAILED", relative) from exc
        if not content:
            raise RuntimeExecutionBlocked("QUEUE_PROFILE_SOURCE_EMPTY", relative)
        sources.append({"ref": relative, "content": content})

    lf_adapter_sources = _safe_adapter_sources(request, repo_root)
    image_path, image_sha = _materialize_image(request, work_dir)
    _materialize_runtime_output_schema(profile_slug, repo_root, work_dir)
    adapter = GitHubHostedLlamaCppAdapter(work_dir=work_dir, image_path=image_path, image_sha256=image_sha)
    verifier = GitHubHostedLlamaCppVerifier(expected_image_path=image_path, expected_image_sha256=image_sha)
    package = execute_profile_runtime(
        execution_id=f"EJECUCION_PERFIL_LF:{request['request_id']}",
        profile_code=request["profile_code"], profile_slug=profile_slug,
        profile_sources=sources, input_literal=request["input_literal"],
        adapter=adapter, attestation_verifier=verifier, allow_test_doubles=False,
        obligation_manifest=request.get("obligation_manifest"),
        lf_adapter_sources=lf_adapter_sources,
        input_governance=request.get("input_governance"),
    )
    package["queue_request_id"] = request["request_id"]
    package["input_image_sha256"] = image_sha
    package["router_receipt"] = request.get("router_receipt")
    package["router_trace"] = request.get("router_trace")
    package["input_governance_execution"] = request.get("input_governance_execution")
    return {
        "schema": RESULT_SCHEMA, "status": "SUCCEEDED", "request_id": request["request_id"],
        "runtime_provider": package["receipt"]["runtime_attestation"]["provider"],
        "runtime_model_id": package["receipt"]["runtime_attestation"]["model_id"],
        "raw_output": package["raw_output"], "receipt": package["receipt"],
        "runtime_attestation_verification": package["runtime_attestation_verification"],
        "router_receipt": package["router_receipt"],
        "router_trace": package["router_trace"],
        "input_governance_execution": package["input_governance_execution"],
        "package": package,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    work_dir = Path(tempfile.mkdtemp(prefix="lf-zero-cost-runtime-"))
    try:
        request = _load_request(args.request)
        result = execute_request(request, repo_root=args.repo_root.resolve(), work_dir=work_dir)
        rc = 0
    except RuntimeExecutionBlocked as exc:
        request_id = None
        try:
            request_id = _load_request(args.request).get("request_id")
        except RuntimeExecutionBlocked:
            pass
        result = {"schema": RESULT_SCHEMA, "status": "BLOCKED", "request_id": request_id,
                  "error_code": exc.code, "error_detail": exc.detail}
        rc = 2
    except Exception as exc:
        result = {"schema": RESULT_SCHEMA, "status": "FAILED", "request_id": None,
                  "error_code": "ZERO_COST_RUNTIME_UNEXPECTED_EXCEPTION",
                  "error_detail": type(exc).__name__}
        rc = 3
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"LF_PROFILE_RUNTIME_STATUS={result['status']}")
    if result.get("error_code"):
        print(f"LF_PROFILE_RUNTIME_ERROR={result['error_code']}", file=sys.stderr)
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
