#!/usr/bin/env python3
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
SQL=ROOT/"supabase/migrations/20261021163500_lf_pe10_c5_independent_review_init_v1.sql"
src=SQL.read_text(encoding="utf-8")

required=[
 "PROFILE_NATIVE_CHAT_MATERIAL_REVIEW",
 "PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C5",
 "731e93ae-a230-4172-ad6c-f2fb4c9024d6",
 "dfbd274fe909bd005027e27f383a8c1e679882bf45e72b9b2429b986900d6cde",
 "8b3b41c20d77125cf4767c79487bc13d752c01a1",
 "f87727d3c81f3cda4c4ea8f5c23d7715bcda9e0f08bd1b2eae1188117b946d35",
 "NATIVE_MATERIAL_CONTENT_ONLY",
 "lf_independent_review_begin_v3",
 "lf_record_independent_review_step_v3",
 "'route_bind'",
 "'target_currentness'",
 "'review_next_step','semantic_review'",
 "'semantic_independent_verdict','NOT_STARTED'",
 "'positive_negative_controls_required',true",
]
for item in required:
    assert item in src, f"MISSING:{item}"

# Exactly two deterministic recorder calls; no semantic/judge/final recorder call.
assert src.count("public.lf_record_independent_review_step_v3(")==2
for forbidden_call in [
    "v_review_id,
    'semantic_review'",
    "v_review_id,
    'judge_record'",
    "v_review_id,
    'reviewer_readback'",
    "v_review_id,
    'report_output'",
]:
    assert forbidden_call not in src, f"FORBIDDEN_CALL:{forbidden_call}"

# No checkpoint closure, cutover admission, policy activation or final review receipt mint.
for forbidden in [
    "status='DONE'",
    "UPDATE public.lf_operation_registry",
    "UPDATE public.lf_policy_versions",
    "'checkpoint_pass',true",
    "'cutover_admitted',true",
    "'production_activation',true",
    "'acceptance_declared',true",
]:
    assert forbidden not in src, f"FORBIDDEN:{forbidden}"

assert "'checkpoint_pass',false" in src
assert "'cutover_admitted',false" in src
assert "'production_activation',false" in src
assert "'semantic_review_executed',false" in src
assert "'independent_review_receipt_created',false" in src
assert "receipt_kind IN ('REVIEW_DECISION','INDEPENDENT_REVIEW_RECEIPT')" in src
print("PASS PE10_C5_INDEPENDENT_REVIEW_INIT_BOUNDARY")
