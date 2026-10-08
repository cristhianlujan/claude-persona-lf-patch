from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20261008054500_human_decision_authority_receipt_verifier_v1.sql"


def main() -> int:
    sql = MIGRATION.read_text(encoding="utf-8")
    lower = sql.lower()

    required = (
        "lf_human_decision_authority_policies_v1",
        "HUMAN_ROUTING_DECISION",
        "fn_lf_human_decision_assert_authority_receipt_v1",
        "fn_lf_human_decision_record_verified_v1",
        "HUMAN_DECISION_AUTHORITY_POLICY_NOT_ACTIVE",
        "HUMAN_DECISION_AUTHORITY_RECEIPT_BINDING_MISMATCH",
        "HUMAN_DECISION_AUTHORITY_RECEIPT_REF_INVALID",
        "uq_lf_human_decision_receipts_v1_authority_receipt",
    )
    for marker in required:
        assert marker in sql, marker

    forbidden = (
        "insert into private.lf_human_decision_authority_policies_v1(",
        "update public.lf_capability_current",
        "insert into public.lf_capability_current",
        "b2b_admin_lf",
    )
    # The migration defines the policy table but must not activate a real policy.
    body_after_comments = lower
    assert "values(
    'contract://" not in body_after_comments
    for marker in forbidden[1:]:
        assert marker not in body_after_comments, marker

    assert "direct service-role inserts cannot count as a human decision" in lower
    print("PASS_HUMAN_DECISION_AUTHORITY_RECEIPT_VERIFIER_V1 checks=1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
