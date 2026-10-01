from pathlib import Path
import json

ROOT = Path(__file__).resolve().parent
APPLY = ROOT / "GITHUB_RECONCILIATION_cutover_v1.sql"
ROLLBACK = ROOT / "GITHUB_RECONCILIATION_cutover_rollback_v1.sql"
INVENTORY = ROOT / "github_reconciliation_cutover_inventory_v1.json"


def main() -> int:
    apply_sql = APPLY.read_text(encoding="utf-8")
    rollback_sql = ROLLBACK.read_text(encoding="utf-8")
    inv = json.loads(INVENTORY.read_text(encoding="utf-8"))
    checks = 0

    assert inv["capability_code"] == "GITHUB_RECONCILIATION"; checks += 1
    assert inv["mode"] == "ISOLATED_REVERSIBLE_EXACT_HEAD"; checks += 1
    assert inv["functional_core"]["git_blob_sha1"] == "2043574b30820aea3a1bde969366b196d23eb8f5"; checks += 1
    assert inv["validator"]["git_blob_sha1"] == "b659d04e0485211a16b46a3788c5f04bb616ea59"; checks += 1
    assert inv["runtime_or_deploy_change"] is False and inv["production_activation"] is False; checks += 1
    assert inv["bulk_cutover"] is False; checks += 1

    for required in (
        "LF_CAPABILITY_MANIFEST_V1",
        "public.fn_lf_capability_promote_v1",
        "public.fn_lf_capability_bind_from_orchestrator_v1",
        "ORCHESTRATOR_EXECUTION_GUARD_V1",
        "CURRENTNESS_AUTHORITY",
        "functional_core_unchanged",
        "legacy_workflow_preserved",
        "legacy_edge_function_preserved",
    ):
        assert required in apply_sql; checks += 1

    assert "delete from public.lf_capability_current" in rollback_sql; checks += 1
    assert "legacy_paths_preserved" in rollback_sql; checks += 1
    assert "delete from public.lf_capability_version_registry" not in rollback_sql; checks += 1
    assert "delete from public.lf_activos" not in rollback_sql; checks += 1

    print(f"PASS_GITHUB_RECONCILIATION_CUTOVER_V1 checks={checks}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
