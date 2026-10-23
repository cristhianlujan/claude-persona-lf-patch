#!/usr/bin/env python3
"""Reproduce the 16-table LF FK closure from exact read-only catalog observations.

Scope: disposable PostgreSQL 17 CI ONLY, BEGIN -> build -> assertions -> ROLLBACK.
This is baseline schema fidelity, NOT migration Train apply, LF data copy or
operational E2E. Trigger function bodies are actual pg_get_functiondef sources,
never mock replacements. No executable arbitrary statements from callers.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "baseline_catalog_observation_v1.json"
ADDITIONAL = ROOT / "baseline_extra_fk_catalog_observation_v1.json"
CLOSURE = ROOT / "baseline_fk_closure_observation_v1.json"
FUNCTIONS = ROOT / "baseline_trigger_source_observation_v1.json"
VALID_IDENT = re.compile(r"[a-z_][a-z_0-9]*\Z")
SHA64 = re.compile(r"[0-9a-f]{64}\Z")
COMMANDS = {"*": "ALL", "r": "SELECT", "a": "INSERT", "w": "UPDATE", "d": "DELETE"}
ALLOWED_ROLES = {"PUBLIC", "anon", "authenticated", "service_role", "lf_ci_readonly"}

def ident(value: str) -> str:
    assert VALID_IDENT.fullmatch(value), "BLOCK_INVALID_CATALOG_IDENTIFIER"
    return '"' + value + '"'

def relation(name: str) -> str:
    parts = name.split(".")
    assert len(parts) == 2, "BLOCK_UNQUALIFIED_RELATION"
    return ".".join(ident(p) for p in parts)

def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))

def psql(sql: str) -> str:
    env = dict(os.environ)
    for k, v in (("PGHOST", "localhost"), ("PGPORT", "5432"),
                 ("PGUSER", "postgres"), ("PGDATABASE", "postgres")):
        env.setdefault(k, v)
    assert env.get("PGPASSWORD"), "BLOCK_PG_CI_PASSWORD_MISSING"
    result = subprocess.run(
        ["psql", "-X", "--no-psqlrc", "-v", "ON_ERROR_STOP=1", "-tA"],
        input=sql, text=True, capture_output=True, env=env, timeout=90, check=False
    )
    if result.returncode:
        raise AssertionError(
            "BLOCK_PG17_CATALOG_REPLAY_SQL_FAILED: "
            + result.stderr[-3100:] + "\n" + result.stdout[-1000:]
        )
    return result.stdout

def main() -> None:
    root, more, closure, funcs = map(load, (SOURCE, ADDITIONAL, CLOSURE, FUNCTIONS))
    original = root["relations"]
    extra = more["relations"]
    tables = original + extra
    names = {r["relation"] for r in tables}
    assert len(original) == 11 and len(extra) == 5 and len(tables) == len(names) == 16
    assert closure["total_count"] == 16
    assert names == {x["relation"] for x in closure["relations"]}
    assert all(t["kind"] == "r" for t in tables)
    assert funcs["function_count"] == 27 and len(funcs["functions"]) == 27
    for fx in funcs["functions"]:
        assert SHA64.fullmatch(fx["source_sha256"])
        assert hashlib.sha256(fx["definition"].encode("utf-8")).hexdigest() == fx["source_sha256"], (
            "BLOCK_TRIGGER_FUNCTION_SOURCE_SHA_DRIFT:" + fx["signature"])

    trigger_signatures = {t["function"] for row in tables for t in row["triggers"]}
    assert trigger_signatures == {fx["signature"] for fx in funcs["functions"]}, (
        "BLOCK_TRIGGER_FUNCTION_SET_NOT_EXACT")
    graph_edges = {
        (x["from"], x["to"], x["constraint"]) for x in closure["edges"]
    }
    observed_edges = {
        (row["relation"], c["references"], c["name"])
        for row in tables for c in row["constraints"] if c["type"] == "f"
    }
    assert graph_edges == observed_edges, "BLOCK_FK_GRAPH_NOT_EXACT"

    statements = [
        "BEGIN;",
        "SET LOCAL check_function_bodies = off;",
        "SET LOCAL search_path = public, pg_catalog;",
        "CREATE SCHEMA IF NOT EXISTS private;",
        "CREATE SCHEMA IF NOT EXISTS programacion;",
        "CREATE SCHEMA IF NOT EXISTS lf_ops;",
        "CREATE SCHEMA IF NOT EXISTS lf_design;",
    ]
    for role in sorted(ALLOWED_ROLES - {"PUBLIC"}):
        statements.append(f"CREATE ROLE {ident(role)} NOLOGIN;")

    # First the exact 16 relations and their typed columns, not dummy tables.
    for row in tables:
        fields = []
        for col in row["columns"]:
            name, typ = ident(col["name"]), col["type"]
            assert re.fullmatch(r"(?:text|text\[\]|bigint|integer|uuid|jsonb|boolean|timestamp with time zone)",typ), (
                "BLOCK_UNREPLAYABLE_TYPE:" + typ)
            field = name + " " + typ
            if col["identity"]:
                assert col["identity"] in ("a", "d")
                field += " GENERATED " + ("ALWAYS" if col["identity"] == "a" else "BY DEFAULT") + " AS IDENTITY"
            if col["generated"]:
                raise AssertionError("BLOCK_UNSUPPORTED_GENERATED_COLUMN")
            if col["default"]:
                assert not col["identity"], "BLOCK_IDENTITY_AND_DEFAULT"
                field += " DEFAULT " + col["default"]
            if col["not_null"]:
                field += " NOT NULL"
            fields.append(field)
        statements.append(f"CREATE TABLE {relation(row['relation'])} (\n  "
                          + ",\n  ".join(fields) + "\n);")

    # Keys and CHECKs before foreign keys, independent of table ordering.
    for phase in ("base", "foreign"):
        for row in tables:
            for c in row["constraints"]:
                is_fk = c["type"] == "f"
                if (phase == "foreign") != is_fk:
                    continue
                statements.append(
                    "ALTER TABLE " + relation(row["relation"])
                    + " ADD CONSTRAINT " + ident(c["name"]) + " "
                    + c["definition"] + ";"
                )

    # PKEY and UNIQUE indexes are already materialized by their constraints.
    for row in tables:
        constraint_indexes = {
            c["name"] for c in row["constraints"] if c["type"] in ("p", "u", "x")
        }
        for idx in row["indexes"]:
            short_name = idx["name"].split(".")[-1]
            if short_name not in constraint_indexes:
                definition = idx["definition"]
                assert definition.startswith(("CREATE INDEX ", "CREATE UNIQUE INDEX "))
                statements.append(definition + ";")

    # Functions are literal pg_get_functiondef output; no implementation stub.
    for fx in funcs["functions"]:
        assert fx["definition"].lstrip().upper().startswith("CREATE OR REPLACE FUNCTION ")
        statements.append(fx["definition"].rstrip().rstrip(";") + ";")
    for row in tables:
        for trigger in row["triggers"]:
            assert trigger["enabled"] == "O", "BLOCK_NONSTANDARD_TRIGGER_STATE"
            definition = trigger["definition"]
            assert definition.startswith("CREATE TRIGGER ")
            statements.append(definition + ";")

    for row in tables:
        rel = relation(row["relation"])
        if row["rls"]:
            statements.append("ALTER TABLE " + rel + " ENABLE ROW LEVEL SECURITY;")
        if row["force_rls"]:
            statements.append("ALTER TABLE " + rel + " FORCE ROW LEVEL SECURITY;")
        for pol in row["policies"]:
            assert pol["command"] in COMMANDS
            assert all(role in ALLOWED_ROLES for role in pol["roles"])
            if not pol["roles"]:
                raise AssertionError("BLOCK_POLICY_ROLE_SET_EMPTY")
            psql_cmd = ("CREATE POLICY " + ident(pol["name"]) + " ON " + rel
                + " AS " + ("PERMISSIVE" if pol["permissive"] else "RESTRICTIVE")
                + " FOR " + COMMANDS[pol["command"]]
                + " TO " + ", ".join(ident(r) if r != "PUBLIC" else "PUBLIC" for r in pol["roles"]))
            if pol["using"] is not None:
                psql_cmd += " USING (" + pol["using"] + ")"
            if pol["with_check"] is not None:
                psql_cmd += " WITH CHECK (" + pol["with_check"] + ")"
            statements.append(psql_cmd + ";")

        statements.append("REVOKE ALL ON TABLE " + rel
                          + " FROM PUBLIC, anon, authenticated, service_role, lf_ci_readonly;")
        for grant in row["grants"]:
            assert grant["role"] in ALLOWED_ROLES
            assert grant["privilege"] in {"SELECT", "INSERT", "UPDATE", "DELETE", "REFERENCES", "TRIGGER", "TRUNCATE", "MAINTAIN"}
            dest = "PUBLIC" if grant["role"] == "PUBLIC" else ident(grant["role"])
            statements.append("GRANT " + grant["privilege"] + " ON TABLE " + rel
                              + " TO " + dest
                              + (" WITH GRANT OPTION" if grant["grantable"] else "") + ";")

    # Fail-closed entrypoint negatives with the six exact candidate functions.
    # No synthetic human authority, handler dispatch or Router acceptance.
    from test_pg17_operational_denial_slice_v1 import denial_sql
    statements.extend(denial_sql())

    table_list = ", ".join("'" + x + "'::regclass" for x in sorted(names))
    expected = {
        "columns": sum(len(x["columns"]) for x in tables),
        "constraints": sum(len(x["constraints"]) for x in tables),
        "indexes": sum(len(x["indexes"]) for x in tables),
        "triggers": sum(len(x["triggers"]) for x in tables),
        "policies": sum(len(x["policies"]) for x in tables),
        "rls": sum(bool(x["rls"]) for x in tables),
        "forced": sum(bool(x["force_rls"]) for x in tables),
    }
    counts = "WITH x AS (SELECT unnest(ARRAY[" + table_list + "]) oid) SELECT " + ", ".join([
        "(SELECT count(*) FROM pg_attribute a JOIN x ON x.oid=a.attrelid WHERE a.attnum>0 AND NOT a.attisdropped)",
        "(SELECT count(*) FROM pg_constraint c JOIN x ON x.oid=c.conrelid)",
        "(SELECT count(*) FROM pg_index i JOIN x ON x.oid=i.indrelid)",
        "(SELECT count(*) FROM pg_trigger t JOIN x ON x.oid=t.tgrelid WHERE NOT t.tgisinternal)",
        "(SELECT count(*) FROM pg_policy p JOIN x ON x.oid=p.polrelid)",
        "(SELECT count(*) FROM pg_class c JOIN x ON x.oid=c.oid WHERE c.relrowsecurity)",
        "(SELECT count(*) FROM pg_class c JOIN x ON x.oid=c.oid WHERE c.relforcerowsecurity)",
    ]) + ";"
    statements.append(counts)
    statements.append("ROLLBACK;")
    statements.append(
        "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace "
        "WHERE n.nspname IN ('private','programacion','lf_ops','lf_design') "
        "AND c.relkind='r';"
    )
    text = psql("\n".join(statements))
    lines = [s.strip() for s in text.splitlines() if s.strip()]
    # psql emits command tags? -tA typically includes SELECT rows only.
    marker = ("PASS_PG17_OPERATIONAL_ENTRYPOINT_DENIAL "
              "missing_approval=true forged_approval=true "
              "invalid_begin=true unadmitted_finish=true "
              "role_isolation=true no_effect_writes=true")
    assert marker in lines, "BLOCK_OPERATIONAL_ENTRYPOINT_NEGATIVES_NO_RECEIPT"
    expected_line = "|".join(str(expected[x]) for x in
        ("columns", "constraints", "indexes", "triggers", "policies", "rls", "forced"))
    assert expected_line in lines, (
        "BLOCK_BASELINE_REPLAY_CATALOG_COUNTS_MISMATCH expected="
        + expected_line + " output_tail=" + str(lines[-12:]))
    assert lines[-1] == "0", "BLOCK_BASELINE_REPLAY_ROLLBACK_LEFT_RELATION_RESIDUE"
    # PostgreSQL public tables must also disappear after the rollback.
    residual = psql(
        "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace "
        "WHERE n.nspname='public' AND c.relkind='r' AND c.relname=ANY(ARRAY["
        + ",".join("'" + n.split(".")[1] + "'" for n in sorted(names) if n.startswith("public."))
        + "]);"
    ).strip()
    assert residual == "0", "BLOCK_PUBLIC_BASELINE_RELATION_RESIDUE"
    role_residue = psql(
        "SELECT count(*) FROM pg_roles WHERE rolname IN ("
        "'lf_op_ci_admit','lf_op_ci_effect','lf_op_ci_unknown',"
        "'lf_operation_executor_runtime','lf_operational_admission_authority');"
    ).strip()
    assert role_residue == "0", "BLOCK_OPERATIONAL_REPLAY_ROLLBACK_ROLE_RESIDUE"
    print(marker + " rollback_roles_clean=true")
    print("PASS_PG17_LF_16_RELATION_CATALOG_REPLAY_ROLLBACK "
          + " ".join(f"{k}={v}" for k, v in expected.items())
          + " exact_trigger_sources=27 rollback_clean=true "
          "catalog_snapshot_only=true full_operational_e2e=false")

if __name__ == "__main__":
    main()

