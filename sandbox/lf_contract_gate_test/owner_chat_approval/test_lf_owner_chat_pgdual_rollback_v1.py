"""B2B-AUTH-002 Recuperar acceso: real request/decide/apply, PG17.6/18.7, ROLLBACK.

Source of promotion functions: frozen LF live-source fixture + production
IG0815 patch; candidate migration patches decide_v1 with its real MD5 guard.
NO doubles for public.lf_rule_promotion_decide_v1 or apply_v1.
The user message, approvals, PR and RUN below are SYNTHETIC fixtures only.
"""
import os
import re
import shutil
import subprocess
import sys
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "sandbox/lf_contract_gate_test/edge_function_operation"))
from test_lf_ig0815_auto_score_promotion_pgdual_v1 import (
    SCHEMA, SOURCE, MIGRATION as IG0815_MIGRATION
)

MIGRATION = ROOT / "supabase/migrations/20261117000100_lf_owner_chat_verified_receipt_guard_v1.sql"
RECOVERY = "B2B-AUTH-002"
SCREEN_ID = 52
RUN = "EXEC-RECOVERY-B2B-AUTH-002-FIXTURE"
PROMOTABLE = (
    "B2B-RULE-AUTH-027", "B2B-RULE-AUTH-028", "B2B-RULE-AUTH-042",
    "B2B-RULE-AUTH-044", "B2B-RULE-AUTH-045", "B2B-RULE-COMPAT-001"
)
PENDING = "B2B-RULE-THEME-002"
VIGENTE = (
    "B2B-RULE-A11Y-001","B2B-RULE-A11Y-002","B2B-RULE-A11Y-003",
    "B2B-RULE-A11Y-004","B2B-RULE-ANALYTICS-001","B2B-RULE-AUDIT-001",
    "B2B-RULE-AUTH-001","B2B-RULE-AUTH-046","B2B-RULE-CONTEXT-001",
    "B2B-RULE-DESIGN-001","B2B-RULE-DESIGN-002","B2B-RULE-ERROR-001",
    "B2B-RULE-ERROR-002","B2B-RULE-ERROR-003","B2B-RULE-INPUT-APPLICABILITY-001",
    "B2B-RULE-LOGO-001","B2B-RULE-OBS-001","B2B-RULE-OBS-002",
    "B2B-RULE-PERF-001","B2B-RULE-PRIVACY-001","B2B-RULE-PROD-001",
    "B2B-RULE-RATE-001","B2B-RULE-THEME-001","B2B-RULE-THEME-003",
    "B2B-RULE-TIMEOUT-001"
)
assert len(PROMOTABLE)==6 and len(VIGENTE)==25
assert len(set(PROMOTABLE + VIGENTE + (PENDING,)))==32

SETUP = r"""
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE SCHEMA private;
CREATE SCHEMA programacion;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE FUNCTION programacion.fn_v09_canonical_jsonb_text(j jsonb)
 RETURNS text LANGUAGE SQL IMMUTABLE STRICT AS $$
 SELECT j::text $$;
CREATE FUNCTION programacion.fn_v09_sha256_jsonb(j jsonb)
 RETURNS text LANGUAGE SQL IMMUTABLE STRICT AS $$
 SELECT encode(extensions.digest(convert_to(programacion.fn_v09_canonical_jsonb_text(j),'UTF8'),'sha256'),'hex') $$;
CREATE TABLE lf_ops.pantallas(id integer PRIMARY KEY,codigo text,nombre text,flujo text);
CREATE TABLE lf_ops.reglas_pantallas(regla_codigo text,pantalla_id integer);
INSERT INTO lf_ops.pantallas VALUES
 (52,'B2B-AUTH-002','Recuperar acceso','BACKOFFICE_B2B');
"""
def sqlarr(values):
    return "ARRAY["+",".join("'"+x+"'" for x in values)+"]::text[]"

SEED = r"""
INSERT INTO lf_ops.reglas(codigo,estado,categoria,pendiente_decision,updated_at)
SELECT code,
 CASE WHEN code=ANY(%(vigente)s) THEN 'VIGENTE' ELSE 'CANDIDATO' END,
 CASE WHEN code='B2B-RULE-COMPAT-001' THEN 'COMPATIBILITY'
      WHEN code='B2B-RULE-THEME-002' THEN 'THEME' ELSE 'SECURITY' END,
 code='B2B-RULE-THEME-002',now()-interval '2 hours'
FROM unnest(%(all_codes)s) AS code;
INSERT INTO lf_ops.reglas_pantallas
SELECT codigo,52 FROM lf_ops.reglas;
INSERT INTO public.lf_operation_execution
 (execution_id,operation_code,target_code,status)
VALUES ('%(run)s','EJECUCION_PERFIL_LF','PERFIL-PRODUCT-DIRECTOR-LF','COMPLETED');
INSERT INTO public.lf_profile_write_authority_v1
VALUES ('PERFIL-PRODUCT-DIRECTOR-LF','PROMOCION_REGLA_LF','ACTIVE');
INSERT INTO public.lf_operation_execution_steps
 (execution_id,step_order,step_id,status,evidence_payload,observed_at)
SELECT '%(run)s',n,
 CASE n WHEN 0 THEN 'init_execution' WHEN 10 THEN 'router'
 WHEN 20 THEN 'profile_resolve' WHEN 30 THEN 'profile_source_read'
 WHEN 40 THEN 'input_validate' WHEN 45 THEN 'context_admission'
 WHEN 47 THEN 'research_baseline_freeze' WHEN 50 THEN 'execute_profile'
 WHEN 60 THEN 'output_validate' WHEN 70 THEN 'semantic_judge'
 ELSE 'report_output' END,
 'STEP_PASS_WITH_EVIDENCE',
 CASE n WHEN 40 THEN jsonb_build_object(
   'scope_authority_packet_sha256','sha256:'||repeat('b',64))
 WHEN 50 THEN jsonb_build_object('raw_output_sha256',repeat('a',64),
   'profile_output',jsonb_build_object('deliverable_created',
      jsonb_build_object('product_decision',jsonb_build_object(
        'source_refs',(SELECT jsonb_agg(jsonb_build_object(
          'source_ref','supabase://lf_ops.reglas/'||code))
          FROM unnest(%(promotable)s) AS code)))))
 WHEN 60 THEN jsonb_build_object('raw_output_sha256',repeat('a',64))
 WHEN 70 THEN jsonb_build_object('semantic_judge_result',
    jsonb_build_object('verdict','PASS_REVIEWED_CURRENT_CONTEXT',
     'candidate_sha256',repeat('a',64),'scope_packet_sha256',repeat('b',64),
     'judge_v3_evidence',jsonb_build_object('unsupported_claims','[]'::jsonb)))
 ELSE '{}'::jsonb END,
 now()
FROM unnest(ARRAY[0,10,20,30,40,45,47,50,60,70,80]) AS n;
""" % {
    "all_codes":sqlarr(VIGENTE+PROMOTABLE+(PENDING,)),
    "vigente":sqlarr(VIGENTE), "promotable":sqlarr(PROMOTABLE), "run":RUN
}

TEST = r"""
DO $e2e$
DECLARE
  sc jsonb; r jsonb; ids text[]; v jsonb; oid uuid; msg text;
  wrong_sc jsonb; snap text; codes text[]; lit text; n integer;
  pr_sc jsonb; pr_order uuid; v_direct jsonb; first_id text;
BEGIN
  IF (SELECT count(*) FROM lf_ops.reglas_pantallas WHERE pantalla_id=52)<>32 OR
     (SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO')<>7 OR
     (SELECT count(*) FROM lf_ops.reglas WHERE estado='VIGENTE')<>25 OR
     (SELECT count(*) FROM lf_ops.reglas
        WHERE codigo='B2B-RULE-THEME-002' AND pendiente_decision)<>1
  THEN RAISE EXCEPTION 'RECOVERY_SCOPE_SEED_DRIFT'; END IF;
  -- All 6 source-bound requests use the actual LF request_v1.
  FOR msg IN SELECT unnest(%(codes)s) LOOP
    v:=public.lf_rule_promotion_request_v1('%(run)s',msg,'RECOVERY_FIXTURE_ONLY');
    IF v->>'status' IS DISTINCT FROM 'PENDING_HUMAN_APPROVAL'
    THEN RAISE EXCEPTION 'RECOVERY_REQUEST_NOT_MANUAL:%:%',msg,v; END IF;
  END LOOP;
  SELECT array_agg(promotion_id ORDER BY rule_code),
   array_agg(rule_code ORDER BY rule_code),
   programacion.fn_v09_sha256_jsonb(
    jsonb_agg(jsonb_build_object('rule_code',rule_code,
      'snapshot_sha256',request_snapshot_sha256) ORDER BY rule_code))
  INTO ids,codes,snap FROM public.lf_rule_promotion_v1
  WHERE request_execution_id='%(run)s';
  IF cardinality(ids)<>6 OR codes IS DISTINCT FROM %(codes)s
  THEN RAISE EXCEPTION 'RECOVERY_PROMOTION_COHORT_DRIFT'; END IF;
  first_id:=ids[1];
  v_direct:=public.lf_rule_promotion_decide_v1(first_id,'APPROVE',
    'HUMAN:Cristhian Lujan','DIRECT_WITHOUT_CHAT');
  IF v_direct->>'blocking_code' IS DISTINCT FROM 'CHAT_OWNER_HUMAN_BATCH_RECEIPT_REQUIRED'
  THEN RAISE EXCEPTION 'RECOVERY_DIRECT_HUMAN_BYPASS:%',v_direct; END IF;
  sc:=jsonb_build_object('action','PROMOTE_RULE_BATCH',
   'repository','cristhianlujan/claude-persona-lf-patch',
   'execution_id','%(run)s','rule_codes',to_jsonb(codes),
   'rule_snapshots_sha256',snap);
  lit:='APRUEBO '||left(programacion.fn_v09_sha256_jsonb(sc),12)||
     ' '||programacion.fn_v09_canonical_jsonb_text(sc);
  -- No order: must fail and leave all 6 pending.
  BEGIN
    PERFORM private.fn_lf_owner_chat_promote_batch_v1(gen_random_uuid(),ids,
      'Cristhian Lujan','fixture');
    RAISE EXCEPTION 'NEG_NO_ORDER_UNBLOCKED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='NEG_NO_ORDER_UNBLOCKED' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'CHAT_OWNER_PROMOTION_NO_VALID_ORDER:%'
    THEN RAISE EXCEPTION 'NEG_NO_ORDER_OTHER_ERROR:%',SQLERRM; END IF;
  END;
  -- Different cohort: receipt is intact but cannot approve the target six.
  wrong_sc:=jsonb_set(sc,'{rule_codes}',to_jsonb(codes[1:5]));
  msg:='APRUEBO '||left(programacion.fn_v09_sha256_jsonb(wrong_sc),12)||
      ' '||programacion.fn_v09_canonical_jsonb_text(wrong_sc);
  v:=private.fn_lf_owner_chat_register_v1('fixture-recovery-chat-0001',
   'fixture-recovery-wrong-scope-01','CHAT_ORCHESTRATOR_USER_TURN',
   'Cristhian Lujan','fixture-proposer-01','fixture-recorder-01',
   clock_timestamp(),msg,wrong_sc);
  oid:=(v->>'order_id')::uuid;
  BEGIN
    PERFORM private.fn_lf_owner_chat_promote_batch_v1(oid,ids,
      'Cristhian Lujan','fixture');
    RAISE EXCEPTION 'NEG_SCOPE_UNBLOCKED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='NEG_SCOPE_UNBLOCKED' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'CHAT_OWNER_PROMOTION_NO_VALID_ORDER:%'
    THEN RAISE EXCEPTION 'NEG_SCOPE_OTHER_ERROR:%',SQLERRM; END IF;
  END;
  v:=private.fn_lf_owner_chat_register_v1('fixture-recovery-chat-0001',
   'fixture-recovery-expired-0001','CHAT_ORCHESTRATOR_USER_TURN',
   'Cristhian Lujan','fixture-proposer-01','fixture-recorder-01',
   clock_timestamp(),lit,sc);
  oid:=(v->>'order_id')::uuid;
  UPDATE private.lf_owner_chat_orders_v1 SET
    sent_at=transaction_timestamp()-interval '20 minutes',
    expires_at=transaction_timestamp()-interval '5 minutes' WHERE order_id=oid;
  BEGIN
    PERFORM private.fn_lf_owner_chat_promote_batch_v1(oid,ids,
      'Cristhian Lujan','fixture');
    RAISE EXCEPTION 'NEG_EXPIRED_UNBLOCKED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='NEG_EXPIRED_UNBLOCKED' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'CHAT_OWNER_PROMOTION_NO_VALID_ORDER:%'
    THEN RAISE EXCEPTION 'NEG_EXPIRED_OTHER_ERROR:%',SQLERRM; END IF;
  END;
  v:=private.fn_lf_owner_chat_register_v1('fixture-recovery-chat-0001',
   'fixture-recovery-revoked-0001','CHAT_ORCHESTRATOR_USER_TURN',
   'Cristhian Lujan','fixture-proposer-01','fixture-recorder-01',
   clock_timestamp(),lit,sc);
  oid:=(v->>'order_id')::uuid;
  v:=private.fn_lf_owner_chat_revoke_v1(oid,'fixture-recovery-revoke-msg',
     'Cristhian Lujan','fixture-only');
  IF v->>'status' IS DISTINCT FROM 'REVOKED'
    THEN RAISE EXCEPTION 'NEG_REVOKE_SETUP:%',v; END IF;
  BEGIN
    PERFORM private.fn_lf_owner_chat_promote_batch_v1(oid,ids,
      'Cristhian Lujan','fixture');
    RAISE EXCEPTION 'NEG_REVOKED_UNBLOCKED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='NEG_REVOKED_UNBLOCKED' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'CHAT_OWNER_PROMOTION_NO_VALID_ORDER:%'
    THEN RAISE EXCEPTION 'NEG_REVOKED_OTHER_ERROR:%',SQLERRM; END IF;
  END;
  BEGIN
    PERFORM private.fn_lf_owner_chat_register_v1('fixture-recovery-chat-0001',
     'fixture-recovery-self-000001','CHAT_ORCHESTRATOR_USER_TURN',
     'Cristhian Lujan','fixture-proposer-01','fixture-proposer-01',
     clock_timestamp(),lit,sc);
    RAISE EXCEPTION 'NEG_SELF_APPROVAL_UNBLOCKED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM='NEG_SELF_APPROVAL_UNBLOCKED' THEN RAISE; END IF;
    IF SQLERRM NOT LIKE 'CHAT_OWNER_ORCHESTRATOR_EVENT_OR_SEPARATION_INVALID%'
    THEN RAISE EXCEPTION 'NEG_SELF_APPROVAL_OTHER_ERROR:%',SQLERRM; END IF;
  END;
  IF EXISTS(SELECT 1 FROM public.lf_rule_promotion_v1
    WHERE request_execution_id='%(run)s' AND status<>'PENDING')
  THEN RAISE EXCEPTION 'NEGATIVE_SIDE_EFFECT_LEAK'; END IF;
  -- Valid original owner USER order: real decide_v1 and real apply_v1.
  v:=private.fn_lf_owner_chat_register_v1('fixture-recovery-chat-0001',
   'fixture-recovery-valid-000001','CHAT_ORCHESTRATOR_USER_TURN',
   'Cristhian Lujan','fixture-proposer-01','fixture-recorder-01',
   clock_timestamp(),lit,sc);
  oid:=(v->>'order_id')::uuid;
  v:=private.fn_lf_owner_chat_promote_batch_v1(oid,ids,
     'Cristhian Lujan','RECOVERY_FIXTURE_ONLY');
  IF v->>'status' IS DISTINCT FROM 'APPLIED' OR (v->>'count')::integer<>6
  THEN RAISE EXCEPTION 'RECOVERY_VALID_ORDER_NOT_APPLIED:%',v; END IF;
  SELECT count(*) INTO n FROM public.lf_rule_promotion_v1 WHERE status='APPLIED';
  IF n<>6 OR (SELECT count(*) FROM lf_ops.reglas
       WHERE codigo=ANY(%(codes)s) AND estado='VIGENTE')<>6 OR
     (SELECT estado FROM lf_ops.reglas WHERE codigo='B2B-RULE-THEME-002')<>'CANDIDATO'
  THEN RAISE EXCEPTION 'RECOVERY_APPLY_READBACK_MISMATCH'; END IF;
  v:=private.fn_lf_owner_chat_consume_v1(oid,'PROMOTE_RULE_BATCH',sc,
      'Cristhian Lujan','REPLAY');
  IF v->>'code' IS DISTINCT FROM 'CHAT_ORDER_REUSED'
  THEN RAISE EXCEPTION 'NEG_REPLAY_UNBLOCKED:%',v; END IF;
  -- Exact HEAD for governance PR, independent action and second unique order.
  pr_sc:=jsonb_build_object('action','MERGE_GOVERNANCE_PR',
    'repository','cristhianlujan/claude-persona-lf-patch',
    'pr_number',4063,'head_sha','%(head)s');
  msg:='APRUEBO '||left(programacion.fn_v09_sha256_jsonb(pr_sc),12)||
       ' '||programacion.fn_v09_canonical_jsonb_text(pr_sc);
  v:=private.fn_lf_owner_chat_register_v1('fixture-recovery-chat-0001',
    'fixture-recovery-merge-000001','CHAT_ORCHESTRATOR_USER_TURN',
    'Cristhian Lujan','fixture-proposer-01','fixture-recorder-01',
    clock_timestamp(),msg,pr_sc);
  pr_order:=(v->>'order_id')::uuid;
  v:=private.fn_lf_owner_chat_train_merge_gate_v1(pr_order,
     'cristhianlujan/claude-persona-lf-patch',4063,repeat('c',40),
     'Cristhian Lujan','TRAIN-TEST-RECOVERY');
  IF v->>'status' IS DISTINCT FROM 'BLOCKED'
  THEN RAISE EXCEPTION 'RECOVERY_MERGE_WRONG_HEAD_UNBLOCKED:%',v; END IF;
  v:=private.fn_lf_owner_chat_train_merge_gate_v1(pr_order,
     'cristhianlujan/claude-persona-lf-patch',4063,'%(head)s',
     'Cristhian Lujan','TRAIN-TEST-RECOVERY');
  IF v->>'status' IS DISTINCT FROM 'AUTHORIZED_FOR_TRAIN_ONLY'
  THEN RAISE EXCEPTION 'RECOVERY_MERGE_VALID_HEAD_BLOCKED:%',v; END IF;
  v:=private.fn_lf_owner_chat_train_merge_gate_v1(pr_order,
     'cristhianlujan/claude-persona-lf-patch',4063,'%(head)s',
     'Cristhian Lujan','TRAIN-TEST-RECOVERY');
  IF v->>'status' IS DISTINCT FROM 'BLOCKED'
  THEN RAISE EXCEPTION 'RECOVERY_MERGE_REPLAY_UNBLOCKED:%',v; END IF;
  RAISE NOTICE 'PASS_RECOVERY_B2B_AUTH_002_REAL_DECIDE_APPLY_6_PROMOTIONS_AND_MERGE_HEAD PG';
END $e2e$;
""" % {"codes":sqlarr(PROMOTABLE),"run":RUN,"head":"b"*40}

class RecoveryRealDecidePgDual(unittest.TestCase):
    def test_pg17_pg18_real_patched_decide_with_rollback(self):
        self.assertTrue(shutil.which("docker"),"DOCKER_REQUIRED_TO_PROVE_PG17_PG18")
        migrate = MIGRATION.read_text(encoding="utf-8")
        self.assertTrue(migrate.startswith("-- Source-only"))
        self.assertTrue(migrate.rstrip().endswith("COMMIT;"))
        # DO not remove the actual guarded patch of decide_v1.
        self.assertIn("CHAT_OWNER_DECIDE_V1_BASE_DRIFT",migrate)
        migrate = re.sub(r"(?m)^BEGIN;\s*$","",migrate,count=1)
        migrate = re.sub(r"(?m)^COMMIT;\s*$","",migrate,count=1)
        head=os.getenv("LF_TEST_HEAD_SHA","b"*40)
        self.assertRegex(head,r"^[a-f0-9]{40}$")
        test_sql=TEST.replace("'"+"b"*40+"'", "'"+head+"'")
        setup=SCHEMA+"\n"+SOURCE.read_text(encoding="utf-8")+"\n"+IG0815_MIGRATION.read_text(encoding="utf-8")+"\n"+SETUP
        for version in ("17.6","18.7"):
            with self.subTest(postgres=version):
                name="lf-recovery-owner-"+uuid.uuid4().hex[:10]
                x=subprocess.run(["docker","run","-d","--rm","--name",name,
                   "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+version],
                   capture_output=True,text=True,timeout=180)
                self.assertEqual(x.returncode,0,x.stderr)
                try:
                    for _ in range(90):
                        ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
                            capture_output=True,text=True,timeout=15)
                        if ready.returncode==0:
                            logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=15)
                            if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):
                                break
                        time.sleep(.5)
                    self.assertEqual(ready.returncode,0,"PG_NOT_READY")
                    def psql(sql):
                        v=subprocess.run(["docker","exec","-i",name,"psql","-X",
                          "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
                          input=sql,capture_output=True,text=True,timeout=240)
                        self.assertEqual(v.returncode,0,v.stderr[-7000:]+"\n"+v.stdout[-3000:])
                        return v.stdout+"\n"+v.stderr
                    psql(setup)
                    out=psql("BEGIN;\n"+migrate+"\n"+SEED+"\n"+test_sql+"\nROLLBACK;\n"
                        +"SELECT CASE WHEN to_regclass('private.lf_owner_chat_orders_v1') IS NULL "
                        +"THEN 'RECOVERY_ROLLBACK_CLEAN' ELSE 'DIRTY' END;\n")
                    self.assertIn("PASS_RECOVERY_B2B_AUTH_002_REAL_DECIDE_APPLY_6_PROMOTIONS_AND_MERGE_HEAD",out)
                    self.assertIn("RECOVERY_ROLLBACK_CLEAN",out)
                    print("PASS_RECOVERY_REAL_DECIDE_PG"+version+"_BEGIN_ROLLBACK",flush=True)
                finally:
                    subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)
if __name__=="__main__":unittest.main()
