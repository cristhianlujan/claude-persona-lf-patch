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

    image_path, image_sha = _materialize_image(request, work_dir)
    adapter = GitHubHostedLlamaCppAdapter(work_dir=work_dir, image_path=image_path, image_sha256=image_sha)
    verifier = GitHubHostedLlamaCppVerifier(expected_image_path=image_path, expected_image_sha256=image_sha)
    package = execute_profile_runtime(
        execution_id=f"EJECUCION_PERFIL_LF:{request['request_id']}",
        profile_code=request["profile_code"], profile_slug=profile_slug,
        profile_sources=sources, input_literal=request["input_literal"],
        adapter=adapter, attestation_verifier=verifier, allow_test_doubles=False,
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
