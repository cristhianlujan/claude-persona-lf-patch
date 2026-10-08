from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20261008093000_ig_runtime_config_existing_authority_reuse_v1.sql"


def main() -> int:
    sql = MIGRATION.read_text(encoding="utf-8")
    lower = sql.lower()

    required = (
        "fn_input_runtime_config_existing_authority_probe_v1",
        "source_architecture_decision",
        "RUNTIME_CONFIG_EXISTING_ARCHITECTURE_AUTHORITY_V1",
        "ARCHITECTURE_DECISION_AUTHORITY_NOT_UNIQUE_CURRENT_SUFFICIENT",
        "production_activation_separate_gate",
        "fn_input_governance_semantic_probe_v3",
        "fn_input_governance_semantic_probe_v3_cached_v1",
        "IG-RUNTIME-CONFIG-EXISTING-AUTHORITY-UNDERCONSUMED-001",
    )
    for marker in required:
        assert marker in sql, marker

    forbidden = (
        "dec-client-auth-session-runtime-001'",
        "p_pantalla_id=2",
        "update public.lf_decisiones_gov",
        "update lf_ops.",
        "insert into lf_ops.",
        "delete from lf_ops.",
    )
    for marker in forbidden:
        assert marker not in lower, marker

    assert "estado_normalizado='vigente'" in lower
    assert "v_ref_count<>1" in lower
    assert "v_current_count<>1" in lower
    assert "v_sufficient_count<>1" in lower

    print("PASS_IG_RUNTIME_CONFIG_EXISTING_AUTHORITY_REUSE_V1 checks=1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
