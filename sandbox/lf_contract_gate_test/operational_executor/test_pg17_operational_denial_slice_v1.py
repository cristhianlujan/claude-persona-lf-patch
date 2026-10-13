#!/usr/bin/env python3
"""Fail-closed operational entrypoint negatives on the exact 16-table PG17 baseline.

This intentionally does NOT forge a human decision, install a handler, or
claim the admission/Router/lease/effect positive E2E. All objects and
negative invocations are run inside the parent replay's BEGIN/ROLLBACK.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CANDIDATES = list((ROOT / "supabase" / "migrations").glob("*_lf_operational_executor_lane_v1.sql"))
FUNCTION_TAGS = (
    ("lf_close_operational_execution_v1", "close"),
    ("lf_operational_executor_begin_v1", "begin"),
    ("lf_operational_executor_finish_v1", "finish"),
    ("lf_operational_executor_assert_principal_v1", "principal"),
    ("lf_operational_executor_admit_v1", "admit"),
    ("lf_operational_executor_assert_decision_current_v1", "decision_current"),
)

def single(regex: str, source: str, label: str) -> str:
    found = re.findall(regex, source, flags=re.MULTILINE | re.DOTALL)
    assert len(found) == 1, "BLOCK_OPERATIONAL_DENIAL_SOURCE_NOT_EXACT:" + label
    return found[0]

def expect_error(invocation: str, expected: str, label: str) -> str:
    assert re.fullmatch(r"OPERATIONAL_[A-Z_]+", expected), "BLOCK_UNSAFE_ERROR_EXPECTATION"
    assert re.fullmatch(r"[A-Z_]+", label), "BLOCK_UNSAFE_TEST_IDENTITY"
    return (f"""DO $deny$
DECLARE rejected boolean:=false;
BEGIN
 BEGIN
  {invocation}
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM IS DISTINCT FROM '{expected}' THEN
   RAISE EXCEPTION 'BLOCK_OPERATIONAL_UNEXPECTED_ERROR:{label}:%', SQLERRM;
  END IF;
  rejected:=true;
 END;
 IF NOT rejected THEN
  RAISE EXCEPTION 'BLOCK_OPERATIONAL_UNAUTHORIZED_ALLOWED:{label}';
 END IF;
END $deny$;""")

def denial_sql() -> list[str]:
    assert len(CANDIDATES) == 1, "BLOCK_OPERATIONAL_DENIAL_MIGRATION_SOURCE_CARDINALITY"
    source = CANDIDATES[0].read_text(encoding="utf-8")
    definitions = []
    for name, tag in FUNCTION_TAGS:
        expr = (
            r"^CREATE OR REPLACE FUNCTION public\." + re.escape(name) +
            r"\(.*?^END \$" + re.escape(tag) + r"\$;"
        )
        body = single(expr, source, name)
        assert body.count("$" + tag + "$") == 2
        assert "SECURITY DEFINER" in body and "COMMIT;" not in body
        definitions.append(body)

    roles = single(r"^DO \$role\$.*?^END \$role\$;", source, "role_ddl")
    verify_roles = single(r"^DO \$roles_verify\$.*?^END \$roles_verify\$;", source, "role_guard")
    role_usage = re.findall(
        r"^GRANT USAGE ON SCHEMA public TO lf_(?:operation_executor_runtime|operational_admission_authority);$",
        source, flags=re.MULTILINE,
    )
    revokes = re.findall(
        r"^REVOKE ALL ON FUNCTION public\.lf_[a-z_]+_v1\([^)]+\) FROM PUBLIC, anon, authenticated, service_role;$",
        source, flags=re.MULTILINE,
    )
    grants = re.findall(
        r"^GRANT EXECUTE ON FUNCTION public\.lf_[a-z_]+_v1\([^)]+\)\s+TO lf_[a-z_,]+;",
        source, flags=re.MULTILINE,
    )
    assert len(role_usage) == 2 and len(revokes) == 6 and len(grants) == 4, (
        "BLOCK_OPERATIONAL_DENIAL_ACL_SOURCE_INCOMPLETE"
    )

    inputs = [
        "CREATE SCHEMA IF NOT EXISTS extensions;",
        roles, verify_roles,
        "CREATE ROLE lf_op_ci_admit LOGIN NOINHERIT;",
        "CREATE ROLE lf_op_ci_effect LOGIN NOINHERIT;",
        "CREATE ROLE lf_op_ci_unknown LOGIN NOINHERIT;",
        "GRANT lf_operational_admission_authority TO lf_op_ci_admit "
            "WITH ADMIN FALSE, INHERIT FALSE, SET TRUE;",
        "GRANT lf_operation_executor_runtime TO lf_op_ci_effect "
            "WITH ADMIN FALSE, INHERIT FALSE, SET TRUE;",
        *definitions, *role_usage, *revokes, *grants,
    ]

    # Verify exact effective permissions on all six functions, not
    # appearance of REVOKE statements alone.
    signature_sql = ", ".join(
        "'" + signature + "'::regprocedure"
        for signature in re.findall(
            r"^REVOKE ALL ON FUNCTION (public\.lf_[a-z_]+_v1\([^)]+\)) "
            r"FROM PUBLIC, anon, authenticated, service_role;$", source,
            flags=re.MULTILINE,
        )
    )
    inputs.append(
        "DO $facade_acl$ DECLARE x regprocedure; r text; BEGIN "
        "FOR x IN SELECT unnest(ARRAY[" + signature_sql + "]) LOOP "
        "FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP "
        "IF has_function_privilege(r,x,'EXECUTE') THEN "
        "RAISE EXCEPTION 'BLOCK_API_ROLE_FUNCTION_EXECUTE:%:%',r,x; END IF; "
        "END LOOP; END LOOP; END $facade_acl$;"
    )
    inputs.append(
        "DO $groups$ BEGIN "
        "IF has_function_privilege('lf_operational_admission_authority', "
        "'public.lf_operational_executor_begin_v1(text,text,text,text,text,text,text,text,text)'::regprocedure,'EXECUTE') "
        "OR has_function_privilege('lf_operation_executor_runtime', "
        "'public.lf_operational_executor_admit_v1(text,text,text,text,text,text,text,jsonb)'::regprocedure,'EXECUTE') "
        "THEN RAISE EXCEPTION 'BLOCK_ADMISSION_AND_EFFECT_ROLE_CROSSOVER'; END IF; "
        "END $groups$;"
    )

    sha = "repeat('a',64)"
    admit_args = (
        "'EXEC-CI-NEGATIVE-001','CI_HANDLER','v1'," + sha
        + ",'ci-scope','ci-dispatch','ci-idempotency',"
    )
    input_with_valid_outer_shape = (
        "jsonb_build_object('schema_version','LF_OPERATIONAL_REQUEST_AUTHORIZATION_V1',"
        "'decision','APPROVED','approval_ref','ci:untrusted-claim',"
        "'operation_code','EJECUCION_OPERATIVA_LF','handler_code','CI_HANDLER',"
        "'handler_revision','v1','payload_sha256'," + sha + ","
        "'effect_scope','ci-scope','dispatch_key','ci-dispatch',"
        "'idempotency_key','ci-idempotency')"
    )

    inputs.append("SET SESSION AUTHORIZATION lf_op_ci_unknown;")
    inputs.append(
        "DO $outsider$ BEGIN "
        "IF has_function_privilege(current_user, "
        "'public.lf_operational_executor_admit_v1(text,text,text,text,text,text,text,jsonb)'::regprocedure,'EXECUTE') "
        "OR has_function_privilege(current_user, "
        "'public.lf_operational_executor_begin_v1(text,text,text,text,text,text,text,text,text)'::regprocedure,'EXECUTE') "
        "THEN RAISE EXCEPTION 'BLOCK_UNTRUSTED_ENTRYPOINT_EXECUTE'; END IF; "
        "END $outsider$;"
    )
    inputs.append("RESET SESSION AUTHORIZATION;")
    inputs.append("SET SESSION AUTHORIZATION lf_op_ci_admit;")
    inputs.append("SET LOCAL ROLE lf_operational_admission_authority;")
    inputs.append(expect_error(
        "PERFORM public.lf_operational_executor_admit_v1("
        + admit_args + "'{}'::jsonb);",
        "OPERATIONAL_ADMISSION_EXTERNAL_DECISION_NOT_EXACT", "MISSING_APPROVAL",
    ))
    inputs.append(expect_error(
        "PERFORM public.lf_operational_executor_admit_v1("
        + admit_args + input_with_valid_outer_shape + ");",
        "OPERATIONAL_ADMISSION_DURABLE_DECISION_REF_REQUIRED", "FORGED_APPROVAL",
    ))
    inputs.append("RESET ROLE;")
    inputs.append("RESET SESSION AUTHORIZATION;")
    inputs.append("SET SESSION AUTHORIZATION lf_op_ci_effect;")
    inputs.append("SET LOCAL ROLE lf_operation_executor_runtime;")
    inputs.append(expect_error(
        "PERFORM public.lf_operational_executor_begin_v1("
        "'EXEC-CI-NEGATIVE-001','NOT_OPERATIONAL','CI_HANDLER','CI_HANDLER','v1',"
        + sha + ",'ci-scope','ci-dispatch','ci-actor');",
        "OPERATIONAL_BEGIN_INPUT_OR_SCOPE_INVALID", "BEGIN_SCOPE",
    ))
    inputs.append(expect_error(
        "PERFORM public.lf_operational_executor_finish_v1("
        "'EXEC-CI-NEGATIVE-001','ci-owner',1,'ci-scope','{}'::jsonb,'ci-actor');",
        "OPERATIONAL_DECISION_EXECUTION_NOT_ACTIVE", "FINISH_WITHOUT_ADMISSION",
    ))
    inputs.append("RESET ROLE;")
    inputs.append("RESET SESSION AUTHORIZATION;")

    # Denied entrypoints must not have reserved a durable LF execution.
    inputs.append(
        "DO $no_effect$ BEGIN "
        "IF EXISTS(SELECT 1 FROM public.lf_operation_execution) "
        "OR EXISTS(SELECT 1 FROM public.lf_operation_execution_steps) THEN "
        "RAISE EXCEPTION 'BLOCK_DENIAL_PRODUCED_EXECUTION_OR_STEP_WRITE'; END IF; "
        "END $no_effect$;"
    )
    inputs.append(
        "SELECT 'PASS_PG17_OPERATIONAL_ENTRYPOINT_DENIAL "
        "missing_approval=true forged_approval=true "
        "invalid_begin=true unadmitted_finish=true "
        "role_isolation=true no_effect_writes=true';"
    )
    return inputs

