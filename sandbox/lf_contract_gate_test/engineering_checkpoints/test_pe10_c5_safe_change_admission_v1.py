#!/usr/bin/env python3
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
matches=list((ROOT/"supabase/migrations").glob("*_lf_pe10_c5_safe_change_admission_v1.sql"))
assert len(matches)==1, f"EXPECTED_ONE_SAFE_CHANGE_MIGRATION:{matches}"
src=matches[0].read_text(encoding="utf-8")

required=[
    "public.lf_safe_change_admission_classify_v1(v_request)",
    "'architecture-gate-test/v1'",
    "'all_confirmed',true",
    "'positive_control_count',2",
    "'negative_rejection_count',3",
    "'transactional_rollback_verified'",
    "21205",
    "ae10a7bb-0e99-4589-a7c7-38e61af506b0",
    "37db027e-ad58-4cbb-b4dc-01b7568f6ac2",
    "73c88455cf0501de2eb4e1226e622de9e3283c0d6b024e77cd725df60966af8a",
    "'classification' IS DISTINCT FROM 'AUTOMATIZABLE'",
    "'execution_permission' IS DISTINCT FROM 'DOWNSTREAM_EXECUTION_ELIGIBLE'",
    "'SAFE_CHANGE_ADMISSION'",
    "'EVIDENCE_LEDGER'",
    "'SAFE_CHANGE_ADMISSION_RESULT'",
    "'provider_readback_verified',true",
    "'digest_recomputed',true",
    "'SAFE_CHANGE_VERIFIED_AWAITING_ADMISSION_EVENT'",
    "LF-PE10-C5-SAFE-CHANGE-RECEIPT-MISSING-20261021-001",
]
for item in required:
    assert item in src, f"MISSING:{item}"

# Authority cannot be inferred from C2/C2B or reviewer text alone.
assert "private.fn_lf_typed_evidence_payload_valid_v3" in src
assert "fn_lf_orchestrator_dispatch_receipt_v1" in src
assert src.count("fn_lf_capability_bind_from_orchestrator_v1") >= 2
assert "receipt_payload->>'execution_permission'='DOWNSTREAM_EXECUTION_ELIGIBLE'" in src

# This lot produces only the safe-change receipt. It must not admit or activate.
for forbidden in [
    "status='DONE'",
    "INSERT INTO private.lf_event_type_contracts_v2",
    "VALUES('PROFILE_EVOLUTION_CUTOVER_ADMITTED'",
    "'c5_pass',true",
    "'cutover_admitted',true",
    "'production_activated',true",
    "'production_activation_authorized',true",
    "UPDATE public.lf_operation_registry",
    "UPDATE public.lf_policy_versions",
]:
    assert forbidden not in src, f"FORBIDDEN:{forbidden}"

assert "'c5_pass',false" in src
assert "'cutover_admitted',false" in src
assert "'production_activated',false" in src
assert "PE10_C5_SAFE_FALSE_ADMISSION" in src
print("PASS PE10_C5_SAFE_CHANGE_ADMISSION_SOURCE_GUARDS")
