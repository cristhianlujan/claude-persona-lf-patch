#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20260913030000_s30_router_authority_failclosed_v1.sql"
CANARY = Path(__file__).resolve().parent / "router_authority_canary_v1.sql"
PROTOCOL = ROOT / "docs/operations/PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF.md"

migration = MIGRATION.read_text(encoding="utf-8")
canary = CANARY.read_text(encoding="utf-8")
protocol = PROTOCOL.read_text(encoding="utf-8")

# Router must retain the canonical public signature while hiding the old implementation.
assert "rename to lf_router_resolve_core_v1" in migration
assert "BLOCK_UNSUPPORTED_DISTRIBUTION_MODE" in migration
assert "p_distribution_mode is distinct from 'ROUTER'" in migration
assert "public.lf_router_resolve_core_v1(\n    p_request_text,\n    null," in migration
assert "from public, anon, authenticated, service_role" in migration
assert "grant execute on function public.lf_router_resolve_v1" in migration

# Generic reservation must re-run Router authority inside the reservation transaction,
# not trust a caller-supplied receipt or operation code alone.
assert "rename to fn_lf_operation_reserve_execution_core_v1" in migration
assert "v_router_request := p_manifest->'router_request'" in migration
assert "ROUTER_PROVENANCE_REQUIRED" in migration
assert "v_route := public.lf_router_resolve_v1(" in migration
assert "ROUTER_OPERATION_MISMATCH" in migration
assert "ROUTER_TARGET_TYPE_MISMATCH" in migration
assert "ROUTER_DOWNSTREAM_EXECUTION_NOT_ALLOWED" in migration
assert "fn_lf_operation_reserve_execution_core_v1(" in migration

# The canary must cover the exact escaped defect classes discovered during S30.
for vector in (
    "BYPASS",
    "router",
    "ROUTER ",
    " ROUTER",
    "UNSUPPORTED_MODE",
    "ACT-0036",
    "ACT-0043",
    "ROUTER_PROVENANCE_REQUIRED",
    "has_function_privilege",
):
    assert vector in canary, vector

# S30 repair must agree with the already-promoted canonical Router protocol.
assert "solo `distribution_mode = 'ROUTER'`" in protocol
assert "omite por completo `target_hint`" in protocol
assert "`target_hint` no" in protocol

print("S30_ROUTER_AUTHORITY_REPAIR_V1_PASS")
