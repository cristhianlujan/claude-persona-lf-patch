from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATION = ROOT / "supabase/migrations/20261008100000_programming_failure_route_separation_v1.sql"


def main() -> int:
    sql = MIGRATION.read_text(encoding="utf-8")
    lower = sql.lower()

    required = (
        "failure_route",
        "'BLOCK'",
        "'AUTO_RESOLVE'",
        "'HUMAN_DECISION'",
        "'CHECK_ONLY'",
        "'DETERMINISTIC'",
        "VALIDATION_FAILED_BLOCKED",
        "PROGRAMMING_HUMAN_DECISION_FAILURE_ROUTE_REQUIRED",
        "PROGRAMMING-VALIDATION-FAILURE-ROUTE-SEPARATION-001",
    )
    for marker in required:
        assert marker in sql, marker

    forbidden = (
        "update lf_ops.",
        "insert into lf_ops.",
        "delete from lf_ops.",
        "human_decision_required',true",
    )
    for marker in forbidden:
        assert marker not in lower, marker

    # Deterministic validators must no longer use HUMAN_DECISION as their registry mode.
    for code in (
        "PROGRAMMING_GITHUB_FILE_SHA256_ASSERT_V1",
        "PROGRAMMING_GITHUB_FILE_TEXT_ASSERT_V1",
        "PROGRAMMING_SUPABASE_CATALOG_ASSERT_V1",
    ):
        assert code in sql

    assert "failure_route='auto_resolve'" in lower
    assert "failure_route''=''block''" in lower
    assert "failure_route''=''human_decision''" in lower

    print("PASS_PROGRAMMING_FAILURE_ROUTE_SEPARATION_V1 checks=1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
