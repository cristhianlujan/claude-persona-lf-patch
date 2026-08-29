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
from profile_runtime_runner import RuntimeExecutionBlocked
from profile_runtime_runner import execute_profile_runtime
from validate_profile_execution import sha256_text

RESULT_SCHEMA = "LF_PROFILE_RUNTIME_QUEUE_RESULT_V1"
MAX_ADAPTER_CAPSULE_CHARS = 2000
LF_ADAPTER_REGISTRY = {
    "ADAPTER-LF-SHELL-PROFILE-20260827": {
        "adapter_code": "ADAPTER_LF_SHELL_PROFILE",
        "package_dir": "adapters/lf_shell_profile_adapter",
    },
    "ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827": {
        "adapter_code": "ADAPTER_PROJECT_BRAND_MOCKUP_RENDER_LF",
        "package_dir": "adapters/project_brand_mockup_render_lf",
    },
    "ADAPTER-MARKETPLACE-LF-UX-20260531": {
        "adapter_code": "ADAPTER_MARKETPLACE_LF_UX",
        "package_dir": "adapters/marketplace_lf_ux",
    },
    "ADAPTER-MARKETPLACE-LF-CX-TRUST-20260531": {
        "adapter_code": "ADAPTER_MARKETPLACE_LF_CX_TRUST",
        "package_dir": "adapters/marketplace_lf_cx_trust",
    },
}


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


def _manifest_version(path: Path) -> str:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise RuntimeExecutionBlocked("QUEUE_ADAPTER_MANIFEST_READ_FAILED", str(path)) from exc
    for line in text.splitlines():
        if line.strip().startswith("version:"):
            version = line.split(":", 1)[1].strip().strip("'\"")
            if version:
                return version
    raise RuntimeExecutionBlocked("QUEUE_ADAPTER_MANIFEST_VERSION_MISSING", str(path))


def _resolve_lf_adapters(
    request: dict[str, Any], *, repo_root: Path,
) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    bindings = request.get("governed_adapter_bindings", [])
    resolution = request.get("lf_adapter_resolution", [])
    if not isinstance(bindings, list):
        raise RuntimeExecutionBlocked("QUEUE_GOVERNED_ADAPTER_BINDINGS_NOT_ARRAY")
    if not isinstance(resolution, list):
        raise RuntimeExecutionBlocked("QUEUE_ADAPTER_RESOLUTION_NOT_ARRAY")

    expected: dict[str, dict[str, Any]] = {}
    for item in bindings:
        if not isinstance(item, dict):
            raise RuntimeExecutionBlocked("QUEUE_GOVERNED_ADAPTER_BINDING_INVALID")
        asset_code = item.get("adapter_asset_code")
        version = item.get("adapter_version")
        target = item.get("target_asset_code")
        if not all(_nonempty(x) for x in (asset_code, version, target)):
            raise RuntimeExecutionBlocked("QUEUE_GOVERNED_ADAPTER_BINDING_INVALID")
        if target != request.get("profile_code"):
            raise RuntimeExecutionBlocked("QUEUE_GOVERNED_ADAPTER_TARGET_MISMATCH", str(asset_code))
        if asset_code in expected:
            raise RuntimeExecutionBlocked("QUEUE_GOVERNED_ADAPTER_BINDING_DUPLICATE", str(asset_code))
        if asset_code not in LF_ADAPTER_REGISTRY:
            raise RuntimeExecutionBlocked("QUEUE_GOVERNED_ADAPTER_UNSUPPORTED", str(asset_code))
        expected[asset_code] = item

    decisions: dict[str, dict[str, str]] = {}
    for item in resolution:
        if not isinstance(item, dict) or set(item) != {"adapter_asset_code", "decision", "activation_reason"}:
            raise RuntimeExecutionBlocked("QUEUE_ADAPTER_RESOLUTION_ITEM_INVALID")
        asset_code = item.get("adapter_asset_code")
        decision = item.get("decision")
        reason = item.get("activation_reason")
        if not all(_nonempty(x) for x in (asset_code, decision, reason)):
            raise RuntimeExecutionBlocked("QUEUE_ADAPTER_RESOLUTION_VALUE_MISSING")
        if decision not in {"APPLY", "SKIP"}:
            raise RuntimeExecutionBlocked("QUEUE_ADAPTER_RESOLUTION_DECISION_INVALID", str(decision))
        if asset_code in decisions:
            raise RuntimeExecutionBlocked("QUEUE_ADAPTER_RESOLUTION_DUPLICATE", str(asset_code))
        decisions[asset_code] = {
            "adapter_asset_code": asset_code,
            "decision": decision,
            "activation_reason": reason,
        }

    if set(decisions) != set(expected):
        missing = sorted(set(expected) - set(decisions))
        extra = sorted(set(decisions) - set(expected))
        detail = f"missing={missing};extra={extra}"
        raise RuntimeExecutionBlocked("QUEUE_ADAPTER_RESOLUTION_BINDING_MISMATCH", detail)

    contexts: list[dict[str, str]] = []
    normalized_resolution = [decisions[key] for key in sorted(decisions)]
    for asset_code in sorted(expected):
        decision = decisions[asset_code]
        if decision["decision"] == "SKIP":
            continue
        registry = LF_ADAPTER_REGISTRY[asset_code]
        package_dir = repo_root / registry["package_dir"]
        authoring_path = package_dir / "ADAPTER.md"
        manifest_path = package_dir / "manifest.yaml"
        capsule_path = package_dir / "runtime_capsule.md"
        for path in (authoring_path, manifest_path, capsule_path):
            if not path.is_file():
                raise RuntimeExecutionBlocked("QUEUE_ADAPTER_PACKAGE_FILE_MISSING", str(path.relative_to(repo_root)))
        package_version = _manifest_version(manifest_path)
        if expected[asset_code]["adapter_version"] != package_version:
            raise RuntimeExecutionBlocked(
                "QUEUE_ADAPTER_VERSION_MISMATCH",
                f"{asset_code}:registry={expected[asset_code]['adapter_version']} package={package_version}",
            )
        try:
            authoring_content = authoring_path.read_text(encoding="utf-8")
            capsule_content = capsule_path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            raise RuntimeExecutionBlocked("QUEUE_ADAPTER_PACKAGE_READ_FAILED", asset_code) from exc
        if not authoring_content or not capsule_content:
            raise RuntimeExecutionBlocked("QUEUE_ADAPTER_PACKAGE_EMPTY", asset_code)
        if len(capsule_content) > MAX_ADAPTER_CAPSULE_CHARS:
            raise RuntimeExecutionBlocked("QUEUE_ADAPTER_CAPSULE_BUDGET_EXCEEDED", asset_code)
        contexts.append({
            "adapter_asset_code": asset_code,
            "adapter_code": registry["adapter_code"],
            "adapter_version": package_version,
            "activation_reason": decision["activation_reason"],
            "source_ref": str(authoring_path.relative_to(repo_root).as_posix()),
            "source_sha256": sha256_text(authoring_content),
            "capsule_ref": str(capsule_path.relative_to(repo_root).as_posix()),
            "capsule_sha256": sha256_text(capsule_content),
            "capsule_content": capsule_content,
        })
    return normalized_resolution, contexts


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

    adapter_resolution, adapter_contexts = _resolve_lf_adapters(request, repo_root=repo_root)
    image_path, image_sha = _materialize_image(request, work_dir)
    adapter = GitHubHostedLlamaCppAdapter(work_dir=work_dir, image_path=image_path, image_sha256=image_sha)
    verifier = GitHubHostedLlamaCppVerifier(expected_image_path=image_path, expected_image_sha256=image_sha)
    package = execute_profile_runtime(
        execution_id=f"EJECUCION_PERFIL_LF:{request['request_id']}",
        profile_code=request["profile_code"], profile_slug=profile_slug,
        profile_sources=sources, input_literal=request["input_literal"],
        adapter=adapter, attestation_verifier=verifier, allow_test_doubles=False,
        obligation_manifest=request.get("obligation_manifest"),
        lf_adapter_resolution=adapter_resolution,
        lf_adapter_contexts=adapter_contexts,
    )
    package["queue_request_id"] = request["request_id"]
    package["input_image_sha256"] = image_sha
    return {
        "schema": RESULT_SCHEMA, "status": "SUCCEEDED", "request_id": request["request_id"],
        "runtime_provider": package["receipt"]["runtime_attestation"]["provider"],
        "runtime_model_id": package["receipt"]["runtime_attestation"]["model_id"],
        "raw_output": package["raw_output"], "receipt": package["receipt"],
        "runtime_attestation_verification": package["runtime_attestation_verification"],
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
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
                           encoding="utf-8")
    print(f"LF_PROFILE_RUNTIME_STATUS={result['status']}")
    if result.get("error_code"):
        print(f"LF_PROFILE_RUNTIME_ERROR={result['error_code']}", file=sys.stderr)
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
