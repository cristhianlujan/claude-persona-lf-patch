"""Scope/anchor regression for the governed recovery family selector candidate."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
M = (ROOT / "supabase/migrations/20261117073400_lf_ig_recovery_family_positive_na_v1.sql").read_text()
T = (ROOT / "sandbox/ig_recovery_family_positive_na_v1/rollback_test.sql").read_text()

def test_no_rule_or_privilege_mutation():
    for forbidden in ("GRANT EXECUTE ON", "INSERT INTO lf_ops.reglas", "UPDATE lf_ops.reglas",
                      "DELETE FROM lf_ops.reglas", "CREATE TABLE", "MERGE INTO"):
        assert forbidden not in M.upper() if forbidden.isupper() else forbidden not in M

def test_all_existing_entrypoints_patched():
    assert M.count("'AUTH','programacion.fn_input_na_positive_authority_v512") == 2
    assert "'AUTH','programacion.fn_input_na_positive_authority_v512_cached_v1" in M
    assert M.count("'CLASS','programacion.fn_input_governance_bootstrap_classify_v1") == 3
    assert "'GUARD','programacion.fn_guard_input_validator_semantic_coherence_v512()" in M

def test_semantic_context_not_screen_code():
    assert "ec.entity_type ~* '(RECOVERY|RECUPER|PASSWORD_UPDATE)'" in M
    assert "v_restricted_recovery_context" in M
    assert not re.search(r"p_pantalla_id\s*(?:=|in\s*\()\s*(?:52|53|56)", M, re.I)

def test_explicit_positive_na_and_sources():
    assert "jsonb_array_length(coalesce(v_na->'rule_codes','[]'::jsonb))>0" in M
    assert "jsonb_build_object('kind','RULE','codigo',q.code)" in M
    assert "v_rule->>'status'='VIGENTE'" in M

def test_recovery_validator_preserves_no_operational_session():
    assert "v_session_applicability<>'APPLICABLE'" in M
    assert "v_recovery_session_policy" not in M or "operational-session DENY" in M
    assert "fn_guard_input_validator_semantic_coherence_v512" in M

def test_rollback_test_checks_both_routes_and_direct_refs():
    assert T.startswith("-- Candidate-only PG test.")
    assert "\nBEGIN;\n" in T and T.rstrip().endswith("ROLLBACK;")
    for family in ("PERMISSIONS", "SESSION", "FEATURE_FLAGS", "I18N_FORMATS"):
        assert family in T
    assert "fn_input_governance_bootstrap_classify_v2_cached_v2" in T
    assert "fn_input_governance_bootstrap_classify_v2(" in T
    assert "'B2B-RULE-INPUT-APPLICABILITY-001'" in T
