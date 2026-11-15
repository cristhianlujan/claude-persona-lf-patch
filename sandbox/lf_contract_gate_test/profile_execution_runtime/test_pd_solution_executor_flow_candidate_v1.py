"""Static, read-only regression for PD solution -> Router executor -> Quality candidate.
Behavioral/E2E verdict requires PostgreSQL 17/18 and real readbacks; this file does
NOT claim those tests passed and never executes a Supabase write.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20261115010000_lf_pd_solution_executor_before_quality_v1.sql"
PRODUCT = ROOT / "profiles/product_director_lf/SKILL.md"
REPAIR = ROOT / "profiles/systemic_root_cause_repair_lf/SKILL.md"
QUALITY = ROOT / "profiles/quality_pack/SKILL.md"


def source():
    return MIGRATION.read_text(encoding="utf-8")


def test_source_preflight_and_rollback_boundary():
    s = source()
    assert s.startswith("-- Candidate ONLY:")
    assert s.count("BEGIN;") == 1
    assert s.strip().endswith("COMMIT;")
    assert "PD_EXECUTOR_CLASSIFIER_SOURCE_STATE_DRIFT" in s
    assert "PD_EXECUTOR_SELECTOR_SOURCE_STATE_DRIFT" in s
    assert "PD_EXECUTOR_CLASSIFIER_ANCHOR_DRIFT" in s
    assert "PD_EXECUTOR_SELECTOR_FILTER_DRIFT" in s
    assert "CREATE TABLE " not in s
    assert not re.search(r"\b(DELETE|TRUNCATE|DROP|GRANT|ALTER ROLE)\b", s, re.I)


def test_analysis_must_continue_to_executor_not_quality():
    s = source()
    assert "'PRODUCT_EXECUTOR_HANDOFF'" in s
    assert "'MISSING_EXECUTABLE_PACKAGE'" in s
    assert "'PROPOSED_IMPLEMENTATION_PACKAGE'" in s
    assert "'quality_allowed_before_executor',false" in s
    assert "'required_next_gate','ROUTER_SELECT_EXECUTOR'" in s
    assert "'status'<>'RETURN_TO_ROUTER'" in s
    assert "PD_EXECUTOR_MISSING_PROPOSAL_REGRESSION" in s
    assert "PD_EXECUTOR_PROPOSAL_READY_REGRESSION" in s
    assert "PD_EXECUTOR_DIRECT_TARGET_REGRESSION" in s
    assert "PD_EXECUTOR_SELECTOR_DERIVED_AUTH_DRIFT" in s
    assert "PD_EXECUTOR_SELECTOR_DERIVED_AUTH_DRIFT" in s.split("DO $lf_pd_derived$", 1)[1]
    assert "PD_EXECUTOR_TERMINAL_ROUTER_RETURN_NOT_ATTACHED" in s


def test_selector_never_invents_route_or_uses_hardcoded_fallback():
    s = source()
    assert "WHERE config_key='FALLBACK_PROFILE'" in s
    assert "v_source_output" in s
    assert "v_redirect:=public.lf_profile_result_router_return_classify_v1" in s
    assert "e.status='COMPLETED'" in s
    assert "v_deriv IS NOT NULL" in s
    assert "v_next_stage->>'phase'='EXECUTOR_BEFORE_QUALITY'" in s
    assert "p->>'profile_code'=v_fallback" in s
    assert "p->>'canonical_profile_key' NOT IN ('product_director_lf','quality_pack')" in s
    assert "v_next_stage->>'phase'='QUALITY_ON_EXECUTED_ARTIFACT'" in s
    assert "p->>'canonical_profile_key'='quality_pack'" in s
    assert "direct_profile_invocation_allowed',true" not in s
    assert "promotion_allowed',true" not in s
    assert "ALTER TABLE" not in s


def test_profiles_define_actual_solution_artifact_and_human_gate():
    product = PRODUCT.read_text(encoding="utf-8")
    repair = REPAIR.read_text(encoding="utf-8")
    quality = QUALITY.read_text(encoding="utf-8")
    assert "deliverable_created.implementation_package" in product
    assert "ROUTER_SELECT_EXECUTOR" in product
    assert "solution_status=PROPOSED_NOT_IMPLEMENTED" in product
    assert "FALLBACK_PROFILE" in product
    assert "UPSTREAM_EXECUTOR_ARTIFACT_MISSING" in quality
    assert "the executor's artifact" in quality
    assert "repair_execution_authority" in repair
    assert "Promotion remains separate" in repair


def test_no_synthetic_success_claims():
    s = source()
    assert "EXEC-FIXTURE-NOT-PERSISTED" in s
    assert "PROMOTION_INDEPENDENT_STEP70_NOT_ATTESTED" not in s
    assert "INSERT INTO lf_ops." not in s
    assert "UPDATE lf_ops." not in s
