from pathlib import Path
import json

ROOT = Path(__file__).resolve().parent
APPLY = ROOT / "RUNTIME_DEPLOY_VERIFICATION_cutover_v1.sql"
ROLLBACK = ROOT / "RUNTIME_DEPLOY_VERIFICATION_cutover_rollback_v1.sql"
INVENTORY = ROOT / "runtime_deploy_verification_cutover_inventory_v1.json"


def main() -> int:
    apply_sql = APPLY.read_text(encoding="utf-8")
    rollback_sql = ROLLBACK.read_text(encoding="utf-8")
    inv = json.loads(INVENTORY.read_text(encoding="utf-8"))
    checks = 0

    assert inv["capability_code"] == "RUNTIME_DEPLOY_VERIFICATION"; checks += 1
    assert inv["mode"] == "ISOLATED_REVERSIBLE_EXACT_HEAD"; checks += 1
    assert inv["functional_core"]["git_blob_sha1"] == "af53b9221d15d27a8ff016e3ec1ada804594867a"; checks += 1
    assert inv["validator"]["git_blob_sha1"] == "6d9ff2a581840eee8844836d4099cd70b513fe3b"; checks += 1
    assert inv["validator"]["known_check_count"] == 19; checks += 1
    assert inv["runtime_or_deploy_effect_executed"] is False and inv["production_activation"] is False; checks += 1
    assert inv["bulk_cutover"] is False; checks += 1

    for required in (
        "LF_CAPABILITY_MANIFEST_V1",
        "public.fn_lf_capability_promote_v1",
        "public.fn_lf_capability_bind_from_orchestrator_v1",
        "ORCHESTRATOR_EXECUTION_GUARD_V1",
        "CURRENTNESS_AUTHORITY",
        "functional_core_unchanged",
        "legacy_installer_preserved",
        "deploy_effect_path_preserved",
        "deploy_executed',false",
        "restart_executed',false",
    ):
        assert required in apply_sql; checks += 1

    assert "delete from public.lf_capability_current" in rollback_sql; checks += 1
    assert "deploy_effect_path_preserved" in rollback_sql; checks += 1
    assert "delete from public.lf_capability_version_registry" not in rollback_sql; checks += 1
    assert "delete from public.lf_activos" not in rollback_sql; checks += 1

    print(f"PASS_RUNTIME_DEPLOY_VERIFICATION_CUTOVER_V1 checks={checks}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
