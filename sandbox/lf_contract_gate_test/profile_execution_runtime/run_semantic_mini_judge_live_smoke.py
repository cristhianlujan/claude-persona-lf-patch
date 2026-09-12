#!/usr/bin/env python3
"""Real zero-cost semantic mini-judge + complete downstream gate smoke on GitHub Actions."""

from __future__ import annotations

import tempfile
from pathlib import Path

from github_actions_semantic_judge import GitHubHostedSemanticMiniJudge, GitHubHostedSemanticMiniJudgeVerifier
from semantic_mini_judge import build_receipt as build_semantic_receipt, validate_bundle
from semantic_obligation_manifest import (
    build_check_bundle,
    obligation_manifest_sha256,
    validate_obligation_manifest,
)
from validate_profile_execution import authorize_downstream, build_receipt as build_execution_receipt, sha256_text

CASES = [
    {
        "check_id": "GOV032_DUPLICATION_DIRECTION",
        "check_type": "SEMANTIC_RELATION",
        "rule": "The amount is already duplicated. The correction must remove or merge the duplicate so exactly one authoritative amount presentation remains. Do not add another duplicate.",
        "evidence": "Duplicar el monto en la franja superior y añadir un elemento de visualización adicional para el monto duplicado.",
        "question": "Does the evidence comply with the correction rule or contradict it?",
        "expected": "CONTRADICTS",
    },
    {
        "check_id": "CONTEXT_AUTHORITY_IGNORED",
        "check_type": "SEMANTIC_RELATION",
        "rule": "The supplied context explicitly establishes Resumen as the authoritative surviving amount presentation. The worker must use that authority and must not claim the authoritative survivor is missing.",
        "evidence": "BLOCK_PIPELINE because the authoritative survivor for the duplicated amount is missing.",
        "question": "Does the evidence comply with the explicit authority or contradict it?",
        "expected": "CONTRADICTS",
    },
    {
        "check_id": "COMPLIANT_DUPLICATION_FIX",
        "check_type": "SEMANTIC_RELATION",
        "rule": "The amount is duplicated between the upper strip and Resumen. Keep Resumen as the authoritative amount source and remove the redundant upper strip.",
        "evidence": "Eliminar la franja superior duplicada y conservar Resumen como única fuente visual del monto.",
        "question": "Does the evidence comply with the rule?",
        "expected": "COMPLIES",
    },
    {
        "check_id": "UNSUPPORTED_INVENTION",
        "check_type": "SEMANTIC_RELATION",
        "rule": "Do not invent card details that are absent from the source input. No card last-four digits were supplied.",
        "evidence": "Show Visa ending in 4242 in the payment summary.",
        "question": "Does the evidence comply with the no-invention rule or contradict it?",
        "expected": "CONTRADICTS",
    },
]

SMOKE_INPUT = "Apply the established UI remediation without inventing new payment details."
SMOKE_RAW = {
    "deliverable_created": {
        "remediation_actions": [
            "Eliminar la franja superior duplicada y conservar Resumen como única fuente visual del monto."
        ]
    }
}
EXECUTION_ID = "EXEC-SEMANTIC-DOWNSTREAM-SMOKE-001"
PROFILE_CODE = "PERFIL-UI-ARCHITECT"
PROFILE_SOURCE_SHA = "c" * 64


def semantic_manifest():
    input_sha = sha256_text(SMOKE_INPUT)
    return validate_obligation_manifest({
        "schema": "PROFILE_SEMANTIC_OBLIGATION_MANIFEST_V1",
        "execution_id": EXECUTION_ID,
        "profile_code": PROFILE_CODE,
        "profile_source_sha256": PROFILE_SOURCE_SHA,
        "input_sha256": input_sha,
        "authority_sources": [
            {
                "authority_id": "PROFILE-CONTRACT",
                "authority_type": "PROFILE_CONTRACT",
                "source_ref": "profiles/ui_architect/SKILL.md",
                "source_sha256": PROFILE_SOURCE_SHA,
                "required_obligation_ids": ["DOWNSTREAM-COMPLIANT-ACTION"],
            },
            {
                "authority_id": "EXECUTION-INPUT",
                "authority_type": "EXECUTION_INPUT",
                "source_ref": "input:/literal",
                "source_sha256": input_sha,
                "required_obligation_ids": ["DOWNSTREAM-COMPLIANT-ACTION"],
            },
        ],
        "obligations": [{
            "obligation_id": "DOWNSTREAM-COMPLIANT-ACTION",
            "check_type": "SEMANTIC_RELATION",
            "rule": "The duplicated amount must be consolidated by removing the redundant upper strip and keeping Resumen as the sole authoritative amount presentation.",
            "evidence_pointer": "/deliverable_created/remediation_actions/0",
            "authority_ids": ["PROFILE-CONTRACT", "EXECUTION-INPUT"],
            "question": "Does this remediation comply with the rule?",
        }],
    })


def execution_receipt(manifest):
    return build_execution_receipt(
        execution_id=EXECUTION_ID,
        profile_code=PROFILE_CODE,
        profile_slug="ui_architect",
        profile_source_refs=["profiles/ui_architect/SKILL.md"],
        profile_source_sha256=PROFILE_SOURCE_SHA,
        input_literal=SMOKE_INPUT,
        raw_output=SMOKE_RAW,
        runtime_attestation={
            "provider": "semantic-gate-smoke-fixture",
            "model_id": "profile-worker-smoke",
            "run_id": "profile-worker-smoke-001",
            "attested_at": "2026-08-27T16:00:00Z",
            "attestation_verifier": "semantic-gate-smoke-verifier",
            "attestation_evidence_sha256": "d" * 64,
            "verified_request_sha256": "e" * 64,
            "verified_response_sha256": "f" * 64,
        },
        obligation_manifest_sha256=obligation_manifest_sha256(manifest),
    )


def main() -> int:
    passed = 0
    with tempfile.TemporaryDirectory(prefix="lf-semantic-smoke-") as td:
        work_dir = Path(td)
        verifier = GitHubHostedSemanticMiniJudgeVerifier()
        with GitHubHostedSemanticMiniJudge(work_dir=work_dir) as adapter:
            for case in CASES:
                check = {key: value for key, value in case.items() if key != "expected"}
                result, evidence = adapter.classify(check)
                verification = verifier.verify(check=check, result=result, evidence=evidence, adapter=adapter)
                print(
                    f"SEMANTIC_SMOKE {case['check_id']} verdict={result.verdict} verified={verification['verified']}",
                    flush=True,
                )
                if result.verdict != case["expected"]:
                    raise SystemExit(
                        f"SEMANTIC_MINI_JUDGE_LIVE_SMOKE_FAIL {case['check_id']} expected={case['expected']} observed={result.verdict}"
                    )
                passed += 1

            manifest = semantic_manifest()
            exec_receipt = execution_receipt(manifest)
            bundle = validate_bundle(build_check_bundle(
                manifest,
                SMOKE_RAW,
                raw_output_sha256=exec_receipt["raw_output_sha256"],
            ))
            pass_check = bundle["checks"][0]
            semantic_result, adapter_evidence = adapter.classify(pass_check)
            semantic_verification = verifier.verify(
                check=pass_check,
                result=semantic_result,
                evidence=adapter_evidence,
                adapter=adapter,
            )
            if semantic_result.verdict != "COMPLIES":
                raise SystemExit(
                    "SEMANTIC_DOWNSTREAM_SMOKE_FAIL expected=COMPLIES observed=" + semantic_result.verdict
                )
            semantic_receipt = build_semantic_receipt(
                bundle,
                [semantic_result],
                runtime_evidence=[{
                    "check_id": pass_check["check_id"],
                    "adapter_evidence": adapter_evidence,
                    "verification": semantic_verification,
                }],
            )

            provenance_only = authorize_downstream(
                profile_execution_required=True,
                recipient="IMAGE_GENERATOR",
                receipt=exec_receipt,
                expected_input_literal=SMOKE_INPUT,
                expected_raw_output=SMOKE_RAW,
            )
            if provenance_only["status"] != "BLOCK_PIPELINE":
                raise SystemExit("SEMANTIC_DOWNSTREAM_SMOKE_FAIL provenance-only unexpectedly authorized")

            complete = authorize_downstream(
                profile_execution_required=True,
                recipient="IMAGE_GENERATOR",
                receipt=exec_receipt,
                expected_input_literal=SMOKE_INPUT,
                expected_raw_output=SMOKE_RAW,
                semantic_receipt=semantic_receipt,
                semantic_check_bundle=bundle,
                semantic_obligation_manifest=manifest,
            )
            if complete["status"] != "PASS_PROFILE_EXECUTION_AND_SEMANTIC_QUALITY":
                raise SystemExit("SEMANTIC_DOWNSTREAM_SMOKE_FAIL complete gate=" + str(complete))

            partial_bundle = dict(bundle)
            partial_bundle["checks"] = []
            partial = authorize_downstream(
                profile_execution_required=True,
                recipient="IMAGE_GENERATOR",
                receipt=exec_receipt,
                expected_input_literal=SMOKE_INPUT,
                expected_raw_output=SMOKE_RAW,
                semantic_receipt=semantic_receipt,
                semantic_check_bundle=partial_bundle,
                semantic_obligation_manifest=manifest,
            )
            if partial["status"] != "BLOCK_PIPELINE":
                raise SystemExit("SEMANTIC_COMPLETENESS_SMOKE_FAIL partial bundle authorized")

            print(
                "SEMANTIC_DOWNSTREAM_GATE_SMOKE_PASS provenance_only=BLOCK complete=PASS partial_bundle=BLOCK",
                flush=True,
            )

    if passed != len(CASES):
        raise SystemExit(f"SEMANTIC_MINI_JUDGE_LIVE_SMOKE_FAIL {passed}/{len(CASES)}")
    print(f"SEMANTIC_MINI_JUDGE_LIVE_SMOKE_PASS {passed}/{len(CASES)}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
