#!/usr/bin/env python3
"""LF #3774: synthetic PG17 authority classification and protected auto-ratification.

No Supabase credentials; all writes in an ephemeral PostgreSQL 17 service.
The signer is TEST-ONLY; no production issuer/channel is installed.
"""
import json,os,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
TEST=Path(__file__).resolve().parent
BASE=ROOT/"sandbox/lf_contract_gate_test/db_write_transport"
CONTAINER=os.environ.get("PG_CONTAINER","")
TOKEN="isolated-unit-test-provenance-token-very-long-32-character-string"
PARENT="EXEC-PROFILE-PG17-PROMO"
PROM="PROM-ISOLATED-OWNER-001"
RULE="TEST-RULE-AUTO-001"
HEAD="a"*40

def sql(source, expect_fail=False):
    assert CONTAINER,"PG_CONTAINER_REQUIRED"
    proc=subprocess.run(
        ["docker","exec","-i",CONTAINER,"psql","-X","-q","-A","-t",
         "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
        input=source,text=True,capture_output=True,timeout=75)
    if expect_fail:
        assert proc.returncode,"EXPECTED_FAIL_NO_FAILURE"
        return proc.stderr
    if proc.returncode:
        raise AssertionError("SQL_FAILURE:"+proc.stderr[-2300:])
    return proc.stdout.strip()

def check(key,condition):
    assert condition,"FAIL_"+key
    print("PASS_"+key,flush=True)

def load(path):
    check("SOURCE_"+path.name,path.is_file())
    sql(path.read_text())

def assessment():
    return json.loads(sql("SELECT public.lf_rule_promotion_authority_assess_v1('B2B-AUTH-001');"))

def detail(code):
    return next(x for x in assessment()["details"] if x["rule_code"]==code)

def status():
    return sql(f"SELECT estado FROM lf_ops.reglas WHERE codigo='{RULE}';")

def promote(receipt_id):
    return json.loads(sql(f"SELECT public.lf_rule_promotion_auto_ratify_v1('{PROM}',{receipt_id});"))

def main():
    check("PG17_CONTAINER",bool(CONTAINER))
    load(BASE/"lf_rule_child_pg17_original_source_fixture_v1.sql")
    load(BASE/"lf_rule_child_pg17_seed_v1.sql")
    load(TEST/"seed_pg17.sql")
    load(TEST/"live_source_pg17.sql")
    sql("CREATE TRIGGER test_protected_receipt BEFORE INSERT "
        "ON programacion.provenance_receipts FOR EACH ROW "
        "EXECUTE FUNCTION programacion.fn_guard_provenance_receipt_insert();")
    sql("CREATE TRIGGER test_promotion_guard BEFORE UPDATE "
        "ON lf_ops.reglas FOR EACH ROW WHEN (OLD.estado IS DISTINCT FROM NEW.estado) "
        "EXECUTE FUNCTION public.lf_rule_promotion_guard_v1();")
    load(ROOT/"supabase/migrations/20261110170000_lf_rule_promotion_governed_authority_v1.sql")
    current=assessment()
    check("READ_ONLY_STATUS",current["status"]=="ASSESSED_READ_ONLY")
    check("ALL_SYNTHETIC_CANDIDATES",current["candidate_count"]==6)
    check("NO_ACTION_AUTHORIZATION_SELF_ASSERTED",current["action_authorized"] is False
          and current["human_queue_allowed"] is False)
    check("ONE_SOURCE_APPROVED_PARITY",current["exact_owner_approved_count"]==1)
    check("MISSING_SOURCE_REMEDIATION",
          detail("TEST-RULE-DOC-001")["blocking_code"]=="SOURCE_LOOKUP_REQUIRED")
    check("SOURCE_NOT_OWNER_APPROVED",
          detail("TEST-RULE-UNAPPROVED-001")["blocking_code"]=="SOURCE_NOT_OWNER_APPROVED")
    check("CONFIG_CONFLICT",
          detail("TEST-RULE-CONFLICT-001")["blocking_code"]=="MATERIAL_PARITY_UNPROVEN")
    check("PENDING_DECISION_BLOCKED",
          detail("TEST-RULE-PENDING-001")["blocking_code"]=="PENDING_DECISION_UNRESOLVED")
    check("PRODUCTION_DENY_BLOCKED",
          detail("TEST-RULE-PROD-DENIED-001")["blocking_code"]=="PRODUCTION_ACTIVATION_NOT_AUTHORIZED")
    check("POSITIVE_NEEDS_ACTION_RECEIPT",
          detail(RULE)["blocking_code"]=="ACTION_AUTHORIZATION_RECEIPT_REQUIRED")
    check("ANON_EXECUTE_DENIED",
          sql("SELECT has_function_privilege('anon',"
          "'public.lf_rule_promotion_auto_ratify_v1(text,bigint)','EXECUTE');")=="f")
    check("AUTHENTICATED_EXECUTE_DENIED",
          sql("SELECT has_function_privilege('authenticated',"
          "'public.lf_rule_promotion_auto_ratify_v1(text,bigint)','EXECUTE');")=="f")
    check("SERVICE_ROLE_EXECUTE_ALLOWED",
          sql("SELECT has_function_privilege('service_role',"
          "'public.lf_rule_promotion_auto_ratify_v1(text,bigint)','EXECUTE');")=="t")

    sql(f"INSERT INTO public.lf_rule_promotion_v1(promotion_id,rule_code,"
        "request_execution_id,requested_by_profile,request_snapshot_sha256,"
        "status,reason) VALUES("
        f"'{PROM}','{RULE}','{PARENT}','PERFIL-PRODUCT-DIRECTOR-LF',"
        f"public.lf_asset_snapshot_sha_v1('REGLA','{RULE}'),'PENDING','synthetic');")
    check("HUMAN_DECIDER_UNCHANGED",json.loads(sql(
       f"SELECT public.lf_rule_promotion_decide_v1('{PROM}','APPROVE',"
       "'GOVERNED:FORGED','test');"))["blocking_code"]=="APPROVER_MUST_BE_HUMAN")
    check("NO_RECEIPT_BLOCKED",promote(999)["code"]=="EXTERNAL_ACTION_RECEIPT_NOT_VERIFIED")
    check("NO_RECEIPT_ZERO_EFFECT",status()=="CANDIDATO")

    details=detail(RULE)
    payload={
        "head_sha":HEAD,"subject_type":"LF_RULE_PROMOTION","subject_ref":PROM,
        "subject_sha256":details["rule_sha256"],
        "promotion_id":PROM,"rule_code":RULE,
        "source_decision_id":details["source_decision_id"],
        "source_decision_sha256":details["source_decision_sha256"],
        "request_execution_id":PARENT,"source_currentness":"CURRENT",
        "semantic_parity":"MATCH_EXACT","decision":"APPROVE",
        "action_code":"PROMOTE_GOVERNED_CANDIDATE",
        "rule_snapshot_sha256":details["rule_sha256"],
        "security_gate":"PASS","owner_policy":"CURRENT_AUTHORITY"
    }
    src="'" + json.dumps(payload,sort_keys=True).replace("'","''") + "'::jsonb"
    cols=(
      "receipt_kind,execution_id,head_sha,subject_type,subject_ref,subject_sha256,"
      "issuer_channel,issuer_identity,verification_ref,payload,receipt_sha256"
    )
    fields=(
      "'RULE_PROMOTION_ACTION_AUTHORIZATION',NULL,"
      f"'{HEAD}','LF_RULE_PROMOTION','{PROM}',"
      f"'{details['rule_sha256']}',"
      "'LF_RULE_PROMOTION_ACTION_AUTHORITY_V1','SYNTHETIC_EXTERNAL_SIGNER',"
      "'ISOLATED_PG17_ACTION_RECEIPT',"
      f"{src},"
      "programacion.fn_v09_sha256_jsonb("
      "jsonb_build_object("
      "'schema_version',1,'receipt_kind','RULE_PROMOTION_ACTION_AUTHORIZATION',"
      "'execution_id',NULL,'head_sha',"
      f"'{HEAD}',"
      "'subject_type','LF_RULE_PROMOTION','subject_ref',"
      f"'{PROM}',"
      "'subject_sha256',"
      f"'{details['rule_sha256']}',"
      "'issuer_channel','LF_RULE_PROMOTION_ACTION_AUTHORITY_V1',"
      "'issuer_identity','SYNTHETIC_EXTERNAL_SIGNER',"
      "'verification_ref','ISOLATED_PG17_ACTION_RECEIPT',"
      f"'payload',{src}))"
    )
    insert=f"INSERT INTO programacion.provenance_receipts({cols}) VALUES ({fields});"
    msg=sql(insert,expect_fail=True)
    check("NO_EXTERNAL_TOKEN_REJECTED","external channel token" in msg)
    check("NO_UNPROTECTED_RECEIPT_INSERTED",sql(
      "SELECT count(*) FROM programacion.provenance_receipts;")=="0")
    sql("BEGIN; SET LOCAL programacion.provenance_channel_token = "
        f"'{TOKEN}'; {insert} COMMIT;")
    rid=int(sql("SELECT id FROM programacion.provenance_receipts LIMIT 1;"))
    check("PROTECTED_RECEIPT_INSERTED",rid>0)
    check("CURRENT_RULE_NOT_YET_PROMOTED",status()=="CANDIDATO")

    # Fail closed on a valid receipt bound to a rule whose source changed.
    sql("UPDATE public.lf_decisiones_gov SET estado_normalizado='CANDIDATO_CONTROLADO' "
        "WHERE id_decision='DEC-OWNER-001';")
    check("SOURCE_REVOKED_BLOCKED",
          promote(rid)["code"]=="SOURCE_SEMANTIC_AUTHORITY_UNPROVEN")
    sql("UPDATE public.lf_decisiones_gov SET estado_normalizado='CANDIDATO_APROBADO_POR_OWNER' "
        "WHERE id_decision='DEC-OWNER-001';")

    # A successful action can be fully rolled back, leaving the original PENDING request.
    tx=sql(f"BEGIN; SELECT public.lf_rule_promotion_auto_ratify_v1('{PROM}',{rid}); ROLLBACK;")
    check("AUTO_RATIFY_POSITIVE_WITH_ROLLBACK",'APPLIED_VERIFIED' in tx)
    check("ROLLBACK_RULE_NOT_PROMOTED",status()=="CANDIDATO")
    check("ROLLBACK_REQUEST_STILL_PENDING",sql(
      f"SELECT status FROM public.lf_rule_promotion_v1 WHERE promotion_id='{PROM}';")=="PENDING")

    result=promote(rid)
    check("ACTUAL_AUTO_APPLY_VERIFIED",result.get("status")=="APPLIED_VERIFIED")
    check("STATE_VIGENTE",status()=="VIGENTE")
    check("RULE_NOT_PENDING_DECISION",sql(
      f"SELECT pendiente_decision::text FROM lf_ops.reglas WHERE codigo='{RULE}';")=="false")
    check("PROMOTION_LEDGER_APPLIED",sql(
      f"SELECT status FROM public.lf_rule_promotion_v1 WHERE promotion_id='{PROM}';")=="APPLIED")
    check("EXACT_GOVERNED_ISSUER",sql(
      f"SELECT decided_by FROM public.lf_rule_promotion_v1 WHERE promotion_id='{PROM}';"
      ).startswith("GOVERNED:LF_RULE_PROMOTION_ACTION_AUTHORITY_V1"))
    check("NO_SECOND_APPLY",promote(rid)["code"]=="PROMOTION_REQUEST_NOT_PENDING")
    print("LF_PROMOTION_AUTHORITY_PG17_POSITIVE_NEGATIVE_ROLLBACK_PASS",flush=True)

if __name__=="__main__":main()
