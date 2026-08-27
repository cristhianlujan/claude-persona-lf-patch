#!/usr/bin/env python3
"""Real zero-cost semantic mini-judge + downstream gate smoke on GitHub Actions."""

from __future__ import annotations

import tempfile
from pathlib import Path

from github_actions_semantic_judge import (
    GitHubHostedSemanticMiniJudge,
    GitHubHostedSemanticMiniJudgeVerifier,
)
from semantic_mini_judge import build_receipt as build_semantic_receipt, validate_bundle
from validate_profile_execution import (
    authorize_downstream,
    build_receipt as build_execution_receipt,
)

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


def execution_receipt():
    return build_execution_receipt(
        execution_id="EXEC-SEMANTIC-DOWNSTREAM-SMOKE-001",
        profile_code="PERFIL-UI-ARCHITECT",
        profile_slug="ui_architect",
        profile_source_refs=["profiles/ui_architect/SKILL.md"],
        profile_source_sha256="c" * 64,
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
                    f"SEMANTIC_SMOKE {case['check_id']} verdict={result.verdict} "
                    f"verified={verification['verified']}",
                    flush=True,
                )
                if result.verdict != case["expected"]:
                    raise SystemExit(
                        f"SEMANTIC_MINI_JUDGE_LIVE_SMOKE_FAIL {case['check_id']} "
                        f"expected={case['expected']} observed={result.verdict}"
                    )
                passed += 1

            exec_receipt = execution_receipt()
            pass_check = {
                "check_id": "DOWNSTREAM_COMPLIANT_ACTION",
                "check_type": "SEMANTIC_RELATION",
                "rule": "The duplicated amount must be consolidated by removing the redundant upper strip and keeping Resumen as the sole authoritative amount presentation.",
                "evidence": SMOKE_RAW["deliverable_created"]["remediation_actions"][0],
                "question": "Does this remediation comply with the rule?",
                "source_refs": ["raw:/deliverable_created/remediation_actions/0"],
            }
            bundle = validate_bundle({
                "schema": "PROFILE_SEMANTIC_CHECK_BUNDLE_V1",
                "execution_id": exec_receipt["execution_id"],
                "profile_code": exec_receipt["profile_code"],
                "input_sha256": exec_receipt["input_sha256"],
                "raw_output_sha256": exec_receipt["raw_output_sha256"],
                "checks": [pass_check],
            })
            semantic_result, adapter_evidence = adapter.classify(pass_check)
            semantic_verification = verifier.verify(
                check=pass_check,
                result=semantic_result,
                evidence=adapter_evidence,
                adapter=adapter,
            )
            if semantic_result.verdict != "COMPLIES":
                raise SystemExit(
                    "SEMANTIC_DOWNSTREAM_SMOKE_FAIL expected=COMPLIES "
                    f"observed={semantic_result.verdict}"
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
                raise SystemExit(
                    "SEMANTIC_DOWNSTREAM_SMOKE_FAIL provenance-only unexpectedly authorized"
                )
            if "PROFILE_SEMANTIC_JUDGE_RECEIPT_MISSING" not in provenance_only["blocking_codes"]:
                raise SystemExit(
                    "SEMANTIC_DOWNSTREAM_SMOKE_FAIL missing semantic-receipt blocker"
                )

            combined = authorize_downstream(
                profile_execution_required=True,
                recipient="IMAGE_GENERATOR",
                receipt=exec_receipt,
                expected_input_literal=SMOKE_INPUT,
                expected_raw_output=SMOKE_RAW,
                semantic_receipt=semantic_receipt,
                semantic_check_bundle=bundle,
            )
            if combined["status"] != "PASS_PROFILE_EXECUTION_AND_SEMANTIC_QUALITY":
                raise SystemExit(
                    "SEMANTIC_DOWNSTREAM_SMOKE_FAIL combined gate=" + str(combined)
                )
            print(
                "SEMANTIC_DOWNSTREAM_GATE_SMOKE_PASS provenance_only=BLOCK combined=PASS",
                flush=True,
            )

    if passed != len(CASES):
        raise SystemExit(f"SEMANTIC_MINI_JUDGE_LIVE_SMOKE_FAIL {passed}/{len(CASES)}")
    print(f"SEMANTIC_MINI_JUDGE_LIVE_SMOKE_PASS {passed}/{len(CASES)}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
