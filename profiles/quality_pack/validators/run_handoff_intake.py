#!/usr/bin/env python3
"""Deterministic Quality Pack intake gate.

This runner proves only whether Quality Pack has enough explicit upstream context and
an observable created artifact to START its normal semantic review. It never emits
a Quality Pack PASS verdict and never evaluates LF safety, leakage, or semantic
quality.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
REQUIRED_CONTEXT_KEYS = [
    "upstream_worker",
    "upstream_output",
    "worker_contract_ref",
    "expected_output_format",
    "acceptance_criteria",
    "blocking_criteria",
    "case_context",
    "lf_governance_constraints",
    "declared_worker_score",
    "declared_worker_evidence",
]


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError("input must be a JSON object")
    return data


def has_developed_evidence(value: Any) -> bool:
    return isinstance(value, (list, dict)) and bool(value)


def result(
    intake_status: str,
    blocking_codes: list[str],
    evidence_map: list[str],
    next_gate: str,
) -> dict[str, Any]:
    return {
        "intake_status": intake_status,
        "validation_scope": "DETERMINISTIC_INTAKE_ONLY",
        "semantic_quality_review_status": "NOT_EXECUTED",
        "quality_pack_verdict": None,
        "blocking_codes": blocking_codes,
        "evidence_map": evidence_map,
        "next_gate": next_gate,
    }


def evaluate(envelope: dict[str, Any]) -> dict[str, Any]:
    missing = [key for key in REQUIRED_CONTEXT_KEYS if key not in envelope]
    if missing:
        return result(
            "RETURN_TO_ORCHESTRATOR",
            ["QUALITY_INTAKE_CONTEXT_INCOMPLETE"],
            ["Missing required intake keys: " + ", ".join(sorted(missing))],
            "ORCHESTRATOR_REPAIR_CONTEXT",
        )

    upstream = envelope.get("upstream_output")
    if not isinstance(upstream, dict):
        return result(
            "RETURN_TO_ORCHESTRATOR",
            ["QUALITY_INTAKE_UPSTREAM_OUTPUT_INVALID"],
            ["upstream_output is not a JSON object"],
            "ORCHESTRATOR_REPAIR_CONTEXT",
        )

    evidence = upstream.get("evidence_map")
    declared_evidence = envelope.get("declared_worker_evidence")
    if not has_developed_evidence(evidence) or not has_developed_evidence(declared_evidence):
        return result(
            "RETURN_TO_WORKER_FOR_SELF_REPAIR",
            ["UPSTREAM_EVIDENCE_NOT_DELIVERED"],
            ["Quality Pack intake requires explicit developed upstream evidence; claims without evidence are not intake-ready."],
            "SELF_REPAIR_THEN_RETRY_INTAKE",
        )

    status = str(upstream.get("status") or "")
    created_claim = upstream.get("deliverable_created") is True or status.endswith("_CREATED")
    if not created_claim:
        return result(
            "RETURN_TO_ORCHESTRATOR",
            ["QUALITY_INTAKE_NO_CREATED_DELIVERABLE_CLAIM"],
            ["This intake runner is scoped to handoffs that claim a created deliverable."],
            "ORCHESTRATOR_REPAIR_CONTEXT",
        )

    artifact_ref = upstream.get("deliverable_artifact_ref")
    artifact = envelope.get("deliverable_artifact")
    if not artifact_ref or not isinstance(artifact, dict):
        return result(
            "RETURN_TO_WORKER_FOR_SELF_REPAIR",
            ["CREATED_ARTIFACT_NOT_DELIVERED"],
            ["Producer claims a created deliverable but no exact artifact reference plus materialized artifact was delivered."],
            "SELF_REPAIR_THEN_RETRY_INTAKE",
        )

    expected_id = upstream.get("profile_pack_id") or upstream.get("learning_candidate_id") or upstream.get("artifact_id")
    actual_id = artifact.get("profile_pack_id") or artifact.get("learning_candidate_id") or artifact.get("artifact_id")
    if expected_id and actual_id != expected_id:
        return result(
            "RETURN_TO_WORKER_FOR_SELF_REPAIR",
            ["CREATED_ARTIFACT_ID_MISMATCH"],
            [f"Delivered artifact id {actual_id!r} does not match producer claim {expected_id!r}."],
            "SELF_REPAIR_THEN_RETRY_INTAKE",
        )

    claimed_files = upstream.get("files_created") or []
    files = artifact.get("files")
    if claimed_files:
        if not isinstance(files, dict):
            return result(
                "RETURN_TO_WORKER_FOR_SELF_REPAIR",
                ["CREATED_ARTIFACT_COMPONENTS_NOT_DELIVERED"],
                ["Producer claims component files but delivered artifact has no files map."],
                "SELF_REPAIR_THEN_RETRY_INTAKE",
            )
        missing_components = [
            rel for rel in claimed_files
            if not isinstance(files.get(rel), str) or not files.get(rel, "").strip()
        ]
        if missing_components:
            return result(
                "RETURN_TO_WORKER_FOR_SELF_REPAIR",
                ["CREATED_ARTIFACT_COMPONENT_NOT_DELIVERED"],
                ["Missing or empty claimed components: " + ", ".join(missing_components)],
                "SELF_REPAIR_THEN_RETRY_INTAKE",
            )

    return result(
        "QUALITY_INTAKE_READY",
        [],
        [
            "Required Quality Pack intake context is explicit.",
            "Created deliverable has an exact reference and materialized artifact.",
            "Artifact identity matches the producer claim.",
            "Every claimed component is delivered with developed content.",
        ],
        "SEMANTIC_QUALITY_REVIEW",
    )


def self_test() -> int:
    matrix_path = ROOT / "evals" / "handoff_intake_matrix.json"
    matrix = load_json(matrix_path)
    failures: list[str] = []
    observations: list[dict[str, Any]] = []
    for case in matrix.get("cases", []):
        fixture = ROOT / case["fixture"]
        actual = evaluate(load_json(fixture))
        expected_status = case["expected_intake_status"]
        ok = actual["intake_status"] == expected_status
        expected_code = case.get("expected_blocking_code")
        if expected_code and expected_code not in actual["blocking_codes"]:
            ok = False
        expected_gate = case.get("expected_next_gate")
        if expected_gate and actual["next_gate"] != expected_gate:
            ok = False
        observations.append({
            "case_id": case["id"],
            "expected": expected_status,
            "actual": actual["intake_status"],
            "blocking_codes": actual["blocking_codes"],
            "next_gate": actual["next_gate"],
            "pass": ok,
        })
        if not ok:
            failures.append(case["id"])

    output = {
        "status": "PASS" if not failures else "FAIL",
        "validation_scope": "DETERMINISTIC_INTAKE_ONLY",
        "semantic_quality_review_status": "NOT_EXECUTED",
        "cases": observations,
        "failed_cases": failures,
        "non_claims": [
            "No PASS_TO_COMPOSER",
            "No PASS_WITH_RESTRICTIONS",
            "No semantic LF safety judgment",
            "No general Quality Pack behavioral pass",
        ],
    }
    print(json.dumps(output, ensure_ascii=False, indent=2))
    return 0 if not failures else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.fixture is None:
        parser.error("fixture is required unless --self-test is used")
    print(json.dumps(evaluate(load_json(args.fixture)), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
