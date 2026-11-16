"""E21: exact E20 LIVE SQL handoff validator behavior under PG17/18 ROLLBACK.
Postgres is fixture-only; this test never creates a real profile execution.
The actual Edge 403 check is covered by Deno SQL-RPC mock tests.
"""
import subprocess,shutil,time,uuid,unittest
from test_lf_e20_promotion_handoff_pgdual_rollback_v1 import SETUP,FIX,BODY

ASSERTS=r"""
DO $e21$
DECLARE lit text;req jsonb;out jsonb;h jsonb;v jsonb;result jsonb;tampered jsonb;
BEGIN
 result:=jsonb_build_object('decision','RESOLVED',
    'semantic_receipt_sha256',repeat('d',64),
    'positive_target_refs',jsonb_build_array('PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'));

 -- Owner explicit positive: validator validates true, no Edge hard-coded veto.
 lit:='Repara y promociona las reglas de login B2B';
 req:=jsonb_build_object('literal_request',lit,
    'request_sha256',encode(extensions.digest(convert_to(lit,'UTF8'),'sha256'),'hex'),
    'router_action_binding',jsonb_build_object(
        'profile_task_intent','REPAIR_MISSING_PRODUCT_STRUCTURE'));
 out:=public.lf_router_profile_execution_handoff_v1(
      req,result,'PROGRAMACION','LF',
      '{"target_type":"PANTALLA","target_hint":"B2B-AUTH-001"}'::jsonb);
 h:=out->'handoff';
 v:=public.lf_router_profile_execution_handoff_validate_v1(
      h,lit,'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF');
 IF out->>'status'<>'READY' OR v->>'valid'<>'true'
    OR v->>'governed_repair_write_allowed'<>'true'
    OR v->>'promotion_allowed'<>'true'
    OR v->>'profile_code'<>'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
    OR v->>'profile_slug'<>'systemic_root_cause_repair_lf'
    OR v->>'repair_execution_authority_fingerprint_sha256'
       IS DISTINCT FROM h#>>'{repair_execution_authority,fingerprint_sha256}'
 THEN RAISE EXCEPTION 'E21_SQL_POSITIVE_HANDOFF_NOT_VALID:%',v; END IF;

 -- A tampered or mismatched handoff must NOT be SQL-validated.
 tampered:=jsonb_set(h,'{repair_execution_authority,promotion_allowed}','false'::jsonb);
 v:=public.lf_router_profile_execution_handoff_validate_v1(tampered,lit,
     'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF');
 IF v->>'valid'<>'false' THEN RAISE EXCEPTION 'E21_SQL_FINGERPRINT_BYPASS:%',v; END IF;
 tampered:=jsonb_set(h,'{profile_code}','"PERFIL-PRODUCT-DIRECTOR-LF"'::jsonb);
 v:=public.lf_router_profile_execution_handoff_validate_v1(tampered,lit,
      'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF');
 IF v->>'valid'<>'false' THEN RAISE EXCEPTION 'E21_SQL_PROFILE_BYPASS:%',v; END IF;

 -- Validated but no owner promotion: SQL returns false without hardcoding.
 lit:='Repara las reglas de login B2B sin promocionar';
 req:=jsonb_build_object('literal_request',lit,
    'request_sha256',encode(extensions.digest(convert_to(lit,'UTF8'),'sha256'),'hex'),
    'router_action_binding',jsonb_build_object(
        'profile_task_intent','REPAIR_MISSING_PRODUCT_STRUCTURE'));
 out:=public.lf_router_profile_execution_handoff_v1(
      req,result,'PROGRAMACION','LF','{"target_type":"PANTALLA"}'::jsonb);
 h:=out->'handoff';
 v:=public.lf_router_profile_execution_handoff_validate_v1(h,lit,
      'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF');
 IF v->>'valid'<>'true' OR v->>'promotion_allowed'<>'false' THEN
   RAISE EXCEPTION 'E21_SQL_NEGATIVE_OWNER_INTENT_NOT_VALID:%',v; END IF;
 -- A forged true after the validated negative MUST still be rejected.
 tampered:=jsonb_set(h,'{repair_execution_authority,promotion_allowed}','true'::jsonb);
 v:=public.lf_router_profile_execution_handoff_validate_v1(tampered,lit,
     'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF');
 IF v->>'valid'<>'false' THEN RAISE EXCEPTION 'E21_SQL_FORGED_TRUE_ACCEPTED:%',v; END IF;
END $e21$;
SELECT 'E21_SQL_VALIDATED_TRUE_FALSE_FORGED_BLOCKED=PASS';
"""

class E21SQLAuthorityPGDual(unittest.TestCase):
 def test_exact_sql_validator_true_false_forged_pgdual_rollback(self):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  for ver in ("17.6","18.7"):
   with self.subTest(pg=ver):
    name="lf-e21-auth-"+uuid.uuid4().hex[:10]
    p=subprocess.run(["docker","run","-d","--rm","--name",name,
        "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+ver],
        capture_output=True,text=True,timeout=180)
    self.assertEqual(p.returncode,0,p.stderr)
    try:
     for _ in range(90):
      ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
          capture_output=True,text=True,timeout=10)
      if ready.returncode==0:
       logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=10)
       if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):break
      time.sleep(.5)
     self.assertEqual(ready.returncode,0,"PG_NOT_READY")
     statement="BEGIN;\n"+SETUP+FIX+BODY+ASSERTS+"\nROLLBACK;\nSELECT 'E21_ROLLBACK_NO_SCHEMA='||(to_regclass('public.lf_operation_execution') IS NULL);\n"
     x=subprocess.run(["docker","exec","-i",name,"psql",
        "-X","-A","-t","-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
        input=statement,capture_output=True,text=True,timeout=180)
     self.assertEqual(x.returncode,0,x.stderr[-5500:]+"\n"+x.stdout[-2000:])
     self.assertIn("E21_SQL_VALIDATED_TRUE_FALSE_FORGED_BLOCKED=PASS",x.stdout)
     self.assertIn("E21_ROLLBACK_NO_SCHEMA=true",x.stdout)
     print("PASS_E21_EDGE_SQL_HANDOFF_AUTHORITY_PG"+ver+"_ROLLBACK",flush=True)
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)
if __name__=="__main__":unittest.main()
