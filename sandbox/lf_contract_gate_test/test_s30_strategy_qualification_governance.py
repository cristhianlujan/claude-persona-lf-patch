from pathlib import Path

repo_root = Path(__file__).resolve().parents[2]
migration = repo_root / "supabase/migrations/20260915041000_s30_strategy_qualification_governance_v1.sql"
assert migration.exists(), "FAIL_S30_STRATEGY_QUALIFICATION_GOVERNANCE_SOURCE_MISSING"
sql = migration.read_text(encoding="utf-8")

# Semantic revision is explicit and excludes operational/handoff state by construction.
assert "CREATE OR REPLACE FUNCTION public.lf_strategy_revision_sha256_from_json_v1" in sql
for material_key in (
    "'content_payload'", "'sections'", "'decisions'", "'backlog'", "'risks'", "'tags'",
    "'semantic_metadata'", "'policy_set_fingerprint'", "'test_assurance'",
):
    assert material_key in sql, f"FAIL_S30_SEMANTIC_REVISION_KEY_MISSING:{material_key}"
assert "S30_STRATEGY_QUALIFICATION_OPERATIONAL_COUPLING_REMAINS" in sql
assert "S30_STRATEGY_QUALIFICATION_SEMANTIC_CHANGE_NOT_DETECTED" in sql

# Qualification caller provenance must fail closed before the first receipt write.
receipt_pos = sql.index("INSERT INTO public.lf_qualification_receipts")
for guard in (
    "LF_STRATEGY_QUALIFICATION_EXECUTION_MISSING",
    "LF_STRATEGY_QUALIFICATION_EXECUTION_NOT_ACTIVE",
    "LF_STRATEGY_QUALIFICATION_EXECUTION_NOT_STRATEGY",
    "LF_STRATEGY_QUALIFICATION_EXECUTION_TARGET_MISMATCH",
    "LF_STRATEGY_QUALIFICATION_EXECUTION_OPERATION_SCOPE_INVALID",
    "LF_STRATEGY_QUALIFICATION_EXECUTION_ROUTE_NOT_ACTIVE",
    "LF_STRATEGY_QUALIFICATION_EXECUTION_POLICY_SNAPSHOT_MISSING",
    "LF_STRATEGY_QUALIFICATION_EXECUTION_POLICY_SNAPSHOT_STALE",
    "LF_STRATEGY_QUALIFICATION_INIT_STEP_NOT_CLEAN",
    "LF_STRATEGY_QUALIFICATION_ROUTER_STEP_NOT_CLEAN",
):
    assert guard in sql, f"FAIL_S30_QUALIFICATION_GUARD_MISSING:{guard}"
    assert sql.index(guard) < receipt_pos, f"FAIL_S30_QUALIFICATION_GUARD_AFTER_WRITE:{guard}"

assert "x.manifest->'operation_policy_snapshots'" in sql
assert "public.v_lf_operation_policy_snapshot" in sql
assert "es.step_id='init_execution'" in sql
assert "es.step_id='router'" in sql
assert "es.status='PASS_CLEAN'" in sql
assert "{route_decision,operation_code}" in sql

# Independent Review must reuse the canonical surface; this migration creates no parallel operation/router.
assert "REVISION_INDEPENDIENTE_ESTRATEGIA_LF" in sql
assert "lf_independent_strategy_review_begin_v1" in sql
assert "lf_independent_strategy_review_finalize_v1" in sql
assert "INSERT INTO public.lf_operation_registry" not in sql
assert "INSERT INTO public.lf_router_action_registry" not in sql

# Scope ceiling: no Strategy snapshot mutation, no runtime/production activation, no R15 continuation.
assert "UPDATE public.lf_strategy_snapshots" not in sql
assert "INSERT INTO public.lf_strategy_snapshots" not in sql
assert "'r15_requalification_performed',false" in sql
assert "'runtime_activation',false" in sql
assert "'production_activation',false" in sql

print("S30_STRATEGY_QUALIFICATION_GOVERNANCE_SELFTEST=PASS")
