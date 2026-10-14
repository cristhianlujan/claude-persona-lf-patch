"""Parse-only PostgreSQL grammar gate; never connects to a database.

PL/pgSQL bodies are string literals to the outer SQL parser. A real sandbox
ROLLBACK is still required before the Train can apply this migration.
"""
from __future__ import annotations

from test_governance_candidate_v1 import SQL


def main() -> None:
    from pglast import parse_sql
    source = SQL.read_text(encoding="utf-8")
    ast = parse_sql(source)
    if len(ast) < 15:
        raise AssertionError(f"OP_GOVERNANCE_SQL_STATEMENT_COUNT_SUSPICIOUS:{len(ast)}")
    test_file=SQL.parents[1]/"tests/lf_operational_executor_authority_readback_rollback_v1.sql"
    check=test_file.read_text(encoding="utf-8")
    test_ast=parse_sql(check)
    if len(test_ast)!=3 or not check.startswith("-- Execute ONLY after") or not check.rstrip().endswith("ROLLBACK;"):
        raise AssertionError("OPERATIONAL_AUTHORITY_TEST_NOT_TRANSACTIONAL_READ_ONLY")
    diagnostic=SQL.parents[1]/"tests/lf_operational_executor_authority_activation_readback_v1.sql"
    diagnostic_sql=diagnostic.read_text(encoding="utf-8")
    diagnostic_ast=parse_sql(diagnostic_sql)
    if (len(diagnostic_ast)!=1
            or diagnostic_ast[0].stmt.__class__.__name__!="SelectStmt"
            or "'authorization_verified',false" not in diagnostic_sql):
        raise AssertionError("OPERATIONAL_DIAGNOSTIC_NOT_A_READ_ONLY_UNAUTHORIZED_REPORT")
    print(f"PASS_OP_GOVERNANCE_SQL_PG_PARSE statements={len(ast)} source={SQL.name}")
    print(f"PASS_OP_GOVERNANCE_CATALOGUE_READBACK_PARSE statements={len(diagnostic_ast)} source={diagnostic.name}")
    print(f"PASS_OP_GOVERNANCE_READ_ONLY_TEST_PARSE statements={len(test_ast)} source={test_file.name}")


if __name__ == "__main__":
    main()
