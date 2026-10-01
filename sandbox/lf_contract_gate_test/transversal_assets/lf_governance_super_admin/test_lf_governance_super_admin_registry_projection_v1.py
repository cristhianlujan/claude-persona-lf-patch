from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CONTRACT = ROOT / "lf_governance_super_admin_contract_v1.json"
PROJECTION = ROOT / "LF_GOVERNANCE_registry_projection_v1.sql"
README = ROOT / "README.md"


def main() -> int:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    sql = PROJECTION.read_text(encoding="utf-8")
    readme = README.read_text(encoding="utf-8")

    assert contract["super_admin"] == "LF_GOVERNANCE"
    assert contract["role"] == "SUPER_ADMIN_GOVERNANCE"
    assert contract["status"] == "CANDIDATE_READ_ONLY"
    assert contract["binding_materialized"] is False
    assert contract["cutover_authorized"] is False
    assert contract["production_authorized"] is False

    assert "insert into public.lf_activos" in sql
    assert "'LF_GOVERNANCE'" in sql
    assert "'SUPER_ADMIN_GOVERNANCE_ROOT'" in sql
    assert "'CANDIDATO'" in sql
    assert "'READ_ONLY'" in sql
    assert "'BLOQUEADO'" in sql

    # Current lf_activos requires source traceability and migration batch identity.
    for required in (
        "source_spreadsheet_id",
        "source_spreadsheet_title",
        "source_sheet_name",
        "source_row_number",
        "migration_batch_id",
        "'NATIVE_SUPABASE'",
        "'LF_TRANSVERSAL_CAPABILITY_INVENTORY'",
        "'LF_GOVERNANCE_20260930'",
        "8c1d2f6c-4a1c-4f80-9d1d-007000000001",
    ):
        assert required in sql

    assert "insert into public.lf_capability_registry" not in sql
    assert "insert into public.lf_operation_registry" not in sql
    assert "insert into public.lf_activo_relaciones" not in sql
    assert "fn_lf_capability_promote" not in sql
    assert "fn_lf_capability_bind_from_orchestrator" not in sql

    assert "NO_VERIFIED_EDGE_AT_L1_007" in sql
    assert "SADM-PP-L1-008" in sql
    assert "do_not_invent_relation_type" in sql
    assert "supabase_apply_authorized',false" in sql
    assert "cutover_authorized',false" in sql
    assert "runtime_authorized',false" in sql
    assert "production_authorized',false" in sql

    assert "LF_GOVERNANCE_registry_projection_v1.sql" in readme
    assert "SADM-PP-L1-008" in readme
    assert "no se inventa una relación" in readme

    print(
        "PASS_LF_GOVERNANCE_REGISTRY_PROJECTION_V1 "
        "asset=1 traceability=complete capability_registry=0 operation_registry=0 "
        "material_relations=0_deferred_to_L1_008"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
