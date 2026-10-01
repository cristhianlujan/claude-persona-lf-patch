from pathlib import Path
import json

ROOT = Path(__file__).resolve().parent
APPLY = ROOT / "EVIDENCE_ANTIREPLAY_cutover_v1.sql"
ROLLBACK = ROOT / "EVIDENCE_ANTIREPLAY_cutover_rollback_v1.sql"
INVENTORY = ROOT / "evidence_antireplay_cutover_inventory_v1.json"


def main() -> int:
    apply_sql = APPLY.read_text(encoding="utf-8")
    rollback_sql = ROLLBACK.read_text(encoding="utf-8")
    inv = json.loads(INVENTORY.read_text(encoding="utf-8"))
    checks = 0
    assert inv["capability_code"] == "EVIDENCE_ANTIREPLAY"; checks += 1
    assert inv["version"] == "1.1.0"; checks += 1
    assert inv["mode"] == "ISOLATED_REVERSIBLE_EXACT_HEAD"; checks += 1
    assert inv["hardening_source"]["statement_sha256"] == "7b1abd2d539a1b58403514d987ec0cdd156d15ff74d45212f74466e6c5dfee0a"; checks += 1
    assert inv["live_guard_md5"] == "2eba89c4c6c87904205564d39994f2e5"; checks += 1
    assert inv["ledger_rows_mutated"] is False; checks += 1
    assert inv["runtime_or_deploy_change"] is False and inv["production_activation"] is False; checks += 1
    assert inv["bulk_cutover"] is False; checks += 1
    for required in (
        "public.fn_lf_capability_promote_v1", "EVIDENCE_LEDGER", "EVIDENCE_RESOLVER_REGISTRY",
        "20260930133539", "7b1abd2d539a1b58403514d987ec0cdd156d15ff74d45212f74466e6c5dfee0a",
        "2eba89c4c6c87904205564d39994f2e5", "ledger_rows_mutated',false", "LF_GOVERNANCE"
    ):
        assert required in apply_sql; checks += 1
    assert "delete from public.lf_capability_current" in rollback_sql; checks += 1
    assert "delete from public.lf_capability_version_registry" not in rollback_sql; checks += 1
    assert "delete from private.lf_evidence_ledger_v1" not in rollback_sql; checks += 1
    print(f"PASS_EVIDENCE_ANTIREPLAY_CUTOVER_V1 checks={checks}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
