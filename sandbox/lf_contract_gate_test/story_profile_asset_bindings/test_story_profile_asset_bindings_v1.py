from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / "supabase/migrations/20261002025500_story_creator_embedded_profile_asset_bindings_v1.sql"

EXPECTED_CODES = {
    "PERFIL-SCREEN-DECOMPOSER-LF",
    "PERFIL-STORY-CORE-AUTHOR-LF",
    "PERFIL-FIELD-CONTRACT-AUDITOR-LF",
    "PERFIL-CROSS-CUTTING-ENRICHER-LF",
    "PERFIL-STORY-TEST-DERIVER-LF",
}
EXPECTED_ARTIFACTS = {
    "PERFIL_SCREEN_DECOMPOSER_LF",
    "PERFIL_STORY_CORE_AUTHOR_LF",
    "PERFIL_FIELD_CONTRACT_AUDITOR_LF",
    "PERFIL_CROSS_CUTTING_ENRICHER_LF",
    "PERFIL_STORY_TEST_DERIVER_LF",
}
EXPECTED_ROLES = {
    "SCREEN_DECOMPOSER",
    "STORY_CORE_AUTHOR",
    "FIELD_CONTRACT_AUTHOR_AUDITOR",
    "CROSS_CUTTING_ENRICHER",
    "STORY_TEST_DERIVER",
}


def main() -> None:
    sql = MIGRATION.read_text(encoding="utf-8")
    checks = 0

    for value in EXPECTED_CODES:
        assert value in sql
        checks += 1
    for value in EXPECTED_ARTIFACTS:
        assert value in sql
        checks += 1
    for value in EXPECTED_ROLES:
        assert value in sql
        checks += 1

    assert "private.lf_skill_artifacts" in sql
    assert "validation_status='PASS_WITH_EVIDENCE'" in sql
    assert "artifact_status='CANDIDATO_READ_ONLY'" in sql
    assert "'source_mode','EMBEDDED_SKILL_PROFILE'" in sql
    assert "'runtime_enabled',false" in sql
    assert "'automatic_impact_enabled',false" in sql
    assert "'runtime_binding_state','BLOCKED_PENDING_PROFILE_TASK_RUNTIME_BINDING'" in sql
    assert "tipo_activo" in sql and "'PERFIL'" in sql
    assert "estado_operativo" in sql and "'READ_ONLY'" in sql
    checks += 9

    # Registration is identity-only. No new relation vocabulary or runtime activation.
    forbidden = (
        "insert into public.lf_activo_relaciones",
        "runtime_enabled',true",
        "estado_operativo','ACTIVE'",
        "create table",
        "create or replace function",
        "create trigger",
        "profiles/screen_decomposer_lf/",
        "profiles/story_core_author_lf/",
    )
    lowered = sql.lower()
    for value in forbidden:
        assert value.lower() not in lowered
        checks += 1

    assert "STORY_PROFILE_BINDING_SOURCE_ARTIFACTS_NOT_READY" in sql
    assert "STORY_PROFILE_BINDING_ASSET_COUNT_MISMATCH" in sql
    assert "STORY_PROFILE_BINDING_READBACK_MISMATCH" in sql
    checks += 3

    assert checks == 35
    print("PASS_STORY_PROFILE_ASSET_BINDINGS_V1 checks=35")


if __name__ == "__main__":
    main()
