from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20261008072000_human_decision_policy_registry_v1.sql"

def main() -> int:
    sql = MIGRATION.read_text(encoding="utf-8")
    lower = sql.lower()

    required = (
        "lf_human_decision_classes_v1",
        "lf_human_decision_classification_rules_v1",
        "lf_human_decision_route_policies_v1",
        "fn_lf_human_decision_resolve_policy_v1",
        "fn_lf_human_decision_open_ig_v2",
        "fn_lf_human_decision_open_story_p0_v2",
        "fn_lf_human_decision_open_programming_v2",
        "DECISION_CLASS_UNRESOLVED",
        "DECISION_ROUTE_POLICY_NOT_ACTIVE",
        "HUMAN_DECISION_ROUTE_NOT_ACTIVE",
        "HUMAN_DECISION_ROUTING','1.0.2",
    )
    for marker in required:
        assert marker in sql, marker

    forbidden = (
        "b2b_admin_lf",
        "insert into public.lf_capability_current",
        "update public.lf_capability_current",
        "insert into private.lf_human_decision_authority_policies_v1",
    )
    for marker in forbidden:
        assert marker not in lower, marker

    # Canonical V2 adapter signatures must not accept caller-selected authority/role/actions.
    for fn in (
        "fn_lf_human_decision_open_ig_v2",
        "fn_lf_human_decision_open_story_p0_v2",
        "fn_lf_human_decision_open_programming_v2",
    ):
        pos = lower.index(f"create or replace function private.{fn}(")
        sig_end = lower.index(")", pos)
        signature = lower[pos:sig_end]
        assert "authority" not in signature, (fn, signature)
        assert "reviewer" not in signature, (fn, signature)
        assert "allowed_actions" not in signature, (fn, signature)

    print("PASS_HUMAN_DECISION_POLICY_REGISTRY_V1 checks=1")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
