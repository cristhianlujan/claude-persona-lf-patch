"""PG17/18 actual V2 trust regression for same-chat SRCR candidate, ROLLBACK only.

Synthetic in disposable Docker PG, not a live Step70 attestation. Preimage drift,
wrong-profile, write authority, hash and V3 semantic controls must fail closed.
"""
import json
import re
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIG_CANDIDATES = tuple((ROOT / "supabase/migrations").glob(
    "*_lf_srcr_step70_v2_current_context_trust_v1.sql"
))
if len(MIG_CANDIDATES) != 1:
    raise RuntimeError("SRCR_V2_TEST_MIGRATION_SOURCE_RESOLUTION_DRIFT")
MIG = MIG_CANDIDATES[0]
HELP = ROOT / "supabase/migrations/20261115074500_lf_srcr_step70_same_native_conversation_candidate_v1.sql"
RUN = "EXEC-PROFILE-GATE2-TESTSRCRV2TRUST000001"
OLD_MD5 = "4a14fef959203b9b41212862877585f0"
OLD = """           and coalesce((e.manifest->>'read_only')::boolean,false) is true
           and coalesce((e.manifest->>'no_write')::boolean,false) is true
           and coalesce((e.manifest->>'no_promotion')::boolean,false) is true"""
NEW = """           and (
             (
               coalesce((e.manifest->>'read_only')::boolean,false) is true
               and coalesce((e.manifest->>'no_write')::boolean,false) is true
               and coalesce((e.manifest->>'no_promotion')::boolean,false) is true
             )
             or (
               e.target_code='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
               and public.lf_profile_srcr_same_context_candidate_scope_v1(p_execution_id)
             )
           )"""

def q(x):
    return "'" + x.replace("'", "''") + "'"

def j(x):
    return q(json.dumps(x, separators=(",", ":"), sort_keys=True)) + "::jsonb"

def psql(name, stmt, success=True):
    r = subprocess.run(["docker", "exec", "-i", name, "psql", "-X", "-A", "-t",
                        "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"],
                       input=stmt, text=True, capture_output=True, timeout=120)
    if success and r.returncode:
        raise AssertionError(r.stderr[-2500:])
    if not success and r.returncode == 0:
        raise AssertionError("NEGATIVE_MIGRATION_GUARD_EXPECTED_ERROR")
    return r.stdout

def ddl_parts():
    raw = MIG.read_text(encoding="utf8")
    assert raw.count(OLD_MD5) == 1
    assert raw.count(NEW) == 1
    sql = raw.strip().removeprefix("BEGIN;").strip().removesuffix("COMMIT;").strip()
    new_ddl = sql.split("END $pre$;", 1)[1].strip()
    old_ddl = new_ddl.replace(NEW, OLD)
    assert old_ddl != new_ddl
    help_source = HELP.read_text(encoding="utf8")
    helper = help_source.split("CREATE FUNCTION public.lf_profile_srcr_same_context_candidate_scope_v1(", 1)[1]
    helper = "CREATE FUNCTION public.lf_profile_srcr_same_context_candidate_scope_v1(" + helper.split(
        "CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_record_semantic_v1(", 1
    )[0]
    return sql, old_ddl, helper

def synthetic():
    reference = ("github://cristhianlujan/claude-persona-lf-patch@" + "f" * 40 +
                 "/sandbox/lf_contract_gate_test/test_contract.json")
    manifest = {
       "executor_mode":"GPT_NATIVE","read_only":False,"no_write":False,
       "governed_repair_write":True,"no_promotion":True,"automatic_impact":False,
       "router_profile_handoff":{"router_authorization_receipt":{"effect_authority":False}}
    }
    step40 = {"analysis_scope":"READ_ONLY_WITH_IG_FINDINGS",
       "mutation_authorized":False,"promotion_authorized":False,
       "input_governance":{"analysis_scope":"READ_ONLY_WITH_IG_FINDINGS"},
       "allowed_actions":["ANALYZE","PROPOSE","VALIDATE","REPORT"],
       "scope_authority_packet_sha256":"sha256:"+"b"*64}
    step50 = {"candidate_digest":"sha256:"+"a"*64,"profile_output":{
        "repair_execution":{"changes":[{
           "after_ref":reference,"target_ref":reference,"before_ref":None,"change_type":"CREATE"
        }]}}}
    checks = {k:{"result":True} for k in [
      "context_resolution_valid","evidence_supported","decision_resolves_objective",
      "authority_resolution_valid","constraints_preserved","claims_authorized",
      "materiality_handled_correctly","tradeoff_defensible",
      "acceptance_detects_wrong_implementation","handoff_implementation_ready",
      "counterfactual_trajectory"]}
    checks["router_direct_consistency"]={"result":"not_applicable","applicability":"ROUTER_ONLY"}
    verdict="PASS_REVIEWED_CURRENT_CONTEXT"
    v3={"verdict":verdict,"review_mode":"CURRENT_CONTEXT_REVIEW",
        "reviewer_is_producer":True,"producer_independence_proven":False,
        "model_call_count":0,"router_direct_consistency":"NOT_TESTED",
        "counterfactual_result":"PASS","decision_checks":checks}
    judge={"status":"PASS","validator_status":"PASS","verdict":verdict,
           "review_mode":"CURRENT_CONTEXT_REVIEW","reviewer_is_producer":True,
           "producer_independence_proven":False,"model_call_count":0,
           "candidate_sha256":"a"*64,"scope_packet_sha256":"b"*64,
           "judge_v3_evidence":v3,
           "result":{"verdict":verdict,"candidate_sha256":"a"*64,
                      "scope_packet_sha256":"b"*64,"unsupported_claims":[],
                      "blocking_codes":[]}}
    step70={"semantic_judge_result":judge,"unsupported_claims":[]}
    return manifest,step40,step50,step70

class SrcrV2TrustPgDual(unittest.TestCase):
    def test_pg17(self): self.exercise("postgres:17.6")
    def test_pg18(self): self.exercise("postgres:18.7")

    def exercise(self, image):
        if not shutil.which("docker"):
            self.fail("DOCKER_REQUIRED_FOR_PG17_18")
        name="lf-step70-v2-"+uuid.uuid4().hex[:12]
        start=subprocess.run(["docker","run","-d","--rm","--name",name,
                              "-e","POSTGRES_PASSWORD=postgres",image],
                             capture_output=True,text=True,timeout=150)
        self.assertEqual(start.returncode,0,start.stderr[-1200:])
        try:
            for _ in range(80):
                out=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
                                   capture_output=True,text=True,timeout=10)
                if out.returncode==0:break
                time.sleep(1)
            else:self.fail("PG_NOT_READY")
            self.verify(name)
        finally:
            subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=30)

    def verify(self, name):
        sql,old_ddl,helper=ddl_parts()
        manifest,step40,step50,step70=synthetic()
        pre = """CREATE SCHEMA private;
CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE TABLE public.lf_operation_execution (
 execution_id text PRIMARY KEY,status text,operation_code text,target_code text,manifest jsonb);
CREATE TABLE public.lf_operation_execution_steps (
 execution_id text,step_id text,status text,evidence_payload jsonb,
 PRIMARY KEY(execution_id,step_id));
CREATE TABLE public.lf_operation_step_judge_bindings (
 operation_code text,step_id text,status text,clean_result_value text);
CREATE FUNCTION public.lf_profile_execution_trust_validation_v1(text,text,jsonb)
 RETURNS jsonb LANGUAGE sql AS $$SELECT '{"valid":true}'::jsonb$$;
CREATE FUNCTION public.lf_profile_execution_canonical_read_judge_v1(text)
 RETURNS jsonb LANGUAGE sql AS $$SELECT '{"status":"NOT_APPLICABLE"}'::jsonb$$;
"""
        pre += f"""INSERT INTO public.lf_operation_execution VALUES(
{q(RUN)},'IN_PROGRESS','EJECUCION_PERFIL_LF','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
{j(manifest)});
INSERT INTO public.lf_operation_step_judge_bindings VALUES
('EJECUCION_PERFIL_LF','input_validate','ACTIVE_ENFORCEMENT','STEP_PASS_WITH_EVIDENCE'),
('EJECUCION_PERFIL_LF','execute_profile','ACTIVE_ENFORCEMENT','STEP_PASS_WITH_EVIDENCE'),
('EJECUCION_PERFIL_LF','semantic_judge','ACTIVE_ENFORCEMENT','STEP_PASS_WITH_EVIDENCE');
"""
        for step,payload in [
            ("input_validate",step40),("execute_profile",step50),
            ("output_validate",{"deterministic_validation":{"status":"PASS"}})
        ]:
            pre += (f"INSERT INTO public.lf_operation_execution_steps VALUES ("
                    f"{q(RUN)},{q(step)},'STEP_PASS_WITH_EVIDENCE',{j(payload)});\n")
        psql(name,pre+helper+"\n"+old_ddl+"\n")
        fn=f"public.lf_profile_execution_trust_validation_v2({q(RUN)},'semantic_judge',{j(step70)})"
        original=psql(name,"SELECT md5(pg_get_functiondef('public.lf_profile_execution_trust_validation_v2(text,text,jsonb)'::regprocedure));").strip()
        self.assertRegex(original,r"^[a-f0-9]{32}$")
        base=psql(name,f"SELECT {fn}->>'valid';").strip()
        self.assertEqual(base,"false","LEGACY_V2_MUST_REJECT_EFFECTS_BEARING_SELF_REVIEW")
        migration=sql.replace(OLD_MD5,original)
        psql(name,"BEGIN;\n"+migration.replace(original,"0"*32,1)+"\nROLLBACK;",success=False)
        test=f"""BEGIN;
{migration}
SELECT 'VALID|'||({fn}->>'valid');
UPDATE public.lf_operation_execution SET manifest=jsonb_set(manifest,'{{no_promotion}}','false'::jsonb);
SELECT 'PROMOTION|'||({fn}->>'valid');
UPDATE public.lf_operation_execution SET manifest=jsonb_set(manifest,'{{no_promotion}}','true'::jsonb);
UPDATE public.lf_operation_execution SET target_code='PERFIL-PRODUCT-DIRECTOR-LF';
SELECT 'WRONG_PROFILE|'||({fn}->>'valid');
UPDATE public.lf_operation_execution SET target_code='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF';
UPDATE public.lf_operation_execution
 SET manifest=jsonb_set(manifest,'{{router_profile_handoff,router_authorization_receipt,effect_authority}}','true'::jsonb);
SELECT 'ROUTER_EFFECT|'||({fn}->>'valid');
UPDATE public.lf_operation_execution
 SET manifest=jsonb_set(manifest,'{{router_profile_handoff,router_authorization_receipt,effect_authority}}','false'::jsonb);
UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,'{{mutation_authorized}}','true'::jsonb)
 WHERE step_id='input_validate';
SELECT 'STEP40_WRITE|'||({fn}->>'valid');
UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,'{{mutation_authorized}}','false'::jsonb)
 WHERE step_id='input_validate';
SELECT 'MISMATCH|'||(public.lf_profile_execution_trust_validation_v2({q(RUN)},'semantic_judge',
 jsonb_set({j(step70)},'{{semantic_judge_result,candidate_sha256}}','"{'c'*64}"'::jsonb))->>'valid');
ROLLBACK;"""
        output=psql(name,test)
        for key in ("VALID|true","PROMOTION|false","WRONG_PROFILE|false",
                    "ROUTER_EFFECT|false","STEP40_WRITE|false","MISMATCH|false"):
            self.assertIn(key,output)
        final=psql(name,"SELECT md5(pg_get_functiondef('public.lf_profile_execution_trust_validation_v2(text,text,jsonb)'::regprocedure));").strip()
        self.assertEqual(final,original,"ROLLBACK_DID_NOT_RESTORE_V2_PREIMAGE")

if __name__=="__main__":
    unittest.main()
