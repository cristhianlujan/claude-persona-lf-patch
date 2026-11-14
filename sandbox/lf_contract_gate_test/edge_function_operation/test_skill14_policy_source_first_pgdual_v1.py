"""#3879 exact SQL candidate PG17.6/18.7 synthetic preimage + rollback/negative.
No Supabase credentials and no live writes.
"""
import json
import re
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
MIGRATION=ROOT/"supabase/migrations/20261114153140_lf_14_skill_policy_source_first_activation_v1.sql"
PREIMAGE="f075ec6faf0572dc4e89d9c101224a8b"

SETUP=r"""
\set ON_ERROR_STOP on
CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE TABLE public.lf_skill_catalog_v1(
 skill_code text,description text,required_operation text,
 handler_fn text,effect text,status text);
CREATE TABLE public.lf_skill_selection_registry_v1(
 skill_code text,descriptor jsonb,source_kind text,source_ref text,
 source_revision text,descriptor_status text,stale_reason text,synced_at timestamptz);
CREATE TABLE public.lf_skill_selector_policy_v1(
 profile_code text,skill_code text,required_operation text,
 channels text[],allowed_effects text[],selection_mode text,
 enabled boolean,owner_decision_required boolean,applicability_contract jsonb,
 policy_evidence_ref text,updated_at timestamptz);
CREATE TABLE public.lf_profile_selection_registry_v1(
 profile_code text,descriptor_status text);
CREATE TABLE public.lf_profile_selector_policy_v1(
 profile_code text,channels text[]);
CREATE TABLE public.lf_profile_write_authority_v1(
 profile_code text,operation_code text,status text);
CREATE FUNCTION public.lf_skill_h_input_governance_context_pack_v1(jsonb)
RETURNS jsonb LANGUAGE sql AS $f$ SELECT '{}'::jsonb $f$;
CREATE FUNCTION public.lf_skill_h_screen_rules_snapshot_v1(jsonb)
RETURNS jsonb LANGUAGE sql AS $f$ SELECT '{}'::jsonb $f$;
CREATE FUNCTION public.lf_skill_h_profile_update_propose_v1(jsonb)
RETURNS jsonb LANGUAGE sql AS $f$ SELECT '{}'::jsonb $f$;
INSERT INTO public.lf_skill_catalog_v1 VALUES
('INPUT_GOVERNANCE_CONTEXT_PACK','IG contextual readiness','EJECUCION_PERFIL_LF',
 'lf_skill_h_input_governance_context_pack_v1','READ_ONLY','READY'),
('SCREEN_RULES_SNAPSHOT','Screen rules read-only','EJECUCION_PERFIL_LF',
 'lf_skill_h_screen_rules_snapshot_v1','READ_ONLY','READY'),
('PROFILE_UPDATE_APPLY','Profile governed writer','ACTUALIZACION_PERFIL_LF',
 'lf_skill_h_profile_update_propose_v1','WRITE_GOVERNED','READY');
INSERT INTO public.lf_skill_selection_registry_v1 VALUES(
 'INPUT_GOVERNANCE_CONTEXT_PACK','{"schema_version":"LF_SKILL_SELECTION_DESCRIPTOR_V1","selection_evidence":[{"kind":"SOURCE","value":"CURRENT"}]}',
 'SUPABASE_CONTRACT',
 'supabase://public.lf_skill_h_input_governance_context_pack_v1',
 'sha256:91dd8dac1266a0a1e7b080c21c37ec47762172e376825e7471cc16b7b7af3f62',
 'CURRENT','SOURCE_AND_HANDLER_NOT_ATTESTED',now());
INSERT INTO public.lf_skill_selector_policy_v1
SELECT 'ACTIVE-'||g,'INPUT_GOVERNANCE_CONTEXT_PACK','EJECUCION_PERFIL_LF',
 ARRAY['PRODUCTO'],ARRAY['READ_ONLY'],'DETERMINISTIC_REQUIRED',
 true,false,'{"only_if_applicable":false}','owner://approved',now()
FROM generate_series(1,4) g;
INSERT INTO public.lf_skill_selector_policy_v1
SELECT 'PENDING-IG-'||g,'INPUT_GOVERNANCE_CONTEXT_PACK','EJECUCION_PERFIL_LF',
 ARRAY['PRODUCTO'],ARRAY['READ_ONLY'],'DETERMINISTIC_REQUIRED',
 false,true,'{"only_if_applicable":true}','owner://approved',now()
FROM generate_series(1,6) g;
INSERT INTO public.lf_skill_selector_policy_v1
SELECT 'PENDING-SNAPSHOT-'||g,'SCREEN_RULES_SNAPSHOT','EJECUCION_PERFIL_LF',
 ARRAY['PRODUCTO'],ARRAY['READ_ONLY'],'SEMANTIC_OPTIONAL',
 false,true,'{"only_if_applicable":false}','owner://approved',now()
FROM generate_series(1,7) g;
INSERT INTO public.lf_skill_selector_policy_v1 VALUES(
 'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','PROFILE_UPDATE_APPLY',
 'ACTUALIZACION_PERFIL_LF',ARRAY['PRODUCTO'],ARRAY['WRITE_GOVERNED'],
 'SEMANTIC_OPTIONAL',false,true,'{"only_if_applicable":false}',
 'owner://approved',now());
INSERT INTO public.lf_profile_selection_registry_v1
SELECT DISTINCT profile_code,'CURRENT' FROM public.lf_skill_selector_policy_v1;
INSERT INTO public.lf_profile_selector_policy_v1
SELECT DISTINCT profile_code,ARRAY['PRODUCTO'] FROM public.lf_skill_selector_policy_v1;
INSERT INTO public.lf_profile_write_authority_v1 VALUES(
 'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','ACTUALIZACION_PERFIL_LF','ACTIVE');
"""
HASH_SQL="SELECT md5(string_agg(to_jsonb(p)::text,'|' ORDER BY profile_code,skill_code,required_operation)) FROM public.lf_skill_selector_policy_v1 p;"
POST_SQL="""
SELECT 'POST='||count(*)::text||':'||
 count(*) FILTER(WHERE enabled AND NOT owner_decision_required)::text||':'||
 count(*) FILTER(WHERE NOT enabled OR owner_decision_required)::text
 FROM public.lf_skill_selector_policy_v1;
SELECT 'DESCRIPTORS='||count(*)::text FROM public.lf_skill_selection_registry_v1;
SELECT 'IG_CONDITIONAL='||count(*)::text FROM public.lf_skill_selector_policy_v1
 WHERE enabled AND skill_code='INPUT_GOVERNANCE_CONTEXT_PACK'
 AND applicability_contract->>'only_if_applicable'='true';
"""
class Skill14SourceFirstPgDual(unittest.TestCase):
    def test_exact_candidate_pg17_18_rollback_and_negative(self):
        self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
        source=MIGRATION.read_text(encoding="utf-8")
        self.assertEqual(source.count(PREIMAGE),1)
        self.assertIn("SKILL_POLICY_READBACK_18_NOT_ACTIVE",source)
        self.assertIn("SKILL_IG_CONDITIONAL_SCOPE_LOST",source)
        self.assertNotIn("UPDATE public.lf_operation_execution",source)
        for image,version in (("postgres:17.6","17.6"),("postgres:18.7","18.7")):
            name="lf-skill14-"+uuid.uuid4().hex[:10]
            started=subprocess.run(["docker","run","-d","--rm","--name",name,
                "-e","POSTGRES_PASSWORD=fixture-only",image],
                capture_output=True,text=True,timeout=240)
            self.assertEqual(started.returncode,0,started.stderr[-1000:])
            try:
                for _ in range(90):
                    ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
                        capture_output=True,timeout=10)
                    if ready.returncode==0: break
                    time.sleep(1)
                self.assertEqual(ready.returncode,0)
                def exec_sql(sql):
                    return subprocess.run(["docker","exec","-i",name,"psql",
                       "-v","ON_ERROR_STOP=1","-X","-A","-t","-U","postgres","-d","postgres"],
                       input=sql,capture_output=True,text=True,timeout=240)
                a=exec_sql(SETUP+"\n"+HASH_SQL)
                self.assertEqual(a.returncode,0,a.stderr[-3000:])
                h=a.stdout.splitlines()[-1].strip()
                self.assertRegex(h,r"^[0-9a-f]{32}$")
                candidate=source.replace(PREIMAGE,h)
                self.assertEqual(candidate.count(h),1)
                self.assertTrue(candidate.startswith("-- #3879:"))
                candidate=candidate.replace("\nBEGIN;\n","\n",1).rsplit("\nCOMMIT;\n",1)[0]
                good=exec_sql("BEGIN;\n"+candidate+"\n"+POST_SQL+"\nROLLBACK;\n"+POST_SQL)
                self.assertEqual(good.returncode,0,
                    "PG"+version+"\n"+good.stderr[-5000:]+"\n"+good.stdout[-2500:])
                lines=good.stdout.splitlines()
                self.assertIn("POST=18:18:0",lines)
                self.assertIn("DESCRIPTORS=3",lines)
                self.assertIn("IG_CONDITIONAL=6",lines)
                self.assertIn("POST=18:4:14",lines)
                self.assertIn("DESCRIPTORS=1",lines)
                # Changed owner flag outside canonical preimage must block and rollback.
                bad=exec_sql("BEGIN;\nUPDATE public.lf_skill_selector_policy_v1 "
                    "SET owner_decision_required=false WHERE profile_code='PENDING-IG-1';\n"
                    +candidate+"\nROLLBACK;\n")
                self.assertNotEqual(bad.returncode,0)
                self.assertIn("SOURCE_STATE_DRIFT_POLICY_18_4_14",bad.stderr)
                stable=exec_sql(POST_SQL)
                self.assertEqual(stable.returncode,0)
                self.assertIn("POST=18:4:14",stable.stdout)
                print("PASS_SKILL_14_PG_"+version+
                      " exact_positive_18_of_18 rollback=true drift_negative=BLOCKED")
            finally:
                subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=45)
