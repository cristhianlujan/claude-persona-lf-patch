#!/usr/bin/env python3
"""B12/G08 historic six V1 ABI + B05 candidate protections + B08 documentary guard.
Disposable real PG17.6 and PG18.7, exact live-object slice, transactions rolled back.
No Supabase credentials, no external issuer or signer. This is NOT B05/B08 closure.
"""
import json
import subprocess
import time
import unittest
import uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
SOURCE=ROOT/"sandbox/lf_contract_gate_test/input_governance_lifecycle/pg18_live_object_slice_baseline.sql"
V1={
 "candidate_write":("public.lf_regla_candidate_write_v1(text,text,text,text,text,text,text,jsonb,boolean,text)","c311087befe49afb2affa668231c9dd1"),
 "skill_invoke":("public.lf_skill_invoke_v1(text,text,jsonb)","ac7e351e1834cbfb91aabf26e1a04a8d"),
 "skill_o_rule_update":("public.lf_skill_o_rule_update_v1(text,jsonb,text,text,text)","dc97a0e7c65b65ae1951e2da86c6238b"),
 "promotion_apply":("public.lf_rule_promotion_apply_v1(text)","d7fe763c999db6f6259b6b1e2bd69644"),
 "promotion_decide":("public.lf_rule_promotion_decide_v1(text,text,text,text)","16e45f40dad5cecc215a2f978be47728"),
 "record_step":("public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)","fe08a25c8e3c023d7181194d2dfdee0d"),
}
SQL="\nBEGIN;\nCREATE OR REPLACE FUNCTION public.lf_skill_h_b12_readonly_probe_v1(p jsonb)\nRETURNS jsonb LANGUAGE sql AS $b12f$ SELECT jsonb_build_object('status','SAFE','input',p); $b12f$;\nDO $b12$\nDECLARE v jsonb; v2 jsonb; msg text; v_sha text; v_total integer;\nBEGIN\n  SELECT count(*) INTO v_total FROM lf_ops.reglas;\n  INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,manifest,request_sha256,idempotency_key,created_by_execution_id)\n  VALUES('B12-V1-RULE-CREATE','CREACION_REGLA_LF','REGLA','B12-V1-RULE','{}'::jsonb,repeat('b',64),'b12-v1-create','B12-SANDBOX-ONLY');\n  -- Candidate creation is governed. Positive: candidate; negative: invalid action, no duplicate.\n  v:=public.lf_regla_candidate_write_v1('B12-V1-RULE-CREATE','REGLA_CREATE','B12-V1-RULE','SECURITY',\n        'B12 candidate under controlled legacy writer','Tested candidate stays non-vigente without promotion','B05 no silent promotion',null,false,'B12_SANDBOX');\n  IF v->>'result' IS DISTINCT FROM 'RULE_CANDIDATE_CREATED' OR\n     (SELECT estado FROM lf_ops.reglas WHERE codigo='B12-V1-RULE') IS DISTINCT FROM 'CANDIDATO'\n  THEN RAISE EXCEPTION 'B12_B05_CANDIDATE_POSITIVE_FAILED:%',v; END IF;\n  BEGIN\n    PERFORM public.lf_regla_candidate_write_v1('B12-V1-RULE-CREATE','BYPASS_CREATE','B12-V1-RULE','SECURITY','Wrong','Wrong');\n    RAISE EXCEPTION 'B12_B05_ACTION_EXPECTED_ERROR_MISSING';\n  EXCEPTION WHEN OTHERS THEN\n    GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;\n    IF msg NOT LIKE 'LF_REGLA_ACTION_INVALID:%'\n      THEN RAISE EXCEPTION 'B12_B05_ACTION_WRONG_NEGATIVE:%',msg; END IF;\n  END;\n  BEGIN\n    PERFORM public.lf_regla_candidate_write_v1('B12-V1-RULE-CREATE','REGLA_CREATE','B12-V1-RULE','SECURITY','Duplicate','Duplicate');\n    RAISE EXCEPTION 'B12_B05_DUPLICATE_EXPECTED_ERROR_MISSING';\n  EXCEPTION WHEN OTHERS THEN\n    GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;\n    IF msg NOT LIKE 'LF_REGLA_CREATE_DUPLICATE:%'\n      THEN RAISE EXCEPTION 'B12_B05_DUPLICATE_WRONG_NEGATIVE:%',msg; END IF;\n  END;\n\n  INSERT INTO public.lf_rule_promotion_v1(promotion_id,rule_code,request_execution_id,requested_by_profile,request_snapshot_sha256,status,reason)\n  VALUES('B12-PROMO','B12-V1-RULE','B12-V1-RULE-CREATE','PERFIL-PRODUCT-DIRECTOR-LF',\n    public.lf_asset_snapshot_sha_v1('REGLA','B12-V1-RULE'),'PENDING','Only laboratory');\n  -- B08 documentary string must not automatically grant operational rights to a non-human label.\n  v:=public.lf_rule_promotion_decide_v1('B12-PROMO','APPROVE','BOT:SPOOFED','bad');\n  IF v->>'blocking_code' IS DISTINCT FROM 'APPROVER_MUST_BE_HUMAN'\n  THEN RAISE EXCEPTION 'B12_B08_HUMAN_FORMAT_NEGATIVE_FAILED:%',v; END IF;\n  v:=public.lf_rule_promotion_decide_v1('B12-PROMO','APPROVE','HUMAN:B12_LAB_ONLY','positive sandbox');\n  IF v->>'status' IS DISTINCT FROM 'APPROVED'\n  THEN RAISE EXCEPTION 'B12_B08_DECIDE_POSITIVE_FAILED:%',v; END IF;\n  v2:=public.lf_rule_promotion_decide_v1('B12-PROMO','APPROVE','HUMAN:B12_LAB_ONLY','replay');\n  IF v2->>'blocking_code' IS DISTINCT FROM 'PROMOTION_NOT_PENDING'\n  THEN RAISE EXCEPTION 'B12_B08_DECIDE_IDEMPOTENCE_FAILED:%',v2; END IF;\n  v:=public.lf_rule_promotion_apply_v1('B12-PROMO');\n  IF v->>'status' IS DISTINCT FROM 'APPLIED' OR\n     (SELECT estado FROM lf_ops.reglas WHERE codigo='B12-V1-RULE') IS DISTINCT FROM 'VIGENTE'\n  THEN RAISE EXCEPTION 'B12_B05_PROMOTE_POSITIVE_FAILED:%',v; END IF;\n  v2:=public.lf_rule_promotion_apply_v1('B12-PROMO');\n  IF v2->>'blocking_code' IS DISTINCT FROM 'PROMOTION_NOT_APPROVED'\n  THEN RAISE EXCEPTION 'B12_B05_APPLY_IDEMPOTENCE_FAILED:%',v2; END IF;\n  IF (SELECT count(*) FROM lf_ops.reglas WHERE codigo='B12-V1-RULE')<>1\n  THEN RAISE EXCEPTION 'B12_B05_RULE_COUNT_MISMATCH'; END IF;\n\n  -- SKILL: genuine legacy function, isolated harmless fixture handler, real parent and catalog policy.\n  INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,manifest,request_sha256,idempotency_key,created_by_execution_id)\n  VALUES('B12-V1-PARENT','EJECUCION_PERFIL_LF','PERFIL','PERFIL-PRODUCT-DIRECTOR-LF',\n    '{\"read_only\":true,\"no_write\":true,\"no_promotion\":true}'::jsonb,repeat('a',64),'b12-v1-parent','B12-SANDBOX-ONLY');\n  INSERT INTO public.lf_skill_catalog_v1(skill_code,description,required_operation,handler_fn,effect,status)\n  VALUES('B12_PROBE','readonly sandbox B12 skill','CREACION_REGLA_LF','lf_skill_h_b12_readonly_probe_v1','READ_ONLY','READY');\n  v:=public.lf_skill_invoke_v1('B12_PROBE','B12-V1-PARENT','{\"case\":\"positive\"}'::jsonb);\n  IF v->>'status' IS DISTINCT FROM 'COMPLETED'\n  THEN RAISE EXCEPTION 'B12_SKILL_INVOKE_POSITIVE_FAILED:%',v; END IF;\n  v2:=public.lf_skill_invoke_v1('B12_PROBE','B12-V1-PARENT','{\"case\":\"positive\"}'::jsonb);\n  IF v2->>'replay' IS DISTINCT FROM 'true'\n    OR (SELECT count(*) FROM public.lf_skill_invocation_v1 WHERE skill_code='B12_PROBE' AND parent_execution_id='B12-V1-PARENT')<>1\n  THEN RAISE EXCEPTION 'B12_SKILL_INVOKE_REPLAY_FAILED:%',v2; END IF;\n  v:=public.lf_skill_invoke_v1('B12_PROBE','B12-V1-NONEXISTENT','{}'::jsonb);\n  IF v->>'blocking_code' IS DISTINCT FROM 'PARENT_EXECUTION_NOT_ACTIVE'\n  THEN RAISE EXCEPTION 'B12_SKILL_PARENT_NEGATIVE_FAILED:%',v; END IF;\n\n  -- Sensitive child writer denies missing parent; no effect or false promotion.\n  BEGIN\n    PERFORM public.lf_skill_o_rule_update_v1('B12-SKILL-CHILD','{}'::jsonb,'B12-MISSING-PARENT','B12-RUN',repeat('b',64));\n    RAISE EXCEPTION 'B12_CHILD_WRITER_EXPECTED_NEGATIVE_MISSING';\n  EXCEPTION WHEN OTHERS THEN\n    GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;\n    IF msg NOT LIKE 'BLOCK_RULE_CHILD_%'\n    THEN RAISE EXCEPTION 'B12_CHILD_WRITER_WRONG_NEGATIVE:%',msg; END IF;\n  END;\n  -- Legacy recorder denies missing actor/identity early and does not write steps.\n  v:=public.lf_record_operation_step_core_v1(NULL,NULL,NULL,'{}'::jsonb,NULL,NULL,NULL,NULL,NULL,NULL,'{\"valid\":false}'::jsonb,false,'B12_TEST');\n  IF v->>'code' IS DISTINCT FROM 'STEP_IDENTITY_OR_ACTOR_MISSING'\n  THEN RAISE EXCEPTION 'B12_RECORDER_INVALID_IDENTITY_NOT_BLOCKED:%',v; END IF;\n  IF (SELECT count(*) FROM public.lf_operation_execution_steps WHERE execution_id LIKE 'B12-%')<>0\n  THEN RAISE EXCEPTION 'B12_RECORDER_ILLEGAL_SIDE_EFFECT'; END IF;\n\n  RAISE NOTICE 'PASS_B12_SIX_B05_B08_PROTECTED';\nEND $b12$;\nROLLBACK;\nSELECT 'B12_SIX_TRANSACTION_ROLLBACK|'||\nCASE WHEN (SELECT count(*) FROM public.lf_operation_execution WHERE execution_id LIKE 'B12-V1%')=0\n  AND (SELECT count(*) FROM lf_ops.reglas WHERE codigo='B12-V1-RULE')=0\n  AND (SELECT count(*) FROM public.lf_skill_invocation_v1 WHERE skill_code='B12_PROBE')=0\nTHEN 'true' ELSE 'false' END;\n"

class B12SixV1(unittest.TestCase):
    def runsql(self,name,sql,timeout=270):
        p=subprocess.run(["docker","exec","-i",name,"psql","-X","-q","-A","-t",
          "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
          input=sql,text=True,capture_output=True,timeout=timeout)
        self.assertEqual(p.returncode,0,"B12_SIX_SQL_FAILURE:"+p.stderr[-2700:]+" SQL:"+sql[:550])
        return p.stdout.strip(),p.stderr

    def check(self,image,major):
        name="lf-b12-six-"+uuid.uuid4().hex[:10]
        p=subprocess.run(["docker","run","-d","--rm","--name",name,"-e",
             "POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
             capture_output=True,text=True,timeout=240)
        self.assertEqual(p.returncode,0,"B12_SIX_DOCKER_START:"+p.stderr[-950:])
        try:
            result=None
            for i in range(75):
                a=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
                    text=True,capture_output=True,timeout=8)
                if a.returncode==0:
                    try:
                        out,_=self.runsql(name,"SHOW server_version;")
                        if out.startswith(image.split(":",1)[1]): result=out; break
                    except AssertionError as e:
                        if "connection to server on socket" not in str(e): raise
                time.sleep(1)
            self.assertIsNotNone(result,"B12_SIX_PG_NOT_READY:"+image)
            print("B12_SIX_POSTGRES_EXACT="+result,flush=True)
            src=SOURCE.read_text(encoding="utf-8")
            self.assertGreater(len(src),200000,"B12_SIX_BASELINE_SOURCE_NOT_PRESENT")
            self.runsql(name,src,timeout=350)
            v1values=",".join("('"+k+"','"+sig+"','"+md5+"')" for k,(sig,md5) in V1.items())
            fingerprint="""WITH f(kind,signature,expected) AS (VALUES """+v1values+""")
                SELECT kind||'|'||coalesce(md5(pg_get_functiondef(to_regprocedure(signature))),'ABSENT')||'|'||expected
                FROM f ORDER BY kind;"""
            result,_=self.runsql(name,fingerprint)
            for row in result.splitlines():
                key,actual,expected=row.split("|")
                self.assertEqual(actual,expected,"B12_SIX_FUNCTION_MD5_DRIFT:"+key)
            self.assertEqual(len(result.splitlines()),6,"B12_SIX_MD5_NOT_6")
            print("PASS_B12_SIX_V1_MD5_6_OF_6_"+image,flush=True)
            # Restore post-#3817 role restrictions in fixture; do not change function definitions.
            self.runsql(name,"REVOKE EXECUTE ON FUNCTION public.lf_rule_promotion_guard_v1() FROM PUBLIC, anon, authenticated;")
            out,err=self.runsql(name,SQL,timeout=210)
            self.assertIn("B12_SIX_TRANSACTION_ROLLBACK|true",out,
                "B12_SIX_ROLLBACK_FAILED:"+out)
            self.assertIn("PASS_B12_SIX_B05_B08_PROTECTED",err,
                "B12_SIX_ASSERTION_BLOCK_NOT_EXECUTED:"+err[-900:])
            print("PASS_B12_SIX_B05_B08_PROTECTED_"+image,flush=True)
            print("PASS_B12_SIX_TRANSACTIONAL_ROLLBACK_"+image,flush=True)
        finally:
            subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=40)

    def test_pg17_6(self): self.check("postgres:17.6",17)
    def test_pg18_7(self): self.check("postgres:18.7",18)
