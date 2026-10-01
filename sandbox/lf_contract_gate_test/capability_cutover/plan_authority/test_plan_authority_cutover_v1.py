from pathlib import Path
import json

ROOT = Path(__file__).resolve().parent
APPLY = ROOT / "PLAN_AUTHORITY_DRIFT_GUARD_cutover_v1.sql"
ROLLBACK = ROOT / "PLAN_AUTHORITY_DRIFT_GUARD_cutover_rollback_v1.sql"
INVENTORY = ROOT / "plan_authority_cutover_inventory_v1.json"


def main() -> int:
    apply_sql = APPLY.read_text(encoding="utf-8")
    rollback_sql = ROLLBACK.read_text(encoding="utf-8")
    inv = json.loads(INVENTORY.read_text(encoding="utf-8"))
    checks = 0
    assert inv["capability_code"] == "PLAN_AUTHORITY_DRIFT_GUARD"; checks += 1
    assert inv["version"] == "1.0.0"; checks += 1
    assert inv["functional_core"]["git_blob_sha1"] == "ff0d702b8d7f49235320ab923dd93fd222c54de2"; checks += 1
    assert inv["validator"]["git_blob_sha1"] == "501ba9088c30fc0cfe44b249d76529a84a491020"; checks += 1
    assert inv["validator"]["known_check_count"] == 13; checks += 1
    assert inv["anchor_event_id"] == 19435; checks += 1
    assert inv["runtime_or_deploy_change"] is False and inv["production_activation"] is False; checks += 1
    assert inv["bulk_cutover"] is False; checks += 1
    for required in ("public.fn_lf_capability_promote_v1","CURRENTNESS_AUTHORITY","CAPABILITY_EXECUTION_CONTRACT","ORCHESTRATOR_EXECUTION_GUARD_V1","functional_core_unchanged","LF_GOVERNANCE"):
        assert required in apply_sql; checks += 1
    assert "delete from public.lf_capability_current" in rollback_sql; checks += 1
    assert "delete from public.lf_capability_version_registry" not in rollback_sql; checks += 1
    print(f"PASS_PLAN_AUTHORITY_CUTOVER_V1 checks={checks}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
