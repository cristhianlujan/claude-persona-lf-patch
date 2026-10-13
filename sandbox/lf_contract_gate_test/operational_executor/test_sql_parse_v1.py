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
    print(f"PASS_OP_GOVERNANCE_SQL_PG_PARSE statements={len(ast)} source={SQL.name}")


if __name__ == "__main__":
    main()
