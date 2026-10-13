#!/usr/bin/env python3
"""Source-only upstream dependency preflight for the operational executor.

This checks that external SQL relations/functions referenced by the *exact*
Train-only candidate have definitions in earlier LF migration sources.
It does not replay the LF schema, verify a deployed ledger, or certify E2E.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIGRATIONS = ROOT / "supabase" / "migrations"
CANDIDATES = sorted(MIGRATIONS.glob("*_lf_operational_executor_lane_v1.sql"))
assert len(CANDIDATES) == 1, "BLOCK_OPERATIONAL_CANDIDATE_SOURCE_CARDINALITY"
CANDIDATE = CANDIDATES[0]

IDENT = r"(?:public|private|programacion)\\.[a-zA-Z_][a-zA-Z_0-9]*"
FUNC_CALL = re.compile(r"\\b(" + IDENT + r")\\s*\\(", re.IGNORECASE)
FUNCTION_DEF = re.compile(
    r"\\bcreate\\s+(?:or\\s+replace\\s+)?function\\s+(" + IDENT + r")\\s*\\(",
    re.IGNORECASE,
)
RELATION_USE = re.compile(
    r"\\b(?:from|join|update|insert\\s+into|references)\\s+(" + IDENT + r")\\b",
    re.IGNORECASE,
)
ROWTYPE_USE = re.compile(r"\\b(" + IDENT + r")\\s*%rowtype\\b", re.IGNORECASE)
RELATION_DEF = re.compile(
    r"\\bcreate\\s+(?:or\\s+replace\\s+)?"
    r"(?:(?:materialized|temporary|temp|unlogged)\\s+)?"
    r"(?:table|view)\\s+(?:if\\s+not\\s+exists\\s+)?(" + IDENT + r")\\b",
    re.IGNORECASE,
)


def normalize(value: str) -> str:
    return value.lower()


def declared_and_required(candidate_source: str):
    local_functions = {normalize(x) for x in FUNCTION_DEF.findall(candidate_source)}
    functions = {normalize(x) for x in FUNC_CALL.findall(candidate_source)}
    relations = {
        normalize(x)
        for pattern in (RELATION_USE, ROWTYPE_USE)
        for x in pattern.findall(candidate_source)
    }
    return functions - local_functions, relations


def upstream_definitions(paths: list[Path]):
    functions: dict[str, str] = {}
    relations: dict[str, str] = {}
    for path in paths:
        text = path.read_text(encoding="utf-8")
        # Ignore ordinary line comments. SQL definitions are still parsed as
        # source text; execution or semantic correctness is *not* claimed.
        text = re.sub(r"(?m)^\\s*--[^\\n]*$", "", text)
        for name in FUNCTION_DEF.findall(text):
            functions.setdefault(normalize(name), path.name)
        for name in RELATION_DEF.findall(text):
            relations.setdefault(normalize(name), path.name)
    return functions, relations


def main():
    current = CANDIDATE.read_text(encoding="utf-8")
    wanted_functions, wanted_relations = declared_and_required(current)
    assert len(wanted_functions) >= 8, "BLOCK_TOO_FEW_UPSTREAM_FUNCTION_DEPENDENCIES"
    assert len(wanted_relations) >= 8, "BLOCK_TOO_FEW_UPSTREAM_RELATION_DEPENDENCIES"

    earlier = sorted(
        path for path in MIGRATIONS.glob("*.sql")
        if re.fullmatch(r"[0-9]{14}_.*\\.sql", path.name)
        and path.name[:14] < CANDIDATE.name[:14]
    )
    assert earlier, "BLOCK_NO_PRIOR_MIGRATION_SOURCE"
    functions, relations = upstream_definitions(earlier)
    missing_functions = sorted(wanted_functions - functions.keys())
    missing_relations = sorted(wanted_relations - relations.keys())

    print(
        "OPERATIONAL_UPSTREAM_SOURCE_PREFLIGHT "
        f"prior_migrations={len(earlier)} "
        f"referenced_functions={len(wanted_functions)} "
        f"referenced_relations={len(wanted_relations)} "
        f"missing_functions={missing_functions} missing_relations={missing_relations}"
    )
    if missing_functions or missing_relations:
        raise AssertionError("BLOCK_OPERATIONAL_SOURCE_DEPENDENCY_NOT_IN_CANONICAL_HISTORY")

    # Negative self-check: unregistered dependency must remain detectable.
    assert "public.lf_unknown_dependency_sentinel_v1" not in functions
    assert "public.lf_unknown_relation_sentinel_v1" not in relations
    print("PASS_OPERATIONAL_UPSTREAM_SOURCE_COVERAGE "
          "source_only=true full_schema_e2e=false")


if __name__ == "__main__":
    main()
