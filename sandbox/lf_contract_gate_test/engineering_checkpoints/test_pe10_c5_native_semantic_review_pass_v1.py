#!/usr/bin/env python3
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
SQL=ROOT/"supabase/migrations/20261021165000_lf_pe10_c5_native_semantic_review_pass_v1.sql"
src=SQL.read_text(encoding="utf-8")

required=[
    "EXEC-PE10C5-INDEP-d288c5ee8b3335e4",
    "EXEC-PE10C5-SOURCE-LEDGER-e804d71999bbdcad",
    "731e93ae-a230-4172-ad6c-f2fb4c9024d6",
    "PROFILE_NATIVE_CHAT_MATERIAL_REVIEW",
    "NATIVE_MATERIAL_CONTENT_ONLY",
    "'semantic_review'",
    "'judge_record'",
    "'reviewer_readback'",
    "'report_output'",
    "'verdict','PASS'",
    "'review_type','INDEPENDENT_REVIEW'",
    "'review_context','INDEPENDENT_OPERATION_CONTEXT'",
    "'utility_dimensions_checked',jsonb_build_array('dependency','data','author')",
    "'state','INDEPENDENT'",
    "CAUSAL_ANALYSIS",
    "SELF_REFINE",
    "INDEPENDENT_REVIEW_RECEIPT",
    "REVIEW_DECISION",
    "INDEPENDENT_REVIEW_PASS_AWAITING_C5_ADMISSION",
    "LF-PE10-C5-SEMANTIC-REVIEW-WAS-PENDING-20261021-001",
]
for item in required:
    assert item in src, f"MISSING:{item}"

# Four remaining governed review steps, in order, no replay of deterministic first two.
positions=[src.index("'semantic_review'"),src.index("'judge_record'"),
           src.index("'reviewer_readback'"),src.index("'report_output'")]
assert positions == sorted(positions)
assert src.count("public.lf_record_independent_review_step_v3(") == 4

# This migration may complete only the reviewer; C5/cutover/production remain false.
for forbidden in [
    "status='DONE'",
    "PROFILE_EVOLUTION_CUTOVER_ADMITTED','OPERACION','ACTUALIZACION_PERFIL_LF",
    "'c5_pass',true",
    "'cutover_admitted',true",
    "'production_activated',true",
    "'production_activation',true",
    "'acceptance_declared',true",
    "UPDATE public.lf_operation_registry",
    "UPDATE public.lf_policy_versions",
]:
    assert forbidden not in src, f"FORBIDDEN:{forbidden}"

assert "'checkpoint_pass',false" in src
assert "'cutover_admitted',false" in src
assert "'production_activation',false" in src
assert "six_steps_passed',true" in src
assert "COMPLETED" in src
print("PASS PE10_C5_NATIVE_SEMANTIC_REVIEW_SOURCE_GUARDS")
