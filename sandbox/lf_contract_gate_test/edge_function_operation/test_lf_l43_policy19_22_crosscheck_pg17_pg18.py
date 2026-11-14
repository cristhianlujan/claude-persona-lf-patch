#!/usr/bin/env python3
"""LF L43: exact STABLE deployed predecision crosscheck in isolated PG17.6/18.7.
Uses the actual drafted Train migration text and frozen live source JSONB, not a rewritten detector.
Synthetic Train row is LAB ONLY and is not owner authorization or a production receipt.
"""
from __future__ import annotations
import hashlib,json,os,re,shutil,subprocess,time,unittest,uuid
from pathlib import Path
HERE=Path(__file__).resolve().parent
SRC=HERE/"fixtures/lf_l43_policies19_22_crosscheck_source.json"
MIG=HERE.parents[2]/"supabase/migrations/20261114013500_lf_b2b_policy19_22_predecision_promotion_v1.sql"
def q(s):return "'"+str(s).replace("'","''")+"'"
def js(x):return q(json.dumps(x,ensure_ascii=False,separators=(",",":")))+"::jsonb"
class TestL43Predecision(unittest.TestCase):
 def lab(self,image,version):
    self.assertTrue(shutil.which("docker"),"Docker required; never fallback to live Supabase")
    f=json.loads(SRC.read_text(encoding="utf8"))
    migration=MIG.read_text(encoding="utf8")
    self.assertIn("LF_L43_PREDECISION_3_TO_1",migration)
    self.assertEqual(f["run_id"],952)
    self.assertEqual(f["human_required"],0)
    self.assertEqual([x["security_policy_id"] for x in f["policies"]],[3,17,19,22])
    self.assertEqual({x["status"] for x in f["policies"] if x["security_policy_id"] in (19,22)},{"CANDIDATO"})
    self.assertEqual(f["pr3848"]["source_policy22_sha"],next(x["sha"] for x in f["policies"] if x["security_policy_id"]==22))
    self.assertIn("SEC-B2B-MFA-FACTOR-ELIGIBILITY",migration)
    self.assertFalse(f["owner_identity_verified"])
    self.assertEqual([p["provolatile"] for p in f["functions"] if p["proname"]=="fn_input_governance_predecision_crosscheck_v1"],["s"])
    name="lf-l43-"+uuid.uuid4().hex[:10]
    x=subprocess.run(["docker","run","-d","--rm","--name",name,
      "-e","POSTGRES_PASSWORD=postgres","-e","POSTGRES_DB=postgres",image],
      capture_output=True,text=True,timeout=240)
    self.assertEqual(x.returncode,0,x.stderr[-2500:])
    try:
      def sql(txt,expect_error=None):
        p=subprocess.run(["docker","exec","-i",name,"psql","-A","-t","-q","-X","-v","ON_ERROR_STOP=1",
          "-U","postgres","-d","postgres"],input=txt,text=True,capture_output=True,timeout=300)
        if expect_error:
          self.assertNotEqual(p.returncode,0,"Expected negative to fail closed")
          self.assertIn(expect_error,p.stderr[-3000:])
        else:
          self.assertEqual(p.returncode,0,p.stderr[-3800:])
        return [z.strip() for z in p.stdout.splitlines() if z.strip()]
      for _ in range(90):
        if subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],capture_output=True,timeout=10).returncode==0:break
        time.sleep(1)
      else:self.fail("DB_NOT_READY")
      self.assertEqual(sql("SHOW server_version_num;"),[version])
      allowed={"text","jsonb","integer","bigint","boolean","timestamp with time zone"}
      def ddl(tab):
        cols=[x for x in f["columns"] if x["table_name"]==tab]
        self.assertTrue(cols)
        self.assertTrue(all(re.fullmatch("[a-z0-9_]+",x["col"]) and x["typ"] in allowed for x in cols))
        return ",".join('"'+x["col"]+'" '+x["typ"] for x in cols)
      setup=["CREATE SCHEMA lf_ops;CREATE SCHEMA programacion;CREATE SCHEMA private;",
        "CREATE SCHEMA extensions;CREATE EXTENSION pgcrypto WITH SCHEMA extensions;",
        "CREATE TABLE lf_ops.politicas_seguridad("+ddl("politicas_seguridad")+");",
        "CREATE TABLE lf_ops.politicas_rate_limit("+ddl("politicas_rate_limit")+");",
        "CREATE TABLE lf_ops.pantallas_politicas(pantalla_id integer,security_policy_id bigint,rate_limit_policy_id bigint);",
        "CREATE TABLE programacion.input_readiness_runs(id bigint,pantalla_id integer);",
        "CREATE TABLE programacion.input_gap_proposals(id bigint,run_id bigint,family_code text,gap_code text,status text,proposal_kind text,validator_outcome text);",
        "CREATE TABLE public.lf_operation_execution(execution_id text,operation_code text,target_type text,status text,target_repo text,target_code text,target_path text,manifest jsonb,request_sha256 text);"]
      for p in f["policies"]:
        setup.append("INSERT INTO lf_ops.politicas_seguridad SELECT (jsonb_populate_record(NULL::lf_ops.politicas_seguridad,"+
              q(p["canonical"])+"::jsonb)).*;")
      setup.append("INSERT INTO lf_ops.politicas_rate_limit SELECT (jsonb_populate_record(NULL::lf_ops.politicas_rate_limit,"+
                   q(f["rate"]["canonical"])+"::jsonb)).*;")
      for link in f["links"]:
        setup.append("INSERT INTO lf_ops.pantallas_politicas VALUES ("+str(f["screen_id"])+","+
            ("NULL" if link["security_policy_id"] is None else str(link["security_policy_id"]))+","+
            ("NULL" if link["rate_limit_policy_id"] is None else str(link["rate_limit_policy_id"]))+");")
      setup.append("INSERT INTO programacion.input_readiness_runs VALUES(952,51);")
      # The historical run has ZERO human decision-required proposals.
      # Private function is deliberately abort-only if a hidden human branch is reached; never mocks its disposition.
      setup.append("CREATE OR REPLACE FUNCTION private.fn_lf_ig_human_decision_live_disposition_v1(bigint) RETURNS jsonb "
                   "LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'LF_L43_UNEXPECTED_HUMAN_DECISION_BRANCH';END;$$;")
      for obj in sorted(f["functions"],key=lambda x:(0 if x["proname"]=="fn_input_parameter_provenance_valid_v1" else 1 if x["proname"]=="fn_guard_input_parameter_provenance_v1" else 2)):
        setup.append(obj["definition"]+";")
      setup.append("CREATE OR REPLACE FUNCTION lf_ops.touch_updated_at() RETURNS trigger LANGUAGE plpgsql "
                   "AS $$BEGIN NEW.updated_at=clock_timestamp(); RETURN NEW; END;$$;")
      setup += [t["definition"]+";" for t in f["triggers"]]
      # Only lab synthetic Train transport, not a signed owner or actual authorization.
      lab_receipt=("INSERT INTO public.lf_operation_execution VALUES ('LAB_SIMULATION_ONLY',"
       "'ACTUALIZACION_DB_LF','MIGRATION','IN_PROGRESS','cristhianlujan/claude-persona-lf-patch',"
       "'20261114013500_lf_b2b_policy19_22_predecision_promotion_v1',"
       "'supabase/migrations/20261114013500_lf_b2b_policy19_22_predecision_promotion_v1.sql',"
       +js({"producer":"lf-migration-merge-train","pr":"3854","train_run_id":"99999999"})+",'"+("a"*64)+"');")
      setup.append(lab_receipt)
      sql("\n".join(setup))
      self.assertEqual(sql("SELECT provolatile FROM pg_proc WHERE oid='programacion.fn_input_governance_predecision_crosscheck_v1(bigint)'::regprocedure;"),["s"])
      before_json=json.loads(sql("SELECT programacion.fn_input_governance_predecision_crosscheck_v1(952)::text;")[0])
      bfind=before_json["deterministic_findings"]
      self.assertEqual(len(bfind),3)
      self.assertEqual(sorted(x["target_id"] for x in bfind if x["type"]=="VIGENTE_REFERENCES_CANDIDATO"),[19,22])
      self.assertEqual([x["type"] for x in bfind].count("IP_COMPOSITE_SCOPE_REQUIRES_RUNTIME_PROOF"),1)
      def sha_rows():
        lines=sql("SELECT 'SEC|'||security_policy_id||'|'||encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),'sha256'),'hex') FROM lf_ops.politicas_seguridad t ORDER BY security_policy_id;"
          "SELECT 'RATE|'||rate_limit_policy_id||'|'||encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),'sha256'),'hex') FROM lf_ops.politicas_rate_limit t ORDER BY rate_limit_policy_id;")
        return dict(s.rsplit("|",1) for s in lines)
      baseline=sha_rows()
      expected={"SEC|"+str(p["security_policy_id"]):p["sha"] for p in f["policies"]}
      expected["RATE|1"]=f["rate"]["sha"]
      self.assertEqual(baseline,expected,"EXACT_LIVE_SOURCE_SHA_MISMATCH")
      # Fail-closed tests on exact migration, NOT a modified duplicate.
      sql("DELETE FROM public.lf_operation_execution;"+migration,expect_error="LF_L43_TRAIN_EXECUTION_NOT_UNIQUE")
      sql(lab_receipt)
      sql("BEGIN;UPDATE lf_ops.politicas_seguridad SET description='DRIFT_LAB' WHERE security_policy_id=19;"+
         migration,expect_error="LF_L43_SOURCE_SHA_DRIFT")
      self.assertEqual(sha_rows(),baseline)
      # Actual deployed STABLE function sees status changes made in the same transaction.
      checks=["BEGIN;",migration,
       "SELECT 'AFTER_FINDINGS|'||programacion.fn_input_governance_predecision_crosscheck_v1(952)::text;",
       "SELECT 'AFTER_STATUS|'||security_policy_id||'|'||status FROM lf_ops.politicas_seguridad WHERE security_policy_id IN(19,22) ORDER BY security_policy_id;",
       "SELECT 'DURING|SEC|'||security_policy_id||'|'||encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),'sha256'),'hex') FROM lf_ops.politicas_seguridad t ORDER BY security_policy_id;",
       "SELECT 'DURING|RATE|'||rate_limit_policy_id||'|'||encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),'sha256'),'hex') FROM lf_ops.politicas_rate_limit t ORDER BY rate_limit_policy_id;",
       "ROLLBACK;",
       "SELECT 'AFTER_ROLLBACK|SEC|'||security_policy_id||'|'||encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),'sha256'),'hex') FROM lf_ops.politicas_seguridad t ORDER BY security_policy_id;",
       "SELECT 'AFTER_ROLLBACK|RATE|'||rate_limit_policy_id||'|'||encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),'sha256'),'hex') FROM lf_ops.politicas_rate_limit t ORDER BY rate_limit_policy_id;",
       "SELECT 'AFTER_ROLLBACK_FINDINGS|'||programacion.fn_input_governance_predecision_crosscheck_v1(952)::text;"]
      out=sql("\n".join(checks))
      after_data=json.loads(next(v[len("AFTER_FINDINGS|"):] for v in out if v.startswith("AFTER_FINDINGS|")))
      self.assertEqual(after_data["deterministic_finding_count"],1)
      self.assertEqual(len(after_data["deterministic_findings"]),1)
      self.assertEqual(after_data["deterministic_findings"][0]["type"],"IP_COMPOSITE_SCOPE_REQUIRES_RUNTIME_PROOF")
      self.assertEqual(after_data["deterministic_findings"][0]["scope_key"],"IP_USER")
      self.assertEqual([x for x in out if x.startswith("AFTER_STATUS|")],["AFTER_STATUS|19|VIGENTE","AFTER_STATUS|22|VIGENTE"])
      back=json.loads(next(v[len("AFTER_ROLLBACK_FINDINGS|"):] for v in out if v.startswith("AFTER_ROLLBACK_FINDINGS|")))
      self.assertEqual(back["deterministic_findings"],before_json["deterministic_findings"],"ROLLBACK_FINDINGS_CHANGED")
      within=dict(v[len("DURING|"):].rsplit("|",1) for v in out if v.startswith("DURING|"))
      restored=dict(v[len("AFTER_ROLLBACK|"):].rsplit("|",1) for v in out if v.startswith("AFTER_ROLLBACK|"))
      self.assertEqual(set(within),set(baseline))
      self.assertEqual(restored,baseline,"ROLLBACK_SHA_NOT_EXACT")
      for key in sorted(baseline):
        if key in ("SEC|19","SEC|22"):
            self.assertNotEqual(within[key],baseline[key],"MISSING_PROMOTION:"+key)
            print("LF_L43_SHA|"+image+"|"+key+"|"+baseline[key]+"|"+within[key]+"|"+restored[key]+"|PASS",flush=True)
        else:self.assertEqual(within[key],baseline[key],"UNAUTHORIZED_SOURCE_EDIT:"+key)
      print("PASS_L43_STABLE_CROSSCHECK_3_TO_1_TWO_PROMOTIONS_ROLLBACK_"+image.replace(":","_"),flush=True)
      if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"],"a",encoding="utf8") as out_file:
            out_file.write("\n### L43 "+image+" STABLE: 3 to 1 (IP_USER persists); lab-only Train fixture\n\n")
            out_file.write("| Policy | Source SHA | Inside UPDATE | After ROLLBACK |\n|---|---|---|---|\n")
            for key in ("SEC|19","SEC|22"):
                out_file.write("| "+key+" | "+baseline[key]+" | "+within[key]+" | "+restored[key]+" |\n")
    finally:
       subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=60)
 def test_pg17_6(self):self.lab("postgres:17.6","170006")
 def test_pg18_7(self):self.lab("postgres:18.7","180007")
if __name__=="__main__":unittest.main()
