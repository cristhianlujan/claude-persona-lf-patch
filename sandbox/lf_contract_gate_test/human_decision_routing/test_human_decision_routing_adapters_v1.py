from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20261008050500_human_decision_routing_adapters_v1.sql"


def main() -> int:
    sql = MIGRATION.read_text(encoding="utf-8")
    lower = sql.lower()

    required = (
        "fn_lf_human_decision_open_ig_v1",
        "fn_lf_human_decision_consume_ig_v1",
        "fn_lf_human_decision_open_story_p0_v1",
        "fn_lf_human_decision_consume_story_p0_v1",
        "fn_lf_human_decision_open_programming_v1",
        "fn_lf_human_decision_consume_programming_v1",
        "IG_HUMAN_DECISION_SOURCE_NOT_ELIGIBLE",
        "STORY_HUMAN_REVIEW_CHALLENGE_EXPIRED",
        "PROGRAMMING_HUMAN_DECISION_CURRENT_FAIL_RECEIPT_REQUIRED",
        "PROGRAMMING_HUMAN_DECISION_ACTIVE_RUN_REQUIRED",
        "HUMAN-DECISION-AUTHORITY-RECEIPT-VERIFICATION-001",
    )
    for marker in required:
        assert marker in sql, marker

    forbidden = (
        "update programacion.input_gap_proposals",
        "insert into programacion.input_gap_proposals",
        "update private.lf_p0_human_review_challenges_v1",
        "insert into private.lf_p0_human_review_decisions_v1",
        "update programacion.engineering_work_checkpoints set",
        "create or replace function programacion.fn_programming_simple_unit_bootstrap_v1",
        "grant execute",
    )
    for marker in forbidden:
        assert marker not in lower, marker

    # Every producer must project through the same generic opener.
    assert sql.count("private.fn_lf_human_decision_open_v1(") >= 3

    # Product LF admin must not authorize software-governance decisions.
    assert "B2B_ADMIN_LF" not in sql

    print("PASS_HUMAN_DECISION_ROUTING_ADAPTERS_V1 checks=1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
