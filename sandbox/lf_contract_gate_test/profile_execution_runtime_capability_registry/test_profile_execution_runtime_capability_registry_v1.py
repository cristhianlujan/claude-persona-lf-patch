from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / "supabase/migrations/20261002032500_profile_execution_runtime_capability_registry_v1.sql"


def main() -> None:
    sql = MIGRATION.read_text(encoding="utf-8")
    lowered = sql.lower()
    checks = 0

    required = (
        "PROFILE_EXECUTION_RUNTIME",
        "EJECUCION_PERFIL_LF",
        "public.lf_profile_execution_begin_v1",
        "private.lf_profile_runtime_queue_v1",
        "CURRENTNESS_AUTHORITY",
        "ORCHESTRATOR_EXECUTION_GUARD_V1",
        "public.fn_lf_capability_promote_v1",
        "TRANSVERSAL_RUNTIME_LANE",
        "OPERATION_MISSING",
        "CURRENTNESS_NOT_CURRENT",
        "PREEXISTING_STATE",
        "UNAUTHORIZED_ACTIVATION",
    )
    for token in required:
        assert token in sql
        checks += 1

    assert "'runtime_activation_authorized',false" in sql
    assert "'production_authorized',false" in sql
    assert "'automatic_impact_authorized',false" in sql
    assert "'story_task_bound_cutover_authorized',false" in sql
    assert "'runtime_enabled',false" in sql
    assert "'NO_HABILITADO'" in sql
    assert "'READ_ONLY'" in sql
    assert "'BLOQUEADO'" in sql
    checks += 8

    assert "insert into public.lf_capability_registry" in lowered
    assert "insert into public.lf_capability_version_registry" in lowered
    assert "insert into public.lf_activos" in lowered
    assert "insert into public.lf_activo_relaciones" in lowered
    assert "fn_lf_capability_promote_v1" in lowered
    checks += 5

    forbidden = (
        "create table",
        "create trigger",
        "create or replace function",
        "update private.lf_profile_runtime_queue_v1",
        "insert into private.lf_profile_runtime_queue_v1",
        "delete from private.lf_profile_runtime_queue_v1",
        "runtime_enabled',true",
        "production_authorized',true",
        "automatic_impact_authorized',true",
        "story_task_bound_cutover_authorized',true",
    )
    for token in forbidden:
        assert token not in lowered
        checks += 1

    assert "3fc0626396b64e1aac6375534b1cb3cadda1e4db" in sql
    assert "profile_execution_runtime_capability_v1.json" in sql
    assert "validate_profile_execution_runtime_capability_v1.py" in sql
    checks += 3

    assert checks == 38
    print("PASS_PROFILE_EXECUTION_RUNTIME_CAPABILITY_REGISTRY_V1 checks=38")


if __name__ == "__main__":
    main()
