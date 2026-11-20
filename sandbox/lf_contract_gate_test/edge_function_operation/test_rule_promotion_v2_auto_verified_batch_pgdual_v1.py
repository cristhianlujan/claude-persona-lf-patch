"""LF V2 auto-promotion PG17.6/18.7: exactly 64 source-selected rule IDs.
Actual V1/V2 and canonical writer function source frozen via SELECT.
Positive owner/Judge are SYNTHETIC ONLY in disposable PG, never live credentials.
Every new change (including 64 VIGENTE updates) is inside BEGIN/ROLLBACK.
"""
from pathlib import Path
import json
import shutil
import subprocess
import time
import unittest
import uuid

ROOT=Path(__file__).resolve().parents[3]
V1=ROOT/"sandbox/lf_contract_gate_test/edge_function_operation/fixtures/lf_rule_promotion_v1_live_defs_20261114.sql"
WRITERS=ROOT/"sandbox/lf_contract_gate_test/edge_function_operation/fixtures/lf_rule_promotion_canonical_writers_live_20261114.sql"
V2=ROOT/"supabase/migrations/20261114185545_lf_rule_promotion_dual_gate_scope_evidence_v2.sql"
NEW=list((ROOT/"supabase/migrations").glob("*_lf_rule_promotion_v2_attested_auto_batch_audit_v1.sql"))
SELECT_SNAPSHOT=ROOT/"docs/rule-promotion/07_rule_promotion_preview_64_and_190_findings_20261114.json"

BASE=r"""
CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
CREATE SCHEMA lf_ops; CREATE SCHEMA programacion; CREATE SCHEMA private;
CREATE TABLE lf_ops.reglas(
 id integer PRIMARY KEY, codigo text UNIQUE NOT NULL, estado text NOT NULL,
 categoria text,valor_config jsonb,es_transversal boolean,razon text,
 pendiente_decision boolean,pendiente_detalle text);
CREATE TABLE lf_ops.reglas_pantallas(regla_id integer,pantalla_id integer);
CREATE TABLE lf_ops.politicas_seguridad(policy_code text);
CREATE TABLE lf_ops.real_business_table(id int);
CREATE TABLE public.lf_operation_contracts(operation_code text,contract_sha text);
INSERT INTO public.lf_operation_contracts VALUES('EJECUCION_PERFIL_LF','sha-catalog');
CREATE TABLE public.lf_error_knowledge(
 id uuid,codigo text,categoria text,titulo text,descripcion text,causa_raiz text,
 patron text,prevencion text,validacion text,severidad text,frecuencia int,
 primera_vez timestamptz,ultima_vez timestamptz,lote_origen text,pr text,
 estado text,evidencia text,created_at timestamptz,updated_at timestamptz,
 lifecycle_phase text,consumer_role text[],root_cause_family text,
 detectability text,source_context text,source_ref text);
CREATE FUNCTION public.lf_rule_promotion_request_v1(text,text,text)
 RETURNS jsonb LANGUAGE sql AS $$SELECT '{}'::jsonb$$;
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,operation_code text,target_code text,status text);
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text,step_order int,step_id text,status text,evidence_payload jsonb);
CREATE TABLE public.lf_profile_write_authority_v1(
 profile_code text,operation_code text,status text);
INSERT INTO public.lf_profile_write_authority_v1 VALUES
 ('PERFIL-PRODUCT-DIRECTOR-LF','PROMOCION_REGLA_LF','ACTIVE');
INSERT INTO public.lf_operation_execution VALUES
 ('EXEC-V2-FIXTURE-64','EJECUCION_PERFIL_LF','PERFIL-PRODUCT-DIRECTOR-LF','IN_PROGRESS');
CREATE TABLE public.lf_rule_promotion_v1 (
 promotion_id text PRIMARY KEY DEFAULT 'PROM-'||upper(substr(md5(random()::text||clock_timestamp()::text),1,16)),
 rule_code text, request_execution_id text,requested_by_profile text,
 request_snapshot_sha256 text,status text NOT NULL DEFAULT 'PENDING',
 reason text,decided_by text,decided_at timestamptz,applied_at timestamptz,
 created_at timestamptz DEFAULT now());
CREATE TABLE private.lf_human_decision_requests_v1 (
 request_id uuid PRIMARY KEY,producer_code text,subject_type text,subject_key text,
 currentness_sha256 text,required_reviewer_role text,required_authority_ref text,
 request_sha256 text,status text);
CREATE TABLE private.lf_human_decision_receipts_v1 (
 receipt_id uuid PRIMARY KEY,request_id uuid,
 decision_code text,decision_payload jsonb,reviewer_identity text,reviewer_role text,
 authority_ref text,authority_receipt_ref text,authority_receipt_sha256 text,
 observed_currentness_sha256 text,receipt_sha256 text,metadata jsonb);
-- The synthetic verifier is only present in disposable tests.
-- In deployed sandbox this binds to the existing canonical provenance writer.
CREATE FUNCTION private.fn_lf_human_decision_assert_authority_receipt_v1(
 uuid,text,text,text,text,text,text)
RETURNS boolean LANGUAGE sql AS $$SELECT true$$;
CREATE FUNCTION private.fn_lf_human_decision_receipt_sha_v1(
 uuid,text,text,jsonb,text,text,text,text,text,text,jsonb)
RETURNS text LANGUAGE sql AS $$SELECT repeat('e',64)$$;
CREATE FUNCTION public.lf_asset_snapshot_sha_v1(text,text)
 RETURNS text LANGUAGE sql STABLE AS $$
 SELECT encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex')
 FROM lf_ops.reglas r WHERE r.codigo=$2;
 $$;
"""

def inner(sql: str):
 assert "\nBEGIN;\n" in sql and "\nCOMMIT;" in sql
 return sql.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;",1)[0]

class RealWriterIntegrationPgDual(unittest.TestCase):
 def test_auto_64_synthetic_verified_receipt_and_rollback(self):
  self.assertEqual(len(NEW),1,"one governed migration / Train")
  self.assertIsNotNone(shutil.which("docker"))
  src=NEW[0].read_text("utf-8")
  self.assertIn("lf_rule_promotion_decide_batch_v1(",src)
  self.assertIn("lf_rule_promotion_apply_batch_v1(",src)
  self.assertIn("lf_rule_promotion_request_v1(",src)
  self.assertIn("fn_lf_human_decision_assert_authority_receipt_v1(",src)
  self.assertNotIn("UPDATE lf_ops.reglas SET estado='VIGENTE'",src)
  rules=json.loads(SELECT_SNAPSHOT.read_text("utf-8"))["automatic_preview"]
  self.assertEqual(len(rules),64)
  self.assertEqual(len({r["rule_id"] for r in rules}),64)
  seed=""
  for r in rules:
   c=r["code"].replace("'","''")
   seed+=(f"INSERT INTO lf_ops.reglas VALUES({r['rule_id']},'{c}',"
           "'CANDIDATO','RULE','{}'::jsonb,false,'source',false,null);\n")
   seed+=(f"INSERT INTO lf_ops.reglas_pantallas VALUES({r['rule_id']},44);\n")
  # Four specifically excluded candidates; two historical VIGENTE.
  for i in (438,439,440,577):
   seed+=(f"INSERT INTO lf_ops.reglas VALUES({i},'IDENTITY_{i}',"
          "'CANDIDATO','AUTH','{\"owner_decision_identity_verified\":false}'::jsonb,"
          "false,'identity',false,null);\n"
          f"INSERT INTO lf_ops.reglas_pantallas VALUES({i},44);\n")
  for i in (235,532):
   seed+=(f"INSERT INTO lf_ops.reglas VALUES({i},'IDENTITY_{i}',"
          "'VIGENTE','AUTH','{\"owner_decision_identity_verified\":false}'::jsonb,"
          "false,'identity',true,null);\n")
  seed+="INSERT INTO lf_ops.reglas VALUES (390,'HOLD_PENDING','CANDIDATO','THEME','{}'::jsonb,false,'pending',true,null);\n"
  seed+="INSERT INTO lf_ops.reglas_pantallas VALUES (390,44);\n"
  seed+="INSERT INTO lf_ops.reglas VALUES (614,'REVIEW_SCOPE','CANDIDATO','UX','{}'::jsonb,false,'review',false,null);\n"
  # Canonical Product Director run synthetic exact Step40/50/60/70 required by V1 request.
  seed+=r"""
WITH v AS (SELECT jsonb_agg(jsonb_build_object(
   'source_ref','supabase://lf_ops.reglas/'||codigo) ORDER BY id) refs
 FROM lf_ops.reglas WHERE id IN(
"""
  seed+=",".join(str(r["rule_id"]) for r in rules)
  seed+=r"""))
INSERT INTO public.lf_operation_execution_steps
SELECT 'EXEC-V2-FIXTURE-64',50,'execute_profile','STEP_PASS_WITH_EVIDENCE',
 jsonb_build_object('raw_output_sha256',repeat('a',64),
 'profile_output',jsonb_build_object('deliverable_created',
 jsonb_build_object('product_decision',jsonb_build_object('source_refs',v.refs))))
FROM v;
INSERT INTO public.lf_operation_execution_steps VALUES
 ('EXEC-V2-FIXTURE-64',40,'input_validate','STEP_PASS_WITH_EVIDENCE',
  jsonb_build_object('scope_authority_packet_sha256','sha256:'||repeat('b',64))),
 ('EXEC-V2-FIXTURE-64',60,'output_validate','STEP_PASS_WITH_EVIDENCE',
  jsonb_build_object('raw_output_sha256',repeat('a',64))),
 ('EXEC-V2-FIXTURE-64',70,'semantic_judge','STEP_PASS_WITH_EVIDENCE',
 jsonb_build_object('semantic_judge_result',jsonb_build_object(
 'verdict','PASS_INDEPENDENT_SEMANTIC','producer_independence_proven',true,
 'model_call_count',2,'candidate_sha256',repeat('a',64),
 'scope_packet_sha256',repeat('b',64),'judge_v3_evidence',jsonb_build_object(
 'judge_invocation_kind','NEW_INDEPENDENT_CURRENT_CHAT_GPT_NATIVE',
 'judge_role','INDEPENDENT_REVIEWER_FIXTURE','unsupported_claims','[]'::jsonb))));
"""
  for image in ("17.6","18.7"):
   with self.subTest(pg=image):
    name="lf-promov2-"+uuid.uuid4().hex[:10]
    start=subprocess.run(["docker","run","-d","--rm","--name",name,
      "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+image],
      capture_output=True,text=True,timeout=180)
    self.assertEqual(start.returncode,0,start.stderr)
    try:
     rdy=None
     for _ in range(100):
      rdy=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],capture_output=True,timeout=8)
      logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=8)
      if rdy.returncode==0 and "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):
       break
      time.sleep(.7)
     self.assertEqual(rdy.returncode,0)
     def psql(src):
      return subprocess.run(["docker","exec","-i",name,"psql","-X","-Atq",
       "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
       input=src,capture_output=True,text=True,timeout=150)
     setup=psql(BASE+"\n"+V1.read_text("utf-8")+"\n"+V2.read_text("utf-8")+
       "\n"+WRITERS.read_text("utf-8")+"\n"+
       "CREATE TRIGGER trg_lf_rule_promotion_guard_v1 BEFORE UPDATE OF estado "
       "ON lf_ops.reglas FOR EACH ROW EXECUTE FUNCTION public.lf_rule_promotion_guard_v1();\n"+
       seed)
     self.assertEqual(setup.returncode,0,setup.stderr[-6500:])
     check=r"""
DO $test$
DECLARE v jsonb; o jsonb; ids jsonb; sha text; aid bigint; rev_sha text;
BEGIN
 v:=public.lf_rule_promotion_v2_auto_plan_v1();
 IF (v->>'eligible_count')::int<>64 THEN RAISE EXCEPTION 'PLAN_NOT_64:%',v; END IF;
 -- User message/unverified chat is NOT an authenticated receipt.
 o:=public.lf_rule_promotion_v2_auto_execute_v1('EXEC-V2-FIXTURE-64',NULL);
 IF o->>'code'<>'OWNER_VERIFIED_RECEIPT_MISSING' OR (o->>'applied')::int<>0
 THEN RAISE EXCEPTION 'MISSING_OWNER_ALLOWED:%',o; END IF;
 IF (SELECT count(*) FROM public.lf_rule_promotion_v1)<>0
 THEN RAISE EXCEPTION 'OWNER_DENIAL_WROTE_REQUEST'; END IF;
 SELECT jsonb_agg((z.value->>'rule_id')::bigint ORDER BY (z.value->>'rule_id')::bigint)
  INTO ids FROM jsonb_array_elements(v->'rules') z;
 sha:=v->>'plan_sha256';
 INSERT INTO private.lf_human_decision_requests_v1 VALUES
 ('12345678-1234-4000-8000-000000000001','RULE_PROMOTION',
  'LF_RULE_PROMOTION_BATCH_V2','EXEC-V2-FIXTURE-64',
  sha,'LF_OWNER','contract://LF_OWNER_RULE_PROMOTION_V2',repeat('c',64),'DECIDED');
 -- This synthetic receipt stands for a cryptographically signed canonical one.
 INSERT INTO private.lf_human_decision_receipts_v1 VALUES
 ('12345678-1234-4000-8000-000000000011',
 '12345678-1234-4000-8000-000000000001','APPROVE',
 jsonb_build_object('rule_ids',ids),'github:cristhianlujan','LF_OWNER',
 'contract://LF_OWNER_RULE_PROMOTION_V2',
 'supabase://programacion/provenance_receipts/1',repeat('d',64),
 sha,repeat('e',64),'{}'::jsonb);
 -- False identity/authority must be rejected.
 UPDATE private.lf_human_decision_receipts_v1 SET reviewer_identity='HUMAN:fake'
 WHERE request_id='12345678-1234-4000-8000-000000000001';
 o:=public.lf_rule_promotion_v2_auto_execute_v1(
 'EXEC-V2-FIXTURE-64','12345678-1234-4000-8000-000000000001');
 IF o->>'code'<>'OWNER_RECEIPT_NOT_BOUND_OR_NOT_VERIFIED'
 THEN RAISE EXCEPTION 'FAKE_OWNER_ACCEPTED:%',o; END IF;
 UPDATE private.lf_human_decision_receipts_v1 SET reviewer_identity='github:cristhianlujan'
 WHERE request_id='12345678-1234-4000-8000-000000000001';
 -- Strong requirement: complete independent Step70 evidence, no shortcut.
 UPDATE public.lf_operation_execution_steps SET evidence_payload=
 jsonb_set(evidence_payload,'{semantic_judge_result,producer_independence_proven}','false'::jsonb)
 WHERE execution_id='EXEC-V2-FIXTURE-64' AND step_order=70;
 o:=public.lf_rule_promotion_v2_auto_execute_v1(
 'EXEC-V2-FIXTURE-64','12345678-1234-4000-8000-000000000001');
 IF o->>'code'<>'PROMOTION_INDEPENDENT_STEP70_NOT_ATTESTED_FOR_ALL_RULES'
 THEN RAISE EXCEPTION 'NON_INDEPENDENT_JUDGE_ACCEPTED:%',o; END IF;
 UPDATE public.lf_operation_execution_steps SET evidence_payload=
 jsonb_set(evidence_payload,'{semantic_judge_result,producer_independence_proven}','true'::jsonb)
 WHERE execution_id='EXEC-V2-FIXTURE-64' AND step_order=70;
 o:=public.lf_rule_promotion_v2_auto_execute_v1(
 'EXEC-V2-FIXTURE-64','12345678-1234-4000-8000-000000000001');
 IF o->>'status'<>'APPLIED_VERIFIED' OR (o->>'applied')::int<>64
 THEN RAISE EXCEPTION 'CANONICAL_BATCH_NOT_APPLIED_64:%',o; END IF;
 IF (SELECT count(*) FROM public.lf_rule_promotion_v1 WHERE status='APPLIED')<>64
 OR (SELECT count(*) FROM public.lf_rule_promotion_auto_audit_v1 WHERE status='APPLIED')<>64
 OR (SELECT count(*) FROM lf_ops.reglas WHERE estado='VIGENTE')<>66
 OR (SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO')<>6
 THEN RAISE EXCEPTION 'POST_BATCH_READBACK_FAILED'; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE id IN(438,439,440,577,390,614)
  AND estado<>'CANDIDATO') THEN RAISE EXCEPTION 'IDENTITY_HOLD_PROMOTED'; END IF;
 SELECT audit_id INTO aid FROM public.lf_rule_promotion_auto_audit_v1 ORDER BY audit_id LIMIT 1;
 o:=public.lf_rule_promotion_v2_auto_reverse_v1(aid,NULL);
 IF o->>'code'<>'OWNER_VERIFIED_RECEIPT_MISSING'
 THEN RAISE EXCEPTION 'REVERSION_NO_OWNER_ALLOWED:%',o; END IF;
 rev_sha:=encode(sha256(convert_to(jsonb_build_object(
 'schema_version','LF_RULE_V2_AUTO_REVERSAL_V1',
 'audit_id',aid,
 'rule_id',(SELECT rule_id FROM public.lf_rule_promotion_auto_audit_v1 WHERE audit_id=aid),
 'after_sha256',(SELECT applied_rule_snapshot_sha256
   FROM public.lf_rule_promotion_auto_audit_v1 WHERE audit_id=aid))::text,'UTF8')),'hex');
 INSERT INTO private.lf_human_decision_requests_v1 VALUES
 ('12345678-1234-4000-8000-000000000002','RULE_PROMOTION',
 'LF_RULE_PROMOTION_BATCH_V2','ROLLBACK:'||aid::text,
 rev_sha,'LF_OWNER','contract://LF_OWNER_RULE_PROMOTION_V2',repeat('c',64),'DECIDED');
 INSERT INTO private.lf_human_decision_receipts_v1 VALUES
 ('12345678-1234-4000-8000-000000000022',
 '12345678-1234-4000-8000-000000000002',
 'APPROVE_ROLLBACK',jsonb_build_object('rule_ids',
 jsonb_build_array((SELECT rule_id FROM public.lf_rule_promotion_auto_audit_v1
 WHERE audit_id=aid))),
 'github:cristhianlujan','LF_OWNER','contract://LF_OWNER_RULE_PROMOTION_V2',
 'supabase://programacion/provenance_receipts/2',repeat('d',64),
 rev_sha,repeat('e',64),'{}'::jsonb);
 o:=public.lf_rule_promotion_v2_auto_reverse_v1(
 aid,'12345678-1234-4000-8000-000000000002');
 IF o->>'status'<>'REVERTED_VERIFIED' OR
 (SELECT count(*) FROM public.lf_rule_promotion_auto_audit_v1
  WHERE status='REVERTED')<>1
 THEN RAISE EXCEPTION 'VERIFIED_REVERSE_FAILED:%',o; END IF;
 RAISE NOTICE 'PASS_64_SYNTHETIC_WRITER_BATCH_REVERSE';
END $test$;
SELECT 'APPLIED_LOG='||count(*) FROM public.lf_rule_promotion_auto_audit_v1;
SELECT 'PROMOTED_CANONICAL='||count(*) FROM public.lf_rule_promotion_v1 WHERE status='APPLIED';
SELECT 'CANDIDATE_AFTER='||count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO';
SELECT 'VIGENTE_AFTER='||count(*) FROM lf_ops.reglas WHERE estado='VIGENTE';
"""
     allsql="BEGIN;\n"+inner(src)+"\n"+check+"\nROLLBACK;\n"
     allsql+="SELECT 'POST_ROLLBACK_PROMOTION='||count(*) FROM public.lf_rule_promotion_v1;\n"
     allsql+="SELECT 'POST_ROLLBACK_CANDIDATE='||count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO';\n"
     allsql+="SELECT 'POST_ROLLBACK_VIGENTE='||count(*) FROM lf_ops.reglas WHERE estado='VIGENTE';\n"
     allsql+="SELECT 'POST_ROLLBACK_AUTO_TABLE='||(to_regclass('public.lf_rule_promotion_auto_audit_v1') IS NULL)::text;\n"
     rr=psql(allsql)
     self.assertEqual(rr.returncode,0,rr.stderr[-8000:])
     for token in ("APPLIED_LOG=64","PROMOTED_CANONICAL=64",
       "CANDIDATE_AFTER=7","VIGENTE_AFTER=65",
       "POST_ROLLBACK_PROMOTION=0","POST_ROLLBACK_CANDIDATE=70",
       "POST_ROLLBACK_VIGENTE=2","POST_ROLLBACK_AUTO_TABLE=true"):
      self.assertIn(token,rr.stdout,token+"\n"+rr.stdout[-3500:])
     print("PASS_LF_RULE_AUTO_V2_PG"+image+
       "_64_SYNTHETIC_STEP70_OWNER_BATCH_REVERSE_ROLLBACK_TRUE")
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)
