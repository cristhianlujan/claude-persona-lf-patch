#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SQL = ROOT / "supabase/migrations/20261005212619_activate_migration_write_ahead_and_saga_v1.sql"
text = SQL.read_text(encoding="utf-8")

checks = 0
for marker in (
    "MIGRATION_WRITE_AHEAD_V1",
    "MIGRATION_ORCHESTRATED_SAGA_V1",
    "public.fn_lf_orchestrator_dispatch_receipt_v1",
    "public.fn_lf_capability_orchestrator_entry_guard_v1",
    "public.fn_lf_capability_promote_v1",
    "public.fn_lf_capability_bind_from_orchestrator_v1",
    "ORCHESTRATOR_EXECUTION_GUARD_V1",
    "OWNER_D3_CURRENT_POINTER_ACTIVE",
    "production_activation',false",
):
    assert marker in text, marker
    checks += 1

assert "insert into public.lf_capability_current" not in text.lower()
checks += 1
assert "delete from public.lf_capability_current" not in text.lower()
checks += 1
assert text.index("BLOCK_D3_WRITE_AHEAD_GUARD") < text.index("BLOCK_D3_WRITE_AHEAD_PROMOTE") < text.index("BLOCK_D3_WRITE_AHEAD_BIND")
checks += 1
assert text.index("BLOCK_D3_SAGA_GUARD") < text.index("BLOCK_D3_SAGA_PROMOTE") < text.index("BLOCK_D3_SAGA_BIND")
checks += 1
assert text.index("BLOCK_D3_SAGA_WRITE_AHEAD_DEPENDENCY_NOT_CURRENT") < text.index("BLOCK_D3_SAGA_PROMOTE")
checks += 1

print(f"PASS_MIGRATION_CAPABILITY_ACTIVATION_TESTS={checks}/14")
