#!/usr/bin/env python3
"""Prepare in-memory candidate semantic requests without persisting private raster bytes.

Sandbox-only helper. It performs no network, database, merge, promotion, or production action.
The returned request objects may be passed by a separate local sandbox runner to the existing
profile runtime. CLI output is metadata-only and never includes image bytes/base64.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import uuid
from pathlib import Path
from typing import Any

SCHEMA = "LF_PROFILE_RUNTIME_SEMANTIC_CANDIDATE_FIXTURE_V1"
BUNDLE_SCHEMA = "LF_PROFILE_RUNTIME_SEMANTIC_CANDIDATE_BUNDLE_V1"
EXPECTED_PROFILES = {
    "PERFIL-UI-ARCHITECT",
    "PERFIL-PRODUCT-DIRECTOR-LF",
    "PERFIL-QUALITY-PACK",
}
FORBIDDEN_FIXTURE_KEYS = {
    "input_image_base64",
    "raw_output",
    "expected_output",
    "expected_answer",
    "supabase_password",
    "service_role",
    "secret",
}


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_fixture(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict) or payload.get("schema") != SCHEMA:
        raise ValueError("SEMANTIC_CANDIDATE_FIXTURE_SCHEMA_INVALID")
    artifact = payload.get("artifact")
    requests = payload.get("requests")
    if not isinstance(artifact, dict) or not isinstance(requests, list) or len(requests) != 3:
        raise ValueError("SEMANTIC_CANDIDATE_FIXTURE_SHAPE_INVALID")
    profiles = set()
    baseline_ids = set()
    for item in requests:
        if not isinstance(item, dict):
            raise ValueError("SEMANTIC_CANDIDATE_REQUEST_INVALID")
        if FORBIDDEN_FIXTURE_KEYS.intersection(item):
            raise ValueError("SEMANTIC_CANDIDATE_FIXTURE_CONTAINS_FORBIDDEN_DATA")
        required = {"baseline_request_id", "profile_code", "profile_slug", "profile_source_paths", "input_literal"}
        if not required.issubset(item):
            raise ValueError("SEMANTIC_CANDIDATE_REQUEST_FIELD_MISSING")
        if not isinstance(item["profile_source_paths"], list) or not item["profile_source_paths"]:
            raise ValueError("SEMANTIC_CANDIDATE_SOURCE_PATHS_INVALID")
        if not isinstance(item["input_literal"], str) or not item["input_literal"].strip():
            raise ValueError("SEMANTIC_CANDIDATE_INPUT_LITERAL_INVALID")
        profiles.add(item["profile_code"])
        baseline_ids.add(item["baseline_request_id"])
    if profiles != EXPECTED_PROFILES or len(baseline_ids) != 3:
        raise ValueError("SEMANTIC_CANDIDATE_PROFILE_SET_INVALID")
    return payload


def prepare_requests(fixture: dict[str, Any], image_path: Path) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    artifact = fixture["artifact"]
    image = image_path.read_bytes()
    expected_sha = artifact.get("sha256")
    expected_bytes = artifact.get("bytes")
    if _sha256(image) != expected_sha:
        raise ValueError("SEMANTIC_CANDIDATE_IMAGE_SHA256_MISMATCH")
    if len(image) != expected_bytes:
        raise ValueError("SEMANTIC_CANDIDATE_IMAGE_SIZE_MISMATCH")
    media_type = artifact.get("mime_type")
    if media_type != "image/png":
        raise ValueError("SEMANTIC_CANDIDATE_IMAGE_MEDIA_TYPE_INVALID")

    encoded = base64.b64encode(image).decode("ascii")
    requests: list[dict[str, Any]] = []
    manifest_requests: list[dict[str, Any]] = []
    for item in fixture["requests"]:
        request_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f"lf-profile-runtime-v3:{item['baseline_request_id']}:{expected_sha}"))
        request = {
            "request_id": request_id,
            "operation_code": "EJECUCION_PERFIL_LF",
            "profile_code": item["profile_code"],
            "profile_slug": item["profile_slug"],
            "profile_source_paths": item["profile_source_paths"],
            "input_literal": item["input_literal"],
            "input_image_base64": encoded,
            "input_image_media_type": media_type,
            "input_image_sha256": expected_sha,
        }
        requests.append(request)
        manifest_requests.append({
            "request_id": request_id,
            "baseline_request_id": item["baseline_request_id"],
            "profile_code": item["profile_code"],
            "profile_slug": item["profile_slug"],
            "profile_source_paths": item["profile_source_paths"],
            "input_literal_sha256": _sha256(item["input_literal"].encode("utf-8")),
            "input_literal_chars": len(item["input_literal"]),
        })

    manifest = {
        "schema": BUNDLE_SCHEMA,
        "status": "CANDIDATE_ONLY_NO_AUTHORITY",
        "artifact_sha256": expected_sha,
        "artifact_bytes": len(image),
        "private_raster_persisted": False,
        "database_access": False,
        "network_write": False,
        "request_count": len(requests),
        "requests": manifest_requests,
    }
    return requests, manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--manifest-out", type=Path)
    args = parser.parse_args()

    fixture = load_fixture(args.fixture)
    _requests, manifest = prepare_requests(fixture, args.image)
    rendered = json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.manifest_out:
        args.manifest_out.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
