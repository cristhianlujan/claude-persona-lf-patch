#!/usr/bin/env python3
"""2F.P candidate test in a disposable Postgres only; no hosted connection."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
IMAGE = "postgres:17.6"
SOURCE = HERE / "fixtures/lf_router_resolve_v1_readback_20261026.sql"
SOURCE_SHA = "c99a99e61adbc783452b487f7fbccf5aa962aacaaa4e98afc2c4d5664b670886"
SUFFIX = "_lf_programming_code_operation_candidate_v1.sql"
KEY = "asset_type='REPOSITORY_ARTIFACT' AND action_code='CODE_DEVELOPMENT'"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--allow-local-docker", action="store_true", required=True)
    parser.add_argument("--sudo-docker", action="store_true")
    args = parser.parse_args()
    docker = (["sudo", "-n"] if args.sudo_docker else []) + ["docker"]
    name = "lf-pg01-2fp-" + uuid.uuid4().hex[:12]
    paths = list((ROOT / "supabase/migrations").glob("*" + SUFFIX))
    if len(paths) != 1:
        raise ValueError("Expected exactly one candidate migration")
    migration = paths[0]
    candidate = migration.read_text()
    resolver = SOURCE.read_text()
    results = []

    def check(case, actual, expected):
        if actual != expected:
            raise AssertionError(f"{case}: {actual!r} != {expected!r}")
        results.append({"case": case, "actual": actual, "expected": expected, "matched": True})

    def sql(text, error=None, case=None):
        q = subprocess.run(docker + ["exec", "-i", name, "psql", "-h", "127.0.0.1",
            "-U", "postgres", "-d", "postgres", "-X", "-Atq", "-v", "ON_ERROR_STOP=1"],
            input=text, text=True, capture_output=True, timeout=30)
        if error:
            check(case or error, q.returncode != 0 and error in q.stderr, True)
        elif q.returncode:
            raise RuntimeError(q.stderr)
        return q.stdout.strip()

    def query(expression):
        return json.loads(sql("SELECT to_jsonb(" + expression + ");"))

    def route():
        # Fully typed fixture avoids earlier unstructured/semantic gates.
        # It never sets semantic-resume GUCs to impersonate an admitted caller.
        return query("public.lf_router_resolve_v1('Propuesta local de codigo',"
            "'fixture-subject','CODE_DEVELOPMENT','REPOSITORY_ARTIFACT','ROUTER')")

    try:
        check("router_readback_sha", hashlib.sha256(SOURCE.read_bytes()).hexdigest(), SOURCE_SHA)
        subprocess.run(docker + ["run", "--rm", "-d", "--name", name, "--network", "none",
            "--tmpfs", "/var/lib/postgresql/data", "-e", "POSTGRES_HOST_AUTH_METHOD=trust", IMAGE],
            check=True, capture_output=True, text=True, timeout=30)
        for _ in range(100):
            q = subprocess.run(docker + ["exec", name, "pg_isready", "-h", "127.0.0.1",
                "-U", "postgres"], capture_output=True, timeout=5)
            if q.returncode == 0:
                break
            time.sleep(0.2)
        else:
            raise RuntimeError("Disposable Postgres not ready")

        # Dependency schemas are fixtures. Registry columns/defaults/checks match
        # the bounded Supabase RO inspection; no other real catalog data copied.
        sql("""
CREATE SCHEMA extensions; CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE TABLE public.lf_router_action_registry (
 asset_type text NOT NULL, action_code text NOT NULL, operation_code text,
 operation_resolution text NOT NULL DEFAULT 'STATIC' CHECK(operation_resolution IN ('STATIC','NONE')),
 requires_existing_target boolean NOT NULL DEFAULT true,
 requires_missing_target boolean NOT NULL DEFAULT false,
 write_allowed boolean NOT NULL DEFAULT false, status text NOT NULL DEFAULT 'ACTIVE', notes text,
 created_by_execution_id text NOT NULL DEFAULT 'EXEC-GOV-ROUTER-ACT0001-20260827-001',
 updated_by_execution_id text, created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(asset_type,action_code),
 CHECK(NOT(requires_existing_target AND requires_missing_target))
);
CREATE TABLE public.lf_operation_execution (
 execution_id text PRIMARY KEY, operation_code text, target_type text,
 target_code text, status text, manifest jsonb
);
CREATE TABLE public.lf_activos (
 codigo_activo text, nombre_canonico text, tipo_activo text, subtipo_activo text,
 estado_documental text, estado_operativo text, version text, archived_at timestamptz,
 aliases jsonb, keywords jsonb, metadata jsonb
);
CREATE VIEW public.v_lf_fuente_operativa_busqueda AS SELECT * FROM public.lf_activos;
CREATE TABLE public.lf_operation_registry (
 operation_code text PRIMARY KEY, operation_type text, lifecycle_state_code text,
 status text, version text, applies_to_asset_type text
);
INSERT INTO public.lf_router_action_registry (
 asset_type,action_code,operation_code,requires_existing_target,
 requires_missing_target,write_allowed,status,created_by_execution_id
) VALUES ('SUPABASE_EDGE_FUNCTION','EDGE_FUNCTION_DEPLOY','DEPLOY_SUPABASE_EDGE_FUNCTION_LF',
 true,false,false,'CANDIDATO_READ_ONLY','fixture://edge-author');
""")
        sql(resolver)
        before_source = query("md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))")
        check("router_live_readback_md5", before_source, "7f2d4d27e6b7a88f9fa22d2db6c00c8b")
        check("candidate_absent_before", query("(SELECT count(*) FROM public.lf_router_action_registry WHERE " + KEY + ")"), 0)
        sql("BEGIN;" + candidate + "ROLLBACK;", error="PG01_2FP_TRAIN_EXECUTION_REQUIRED", case="missing_train_execution_refused")
        actor = "fixture://train-execution-2fp"
        manifest = {"producer": "lf-migration-merge-train",
            "router_authority_receipt": {"operation_code": "ACTUALIZACION_DB_LF",
                "target_repo": "cristhianlujan/claude-persona-lf-patch",
                "target_path": "supabase/migrations/" + migration.name}}
        values = [actor, "ACTUALIZACION_DB_LF", "MIGRATION", migration.stem, "IN_PROGRESS"]
        quote = lambda value: "'" + value.replace("'", "''") + "'"
        sql("INSERT INTO public.lf_operation_execution VALUES (" +
            ",".join(quote(v) for v in values) + "," + quote(json.dumps(manifest)) + "::jsonb);")
        sql(candidate)
        row = query("(SELECT to_jsonb(r) FROM public.lf_router_action_registry r WHERE " + KEY + ")")
        check("candidate_exact_operation", row["operation_code"], "DESARROLLO_CODIGO_AGENTE_LF")
        check("candidate_state", row["status"], "CANDIDATO_READ_ONLY")
        check("candidate_write_forbidden", row["write_allowed"], False)
        check("candidate_static_resolution", row["operation_resolution"], "STATIC")
        check("candidate_train_author", row["created_by_execution_id"], actor)
        check("candidate_target_flags", [row["requires_existing_target"], row["requires_missing_target"]], [False, False])
        check("candidate_excluded_from_active_lookup",
            query("(SELECT count(*) FROM public.lf_router_action_registry WHERE " + KEY + " AND status='ACTIVE')"), 0)
        blocked = route()
        check("actual_router_candidate_block", blocked["blocking_code"], "BLOCK_OPERATION_NOT_REGISTERED")
        check("actual_router_does_not_return_operation", blocked.get("operation_code"), None)
        sql(candidate)
        check("candidate_repeat_preserves_entire_row",
            query("(SELECT to_jsonb(r) FROM public.lf_router_action_registry r WHERE " + KEY + ")"), row)

        # Mutation control is local/transactional ONLY. If ACTIVE, the exact
        # unmodified Router reaches its next gate (missing operation registry).
        control = json.loads(sql("BEGIN;UPDATE public.lf_router_action_registry SET status='ACTIVE' WHERE " +
            KEY + ";SELECT public.lf_router_resolve_v1('Propuesta local de codigo',"
            "'fixture-subject','CODE_DEVELOPMENT','REPOSITORY_ARTIFACT','ROUTER');ROLLBACK;"))
        check("active_control_reaches_next_gate", control["blocking_code"], "BLOCK_OPERATION_REGISTRY_MISSING")
        check("active_control_next_operation", control["operation_code"], "DESARROLLO_CODIGO_AGENTE_LF")
        check("active_control_rollback_restores_candidate", route()["blocking_code"], "BLOCK_OPERATION_NOT_REGISTERED")
        sql("BEGIN;UPDATE public.lf_router_action_registry SET status='ACTIVE' WHERE " + KEY + ";" +
            candidate + "ROLLBACK;", error="PG01_2FP_ROUTER_ROW_CONFLICT", case="active_row_conflict_refused")
        sql("BEGIN;UPDATE public.lf_router_action_registry SET write_allowed=true WHERE " + KEY + ";" +
            candidate + "ROLLBACK;", error="PG01_2FP_ROUTER_ROW_CONFLICT", case="write_allowed_conflict_refused")
        sql("BEGIN;UPDATE public.lf_operation_execution SET status='COMPLETED';" +
            candidate + "ROLLBACK;", error="PG01_2FP_TRAIN_EXECUTION_REQUIRED", case="completed_train_execution_refused")
        sql("BEGIN;UPDATE public.lf_operation_execution SET target_code='different';" +
            candidate + "ROLLBACK;", error="PG01_2FP_TRAIN_EXECUTION_REQUIRED", case="wrong_target_train_execution_refused")
        sql("BEGIN;INSERT INTO public.lf_operation_execution SELECT execution_id||'-duplicate'," +
            "operation_code,target_type,target_code,status,manifest FROM public.lf_operation_execution;" +
            candidate + "ROLLBACK;", error="PG01_2FP_TRAIN_EXECUTION_REQUIRED",
            case="ambiguous_train_execution_refused")
        sql("BEGIN;UPDATE public.lf_router_action_registry SET action_code='OTHER_CODE_ACTION' WHERE " +
            KEY + ";" + candidate + "ROLLBACK;", error="PG01_2FP_OPERATION_ROUTE_CONFLICT",
            case="operation_under_other_key_refused")
        check("edge_reference_row_unchanged", query("(SELECT status||':'||write_allowed::text FROM public.lf_router_action_registry WHERE asset_type='SUPABASE_EDGE_FUNCTION')"), "CANDIDATO_READ_ONLY:false")
        check("router_source_unchanged", query("md5(pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure))"), before_source)
        check("no_operation_registry_created", query("(SELECT count(*) FROM public.lf_operation_registry)"), 0)
        check("only_one_candidate_row", query("(SELECT count(*) FROM public.lf_router_action_registry WHERE operation_code='DESARROLLO_CODIGO_AGENTE_LF')"), 1)
        check("candidate_final_row_unchanged", query("(SELECT to_jsonb(r) FROM public.lf_router_action_registry r WHERE " + KEY + ")"), row)
        print(json.dumps({"evidence_tier": "LOCAL_DISPOSABLE_POSTGRES_WITH_SYNTHETIC_CATALOGS_AND_EXACT_ROUTER_RO_READBACK",
            "main_base": "ce3a96ba7bf25cc8ef4b1142509a5a6c6399a267",
            "migration": str(migration.relative_to(ROOT)),
            "migration_sha256": hashlib.sha256(migration.read_bytes()).hexdigest(),
            "router_readback_sha256": SOURCE_SHA, "postgres": sql("SELECT version();"),
            "assertions": len(results), "results": results,
            "actual_candidate_router_output": blocked, "local_active_mutation_control_output": control,
            "hosted_writes": False, "models_executed": False, "activation_allowed": False,
            "operation_contract_implemented": False, "D8_owner_GO": False}, indent=2))
    finally:
        subprocess.run(docker + ["rm", "-f", name], capture_output=True, timeout=30)


if __name__ == "__main__":
    main()
