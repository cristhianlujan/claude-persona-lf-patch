#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20260926170500_lf_independent_assurance_inventory_boundary_v1.sql"


def main() -> None:
    sql = MIGRATION.read_text(encoding="utf-8")
    lowered = sql.lower()

    assert "S36-ASSURANCE-BOUNDARY-CONTAMINATION-001" in sql
    assert "codigo_activo='INDEPENDENT_ASSURANCE'" in sql
    assert "REVISION_INDEPENDIENTE_ESTRATEGIA_LF" in sql
    assert "operation_type='INDEPENDENT_REVIEW'" in sql
    assert "lf_finalize_qualification_independent_review_v1(uuid,text,jsonb)" in sql

    # Exact prestate proves the finalizer is currently misclassified as an owned
    # physical asset; poststate retains only the reviewer operation.
    assert '["REVISION_INDEPENDIENTE_ESTRATEGIA_LF","public.lf_finalize_qualification_independent_review_v1"]' in sql
    assert "'{transversal_inventory,physical_assets}'" in sql
    assert "'[\"REVISION_INDEPENDIENTE_ESTRATEGIA_LF\"]'::jsonb" in sql

    # Inventory cleanup must not invent an owner or alter lifecycle/capability identity.
    assert "v.owner_name IS NOT NULL" in sql
    assert "v.estado_operativo<>'ACTIVO'" in sql
    for token in (
        "set owner_name",
        "set estado_operativo",
        "set archived_at",
        "delete from public.lf_activos",
        "insert into public.lf_activos",
        "create table",
        "create or replace function",
        "drop function",
        "insert into public.lf_operation_registry",
        "insert into public.lf_router_action_registry",
    ):
        assert token not in lowered, f"FAIL_INDEPENDENT_ASSURANCE_INVENTORY_SCOPE_EXPANSION:{token}"

    assert "LF_INDEPENDENT_ASSURANCE_INVENTORY_PRESTATE_MISMATCH" in sql
    assert "LF_INDEPENDENT_ASSURANCE_INVENTORY_POSTSTATE_MISMATCH" in sql
    assert "LF_QUALIFICATION_FINALIZER_REMOVED_BY_INVENTORY_CLEANUP" in sql

    print("INDEPENDENT_ASSURANCE_INVENTORY_BOUNDARY=PASS")


if __name__ == "__main__":
    main()
