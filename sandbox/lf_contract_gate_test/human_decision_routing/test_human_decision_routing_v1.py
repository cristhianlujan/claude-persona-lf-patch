from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20261008043000_human_decision_routing_v1.sql"
DOC = ROOT / "docs/operations/HUMAN_DECISION_ROUTING_V1.md"


def main() -> int:
    sql = MIGRATION.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")

    required_sql = (
        "private.lf_human_decision_requests_v1",
        "private.lf_human_decision_receipts_v1",
        "private.v_lf_human_decision_active_queue_v1",
        "private.fn_lf_human_decision_open_v1",
        "private.fn_lf_human_decision_consume_v1",
        "HUMAN_DECISION_REQUEST_CONTRACT_IMMUTABLE",
        "HUMAN_DECISION_REQUEST_STATUS_TRANSITION_INVALID",
        "HUMAN_DECISION_REVIEWER_ROLE_MISMATCH",
        "HUMAN_DECISION_AUTHORITY_REF_MISMATCH",
        "HUMAN_DECISION_CURRENTNESS_STALE",
        "HUMAN_DECISION_ACTION_NOT_ALLOWED",
        "uq_lf_human_decision_requests_v1_open_subject",
        "revoke all on private.lf_human_decision_requests_v1 from public,anon,authenticated",
        "revoke all on private.lf_human_decision_receipts_v1 from public,anon,authenticated",
    )
    for marker in required_sql:
        assert marker in sql, marker

    required_doc = (
        "Input Governance",
        "Story Creator",
        "Programming",
        "A human decision never turns a deterministic validator FAIL into PASS.",
        "LF_GOVERNANCE_SUPER_ADMIN_V1",
        "candidate/read-only",
        "does not expose a general unauthenticated decision-write API",
    )
    for marker in required_doc:
        assert marker in doc, marker

    # Stage-bound assets may be documented, but the generic migration cannot
    # mutate or depend on them as its canonical storage engine.
    forbidden_sql = (
        "insert into private.lf_p0_human_review_challenges_v1",
        "update private.lf_p0_human_review_challenges_v1",
        "insert into private.lf_p0_human_review_decisions_v1",
        "update private.lf_p0_human_review_decisions_v1",
        "insert into programacion.input_gap_proposals",
        "update programacion.input_gap_proposals",
        "create or replace function programacion.fn_programming_simple_unit_bootstrap_v1",
        "create or replace function programacion.fn_input_governance_execute",
        "insert into public.lf_capability_registry",
    )
    lower_sql = sql.lower()
    for marker in forbidden_sql:
        assert marker.lower() not in lower_sql, marker

    # No direct product-role authority may authorize software governance.
    assert "required_authority_ref text not null" in lower_sql
    assert "required_reviewer_role text not null" in lower_sql

    print("PASS_HUMAN_DECISION_ROUTING_V1_STATIC checks=1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
