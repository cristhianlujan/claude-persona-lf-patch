#!/usr/bin/env python3
from __future__ import annotations

import json
import os
from pathlib import Path

from story_independent_assurance_adapter_v1 import (
    consume_story_independent_review,
    prepare_story_independent_review,
)

HERE = Path(__file__).resolve().parent
CONTRACT = HERE / "fixtures" / "programming_consumer_v2_contract_snapshot_20261002.json"
PACKAGE = HERE / "fixtures" / "onb_004_implementation_package_v1_1.json"
SOURCE_PACK_SHA = "e24475612abd6b4011339621a9c8628005ef2f1c4111711d06ac03dd0b18a472"
CURRENT_INDEPENDENT_ASSURANCE = {
    "capability_code": "INDEPENDENT_ASSURANCE",
    "status": "ACTIVE",
    "version": "1.0.0",
    "manifest_sha256": "a6f5e2fe21ed305b6d47e8722035685b243cfc4e697ff397d1724e5d34f6c6e8",
}


def _adapter_checks(package: dict, source_head_sha: str) -> list[str]:
    errors: list[str] = []
    prepared = prepare_story_independent_review(
        package,
        source_head_sha=source_head_sha,
        capability_current=CURRENT_INDEPENDENT_ASSURANCE,
    )
    if prepared.get("result") != "REVIEW_REQUIRED":
        return [f"M43D_PREPARE_FAILED:{prepared}"]
    if prepared.get("subject_type") != "STORY_IMPLEMENTATION_PACKAGE":
        errors.append("M43D_SUBJECT_TYPE_INVALID")
    if prepared.get("capability_version") != "1.0.0":
        errors.append("M43D_CURRENT_CAPABILITY_NOT_RESOLVED")

    missing = consume_story_independent_review(
        package,
        source_head_sha=source_head_sha,
        capability_current=CURRENT_INDEPENDENT_ASSURANCE,
        ledger_receipt=None,
    )
    if missing.get("code") != "INDEPENDENT_REVIEW_RECEIPT_REQUIRED":
        errors.append("M43D_MISSING_RECEIPT_NOT_FAIL_CLOSED")

    receipt = {
        "receipt_id": "11111111-1111-4111-8111-111111111111",
        "receipt_sha256": "1" * 64,
        "capability_code": "INDEPENDENT_ASSURANCE",
        "receipt_kind": "AUDIT_VERDICT",
        "subject_type": prepared["subject_type"],
        "subject_ref": prepared["subject_ref"],
        "subject_sha256": prepared["subject_sha256"],
        "source_head_sha": source_head_sha,
        "authority_ref": prepared["authority_ref"],
        "verification_state": "VERIFIED",
        "receipt_payload": {
            "capability_version": CURRENT_INDEPENDENT_ASSURANCE["version"],
            "capability_manifest_sha256": CURRENT_INDEPENDENT_ASSURANCE["manifest_sha256"],
            "producer_identity": "STORY_CREATOR",
            "reviewer_identity": "INDEPENDENT_REVIEWER_A",
            "independent": True,
            "independence_measure": {"state": "INDEPENDENT"},
            "verdict": "PASS",
            "review_dimensions": {
                "implementation_actionability": "PASS",
                "source_fidelity": "PASS",
                "reuse_correctness": "PASS",
                "context_sufficiency": "PASS",
                "acceptance_executability": "PASS",
            },
            "evidence_refs": ["provider-bound://test-evidence"],
        },
    }
    consumed = consume_story_independent_review(
        package,
        source_head_sha=source_head_sha,
        capability_current=CURRENT_INDEPENDENT_ASSURANCE,
        ledger_receipt=receipt,
    )
    if consumed.get("result") != "PASS":
        errors.append(f"M43D_EXACT_RECEIPT_NOT_ACCEPTED:{consumed}")

    self_receipt = json.loads(json.dumps(receipt))
    self_receipt["receipt_payload"]["reviewer_identity"] = "STORY_CREATOR"
    rejected = consume_story_independent_review(
        package,
        source_head_sha=source_head_sha,
        capability_current=CURRENT_INDEPENDENT_ASSURANCE,
        ledger_receipt=self_receipt,
    )
    if rejected.get("code") != "INDEPENDENT_REVIEW_INDEPENDENCE_INVALID":
        errors.append("M43D_SELF_REVIEW_NOT_REJECTED")
    return errors


def main() -> int:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    package = json.loads(PACKAGE.read_text(encoding="utf-8"))

    errors: list[str] = []
    if contract.get("schema_version") != "PROGRAMMING_CONSUMER_V2_CONTRACT_SNAPSHOT_V1":
        errors.append("PROGRAMMING_CONSUMER_SNAPSHOT_SCHEMA_INVALID")
    if contract.get("source_function_sha256") != "5ad232b71125219b2f05abee93a4c07676d9365f797781a797200c87003b5731":
        errors.append("PROGRAMMING_CONSUMER_FUNCTION_SHA_DRIFT")
    if package.get("canonical_story_sha256") != SOURCE_PACK_SHA:
        errors.append("IMPLEMENTATION_PACKAGE_SOURCE_SHA_MISMATCH")

    reqs = contract.get("ab_requirements", [])
    legacy = {"EXPLICIT": 0, "GENERIC_CONTAINER": 0, "ABSENT": 0}
    implementation = {"EXPLICIT": 0, "GENERIC_CONTAINER": 0, "ABSENT": 0}
    for req in reqs:
        legacy[req["legacy_support"]] += 1
        implementation[req["implementation_support"]] += 1

    boundary = contract.get("benchmark_boundary", {})
    if boundary.get("model_runtime_executed") is not False:
        errors.append("MODEL_RUNTIME_MUST_REMAIN_OFF")
    if boundary.get("agent_quality_claim_allowed") is not False:
        errors.append("AGENT_QUALITY_CLAIM_MUST_REMAIN_DISABLED")
    if boundary.get("comparison_kind") != "FORMAT_CONTRACT_AB":
        errors.append("AB_COMPARISON_KIND_INVALID")

    if implementation["EXPLICIT"] < legacy["EXPLICIT"]:
        errors.append("IMPLEMENTATION_EXPLICIT_COVERAGE_REGRESSION")
    if implementation["ABSENT"] > legacy["ABSENT"]:
        errors.append("IMPLEMENTATION_ABSENCE_REGRESSION")

    source_head_sha = os.environ.get("GITHUB_SHA", "85bb733e73b9d21222f4e86b618ef1a099208051")
    errors.extend(_adapter_checks(package, source_head_sha))

    task_view = package["task_views"][0]
    selected = {key: package[key] for key in task_view["selected_sections"]}
    metrics = {
        "same_source_snapshot_sha256": SOURCE_PACK_SHA,
        "requirements_total": len(reqs),
        "legacy_explicit": legacy["EXPLICIT"],
        "legacy_generic_container": legacy["GENERIC_CONTAINER"],
        "legacy_absent": legacy["ABSENT"],
        "implementation_explicit": implementation["EXPLICIT"],
        "implementation_generic_container": implementation["GENERIC_CONTAINER"],
        "implementation_absent": implementation["ABSENT"],
        "implementation_full_package_bytes": len(json.dumps(package, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")),
        "implementation_task_view_bytes": len(json.dumps(selected, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")),
        "typed_blocker_count": len(package.get("blocked_if", [])),
        "source_ref_count": len(package.get("source_refs", [])),
        "model_runtime_executed": False,
        "comparison_kind": "FORMAT_CONTRACT_AB",
        "m43d_adapter_checked": True,
        "m43d_current_capability_version": CURRENT_INDEPENDENT_ASSURANCE["version"],
    }

    out = {
        "schema": "SC_M4_3_PROGRAMMING_CONSUMER_AB_V1",
        "result": "PASS" if not errors else "FAIL",
        "errors": errors,
        "metrics": metrics,
        "requirements": reqs,
        "limitation": boundary.get("reason"),
    }
    print(json.dumps(out, indent=2, sort_keys=True, ensure_ascii=False))
    return 0 if out["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
