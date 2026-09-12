#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
from pathlib import Path

from prepare_semantic_candidate_bundle import (
    EXPECTED_PROFILES,
    SCHEMA,
    load_fixture,
    prepare_requests,
)

ROOT = Path(__file__).resolve().parent
FIXTURE = ROOT / "fixtures" / "semantic_candidate_b2b_carga_001.json"


def check(name: str, condition: bool) -> None:
    if not condition:
        raise AssertionError(name)
    print(f"PASS {name}")


fixture = load_fixture(FIXTURE)
check("fixture_schema", fixture["schema"] == SCHEMA)
check("artifact_exact_sha", fixture["artifact"]["sha256"] == "ee36e056038832e9efbd0a369ded22808614c0c9a3f8ea7766e22f739ecdb287")
check("artifact_exact_size", fixture["artifact"]["bytes"] == 142727)
check("private_raster_not_embedded", fixture["artifact"]["access_level"] == "PRIVATE" and fixture["artifact"]["raster_embedded"] is False)
check("three_exact_profiles", {item["profile_code"] for item in fixture["requests"]} == EXPECTED_PROFILES)
check("baseline_ids_unique", len({item["baseline_request_id"] for item in fixture["requests"]}) == 3)
check("no_expected_answer_leakage", all(not ({"raw_output", "expected_output", "expected_answer"} & set(item)) for item in fixture["requests"]))
check("no_private_image_bytes_in_fixture", all("input_image_base64" not in item for item in fixture["requests"]))
check("baseline_run_bound", fixture["source"]["baseline_github_run_id"] == 33596749435)
check("baseline_semantic_utility_bound", fixture["source"]["baseline_semantic_utility"] == "0/3_CONSUMABLE")

with tempfile.TemporaryDirectory() as tmp:
    tmp_path = Path(tmp)
    image = tmp_path / "fake.png"
    image.write_bytes(b"candidate-private-raster-test")
    test_fixture = json.loads(json.dumps(fixture))
    test_fixture["artifact"]["sha256"] = __import__("hashlib").sha256(image.read_bytes()).hexdigest()
    test_fixture["artifact"]["bytes"] = image.stat().st_size
    requests, manifest = prepare_requests(test_fixture, image)
    check("prepared_request_count", len(requests) == 3)
    check("prepared_request_image_bound", all(item["input_image_sha256"] == test_fixture["artifact"]["sha256"] for item in requests))
    check("manifest_no_private_raster_persistence", manifest["private_raster_persisted"] is False)
    check("manifest_no_database_access", manifest["database_access"] is False)
    check("manifest_no_network_write", manifest["network_write"] is False)
    check("manifest_metadata_only", "input_image_base64" not in json.dumps(manifest))

with tempfile.TemporaryDirectory() as tmp:
    bad_image = Path(tmp) / "wrong.png"
    bad_image.write_bytes(b"wrong")
    try:
        prepare_requests(fixture, bad_image)
    except ValueError as exc:
        check("wrong_sha_fails_closed", str(exc) == "SEMANTIC_CANDIDATE_IMAGE_SHA256_MISMATCH")
    else:
        raise AssertionError("wrong_sha_fails_closed")

print("PROFILE_RUNTIME_V3_SEMANTIC_CANDIDATE_PRIVATE_RASTER_HARNESS_PASS")
