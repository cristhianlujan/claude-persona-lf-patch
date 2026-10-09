from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20261008090000_ig_live_pre_human_disposition_v1.sql"


def main() -> int:
    sql = MIGRATION.read_text(encoding="utf-8")
    lower = sql.lower()

    required = (
        "fn_lf_ig_human_decision_live_disposition_v1",
        "fn_input_governance_bootstrap_classify_v2",
        "LIVE_CANONICAL_CLASSIFIER_RESOLVED",
        "GOVERNED_CANDIDATE_PROMOTION_REQUIRED",
        "LIVE_GAP_EVIDENCE_OR_SOURCE_REMEDIATION",
        "ACTION_AUTHORIZATION_GATE",
        "PRE_HUMAN_ADMISSION",
        "v_lf_ig_nonhuman_action_groups_v1",
        "HUMAN_ESCALATION_ADMISSION','1.0.2",
        "HUMAN_DECISION_ROUTING','1.0.5",
    )
    for marker in required:
        assert marker in sql, marker

    forbidden = (
        "update lf_ops.",
        "delete from lf_ops.",
        "insert into lf_ops.",
        "update programacion.input_gap_proposals",
        "delete from programacion.input_gap_proposals",
        "b2b_admin_lf",
    )
    for marker in forbidden:
        assert marker not in lower, marker

    # The IG adapter must resolve live canonical state before the shared human gate.
    pos = lower.index("create or replace function private.fn_lf_human_decision_open_ig_v3")
    body = lower[pos:]
    assert body.index("fn_lf_ig_human_decision_live_disposition_v1") < body.index("lf_human_escalation_admission_v1")

    # Candidate authority is an action authorization gate, not a semantic decision.
    assert "'semantic_decision_required',false" in lower
    assert "'human_queue_allowed',false" in lower

    print("PASS_IG_LIVE_PRE_HUMAN_DISPOSITION_V1 checks=1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
