from pathlib import Path
import json

ROOT = Path(__file__).resolve().parent
APPLY = ROOT / "AUTHORITY_READBACK_cutover_v1.sql"
ROLLBACK = ROOT / "AUTHORITY_READBACK_cutover_rollback_v1.sql"
INVENTORY = ROOT / "authority_readback_cutover_inventory_v1.json"


def main() -> int:
    apply_sql = APPLY.read_text(encoding="utf-8")
    rollback_sql = ROLLBACK.read_text(encoding="utf-8")
    inv = json.loads(INVENTORY.read_text(encoding="utf-8"))
    checks = 0

    assert inv["capability_code"] == "AUTHORITY_READBACK"; checks += 1
    assert inv["mode"] == "ISOLATED_REVERSIBLE_EXACT_HEAD"; checks += 1
    assert inv["functional_core"]["git_blob_sha1"] == "686c21c49efa21f6ea83ae20d91dec046722c92c"; checks += 1
    assert inv["adapters"]["git_blob_sha1"] == "6ffc635c25b70472e28229f4d5da290555a77728"; checks += 1
    assert sum(row["known_check_count"] for row in inv["validators"]) == 26; checks += 1
    assert inv["runtime_or_deploy_change"] is False and inv["production_activation"] is False; checks += 1
    assert inv["bulk_cutover"] is False; checks += 1

    for required in (
        "LF_CAPABILITY_MANIFEST_V1",
        "public.fn_lf_capability_promote_v1",
        "public.fn_lf_capability_bind_from_orchestrator_v1",
        "ORCHESTRATOR_EXECUTION_GUARD_V1",
        "CURRENTNESS_AUTHORITY",
        "functional_core_unchanged",
        "read_only_adapters_unchanged",
        "legacy_mutation_functions_preserved",
    ):
        assert required in apply_sql; checks += 1

    assert "delete from public.lf_capability_current" in rollback_sql; checks += 1
    assert "legacy_mutation_functions_preserved" in rollback_sql; checks += 1
    assert "delete from public.lf_capability_version_registry" not in rollback_sql; checks += 1
    assert "delete from public.lf_activos" not in rollback_sql; checks += 1

    print(f"PASS_AUTHORITY_READBACK_CUTOVER_V1 checks={checks}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
