from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20261008081500_human_escalation_admission_v1.sql"

def main() -> int:
    sql = MIGRATION.read_text(encoding="utf-8")
    lower = sql.lower()

    required = (
        "HUMAN_ESCALATION_ADMISSION",
        "lf_human_escalation_policies_v1",
        "lf_human_escalation_admission_v1",
        "fn_lf_human_decision_open_ig_v3",
        "fn_lf_human_decision_open_story_p0_v3",
        "fn_lf_human_decision_open_programming_v3",
        "EVIDENCE_INVENTORY_NOT_PROVEN",
        "DECISION_CHANGING_EVIDENCE_AVAILABLE",
        "AUTOMATION_OPTIONS_EXHAUSTED",
        "DETERMINISTIC_OUTCOME_SUFFICIENT",
        "PROVEN_RESOLVER_AVAILABLE",
        "HUMAN_DECISION_ROUTING','1.0.3",
    )
    for marker in required:
        assert marker in sql, marker

    forbidden = (
        "b2b_admin_lf",
        "insert into public.lf_capability_current",
        "update public.lf_capability_current",
        "human_queue_allowed',true,'policy',v_policy,'subject_ref'",
    )
    # Human eligibility must be reached only by the two explicit controlled branches:
    # exhausted evidence + policy, or specialized prequalification.
    assert lower.count("'human_queue_allowed',true") == 2
    for marker in forbidden[:3]:
        assert marker not in lower, marker

    # V3 adapters may accept evidence inputs, but never caller-selected authority/reviewer/actions.
    for fn in (
        "fn_lf_human_decision_open_ig_v3",
        "fn_lf_human_decision_open_story_p0_v3",
        "fn_lf_human_decision_open_programming_v3",
    ):
        pos = lower.index(f"create or replace function private.{fn}(")
        sig_end = lower.index(")", pos)
        signature = lower[pos:sig_end]
        assert "authority_ref" not in signature, (fn, signature)
        assert "reviewer_role" not in signature, (fn, signature)
        assert "allowed_actions" not in signature, (fn, signature)

    assert "empty_candidate_inventory_proves_exhaustion',false" in lower
    assert "deterministic_failure_is_not_human_by_default" in lower

    print("PASS_HUMAN_ESCALATION_ADMISSION_V1 checks=1")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
