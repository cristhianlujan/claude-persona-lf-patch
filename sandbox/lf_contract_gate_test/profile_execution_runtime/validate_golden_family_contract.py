#!/usr/bin/env python3
"""Validate the LF Profiles Golden Family contract without claiming runtime proof."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CONTRACT = Path(__file__).with_name("golden_family_ui_architect_v1.json")


def fail(code: str) -> None:
    raise SystemExit(code)


def require_file(rel: str) -> Path:
    path = ROOT / rel
    if not path.is_file():
        fail(f"GOLDEN_FAMILY_REQUIRED_FILE_MISSING:{rel}")
    return path


def main() -> int:
    if not CONTRACT.is_file():
        fail("GOLDEN_FAMILY_CONTRACT_MISSING")

    data = json.loads(CONTRACT.read_text(encoding="utf-8"))

    if data.get("schema") != "LF_PROFILE_GOLDEN_FAMILY_CONTRACT_V1":
        fail("GOLDEN_FAMILY_SCHEMA_INVALID")
    if data.get("family_id") != "GOLDEN-FAMILY-UI-ARCHITECT-MARKETPLACE-LF-V1":
        fail("GOLDEN_FAMILY_ID_INVALID")

    allowed_statuses = {
        "CONTRACT_DEFINED_E2E_NOT_PROVEN",
        "E2E_BLOCKED",
        "E2E_PROVEN",
    }
    if data.get("status") not in allowed_statuses:
        fail("GOLDEN_FAMILY_STATUS_INVALID")

    authority = data.get("authority", {})
    if authority.get("router_asset") != "ACT-0001":
        fail("GOLDEN_FAMILY_ROUTER_AUTHORITY_INVALID")
    if authority.get("operational_source") != "public.v_lf_fuente_operativa":
        fail("GOLDEN_FAMILY_OPERATIONAL_SOURCE_INVALID")
    if authority.get("creator_asset") != "ACT-0045":
        fail("GOLDEN_FAMILY_CREATOR_AUTHORITY_INVALID")

    profile = data.get("profile", {})
    if profile.get("code") != "PERFIL-UI-ARCHITECT":
        fail("GOLDEN_FAMILY_PROFILE_CODE_INVALID")
    require_file(f"{profile.get('path')}/SKILL.md")

    card = data.get("card", {})
    require_file(f"{card.get('path')}/CARD.md")
    require_file(f"{card.get('path')}/validators/validate_pack.py")
    if card.get("expected_registry") != "public.lf_cards":
        fail("GOLDEN_FAMILY_CARD_REGISTRY_INVALID")

    adapter = data.get("adapter", {})
    require_file(f"{adapter.get('path')}/ADAPTER.md")
    require_file(f"{adapter.get('path')}/manifest.yaml")
    if adapter.get("binding_authority") != "public.v_lf_router_adapter_bindings":
        fail("GOLDEN_FAMILY_ADAPTER_BINDING_AUTHORITY_INVALID")

    input_gov = data.get("input_governance", {})
    require_file(input_gov.get("binding_ref", ""))
    if input_gov.get("contract_code") != "INPUT_READINESS_CONTRACT":
        fail("GOLDEN_FAMILY_INPUT_GOVERNANCE_CONTRACT_INVALID")

    runtime = data.get("runtime", {})
    if runtime.get("primary_target") != "HETZNER":
        fail("GOLDEN_FAMILY_PRIMARY_RUNTIME_NOT_HETZNER")
    if runtime.get("backup_target") != "GITHUB_ACTIONS":
        fail("GOLDEN_FAMILY_BACKUP_RUNTIME_INVALID")
    if runtime.get("implicit_fallback_allowed") is not False:
        fail("GOLDEN_FAMILY_IMPLICIT_FALLBACK_MUST_BE_FALSE")
    if runtime.get("queue") != "private.lf_profile_runtime_queue_v1":
        fail("GOLDEN_FAMILY_RUNTIME_QUEUE_INVALID")
    require_file(runtime.get("transport_contract_validator", ""))

    success = data.get("success_rule", {})
    if success.get("primary_runtime_required_for_family_pass") is not True:
        fail("GOLDEN_FAMILY_PRIMARY_RUNTIME_GATE_MISSING")
    if success.get("github_actions_backup_can_satisfy_primary_gate") is not False:
        fail("GOLDEN_FAMILY_BACKUP_FALSE_PASS_ALLOWED")
    if success.get("isolated_component_pass_can_satisfy_family_gate") is not False:
        fail("GOLDEN_FAMILY_ISOLATED_PASS_FALSE_POSITIVE_ALLOWED")

    required_evidence = set(data.get("required_e2e_evidence", []))
    must_have = {
        "router_receipt",
        "input_governance_receipt_or_governed_na",
        "profile_source_ref_and_hash",
        "card_receipt_or_governed_na",
        "adapter_resolution_and_receipt_or_governed_na",
        "runtime_target_hetzner",
        "runtime_provider_and_model",
        "model_outcome",
        "deterministic_validator_results",
        "semantic_judge_results",
        "durable_persistence",
        "readback_same_request_id",
        "quality_and_depth_metrics",
        "stage_and_total_latency",
        "input_output_cache_tokens_when_available",
        "source_provenance_snapshot",
    }
    missing = sorted(must_have - required_evidence)
    if missing:
        fail("GOLDEN_FAMILY_E2E_EVIDENCE_MISSING:" + ",".join(missing))

    main_contract = require_file("skills/profile_creator/contracts/main_contract.md").read_text(
        encoding="utf-8"
    )
    for token in (
        "Full family E2E success contract",
        "Input Governance",
        "Cards are referenced",
        "Adapters are resolved",
        "runtime_target=HETZNER",
        "GITHUB_ACTIONS",
        "request_id",
    ):
        if token not in main_contract:
            fail(f"GOLDEN_FAMILY_TRANSVERSAL_CONTRACT_TOKEN_MISSING:{token}")

    # Contract integrity is not runtime proof. Preserve the evidence ladder.
    if data.get("status") != "E2E_PROVEN":
        if data.get("runtime_proof") != "NOT_EXECUTED":
            fail("GOLDEN_FAMILY_UNPROVEN_STATUS_HAS_RUNTIME_PROOF")
        result = "GOLDEN_FAMILY_CONTRACT_PASS runtime_proof=NOT_EXECUTED"
    else:
        if data.get("runtime_proof") == "NOT_EXECUTED":
            fail("GOLDEN_FAMILY_E2E_PROVEN_WITHOUT_RUNTIME_PROOF")
        result = f"GOLDEN_FAMILY_CONTRACT_PASS runtime_proof={data.get('runtime_proof')}"

    if data.get("automatic_impact_authorized") is not False:
        fail("GOLDEN_FAMILY_AUTOMATIC_IMPACT_MUST_REMAIN_BLOCKED")
    if data.get("promotion_authorized") is not False:
        fail("GOLDEN_FAMILY_PROMOTION_MUST_REMAIN_BLOCKED")

    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
