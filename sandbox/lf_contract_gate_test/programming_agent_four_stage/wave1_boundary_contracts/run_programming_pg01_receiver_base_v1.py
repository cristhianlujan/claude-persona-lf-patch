#!/usr/bin/env python3
"""SQL foundation tests in a disposable, network-isolated local Docker only.

No hosted URL/credentials accepted. Uses canonical as-of SQL functions with a
synthetic dependency catalog. This does not qualify PG-01 or live currentness.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
IMAGE = "postgres:17.6"
DEPENDENCY = "supabase/migrations/20261004144500_t_decctx_decision_context_asof_v1.sql"
MIGRATION_SUFFIX = "_programming_context_snapshot_runtime_guard_pg01_receiver_base_v1.sql"


def canonical_function(source: str, name: str) -> str:
    """Extract one dollar-quoted function, never rewrite transaction tokens."""
    match = re.search(r"(?im)^create or replace function\s+" + re.escape(name) + r"\s*\(", source)
    if match is None:
        raise ValueError("Missing canonical function: " + name)
    opening = re.search(r"(?i)\bas\s+(\$[A-Za-z_0-9]*\$)", source[match.start():])
    if opening is None:
        raise ValueError("Missing function delimiter: " + name)
    start = match.start() + opening.end()
    end = source.index(opening.group(1) + ";", start)
    return source[match.start():end + len(opening.group(1)) + 1]


def literal(value: object) -> str:
    return "'" + json.dumps(value, separators=(",", ":")).replace("'", "''") + "'::jsonb"


def text_literal(value: str | None) -> str:
    return "NULL" if value is None else "'" + value.replace("'", "''") + "'"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--allow-local-docker", action="store_true", required=True)
    parser.add_argument("--sudo-docker", action="store_true")
    parser.add_argument("--router-v2-evidence", action="store_true", help="Run actual Router V2 function and characterize boundary gaps locally")
    parser.add_argument("--historical-input", type=Path, help="Optional exact RO export; consumed only by disposable local PG")
    args = parser.parse_args()
    docker = (["sudo"] if args.sudo_docker else []) + ["docker"]
    name = "lf-pg01-foundation-" + uuid.uuid4().hex[:12]
    paths = list((ROOT / "supabase/migrations").glob("*" + MIGRATION_SUFFIX))
    if len(paths) != 1:
        raise ValueError("Expected exactly one foundation migration")
    migration = paths[0]
    dependency = (ROOT / DEPENDENCY).read_text()
    context = json.loads((HERE / "fixtures/programming_pg01_receiver_base_v1.json").read_text())["context"]
    results: list[dict] = []

    def sql(statement: str) -> str:
        proc = subprocess.run(docker + ["exec", "-i", name, "psql", "-h", "127.0.0.1", "-U", "postgres", "-d", "postgres", "-X", "-Atq", "-v", "ON_ERROR_STOP=1"], input=statement, text=True, capture_output=True, timeout=30)
        if proc.returncode:
            raise RuntimeError(proc.stderr)
        return proc.stdout.strip()

    def query(expression: str):
        return json.loads(sql("SELECT to_jsonb(" + expression + ");"))

    def check(case: str, actual, expected) -> None:
        if actual != expected:
            raise AssertionError(f"{case}: expected {expected!r}, got {actual!r}")
        def compact(value):
            encoded = json.dumps(value, sort_keys=True)
            return value if len(encoded) < 500 else {"sha256": hashlib.sha256(encoded.encode()).hexdigest(), "type": type(value).__name__}
        results.append({"case": case, "actual": compact(actual), "expected": compact(expected), "matched": True})

    def validate(candidate):
        return query("programacion.fn_programming_context_snapshot_validate_v1(" + literal(candidate) + ")")

    def reject(case: str, mutate, code: str):
        candidate = copy.deepcopy(context)
        mutate(candidate)
        actual = validate(candidate)
        check(case, (actual.get("state"), actual.get("code")), ("BLOCKED", code))
        check(case + "_record_refuses", query("programacion.fn_programming_context_record_v1(" + literal(candidate) + ",'LOCAL-PG01-NEGATIVE')").get("state"), "BLOCKED")

    def guard(resolution, expected_id, expected_sha, expected_schema="PROGRAMMING_CONTEXT_SNAPSHOT_V1"):
        return query("programacion.fn_analysis_pg01_exact_receipt_guard_v1(" + literal(resolution) + "," + ",".join(text_literal(x) for x in (expected_id, expected_sha, expected_schema)) + ")")

    try:
        # No published ports, no external network, tmpfs-only test data, no secrets.
        subprocess.run(docker + ["run", "--rm", "-d", "--name", name, "--network", "none", "--tmpfs", "/var/lib/postgresql/data", "-e", "POSTGRES_HOST_AUTH_METHOD=trust", IMAGE], check=True, capture_output=True, text=True, timeout=30)
        for _ in range(100):
            ready = subprocess.run(docker + ["exec", name, "pg_isready", "-h", "127.0.0.1", "-U", "postgres"], capture_output=True, timeout=5)
            if ready.returncode == 0:
                break
            time.sleep(0.2)
        else:
            raise RuntimeError("Local PostgreSQL did not become ready")

        bootstrap = """
CREATE SCHEMA extensions; CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE SCHEMA private; CREATE SCHEMA programacion; CREATE ROLE pg01_unprivileged;
CREATE TABLE public.lf_capability_current(capability_code text PRIMARY KEY, version text, manifest_sha256 text);
CREATE TABLE public.lf_capability_version_registry(capability_code text, version text, manifest_sha256 text, manifest jsonb);
-- Deliberately unsupported branch: no typed-evidence payloads in this fixture.
CREATE FUNCTION private.fn_lf_typed_evidence_payload_valid_v3(text,jsonb) RETURNS boolean
LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'LOCAL_TEST_TYPED_EVIDENCE_UNSUPPORTED'; END $$;
"""
        table_start = dependency.index("CREATE TABLE private.lf_decision_context_asof_v1")
        table_end = dependency.index("CREATE OR REPLACE FUNCTION private.fn_lf_decision_context_asof_payload_valid_v1")
        bootstrap += dependency[table_start:table_end]
        for fn in ("private.fn_lf_decision_context_asof_payload_valid_v1", "public.fn_lf_decision_context_asof_record_v1", "public.fn_lf_decision_context_asof_resolve_v1"):
            bootstrap += "\n" + canonical_function(dependency, fn) + "\n"
        manifest = {"dependencies": {ref["capability_code"]: {"version": ref["version"], "manifest_sha256": ref["manifest_sha256"]} for ref in context["authority_refs"]}}
        for ref in context["authority_refs"]:
            bootstrap += "INSERT INTO public.lf_capability_current VALUES (" + ",".join(text_literal(ref[k]) for k in ("capability_code", "version", "manifest_sha256")) + ");\n"
        bootstrap += "INSERT INTO public.lf_capability_current VALUES ('DECISION_CONTEXT_ASOF','1.0.0',repeat('a',64));\n"
        bootstrap += "INSERT INTO public.lf_capability_version_registry VALUES ('DECISION_CONTEXT_ASOF','1.0.0',repeat('a',64)," + literal(manifest) + ");\n"
        sql(bootstrap)
        # Install the real original guard first: migration must replace, not invent, it.
        original = next((ROOT / "supabase/migrations").glob("*_analysis_a9_pg01_exact_receipt_guard_v1.sql")).read_text()
        sql(canonical_function(original, "programacion.fn_analysis_pg01_exact_receipt_guard_v1"))
        baseline_acl = sql("SELECT coalesce(proacl::text,'DEFAULT') FROM pg_proc WHERE oid='programacion.fn_analysis_pg01_exact_receipt_guard_v1(jsonb,text,text,text)'::regprocedure;")
        original_guard_body = sql("SELECT md5(prosrc) FROM pg_proc WHERE oid='programacion.fn_analysis_pg01_exact_receipt_guard_v1(jsonb,text,text,text)'::regprocedure;")
        source = migration.read_text()
        # Migration wrappers are exact boundaries, not regex-stripped COMMIT tokens.
        boundary = re.fullmatch(r"(?s)(.*?\nbegin;\n)(.*)(\ncommit;\n)", source)
        if boundary is None:
            raise AssertionError("Expected exact outer BEGIN/COMMIT boundaries")
        check("foundation_functions_before", query("(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='programacion' AND p.proname LIKE 'fn_programming_context_%')"), 0)
        sql("BEGIN;\n" + boundary.group(2) + "\nROLLBACK;")
        check("ddl_rollback_restores_absence", query("(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='programacion' AND p.proname LIKE 'fn_programming_context_%')"), 0)
        check("ddl_rollback_restores_original_guard", sql("SELECT md5(prosrc) FROM pg_proc WHERE oid='programacion.fn_analysis_pg01_exact_receipt_guard_v1(jsonb,text,text,text)'::regprocedure;"), original_guard_body)
        sql(source)
        check("guard_acl_preserved", sql("SELECT coalesce(proacl::text,'DEFAULT') FROM pg_proc WHERE oid='programacion.fn_analysis_pg01_exact_receipt_guard_v1(jsonb,text,text,text)'::regprocedure;"), baseline_acl)
        for signature in ("fn_programming_context_snapshot_validate_v1(jsonb)", "fn_programming_context_record_v1(jsonb,text)", "fn_programming_context_resolve_v1(text,text,timestamptz)"):
            check("no_public_execute_" + signature, query("has_function_privilege('pg01_unprivileged','programacion." + signature + "','EXECUTE')"), False)
        check("valid_synthetic_payload", validate(context).get("state"), "VALID")
        receipt = query("programacion.fn_programming_context_record_v1(" + literal(context) + ",'LOCAL-PG01-POSITIVE')")
        check("record_positive", receipt.get("state"), "RECORDED")
        again = query("programacion.fn_programming_context_record_v1(" + literal(context) + ",'LOCAL-PG01-POSITIVE')")
        check("record_idempotency", (again.get("context_id"), again.get("context_sha256"), again.get("code")), (receipt["context_id"], receipt["context_sha256"], "IDEMPOTENT_REPLAY"))
        resolve_expr = "programacion.fn_programming_context_resolve_v1('PG01_LOCAL_FIXTURE','fixture://pg01/subject','2026-10-02T00:00:00Z')"
        resolution = query(resolve_expr)
        check("resolve_positive", resolution.get("state"), "RESOLVED")
        check("resolve_repeat_identical", query(resolve_expr), resolution)
        check("exact_guard_positive", guard(resolution, receipt["context_id"], receipt["context_sha256"]), True)
        check("unknown_subject", query("programacion.fn_programming_context_resolve_v1('PG01_LOCAL_FIXTURE','fixture://missing','2026-10-02T00:00:00Z')").get("state"), "UNKNOWN")

        partial = copy.deepcopy(context)
        s = partial["extensions"]["programming_context_snapshot"]
        s["package_readiness"] = "PARTIAL_READY"
        s["scope_readiness"].append({"scope_id":"S2","scope_kind":"COMPONENT","status":"BLOCKED","depends_on_scope_ids":[],"material_front_refs":["F2"],"authority_refs":["fixture://authority"],"blockers":["OWNER_PENDING"],"reason":"independent blocked scope"})
        s["scope_front_matrix"].append({"scope_id":"S2","front_id":"F2","front_status":"REQUIRED","front_closure":"BLOCKED","effect_on_scope":"BLOCKS","evidence_refs":[],"reason":"authority unresolved"})
        s["material_front_coverage"]["material_fronts"].append({"front_id":"F2","front_kind":"AUTHORITY","status":"REQUIRED","closure":"BLOCKED","source_signal_refs":["fixture://signal"],"scope_refs":["S2"],"authority_refs":["fixture://authority"],"evidence_refs":[],"currentness_refs":[],"blockers":[{"blocker_code":"OWNER_PENDING","blocker_class":"OWNER_DECISION_REQUIRED","reason":"fixture decision missing","evidence_refs":[]}],"reason":"independent material front"})
        check("partial_ready_shape_preserves_independent_ready_scope", validate(partial).get("state"), "VALID")

        reject("missing_required_field", lambda c: c["extensions"]["programming_context_snapshot"].pop("decision_context"), "PROGRAMMING_SNAPSHOT_REQUIRED_FIELD_MISSING")
        reject("empty_scope_front_matrix", lambda c: c["extensions"]["programming_context_snapshot"].update(scope_front_matrix=[]), "PROGRAMMING_SCOPE_FRONT_MATRIX_INCOMPLETE")
        reject("blocked_front_hidden_as_preserve", lambda c: c["extensions"]["programming_context_snapshot"]["scope_front_matrix"][0].update(front_closure="BLOCKED"), "PROGRAMMING_SCOPE_FRONT_MATRIX_FRONT_DRIFT")
        reject("a6_permission_field_missing", lambda c: c["extensions"]["programming_context_snapshot"]["implementability_schema"]["requirements"][0].pop("permission_refs"), "PROGRAMMING_IMPLEMENTABILITY_REQUIREMENT_INVALID")
        reject("inner_snapshot_wrong_version", lambda c: c["extensions"]["programming_context_snapshot"].update(schema_version="WRONG"), "PROGRAMMING_SNAPSHOT_VERSION")
        reject("ready_scope_has_blocker", lambda c: c["extensions"]["programming_context_snapshot"]["scope_readiness"][0].update(blockers=["fixture blocker"]), "PROGRAMMING_READY_SCOPE_HAS_BLOCKER")
        check("negative_record_leaves_one_row", query("(SELECT count(*) FROM private.lf_decision_context_asof_v1)"), 1)

        for case, field, value in (("id_mismatch", "context_id", "00000000-0000-0000-0000-000000000000"), ("reported_hash_mismatch", "context_sha256", "0"*64), ("not_resolved", "state", "UNKNOWN"), ("mutable_resolution", "resolution_basis", "LATEST"), ("latest_reinterpreted", "latest_reinterpreted", True)):
            changed = copy.deepcopy(resolution); changed[field] = value
            check(case, guard(changed, receipt["context_id"], receipt["context_sha256"]), False)
        changed = copy.deepcopy(resolution); changed["context"]["actor_authority"]["authority_sha256"] = "b"*64
        check("authority_payload_tamper", guard(changed, receipt["context_id"], receipt["context_sha256"]), False)
        check("wrong_expected_snapshot_version", guard(resolution, receipt["context_id"], receipt["context_sha256"], "LF_DECISION_CONTEXT_ASOF_INPUT_V1"), False)
        for case, ident, digest in (("missing_expected_id", None, receipt["context_sha256"]), ("missing_expected_hash", receipt["context_id"], None)):
            check(case, guard(resolution, ident, digest), False)
        check("missing_expected_schema", guard(resolution, receipt["context_id"], receipt["context_sha256"], None), False)

        # Honest characterization: shape validity is not scope/currentness admission.
        zero_ready = copy.deepcopy(context); s = zero_ready["extensions"]["programming_context_snapshot"]
        s["scope_readiness"][0].update(status="NOT_APPLICABLE"); s["package_readiness"] = "NEED_MORE_EVIDENCE"
        check("zero_ready_is_only_shape_valid", validate(zero_ready).get("state"), "VALID")
        # A real dependency mismatch is rejected by canonical RECORD, not by the guard.
        sql("UPDATE public.lf_capability_current SET version='2.0.0' WHERE capability_code='CURRENTNESS_AUTHORITY';")
        drifted = copy.deepcopy(context); drifted["decision_ref"] = "fixture://pg01/drift"
        check("record_dependency_drift", query("programacion.fn_programming_context_record_v1(" + literal(drifted) + ",'LOCAL-PG01-DRIFT')").get("code"), "DEPENDENCY_CURRENTNESS_OR_REFERENCE_DRIFT")
        check("historical_guard_not_currentness_admission", guard(query(resolve_expr), receipt["context_id"], receipt["context_sha256"]), True)

        sql("UPDATE public.lf_capability_current SET version='1.0.0' WHERE capability_code='CURRENTNESS_AUTHORITY';")
        from test_programming_pg01_receiver_v1 import exercise_receiver
        router_exercise = None
        if args.router_v2_evidence:
            from test_programming_pg01_router_v2_compatibility_v1 import exercise_router_v2
            router_exercise = exercise_router_v2
        emitter_evidence = exercise_receiver(context=context, sql=sql, query=query, check=check, repo=ROOT,
                                             router_v2_exercise=router_exercise)

        historical_results = []
        if args.historical_input:
            from test_programming_pg01_receiver_v1 import exercise_historical
            historical_results = exercise_historical(rows=json.loads(args.historical_input.read_text()), sql=sql, query=query, check=check, repo=ROOT)
            emitter_evidence["historical_snapshots_executed"] = bool(historical_results)

        print(json.dumps({"status": "LOCAL_FOUNDATION_TESTS_COMPLETED", "evidence_tier": "LOCAL_POSTGRES_CANONICAL_FUNCTIONS_SYNTHETIC_CATALOG", "provider_attested": False, "pg01_runtime_verified": False, "hosted_database_touched": False, "independent_review": False, "postgres": sql("SELECT version();"), "image": IMAGE, "migration": str(migration.relative_to(ROOT)), "migration_sha256": hashlib.sha256(migration.read_bytes()).hexdigest(), "dependency_source": DEPENDENCY, "dependency_source_sha256": hashlib.sha256(dependency.encode()).hexdigest(), "assertions": len(results), "results": results, "pending_operational_gates": ["PG-01_C4", "PG-01_C7", "durable_receipt", "trusted_currentness_provider_wiring"], "receipt_emitter_implemented": True, "emitter_evidence": emitter_evidence, "historical_results": historical_results}, indent=2))
    finally:
        subprocess.run(docker + ["rm", "-f", name], capture_output=True, timeout=30)


if __name__ == "__main__":
    main()
