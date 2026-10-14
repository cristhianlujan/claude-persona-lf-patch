#!/usr/bin/env python3
"""Validate a READ-ONLY LF catalog observation; never claim full-schema replay.

The observation is bounded evidence of the live catalog, NOT a replacement
for canonical migration source or permission to deploy or apply anything.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from test_upstream_source_dependencies_v1 import (
    CANDIDATE, MIGRATIONS, declared_and_required, upstream_definitions,
)

BASE = Path(__file__).resolve().parent
CATALOG = BASE / "baseline_catalog_observation_v1.json"
CLOSURE = BASE / "baseline_fk_closure_observation_v1.json"
CATALOG_SQL = BASE / "baseline_catalog_readback_v1.sql"
CLOSURE_SQL = BASE / "baseline_fk_closure_readback_v1.sql"
SHA256 = re.compile(r"[0-9a-f]{64}\Z")


def check_readonly_sql(path: Path) -> None:
    sql = path.read_text(encoding="utf-8")
    assert sql.startswith("-- Read only:") or sql.startswith("-- LF Executor 4.3:"), (
        "BLOCK_BASELINE_UNDECLARED_READBACK_SOURCE")
    assert "pg_class" in sql and "pg_constraint" in sql
    assert not re.search(
        r"(?im)^\s*(?:INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE|GRANT|REVOKE)\b",
        sql,
    ), "BLOCK_BASELINE_READBACK_SOURCE_NOT_READONLY"


def main() -> None:
    for path in (CATALOG_SQL, CLOSURE_SQL):
        check_readonly_sql(path)
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    closure = json.loads(CLOSURE.read_text(encoding="utf-8"))
    assert catalog["schema_version"] == "LF_OPERATIONAL_BASELINE_CATALOG_READBACK_V1"
    assert closure["schema_version"] == "LF_OPERATIONAL_BASELINE_FK_CLOSURE_READBACK_V1"
    for proof in (catalog, closure):
        assert proof["authority"] == "LIVE_PG_CATALOG_READONLY_NOT_MIGRATION_SOURCE"
        assert proof.get("observed_at"), "BLOCK_READBACK_TIMESTAMP_MISSING"

    earlier = sorted(
        path for path in MIGRATIONS.glob("*.sql")
        if re.fullmatch(r"[0-9]{14}_.*\.sql", path.name)
        and path.name[:14] < CANDIDATE.name[:14]
    )
    functions, relations = upstream_definitions(earlier)
    requested_functions, requested_relations = declared_and_required(
        CANDIDATE.read_text(encoding="utf-8"))
    assert requested_functions <= functions.keys(), "BLOCK_DEPENDENT_FUNCTION_SOURCE_MISSING"
    missing = requested_relations - relations.keys()
    observed = {x["relation"] for x in catalog["relations"]}
    assert len(observed) == len(catalog["relations"]), "BLOCK_DUPLICATE_OBSERVED_RELATION"
    assert observed == missing, (
        "BLOCK_OBSERVED_BASELINE_NOT_CURRENT_CANDIDATE_DEPENDENCIES:"
        + str(sorted(observed ^ missing)))
    assert catalog["expected_relations"] == catalog["resolved_relations"] == len(observed)
    assert len(observed) > 0, "BLOCK_EMPTY_BASELINE_OBSERVATION"

    for obj in catalog["relations"]:
        assert obj["kind"] == "r" and obj["rls"] is True
        assert obj["columns"] and obj["constraints"] and obj["indexes"], (
            "BLOCK_INCOMPLETE_CATALOG_RELATION:" + obj["relation"])
        for column in obj["columns"]:
            assert column["name"] and column["type"], "BLOCK_CATALOG_COLUMN_INCOMPLETE"
        for constraint in obj["constraints"]:
            assert constraint["name"] and constraint["definition"], (
                "BLOCK_CATALOG_CONSTRAINT_INCOMPLETE")
        for index in obj["indexes"]:
            assert index["name"] and index["definition"], "BLOCK_CATALOG_INDEX_INCOMPLETE"
        for trigger in obj["triggers"]:
            assert trigger["name"] and trigger["definition"] and trigger["function"]
            assert SHA256.fullmatch(trigger["function_source_sha256"]), (
                "BLOCK_UNANCHORED_TRIGGER_FUNCTION_DEFINITION")
        assert isinstance(obj["policies"], list) and isinstance(obj["grants"], list)

    root = {x["relation"] for x in closure["relations"] if x["min_depth"] == 0}
    graph = {x["relation"] for x in closure["relations"]}
    assert root == observed and closure["root_count"] == len(root), (
        "BLOCK_FK_CLOSURE_ROOT_MISMATCH")
    assert closure["total_count"] == len(graph), "BLOCK_FK_CLOSURE_NODE_DUPLICATE"
    assert all(e["from"] in graph and e["to"] in graph for e in closure["edges"])
    observed_fks = {
        (obj["relation"], c["references"], c["name"])
        for obj in catalog["relations"]
        for c in obj["constraints"]
        if c["type"] == "f"
    }
    closure_fks = {
        (e["from"], e["to"], e["constraint"]) for e in closure["edges"]
    }
    assert observed_fks <= closure_fks, "BLOCK_FK_CATALOG_AND_CLOSURE_DRIFT"
    assert len(graph - observed) > 0, "BLOCK_UNEXPECTED_COMPLETE_FK_CLOSURE_CLAIM"

    print("PASS_OPERATIONAL_BASELINE_CATALOG_EVIDENCE_VALIDATED "
          f"observed_relations={len(observed)} "
          f"columns={sum(len(o['columns']) for o in catalog['relations'])} "
          f"constraints={sum(len(o['constraints']) for o in catalog['relations'])} "
          f"triggers={sum(len(o['triggers']) for o in catalog['relations'])} "
          f"indexes={sum(len(o['indexes']) for o in catalog['relations'])} "
          f"policies={sum(len(o['policies']) for o in catalog['relations'])}")
    print("BLOCK_FULL_SCHEMA_REPLAY_SOURCE_AUTHORITY_UNRESOLVED "
          f"fk_closure_relations={len(graph)} "
          f"additional_dependencies={sorted(graph - observed)} "
          "live_currentness_revalidation=required e2e_certified=false")


if __name__ == "__main__":
    main()
