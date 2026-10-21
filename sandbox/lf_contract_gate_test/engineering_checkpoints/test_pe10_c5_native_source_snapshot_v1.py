#!/usr/bin/env python3
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[3]
SQL=ROOT/"supabase/migrations/20261021162500_lf_pe10_c5_native_source_snapshot_v1.sql"
src=SQL.read_text(encoding="utf-8")

required=[
 "PROFILE_NATIVE_CHAT_MATERIAL_REVIEW",
 "PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C5",
 "dfbd274fe909bd005027e27f383a8c1e679882bf45e72b9b2429b986900d6cde",
 "c07498fa3cd34ad65e296d63536c743a251d90834f4698ecd7ed318db293692a",
 "944eaa1ce1d7c10ccd80f2f6e1153d657a523ecba875284a8b51a20d4644795a",
 "673888f8a720aa9167bc558036f0a26d540ae1e3fb664d11621e4a93df709fe3",
 "2187c2671d0c05e7db0939b987c0a64f032e8d837603470b1330be61cf4e21f7",
 "663683bf2c101651291a89caa5ea56cea8649f32",
 "8b3b41c20d77125cf4767c79487bc13d752c01a1",
 "9b36d39555950a3baeb22d1bc57f80d489250d07",
 "b0864fbdd96a6874bcf7c7f048a2280abb94df69",
 "LF_GITHUB_SOURCE_READBACK_V1",
 "GITHUB_API_READBACK_PLUS_OFFLINE_HASH",
 "fn_lf_evidence_ledger_anchor_v1",
 "SOURCE_SNAPSHOT",
 "CAUSAL_ANALYSIS",
 "SELF_REFINE",
 "LF-PE10-C5-NATIVE-SOURCE-SNAPSHOT-MISSING-20261021-001",
]
for item in required:
    assert item in src, f"MISSING:{item}"

# This migration may establish source provenance only.
for forbidden in [
 "INDEPENDENT_REVIEW_RECEIPT",
 "PROFILE_EVOLUTION_CUTOVER_ADMITTED','OPERACION','ACTUALIZACION_PERFIL_LF",
 "status='DONE'",
 "production_activation',true",
 "cutover_admitted',true",
 "acceptance_declared',true",
 "UPDATE public.lf_operation_registry",
 "UPDATE public.lf_policy_versions",
]:
    assert forbidden not in src, f"FORBIDDEN:{forbidden}"

assert re.search(r"checkpoint_code=v_checkpoint\) <> 'PENDING'",src)
assert "'checkpoint_pass',false" in src
assert "'independent_review_executed',false" in src
assert "'cutover_admitted',false" in src
assert "'production_activated',false" in src
assert "provider_readback_verified',true" in src
assert "digest_recomputed',true" in src
assert "capture_blob_identical_authoring_to_readback',true" in src
assert "profile_blob_identical_authoring_to_readback',true" in src

# Exactly one anchor call and one durable EKB code keep this change bounded.
assert src.count("fn_lf_evidence_ledger_anchor_v1(")==1
assert src.count("LF-PE10-C5-NATIVE-SOURCE-SNAPSHOT-MISSING-20261021-001")>=2

print("PASS PE10_C5_NATIVE_SOURCE_SNAPSHOT_SOURCE_GUARDS")
