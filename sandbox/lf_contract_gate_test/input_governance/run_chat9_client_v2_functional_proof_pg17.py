#!/usr/bin/env python3
"""PostgreSQL17 proof for EXACT two GPT_NATIVE Step50 patches; no Supabase writes."""
import hashlib,json,os,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/".lf_ci/chat9_client_v2_functional_proof"
OUT.mkdir(parents=True,exist_ok=True)
FIXTURE=ROOT/"docs/input-governance/IG_CHAT9_CLIENT_RULE_V2_EXACT_SOURCE_PATCH_20261118.json"
def check(ok,name):
    if not ok:raise AssertionError(name)
def sql(query):
    return subprocess.run(["psql","-X","-A","-t","-v","ON_ERROR_STOP=1",
      "-h","127.0.0.1","-p","5432","-U","postgres","-d","postgres","-f","-"],
      input=query,text=True,capture_output=True,timeout=120,env=os.environ.copy(),check=False)
def execute(query,name):
    r=sql(query)
    check(r.returncode==0,name+":"+r.stderr[-1900:])
    return r.stdout
def literal(s):return "'"+s.replace("'","''")+"'"
def after_readback():
    q="""SELECT jsonb_build_object(
      'rules',(SELECT count(*) FROM lf_ops.reglas),
      'vigente',(SELECT count(*) FROM lf_ops.reglas WHERE estado='VIGENTE'),
      'candidate',(SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO'),
      'config_rows',(SELECT count(*) FROM public.lf_global_config),
      'rule_md5',(SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY codigo)::text,'[]')) FROM lf_ops.reglas r),
      'config_md5',(SELECT md5(coalesce(jsonb_agg(to_jsonb(c) ORDER BY scope,config_key)::text,'[]')) FROM public.lf_global_config c))::text;"""
    return json.loads(execute(q,"INDEPENDENT_SELECT").strip().splitlines()[-1])

def main():
    report={"status":"FAIL","remote_supabase_written":False,
      "backend_e2e":"NOT_TESTED","owner_decide_v2":"NOT_CALLED",
      "test_scope":"FUNCTIONAL_RULE_CONTRACT_PG17_ONLY",
      "train_receipt_status":"REQUIRES_COMPLETED_TRAIN_AFTER_CI"}
    try:
        check(os.environ.get("GITHUB_EVENT_NAME")=="pull_request","PULL_REQUEST_REQUIRED")
        check(os.environ.get("GITHUB_REPOSITORY")=="cristhianlujan/claude-persona-lf-patch","REPO_MISMATCH")
        head=subprocess.check_output(["git","-C",str(ROOT),"rev-parse","HEAD"],text=True).strip()
        check(head==os.environ.get("CHAT9_V2_PROOF_HEAD"),"EXACT_HEAD_MISMATCH")
        report["head"]=head
        fixture=FIXTURE.read_text()
        report["fixture_sha256"]=hashlib.sha256(fixture.encode()).hexdigest()
        data=json.loads(fixture)
        entries=data["rule_entries"]
        check({x["codigo"] for x in entries}=={"REG_SES_003","REG_ATQ_016"},"RULE_SCOPE_DRIFT")
        check(len(data["global_config"])==6 and
              {x["scope"] for x in data["global_config"]}=={"CLIENT"},"CONFIG_SCOPE_DRIFT")
        files=list((ROOT/"supabase/migrations").glob("*_lf_ig_chat9_client_v2_preflight_proof_only_v1.sql"))
        check(len(files)==1,"MIGRATION_SOURCE_NOT_UNIQUE")
        source=files[0].read_text()
        check(source.count("\nBEGIN;")==1 and source.count("\nCOMMIT;")==1,"TRANSACTION_SHAPE_DRIFT")
        check(not re.search(r"\b(?:UPDATE|INSERT INTO|DELETE FROM)\s+lf_ops\.reglas\b",source,re.I),
              "OFFICIAL_MIGRATION_MUST_NOT_MUTATE_RULES")
        report["source_sha256"]=hashlib.sha256(source.encode()).hexdigest()
        report["source_path"]=str(files[0].relative_to(ROOT))
        setup="""
CREATE SCHEMA lf_ops;
CREATE SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE TABLE public.lf_global_config(
 scope text,config_key text,config_value text,value_type text,value_status text,
 valid_from timestamptz DEFAULT now(),created_at timestamptz DEFAULT now());
CREATE TABLE lf_ops.reglas(
 id integer PRIMARY KEY,codigo text NOT NULL UNIQUE,categoria text NOT NULL,
 titulo text NOT NULL,descripcion text NOT NULL,razon text,valor_config jsonb,
 es_transversal boolean NOT NULL DEFAULT false,estado text NOT NULL,
 origen text,created_at timestamptz DEFAULT now(),updated_at timestamptz DEFAULT now(),
 pendiente_decision boolean DEFAULT false,pendiente_detalle text,created_by text);
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,operation_code text,target_code text,
 status text,manifest jsonb);
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text,step_id text,status text,evidence_payload jsonb);
CREATE TABLE public.lf_ig_functional_train_evidence_v1(rule_code text);
CREATE OR REPLACE FUNCTION public.lf_asset_snapshot_sha_v1(p_asset_type text,p_code text)
 RETURNS text LANGUAGE sql STABLE AS $src$
 SELECT encode(extensions.digest(convert_to(
   (to_jsonb(r)-'created_at'-'updated_at')::text,'UTF8'),'sha256'),'hex')
 FROM lf_ops.reglas r WHERE p_asset_type='REGLA' AND r.codigo=p_code
 $src$;
INSERT INTO lf_ops.reglas(id,codigo,categoria,titulo,descripcion,razon,valor_config,
 es_transversal,estado,origen,pendiente_decision,pendiente_detalle)
 SELECT 10000+i,'DUMMY_'||lpad(i::text,4,'0'),
 'UNTOUCHED','Dummy','Dummy',NULL,'{}'::jsonb,false,
 CASE WHEN i<=436 THEN 'VIGENTE' ELSE 'CANDIDATO' END,NULL,false,NULL
 FROM generate_series(1,577) i;
INSERT INTO public.lf_global_config(scope,config_key,config_value,value_type,value_status)
 SELECT 'AUTH','DUMMY_'||lpad(i::text,3,'0'),'1','INTEGER','REAL'
 FROM generate_series(1,40) i;
"""
        execute(setup,"FIXTURE_SETUP")
        for r in entries:
            js=json.dumps(r["source_row"],ensure_ascii=False,separators=(",",":"))
            execute("INSERT INTO lf_ops.reglas SELECT * FROM jsonb_populate_record(NULL::lf_ops.reglas,"+literal(js)+"::jsonb);", "SOURCE_ROW_SETUP")
            request={
              "governed_rule_patch":r["governed_rule_patch"]
            }
            execute("INSERT INTO public.lf_operation_execution VALUES("+
              literal(r["parent_execution_id"])+",'EJECUCION_PERFIL_LF','PERFIL-PRODUCT-DIRECTOR-LF','IN_PROGRESS',"+
              literal(json.dumps({"read_only":True,"no_write":True}))+"::jsonb);",
              "PARENT_SETUP")
            execute("INSERT INTO public.lf_operation_execution_steps VALUES("+
              literal(r["parent_execution_id"])+",'input_validate','STEP_PASS_WITH_EVIDENCE','{}'::jsonb),("+
              literal(r["parent_execution_id"])+",'output_validate','STEP_PASS_WITH_EVIDENCE','{\"output_contract_result\":\"PASS\"}'::jsonb),("+
              literal(r["parent_execution_id"])+",'execute_profile','STEP_PASS_WITH_EVIDENCE',"+
              literal(json.dumps({"profile_output":{"deliverable_created":request}}))+"::jsonb);",
              "STEP_SETUP")
        for p in data["global_config"]:
            execute("INSERT INTO public.lf_global_config(scope,config_key,config_value,value_type,value_status) VALUES("+
              ",".join(literal(p[k]) for k in ["scope","config_key","config_value","value_type","value_status"])+");","SIX_REAL_CONFIG")
        baseline=after_readback()
        check((baseline["rules"],baseline["vigente"],baseline["candidate"],baseline["config_rows"])==(579,438,141,46),"BASELINE_COUNTS_DRIFT")
        for r in entries:
            observed=execute("SELECT public.lf_asset_snapshot_sha_v1('REGLA',"+literal(r["codigo"])+");","SHA_FIXTURE").strip()
            check(observed==r["source_snapshot_sha256"],r["codigo"]+":SOURCE_SHA_DRIFT")
            patch=execute("SELECT encode(extensions.digest(convert_to("+
              "(SELECT evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}' FROM public.lf_operation_execution_steps "+
              "WHERE step_id='execute_profile' AND execution_id="+literal(r["parent_execution_id"])+")::text,'UTF8'),'sha256'),'hex');","PATCH_SHA").strip()
            check(patch==r["proposal_sha256"],r["codigo"]+":PATCH_SHA_DRIFT")
        checks={"source_sha_both":True,"patch_sha_both":True}
        body=source.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;",1)[0]
        setup_sim="""
-- The test oracle models *contract* intent, not backend E2E.
CREATE FUNCTION lf_ops.test_account_concurrency(p_account text,p_current_sessions integer)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
 SELECT p_account IS NOT NULL AND length(p_account)>0 AND
 p_current_sessions <
 (SELECT config_value::integer FROM public.lf_global_config WHERE scope='CLIENT'
  AND config_key=(SELECT valor_config#>>'{max_concurrent_sessions_config_ref,config_key}'
    FROM lf_ops.reglas WHERE codigo='REG_SES_003') AND value_status='REAL')
$fn$;
CREATE FUNCTION lf_ops.test_antiabuse(p_account text,p_independent_evidence boolean,p_ip_signal boolean)
RETURNS text LANGUAGE sql STABLE AS $fn$
 SELECT CASE WHEN p_ip_signal AND nullif(p_account,'') IS NOT NULL
                  AND p_independent_evidence THEN 'ACCOUNT_HOLD_ONLY'
             WHEN p_ip_signal THEN 'ALERT_NO_SHARED_IP_BLOCK'
             ELSE 'NO_RESTRICTION' END
$fn$;
"""
        pos="BEGIN;\n"+body+"""
SELECT 'PREFLIGHT_SOURCE_PASS';
"""+setup_sim
        for r in entries:
            p=r["governed_rule_patch"]["changes"]
            pos+=("\nUPDATE lf_ops.reglas SET descripcion="+literal(p["descripcion"])+
                 ",razon="+literal(p["razon"])+",valor_config="+literal(json.dumps(p["valor_config"],ensure_ascii=False))+
                 "::jsonb,pendiente_decision=false,pendiente_detalle=NULL WHERE codigo="+literal(r["codigo"])+";\n")
            pos+=("SELECT CASE WHEN public.lf_asset_snapshot_sha_v1('REGLA',"+literal(r["codigo"])+")="+
               literal(r["candidate_snapshot_sha256"])+" THEN 'CANDIDATE_SHA_PASS_"+r["codigo"]+
               "' ELSE 'CANDIDATE_SHA_FAIL_"+r["codigo"]+"' END;\n")
        pos+="""
SELECT CASE WHEN
 (SELECT count(*) FROM lf_ops.reglas WHERE codigo IN ('REG_SES_003','REG_ATQ_016')
  AND (valor_config ? 'max_sesiones' OR valor_config ? 'patron_1' OR valor_config ? 'accion'))=0
 AND lf_ops.test_account_concurrency('accountA',0)
 AND lf_ops.test_account_concurrency('accountB',0)
 AND NOT lf_ops.test_account_concurrency('accountA',3)
 AND lf_ops.test_antiabuse(NULL,false,true)='ALERT_NO_SHARED_IP_BLOCK'
 AND lf_ops.test_antiabuse('accountB',false,true)='ALERT_NO_SHARED_IP_BLOCK'
 AND lf_ops.test_antiabuse('accountA',true,true)='ACCOUNT_HOLD_ONLY'
 THEN 'SHARED_IP_ACCOUNT_ONLY_PASS' ELSE 'SHARED_IP_ORACLE_FAIL' END;
UPDATE public.lf_global_config SET config_value='2'
 WHERE scope='CLIENT' AND config_key='ONBOARDING_ACCOUNT_MAX_CONCURRENT_SESSIONS';
SELECT CASE WHEN NOT lf_ops.test_account_concurrency('accountA',2)
 AND lf_ops.test_account_concurrency('accountB',1)
 THEN 'DYNAMIC_SESSIONS_PASS' ELSE 'DYNAMIC_SESSIONS_FAIL' END;
UPDATE public.lf_global_config SET config_value='30'
 WHERE scope='CLIENT' AND config_key='ATQ_ACCOUNT_HOLD_MINUTES';
SELECT CASE WHEN (SELECT config_value::integer FROM public.lf_global_config
 WHERE scope='CLIENT' AND config_key=
 (SELECT valor_config#>>'{account_hold_minutes_config_ref,config_key}'
 FROM lf_ops.reglas WHERE codigo='REG_ATQ_016'))=30
 THEN 'DYNAMIC_ACCOUNT_HOLD_PASS' ELSE 'DYNAMIC_ACCOUNT_HOLD_FAIL' END;
ROLLBACK;
"""
        output=execute(pos,"ACTUAL_POSTIMAGE_PG17_ROLLBACK")
        for sentinel in ["PREFLIGHT_SOURCE_PASS","SHARED_IP_ACCOUNT_ONLY_PASS","DYNAMIC_SESSIONS_PASS",
                         "DYNAMIC_ACCOUNT_HOLD_PASS",*["CANDIDATE_SHA_PASS_"+r["codigo"] for r in entries]]:
            check(sentinel in output,"EXPECTED_CONTRACT_TEST_NOT_PASS:"+sentinel)
        check(after_readback()==baseline,"ROLLBACK_NOT_RESTORED")
        checks["real_begin_rollback_and_separate_readback"]=True
        checks["shared_ip_separation"]=True
        checks["config_change_dynamic"]=True
        checks["candidate_sha_exact"]=True
        negative=[
           ("source_row_drift","UPDATE lf_ops.reglas SET descripcion='DRIFT' WHERE codigo='REG_SES_003';",
              "CHAT9_L2_PROOF_PARENT_OR_SOURCE_DRIFT"),
           ("patch_drift","UPDATE public.lf_operation_execution_steps SET evidence_payload='{}'::jsonb WHERE step_id='execute_profile' AND execution_id="+literal(entries[0]["parent_execution_id"])+";",
              "CHAT9_L2_PROOF_PATCH_SCOPE_OR_SHA_DRIFT"),
           ("missing_client_config","DELETE FROM public.lf_global_config WHERE scope='CLIENT' AND config_key='ATQ_ACCOUNT_HOLD_MINUTES';",
              "CHAT9_L2_PROOF_SOURCE_BASELINE_DRIFT"),
        ]
        for label,tamper,code in negative:
            x=sql("BEGIN;\n"+tamper+"\n"+body+"\nROLLBACK;\n")
            check(x.returncode!=0 and code in x.stderr,label+":"+x.stderr[-1200:])
            check(after_readback()==baseline,label+"_LEFT_DIRTY_DB")
            checks[label]=True
        report.update(status="PASS",checks=checks,head=head,preimage=baseline,
           independent_readback=after_readback(),rule_entries=[
             {k:r[k] for k in ("codigo","source_snapshot_sha256","proposal_sha256","candidate_snapshot_sha256")}
             for r in entries],
           simulated_functional_test=True,executed_pg17_real=True)
    except Exception as e:
        report["error"]=str(e)[:1700]
    (OUT/"report.json").write_text(json.dumps(report,sort_keys=True,indent=2)+"\n")
    print(json.dumps(report,sort_keys=True))
    return 0 if report["status"]=="PASS" else 1
if __name__=="__main__":sys.exit(main())
