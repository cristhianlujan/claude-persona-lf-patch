#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
MIGRATION = ROOT / "supabase" / "migrations" / "20261003213100_independent_assurance_subject_extension_v2.sql"
REQUALIFICATION_DEP = ROOT / "supabase" / "migrations" / "20261003213000_operation_requalification_multisubject_scope_v2.sql"
HERE = Path(__file__).resolve().parent
ROLLBACK = HERE / "rollback_independent_assurance_subject_extension_v2.sql"
BASELINE = HERE / "independent_assurance_preextension_baseline_20261003.json"


def main() -> None:
    sql = MIGRATION.read_text(encoding="utf-8")
    lower = sql.lower()
    req = REQUALIFICATION_DEP.read_text(encoding="utf-8")
    req_lower = req.lower()
    rollback = ROLLBACK.read_text(encoding="utf-8")
    rollback_lower = rollback.lower()
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))

    # Existing engine only.
    assert "operation_code='revision_independiente_estrategia_lf'" in lower
    assert "create or replace function public.lf_independent_review_begin_v2" in lower
    assert "create or replace function public.lf_record_independent_review_step_v2" in lower
    assert "create or replace function public.lf_record_independent_strategy_review_step_v1" in lower

    # Forbidden parallel-stack construction must not appear as writes.
    assert "insert into public.lf_operation_registry" not in lower
    assert "insert into public.lf_router_action_registry" not in lower
    assert "insert into public.lf_operation_judges" not in lower
    assert "values('revision_independiente_lf'" not in lower
    assert "values ('revision_independiente_lf'" not in lower

    # Six existing judge identities are reused, not replaced with Story-specific judges.
    required_judges = {
        "JUDGE-INDEPENDENT-STRATEGY-REVIEW-ROUTE-v1",
        "JUDGE-INDEPENDENT-STRATEGY-REVIEW-CURRENTNESS-v1",
        "JUDGE-INDEPENDENT-STRATEGY-REVIEW-SEMANTIC-v1",
        "JUDGE-INDEPENDENT-STRATEGY-REVIEW-JUDGE-v1",
        "JUDGE-INDEPENDENT-STRATEGY-REVIEW-READBACK-v1",
        "JUDGE-INDEPENDENT-STRATEGY-REVIEW-REPORT-v1",
    }
    for judge in required_judges:
        assert judge in sql
    assert "STORY_IMPLEMENTATION_PACKAGE" in sql
    assert "EVIDENCE_LEDGER" in sql
    assert "CURRENTNESS_AUTHORITY" in sql
    assert "BLOCK_UNSUPPORTED_SUBJECT_REQUIRES_OWNER_EXTENSION" in sql
    assert "BUILDER_REVIEWER_NOT_INDEPENDENT" in sql

    # Promotion is deliberately deferred until exact post-migration operation requalification.
    assert "fn_lf_capability_promote_v1(" not in lower
    assert "block_t_indep_base_current_v1_missing_or_drifted" in lower
    assert "block_t_indep_expected_requalification_gate_not_observed" in lower

    # Requalification is extended in place; no second qualification engine is introduced.
    assert "create or replace function public.lf_operation_requalification_bootstrap_v1" in req_lower
    assert "route_asset_type" in req_lower
    assert "applies_to_asset_type is not null" in req_lower
    assert "insert into public.lf_router_action_registry" not in req_lower
    assert "create or replace function public.lf_run_operation_qualification" not in req_lower
    assert "operation_requalification_bootstrap_v2" not in req_lower

    # Rollback is bounded, preserves audit evidence and restores the exact pre-extension operation revision.
    assert baseline["operation_revision_sha256"] == "fb59333049740f13332d68b07d38493dff0732545e856facea817f6d3ad34811"
    assert baseline["registry"]["applies_to_asset_type"] == "STRATEGY"
    assert baseline["capability_registry_prestate"]["current_pointer_exists"] is True
    assert baseline["capability_registry_prestate"]["current_version"] == "1.0.0"
    assert baseline["capability_registry_prestate"]["current_manifest_sha256"] == "a6f5e2fe21ed305b6d47e8722035685b243cfc4e697ff397d1724e5d34f6c6e8"
    assert "block_t_indep_rollback_active_story_reviews" in rollback_lower
    assert "delete from public.lf_capability_current" in rollback_lower
    assert "drop function if exists public.lf_independent_review_begin_v2" in rollback_lower
    assert "drop function if exists public.lf_record_independent_review_step_v2" in rollback_lower
    assert "applies_to_asset_type='strategy'" in rollback_lower
    assert "release_state='retired'" in rollback_lower
    assert baseline["operation_revision_sha256"] in rollback
    assert "block_t_indep_rollback_old_qualification_not_current" in rollback_lower
    assert "delete from private.lf_evidence_ledger_v1" not in rollback_lower

    print("INDEPENDENT_ASSURANCE_SUBJECT_EXTENSION_MIGRATION_V2=PASS")


if __name__ == "__main__":
    main()
