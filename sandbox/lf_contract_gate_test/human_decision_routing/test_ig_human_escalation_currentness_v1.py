from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20261008083500_ig_human_escalation_currentness_v1.sql"


def main() -> int:
    sql = MIGRATION.read_text(encoding="utf-8")
    lower = sql.lower()

    required = (
        "fn_lf_ig_human_decision_source_currentness_v1",
        "v_lf_ig_human_decision_source_current_v1",
        "SOURCE_SUPERSEDED_RESOLVED",
        "SOURCE_SUPERSEDED_CURRENT_GAP",
        "RESOLVED_BY_NEWER_EVIDENCE",
        "SUPERSEDED_BY_CURRENT_GAP",
        "HUMAN_ESCALATION_ADMISSION','1.0.1",
        "HUMAN_DECISION_ROUTING','1.0.4",
        "CURRENTNESS_AUTHORITY",
    )
    for marker in required:
        assert marker in sql, marker

    forbidden = (
        "update programacion.input_gap_proposals",
        "delete from programacion.input_gap_proposals",
        "insert into public.lf_capability_current",
        "update public.lf_capability_current",
        "b2b_admin_lf",
    )
    for marker in forbidden:
        assert marker not in lower, marker

    # Historical proposals are preserved as history; only current-source proposals
    # are allowed to continue into the human admission gate.
    open_pos = lower.index("create or replace function private.fn_lf_human_decision_open_ig_v3")
    body = lower[open_pos:]
    assert body.index("fn_lf_ig_human_decision_source_currentness_v1") < body.index("lf_human_escalation_admission_v1")
    assert "'human_queue_allowed',false" in body

    print("PASS_IG_HUMAN_ESCALATION_CURRENTNESS_V1 checks=1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
