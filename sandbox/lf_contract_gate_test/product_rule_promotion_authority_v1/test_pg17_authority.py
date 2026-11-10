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
    load(ROOT/"supabase/migrations/20261110181000_lf_rule_authority_marks_and_product_handoff_v1.sql")
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

    # New, filterable per-rule markers must be registered ONLY after the
    # same profile run has a clean validated semantic judge and Router receipt.
    marker=json.loads(sql(f"SELECT public.lf_rule_authority_mark_refresh_v1("
      f"'{PARENT}','B2B-AUTH-001','PG17/JUDGE/70');"))
    check("MARKS_DURABLE_RECORDED",marker.get("status")=="MARKS_RECORDED"
          and marker.get("marked")==6)
    check("MARKS_SIX_FILTERABLE",sql(
      "SELECT count(*) FROM public.v_lf_rule_authority_filter_v1 "
      "WHERE pantalla_codigo='B2B-AUTH-001' "
      "AND marca NOT IN ('SIN_EVALUACION_REGISTRADA','REVALIDAR_SNAPSHOT');")=="6")
    check("SOURCE_LOOKUP_FLAG_FILTERABLE",sql(
      "SELECT count(*) FROM public.v_lf_rule_authority_filter_v1 "
      "WHERE pantalla_codigo='B2B-AUTH-001' AND marca='SOURCE_LOOKUP_REQUIRED';")=="1")
    check("PENDING_RECEIPT_FLAG_FILTERABLE",sql(
      "SELECT count(*) FROM public.v_lf_rule_authority_filter_v1 "
      "WHERE pantalla_codigo='B2B-AUTH-001' "
      "AND marca='ACTION_AUTHORIZATION_RECEIPT_REQUIRED';")=="1")
    check("MARK_NO_AUTO_PROMOTION",status()=="CANDIDATO"
          and sql("SELECT count(*) FROM public.lf_rule_promotion_v1;")=="0")
    check("MARK_NOT_PUBLICLY_WRITABLE",sql(
      "SELECT has_table_privilege('authenticated',"
      "'public.lf_rule_authority_tracking_v1','UPDATE');")=="f")

    sql("UPDATE public.lf_operation_execution_steps SET "
      "evidence_payload=jsonb_set(evidence_payload,"
      "'{semantic_judge_result,status}','\"FAIL\"'::jsonb) "
      f"WHERE execution_id='{PARENT}' AND step_id='semantic_judge';")
    guard=json.loads(sql(f"SELECT public.lf_rule_authority_mark_refresh_v1("
      f"'{PARENT}','B2B-AUTH-001','PG17/NEGATIVE');"))
    check("FAILED_JUDGE_CANNOT_MARK",
          guard.get("code")=="PRODUCT_JUDGE_OR_VALIDATOR_NOT_CLEAN")
    sql("UPDATE public.lf_operation_execution_steps SET "
      "evidence_payload=jsonb_set(evidence_payload,"
      "'{semantic_judge_result,status}','\"PASS\"'::jsonb) "
      f"WHERE execution_id='{PARENT}' AND step_id='semantic_judge';")

    # No independent issuer configured -> no speculative pending promotion.
    sql("UPDATE programacion.provenance_channels SET allowed_kinds=ARRAY[]::text[] "
        "WHERE channel_code='LF_RULE_PROMOTION_ACTION_AUTHORITY_V1';")
    noissuer=json.loads(sql(
      f"SELECT public.lf_rule_promotion_request_eligible_v1("
      f"'{PARENT}','B2B-AUTH-001','{RULE}');"))
    check("NO_ISSUER_NO_PROMOTION_REQUEST",
          noissuer.get("code")=="INDEPENDENT_PROMOTION_ISSUER_NOT_CONFIGURED"
          and sql("SELECT count(*) FROM public.lf_rule_promotion_v1;")=="0")
    sql("UPDATE programacion.provenance_channels SET "
      "allowed_kinds=ARRAY['RULE_PROMOTION_ACTION_AUTHORIZATION'] "
      "WHERE channel_code='LF_RULE_PROMOTION_ACTION_AUTHORITY_V1';")

    global PROM
    opened=json.loads(sql(
      f"SELECT public.lf_rule_promotion_request_eligible_v1("
      f"'{PARENT}','B2B-AUTH-001','{RULE}');"))
    check("PRODUCT_POST_JUDGE_PROMOTION_REQUEST",
          opened.get("status")=="WAIT_GOVERNED_ACTION_RECEIPT"
          and opened.get("business_redecision_required") is False)
    PROM=opened["promotion_id"]
    check("PROMOTION_REQUEST_TRACKED",sql(
      f"SELECT marca FROM public.lf_rule_authority_tracking_v1 "
      f"WHERE rule_code='{RULE}';")=="PROMOTION_REQUESTED")
    check("PENDING_RECEIPT_NOT_VIGENTE",status()=="CANDIDATO")
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

    # A different protected issuer can issue a genuine receipt in the
    # synthetic database, but it must not authorize this rule's promotion.
    sql("INSERT INTO programacion.provenance_channels("
        "channel_code,secret_sha256,allowed_kinds,description)"
        "SELECT 'OTHER_EVIDENCE_CHANNEL',secret_sha256,allowed_kinds,'synthetic wrong issuer'"
        " FROM programacion.provenance_channels "
        "WHERE channel_code='LF_RULE_PROMOTION_ACTION_AUTHORITY_V1';")
    other_channel_insert=insert.replace(
        "LF_RULE_PROMOTION_ACTION_AUTHORITY_V1","OTHER_EVIDENCE_CHANNEL")
    sql("BEGIN; SET LOCAL programacion.provenance_channel_token = "
        f"'{TOKEN}'; {other_channel_insert} COMMIT;")
    foreign_id=int(sql("SELECT id FROM programacion.provenance_receipts "
        "WHERE issuer_channel='OTHER_EVIDENCE_CHANNEL' LIMIT 1;"))
    check("WRONG_ISSUER_BLOCKED",
          promote(foreign_id)["code"]=="EXTERNAL_ACTION_RECEIPT_NOT_VERIFIED")
    check("WRONG_ISSUER_ZERO_EFFECT",status()=="CANDIDATO")

    # A superseding decision, even still CANDIDATO, invalidates old currentness.
    sql("INSERT INTO public.lf_decisiones_gov("
        "id_decision,estado_normalizado,decision_number,raw_payload) VALUES("
        "'DEC-SUPERSEDING-001','CANDIDATO_CONTROLADO',301,"
        "'{\"supersedes_decision_id\":\"DEC-OWNER-001\"}'::jsonb);")
    check("SUPERSEDED_SOURCE_BLOCKED",
          promote(rid)["code"]=="SOURCE_SEMANTIC_AUTHORITY_UNPROVEN")
    sql("DELETE FROM public.lf_decisiones_gov "
        "WHERE id_decision='DEC-SUPERSEDING-001';")
    check("SOURCE_CURRENTNESS_RECOVERED",
          detail(RULE)["blocking_code"]=="ACTION_AUTHORIZATION_RECEIPT_REQUIRED")

    # Tampering with a protected receipt after issuance cannot bypass the
    # canonical digest even if the stale receipt_sha256 is left unchanged.
    sql("UPDATE programacion.provenance_receipts SET "
        "payload=jsonb_set(payload,'{security_gate}','\"FAIL\"'::jsonb) "
        f"WHERE id={rid};")
    check("TAMPERED_RECEIPT_BLOCKED",
          promote(rid)["code"]=="EXTERNAL_ACTION_RECEIPT_NOT_VERIFIED")
    sql("UPDATE programacion.provenance_receipts SET "
        "payload=jsonb_set(payload,'{security_gate}','\"PASS\"'::jsonb) "
        f"WHERE id={rid};")
    check("TAMPER_RESTORE_NO_EFFECT",status()=="CANDIDATO")

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

    result=json.loads(sql(f"SELECT public.lf_rule_promotion_complete_tracked_v1("
      f"'{PARENT}','B2B-AUTH-001','{RULE}',{rid});"))
    check("ACTUAL_AUTO_APPLY_VERIFIED",result.get("status")=="APPLIED_VERIFIED")
    check("PROMOTION_MARK_VIGENTE_FILTER",sql(
      "SELECT count(*) FROM public.v_lf_rule_authority_filter_v1 "
      f"WHERE regla_codigo='{RULE}' AND marca='PROMOVIDA_VERIFICADA';")=="1")
    check("PROMOTION_LEDGER_MARK_PERSISTED",sql(
      "SELECT count(*) FROM public.lf_rule_authority_tracking_v1 "
      f"WHERE rule_code='{RULE}' AND marca='PROMOTED_VERIFIED' "
      "AND estado_flujo='VIGENTE_VERIFICADA';")=="1")
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
