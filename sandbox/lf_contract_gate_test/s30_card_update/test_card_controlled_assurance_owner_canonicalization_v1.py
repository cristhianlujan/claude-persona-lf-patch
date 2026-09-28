from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20260927000500_lf_card_update_controlled_assurance_owner_canonicalization_v1.sql"

sql = MIGRATION.read_text(encoding="utf-8")

required = [
    "CARD_UPDATE_CONTROLLED_ASSURANCE",
    "CARD_OPERATIONS",
    "INDEPENDENT_HOLDOUT_OR_INDEPENDENT_REVIEW",
    "CARD_UPDATE_LEGACY_S36_EXECUTION_REQUIRES_RECONCILIATION",
    "legacy_s36_execution_policy",
    "BLOCK_REQUIRES_RECONCILIATION",
    "LF_CARD_CONTROLLED_ASSURANCE_LEGACY_ACTIVE_LEASE_BLOCKS_CUTOVER",
    "card_controlled_assurance_owner",
]
for fragment in required:
    assert fragment in sql, f"missing Card owner canonicalization fragment: {fragment}"

# Historical stale executions are evidence. This lot must not fabricate terminal state,
# delete them, or rewrite their stored manifests.
for forbidden in [
    "UPDATE public.lf_operation_execution SET",
    "UPDATE public.lf_operation_execution\nSET",
    "DELETE FROM public.lf_operation_execution",
    "TRUNCATE public.lf_operation_execution",
]:
    assert forbidden not in sql, f"legacy execution mutation forbidden: {forbidden}"

# The active Card contract is re-owned in place; no parallel operation/router/capability.
for forbidden in [
    "INSERT INTO public.lf_operation_registry",
    "INSERT INTO public.lf_router_action_registry",
    "INSERT INTO public.lf_activos",
    "CREATE TABLE",
]:
    assert forbidden not in sql, f"parallel owner surface forbidden: {forbidden}"

# Legacy S36 strings may survive only in prestate/compatibility/reconciliation guards.
assert "'assurance_owner','CARD_OPERATIONS'" in sql
assert "is distinct from 'CARD_OPERATIONS'" in sql
assert "replace(v_def,'S36_ASSURANCE','INDEPENDENT_REVIEW')" in sql

print("PASS_CARD_CONTROLLED_ASSURANCE_OWNER_CANONICALIZATION checks=12 historical_execution_mutation=0 parallel_owner=0")
