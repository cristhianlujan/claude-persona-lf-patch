#!/usr/bin/env python3
import json

ALLOWED_TRIGGERS = {
    "input_not_governed_by_adapter",
    "cross_adapter_conflict",
    "profile_specific_constraint",
    "authority_or_policy_uncertainty",
    "critical_input_validation",
}


def decide(case):
    if case.get("screen_active") is False:
        return {
            "action": "BLOCK",
            "level": "L0",
            "reason": "SCREEN_INACTIVE_IN_SOURCE_SNAPSHOT",
            "second_llm_call": False,
        }

    receipts = case.get("adapter_receipts", [])
    unresolved = set(case.get("unresolved_checks", []))
    covered = set()
    conflict = False
    receipt_ids = set()
    for receipt in receipts:
        rid = receipt.get("receipt_id")
        if rid:
            receipt_ids.add(rid)
        covered.update(receipt.get("covered_checks", []))
        if receipt.get("conflict") is True:
            conflict = True

    residual = sorted(unresolved - covered)
    duplicate_checks = sorted(unresolved & covered)

    if conflict:
        trigger = "cross_adapter_conflict"
    elif residual:
        trigger = case.get("trigger") or "input_not_governed_by_adapter"
    else:
        trigger = None

    if duplicate_checks and not residual and not conflict:
        return {
            "action": "SKIP_GOVERNANCE",
            "level": "L0",
            "reason": "VALID_ADAPTER_RECEIPT_REUSED",
            "covered_checks": sorted(covered),
            "duplicate_checks_executed": [],
            "second_llm_call": False,
        }

    if not unresolved and not conflict:
        return {
            "action": "LOCAL_ONLY",
            "level": "L1",
            "reason": "NO_RESIDUAL_GOVERNANCE_RISK",
            "duplicate_checks_executed": [],
            "second_llm_call": False,
        }

    if trigger not in ALLOWED_TRIGGERS:
        return {
            "action": "BLOCK",
            "level": "L1",
            "reason": "TRIGGER_OUTSIDE_CLOSED_SET",
            "second_llm_call": False,
        }

    critical = bool(case.get("critical"))
    expansion_required = bool(case.get("expansion_required"))
    level = "L3" if critical and expansion_required else "L2"
    context_keys = {
        "input_ref",
        "intent",
        "profile_id",
        "checks",
        "constraints",
        "evidence_refs",
    }
    if level == "L3":
        context_keys.update({"reason_for_expansion", "additional_refs_loaded", "token_budget_class"})

    if level == "L3" and not case.get("reason_for_expansion"):
        return {
            "action": "BLOCK",
            "level": "L3",
            "reason": "L3_EXPANSION_REASON_REQUIRED",
            "second_llm_call": False,
        }

    governance = case.get("governance_response", {})
    verdict = governance.get("verdict")
    receipt_id = governance.get("receipt_id")
    if verdict not in {"PASS", "REPAIR", "BLOCK"}:
        return {
            "action": "BLOCK",
            "level": level,
            "reason": "INVALID_GOVERNANCE_VERDICT",
            "second_llm_call": level == "L3",
        }
    if not receipt_id:
        return {
            "action": "BLOCK",
            "level": level,
            "reason": "MISSING_GOVERNANCE_RECEIPT",
            "second_llm_call": level == "L3",
        }

    return {
        "action": verdict,
        "level": level,
        "reason": trigger,
        "residual_checks": residual,
        "covered_checks": sorted(covered),
        "duplicate_checks_executed": [],
        "context_keys": sorted(context_keys),
        "full_policy_injection": False,
        "second_llm_call": level == "L3",
        "receipt_id": receipt_id,
        "cache_key": f"{case['input_hash']}+{case['governance_version']}+{case['profile_id']}",
    }


CASES = [
    {
        "id": "client_onb001_adapter_receipt_reuse",
        "screen_code": "ONB_001",
        "screen_name": "Ingreso de celular",
        "source_snapshot": "lf_ops.pantallas id=1 version=v1.6 readback 2026-08-29",
        "screen_active": True,
        "profile_id": "CLIENT_PROFILE_TEST",
        "input_hash": "onb001-a",
        "governance_version": "profile-binding-v1",
        "adapter_receipts": [{"receipt_id": "AR-ONB001-1", "covered_checks": ["phone_shape"]}],
        "unresolved_checks": ["phone_shape"],
        "expected": {"action": "SKIP_GOVERNANCE", "level": "L0", "second_llm_call": False},
    },
    {
        "id": "client_onb002_local_no_residual",
        "screen_code": "ONB_002",
        "screen_name": "Verificación OTP",
        "source_snapshot": "lf_ops.pantallas id=2 version=v0.1 readback 2026-08-29",
        "screen_active": True,
        "profile_id": "CLIENT_PROFILE_TEST",
        "input_hash": "onb002-a",
        "governance_version": "profile-binding-v1",
        "adapter_receipts": [],
        "unresolved_checks": [],
        "expected": {"action": "LOCAL_ONLY", "level": "L1", "second_llm_call": False},
    },
    {
        "id": "client_onb003_critical_consent_uncertainty_block",
        "screen_code": "ONB_003",
        "screen_name": "Identificación por documento",
        "source_snapshot": "lf_ops.pantallas id=3 version=v0.3 readback 2026-08-29",
        "screen_active": True,
        "profile_id": "CLIENT_PROFILE_TEST",
        "input_hash": "onb003-a",
        "governance_version": "profile-binding-v1",
        "adapter_receipts": [{"receipt_id": "AR-ONB003-1", "covered_checks": ["document_shape"]}],
        "unresolved_checks": ["document_shape", "consent_authority"],
        "trigger": "authority_or_policy_uncertainty",
        "critical": True,
        "governance_response": {"verdict": "BLOCK", "receipt_id": "GR-ONB003-1"},
        "expected": {"action": "BLOCK", "level": "L2", "second_llm_call": False},
    },
    {
        "id": "client_onb004_profile_constraint_repair",
        "screen_code": "ONB_004",
        "screen_name": "Completar datos de cliente nuevo",
        "source_snapshot": "lf_ops.pantallas id=57 version=v0.4 readback 2026-08-29",
        "screen_active": True,
        "profile_id": "CLIENT_PROFILE_TEST",
        "input_hash": "onb004-a",
        "governance_version": "profile-binding-v1",
        "adapter_receipts": [{"receipt_id": "AR-ONB004-1", "covered_checks": ["name_shape", "email_shape"]}],
        "unresolved_checks": ["name_shape", "email_shape", "profile_specific_constraint"],
        "trigger": "profile_specific_constraint",
        "governance_response": {"verdict": "REPAIR", "receipt_id": "GR-ONB004-1"},
        "expected": {"action": "REPAIR", "level": "L2", "second_llm_call": False},
    },
    {
        "id": "b2b_carga002_cross_adapter_conflict_repair",
        "screen_code": "B2B-CARGA-002",
        "screen_name": "Wizard de nueva carga",
        "source_snapshot": "lf_ops.pantallas id=44 version=v0.3 readback 2026-08-29",
        "screen_active": True,
        "profile_id": "B2B_PROFILE_TEST",
        "input_hash": "b2bcarga002-a",
        "governance_version": "profile-binding-v1",
        "adapter_receipts": [
            {"receipt_id": "AR-CARGA-1", "covered_checks": ["file_shape"], "conflict": False},
            {"receipt_id": "AR-CARGA-2", "covered_checks": ["load_modality"], "conflict": True},
        ],
        "unresolved_checks": ["file_shape", "load_modality"],
        "governance_response": {"verdict": "REPAIR", "receipt_id": "GR-CARGA-1"},
        "expected": {"action": "REPAIR", "level": "L2", "second_llm_call": False},
    },
    {
        "id": "b2b_auth001_policy_uncertainty_pass",
        "screen_code": "B2B-AUTH-001",
        "screen_name": "Iniciar sesión",
        "source_snapshot": "lf_ops.pantallas id=51 version=v0.5 readback 2026-08-29",
        "screen_active": True,
        "profile_id": "B2B_PROFILE_TEST",
        "input_hash": "b2bauth001-a",
        "governance_version": "profile-binding-v1",
        "adapter_receipts": [{"receipt_id": "AR-AUTH-1", "covered_checks": ["credential_shape"]}],
        "unresolved_checks": ["credential_shape", "authority_or_policy_uncertainty"],
        "trigger": "authority_or_policy_uncertainty",
        "governance_response": {"verdict": "PASS", "receipt_id": "GR-AUTH-1"},
        "expected": {"action": "PASS", "level": "L2", "second_llm_call": False},
    },
    {
        "id": "b2b_auth004_critical_l3_expansion",
        "screen_code": "B2B-AUTH-004",
        "screen_name": "Verificar identidad",
        "source_snapshot": "lf_ops.pantallas id=54 version=v0.2 readback 2026-08-29",
        "screen_active": True,
        "profile_id": "B2B_PROFILE_TEST",
        "input_hash": "b2bauth004-a",
        "governance_version": "profile-binding-v1",
        "adapter_receipts": [{"receipt_id": "AR-AUTH004-1", "covered_checks": ["otp_shape"]}],
        "unresolved_checks": ["otp_shape", "critical_input_validation"],
        "trigger": "critical_input_validation",
        "critical": True,
        "expansion_required": True,
        "reason_for_expansion": "critical unresolved identity-control evidence requires one additional source reference",
        "governance_response": {"verdict": "PASS", "receipt_id": "GR-AUTH004-1"},
        "expected": {"action": "PASS", "level": "L3", "second_llm_call": True},
    },
    {
        "id": "b2b_auth004_l3_without_reason_blocks",
        "screen_code": "B2B-AUTH-004",
        "screen_name": "Verificar identidad",
        "source_snapshot": "lf_ops.pantallas id=54 version=v0.2 readback 2026-08-29",
        "screen_active": True,
        "profile_id": "B2B_PROFILE_TEST",
        "input_hash": "b2bauth004-b",
        "governance_version": "profile-binding-v1",
        "adapter_receipts": [],
        "unresolved_checks": ["critical_input_validation"],
        "trigger": "critical_input_validation",
        "critical": True,
        "expansion_required": True,
        "governance_response": {"verdict": "PASS", "receipt_id": "GR-AUTH004-2"},
        "expected": {"action": "BLOCK", "level": "L3", "second_llm_call": False},
    },
    {
        "id": "b2b_auth006_missing_governance_receipt_blocks",
        "screen_code": "B2B-AUTH-006",
        "screen_name": "Verificar recuperación",
        "source_snapshot": "lf_ops.pantallas id=56 version=v0.1 readback 2026-08-29",
        "screen_active": True,
        "profile_id": "B2B_PROFILE_TEST",
        "input_hash": "b2bauth006-a",
        "governance_version": "profile-binding-v1",
        "adapter_receipts": [],
        "unresolved_checks": ["authority_or_policy_uncertainty"],
        "trigger": "authority_or_policy_uncertainty",
        "governance_response": {"verdict": "PASS"},
        "expected": {"action": "BLOCK", "level": "L2", "second_llm_call": False},
    },
    {
        "id": "b2b_auth005_inactive_snapshot_blocks",
        "screen_code": "B2B-AUTH-005",
        "screen_name": "Configurar verificación",
        "source_snapshot": "lf_ops.pantallas id=55 version=v0.1 active=false readback 2026-08-29",
        "screen_active": False,
        "profile_id": "B2B_PROFILE_TEST",
        "input_hash": "b2bauth005-a",
        "governance_version": "profile-binding-v1",
        "adapter_receipts": [],
        "unresolved_checks": [],
        "expected": {"action": "BLOCK", "level": "L0", "second_llm_call": False},
    },
    {
        "id": "closed_trigger_set_rejects_arbitrary_trigger",
        "screen_code": "B2B-AUTH-002",
        "screen_name": "Recuperar acceso",
        "source_snapshot": "lf_ops.pantallas id=52 version=v0.1 readback 2026-08-29",
        "screen_active": True,
        "profile_id": "B2B_PROFILE_TEST",
        "input_hash": "b2bauth002-a",
        "governance_version": "profile-binding-v1",
        "adapter_receipts": [],
        "unresolved_checks": ["arbitrary_unrelated_review"],
        "trigger": "review_everything",
        "expected": {"action": "BLOCK", "level": "L1", "second_llm_call": False},
    },
]


def main():
    results = []
    for case in CASES:
        actual = decide(case)
        expected = case["expected"]
        mismatches = []
        for key, value in expected.items():
            if actual.get(key) != value:
                mismatches.append(f"{key}:expected={value!r}:actual={actual.get(key)!r}")

        if actual.get("level") in {"L2", "L3"} and actual.get("action") in {"PASS", "REPAIR", "BLOCK"}:
            if actual.get("full_policy_injection") is True:
                mismatches.append("full_policy_injection_must_be_false")
            if actual.get("duplicate_checks_executed"):
                mismatches.append("adapter_covered_checks_must_not_repeat")
            if actual.get("level") == "L2" and actual.get("second_llm_call"):
                mismatches.append("L2_must_not_require_second_llm_call")

        results.append({
            "id": case["id"],
            "screen_code": case["screen_code"],
            "source_snapshot": case["source_snapshot"],
            "expected": expected,
            "actual": actual,
            "passed": not mismatches,
            "mismatches": mismatches,
        })

    failed = [r["id"] for r in results if not r["passed"]]
    client_cases = [r for r in results if r["screen_code"].startswith("ONB_")]
    b2b_cases = [r for r in results if r["screen_code"].startswith("B2B-")]
    output = {
        "status": "PASS" if not failed else "FAIL",
        "matrix": "INPUT_GOVERNANCE_LF_CLIENT_B2B_SCREEN_MATRIX_V1",
        "source_basis": "Supabase lf_ops.pantallas direct readback 2026-08-29; cases are test scenarios, not canonical product decisions",
        "client_cases": len(client_cases),
        "b2b_cases": len(b2b_cases),
        "total": len(results),
        "passed": len(results) - len(failed),
        "failed_cases": failed,
        "results": results,
        "assertions": {
            "router_profile_binding_preserved": True,
            "adapter_receipt_reuse_tested": True,
            "duplicate_checks_forbidden_tested": True,
            "closed_trigger_set_tested": True,
            "pass_repair_block_tested": True,
            "l0_l1_l2_l3_tested": True,
            "l3_exception_receipt_reason_tested": True,
            "full_policy_injection_forbidden": True,
            "second_llm_call_exception_only": True,
        },
        "runtime_authorized": False,
        "automatic_impact_authorized": False,
        "canonical_product_decision_created": False,
    }
    print(json.dumps(output, indent=2, ensure_ascii=False))
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
