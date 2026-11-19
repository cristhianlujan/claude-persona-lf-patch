#!/usr/bin/env python3
"""Contract-level Niubiz 3 CREATE patch source model: REAL PG17 synthetic only.

Reports hashes from actual Step50 proposal preimages, NOT Niubiz hosted-form PASS.
"""
from pathlib import Path
import hashlib,json,os,subprocess,sys

ROOT=Path(__file__).resolve().parents[3]
SPEC=ROOT/"docs/input-governance/NIUBIZ_THREE_CANDIDATE_RULES_20261118.json"
MIG=ROOT/"supabase/migrations/20261119003000_lf_ig_niubiz_three_rule_contract_proof_only_v1.sql"
OUT=ROOT/".lf_ci/ig_niubiz_three_rule_contract_pg17"
DB="ig_niubiz_three_contract_pg17"
EXPECTED={
 "REG_CLIENT_NIUBIZ_UNIQUE_EMAIL_001":"b054d2d03bfa02d7730198c4cd19eb27ecc77a5fad7aa2fa36fbb07070e31eaa",
 "REG_CLIENT_PAYMENT_RECEIPT_REAL_EMAIL_001":"4ec80cae76a148a798fb6ceb69c2e53cc8f4f00346181e41582f3039e03bc3d4",
 "REG_CLIENT_NIUBIZ_GENERIC_BOUNCE_001":"b0d1b49a366397a69e7edff29bf604c3717c81e9a20e23b9a32f2314a46fa52c",
}
def ensure(x,why):
 if not x: raise AssertionError(why)
def pg(sql,database=DB):
 return subprocess.run(["psql","-X","-v","ON_ERROR_STOP=1","-A","-t",
       "-h","127.0.0.1","-p","5432","-U","postgres","-d",database,"-f","-"],
   input=sql,text=True,capture_output=True,env=os.environ.copy(),timeout=120,check=False)
def good(sql,label,database=DB):
 r=pg(sql,database)
 ensure(r.returncode==0,label+": "+r.stderr[-1500:])
 return r

def main():
 OUT.mkdir(parents=True,exist_ok=True)
 docs=json.loads(SPEC.read_text(encoding="utf-8"))
 mig=MIG.read_text(encoding="utf-8")
 rules=docs["rules"]
 ensure(set(EXPECTED)=={x["code"] for x in rules},"PROPOSAL_PREIMAGE_SCOPE_DRIFT")
 ensure(mig.startswith("-- Contract-level proof only"),"MIGRATION_CONTRACT_MARKER_MISSING")
 ensure("INSERT INTO lf_ops.reglas" not in mig
   and "INSERT INTO public.lf_ig_owner_decision_v2" not in mig
   and "INSERT INTO public.lf_ig_functional_train_evidence_v1" not in mig,
   "PROOF_MIGRATION_MAY_NOT_WRITE_BUSINESS_DATA")
 ensure("NIUBIZ_3_RULE_CONTRACT_PROOF_ONLY_NO_RULE_WRITES" in mig,
        "PROOF_MIGRATION_NO_FINAL_GUARD")
 specs=[{"code":x["code"],"patch":{"rule_code":x["code"],
       "change_kind":x["change_kind"],"changes":x["changes"]}} for x in rules]
 for x in rules:
   v=x["changes"]["valor_config"]
   ensure(v.get("niubiz_email_config_refs")==[
      {"scope":"PAGOS","config_key":"NIUBIZ_EMAIL_TEMPLATE"},
      {"scope":"PAGOS","config_key":"NIUBIZ_EMAIL_DOMAIN"}],"WRONG_CONFIG_REF")
   ensure("expected_template" not in v and "expected_domain" not in v,
      "VALUES_COPIED_INTO_RULE")
 good("CREATE DATABASE "+DB+";","CREATE_EPHEMERAL_FAILED","postgres")
 pre="SELECT CASE WHEN to_regclass('public.niubiz_test_proposals') IS NULL AND to_regclass('public.niubiz_test_config') IS NULL THEN 'CLEAN' ELSE 'DIRTY' END;"
 ensure(good(pre,"PRE_IMAGE").stdout.strip()=="CLEAN","EPHEMERAL_PREIMAGE_DIRTY")
 source=json.dumps(specs,ensure_ascii=False,separators=(",",":")).replace("'","''")
 sql=r"""
BEGIN;
CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE TABLE public.niubiz_test_config(
 scope text, config_key text, config_value text, value_type text, value_status text);
INSERT INTO public.niubiz_test_config VALUES
 ('PAGOS','NIUBIZ_EMAIL_TEMPLATE','{nombre}.{apellido}.synthetic-{codigo}','TEXT','REAL'),
 ('PAGOS','NIUBIZ_EMAIL_DOMAIN','dynamic-a.invalid','TEXT','REAL');
CREATE TABLE public.niubiz_test_proposals AS
SELECT p->>'code' AS code,p->'patch' AS patch
FROM jsonb_array_elements('""" + source + r"""'::jsonb) p;
DO $test$
DECLARE v record; sha text; expected_sha text; refs jsonb;
        current_ref jsonb:='[
          {"scope":"PAGOS","config_key":"NIUBIZ_EMAIL_TEMPLATE"},
          {"scope":"PAGOS","config_key":"NIUBIZ_EMAIL_DOMAIN"}]'::jsonb;
        pre_digest text; post_digest text;
BEGIN
 IF (SELECT count(*) FROM public.niubiz_test_proposals)<>3
    OR (SELECT count(DISTINCT code) FROM public.niubiz_test_proposals)<>3
 THEN RAISE EXCEPTION 'THREE_DISTINCT_PATCHES_REQUIRED'; END IF;
 RAISE NOTICE 'NIUBIZ_CONTRACT_3_DISTINCT_CODES_PASS';
 FOR v IN SELECT * FROM public.niubiz_test_proposals ORDER BY code LOOP
   sha:=encode(extensions.digest(convert_to(v.patch::text,'UTF8'),'sha256'),'hex');
   expected_sha:=CASE v.code
     WHEN 'REG_CLIENT_NIUBIZ_UNIQUE_EMAIL_001' THEN 'b054d2d03bfa02d7730198c4cd19eb27ecc77a5fad7aa2fa36fbb07070e31eaa'
     WHEN 'REG_CLIENT_PAYMENT_RECEIPT_REAL_EMAIL_001' THEN '4ec80cae76a148a798fb6ceb69c2e53cc8f4f00346181e41582f3039e03bc3d4'
     WHEN 'REG_CLIENT_NIUBIZ_GENERIC_BOUNCE_001' THEN 'b0d1b49a366397a69e7edff29bf604c3717c81e9a20e23b9a32f2314a46fa52c'
     ELSE NULL END;
   IF sha IS DISTINCT FROM expected_sha OR v.patch->>'change_kind'<>'CREATE'
      OR v.patch->>'rule_code' IS DISTINCT FROM v.code
   THEN RAISE EXCEPTION 'REAL_STEP50_PATCH_SHA_MISMATCH:%:%',v.code,sha; END IF;
   refs:=v.patch#>'{changes,valor_config,niubiz_email_config_refs}';
   IF refs IS DISTINCT FROM current_ref
      OR EXISTS(SELECT 1 FROM jsonb_array_elements(refs) e
           LEFT JOIN public.niubiz_test_config c ON c.scope=e->>'scope'
             AND c.config_key=e->>'config_key'
           WHERE c.scope IS NULL OR c.value_status<>'REAL' OR c.value_type<>'TEXT')
   THEN RAISE EXCEPTION 'CONFIG_REF_NOT_RESOLVED:%',v.code; END IF;
   IF v.patch#>>'{changes,descripcion}' LIKE '%gmail.com%'
      OR v.patch#>>'{changes,descripcion}' LIKE '%lf-{codigo}%'
      OR (v.patch#>'{changes,valor_config}') ? 'expected_template'
      OR (v.patch#>'{changes,valor_config}') ? 'expected_domain'
      OR v.patch#>>'{changes,valor_config,production_authorized}'<>'false'
   THEN RAISE EXCEPTION 'HARDCODE_OR_GO_INVALID:%',v.code; END IF;
 END LOOP;
 RAISE NOTICE 'NIUBIZ_CONTRACT_3_EXACT_STEP50_SHA_AND_DYNAMIC_REFS_PASS';
 SELECT md5(coalesce(jsonb_agg(to_jsonb(t) ORDER BY code)::text,'[]'))
 INTO pre_digest FROM public.niubiz_test_proposals t;
 UPDATE public.niubiz_test_config SET config_value='dynamic-b.invalid'
 WHERE scope='PAGOS' AND config_key='NIUBIZ_EMAIL_DOMAIN';
 SELECT md5(coalesce(jsonb_agg(to_jsonb(t) ORDER BY code)::text,'[]'))
 INTO post_digest FROM public.niubiz_test_proposals t;
 IF pre_digest IS DISTINCT FROM post_digest
 THEN RAISE EXCEPTION 'CONFIG_VALUE_CHANGE_MUTATED_PATCH'; END IF;
 RAISE NOTICE 'NIUBIZ_CONTRACT_CONFIG_VALUES_DYNAMIC_NO_PATCH_MUTATION_PASS';
 IF NOT EXISTS(SELECT 1 FROM public.niubiz_test_proposals
    WHERE code='REG_CLIENT_PAYMENT_RECEIPT_REAL_EMAIL_001'
      AND patch#>>'{changes,valor_config,customer_receipt_destination}'='REAL_EMAIL_ONLY'
      AND patch#>>'{changes,valor_config,receipt_trigger}'='PAYMENT_CONFIRMED_AUTHORITATIVE'
      AND patch#>>'{changes,valor_config,provider_technical_email_not_receipt_destination}'='true')
 THEN RAISE EXCEPTION 'REAL_RECEIPT_CONTRACT_MISSING'; END IF;
 RAISE NOTICE 'NIUBIZ_CONTRACT_REAL_RECEIPT_CONFIRMED_ONLY_PASS';
 IF NOT EXISTS(SELECT 1 FROM public.niubiz_test_proposals
   WHERE code='REG_CLIENT_NIUBIZ_GENERIC_BOUNCE_001'
     AND patch#>>'{changes,valor_config,generic_email_bounce_policy}'='ACCEPT_AFTER_PROVIDER_ACCEPTANCE'
     AND patch#>>'{changes,valor_config,bounce_is_payment_rejection}'='false'
     AND patch#>>'{changes,valor_config,bounce_is_payment_confirmation}'='false'
     AND patch#>>'{changes,valor_config,provider_format_rejection}'='BLOCK_AND_TRACE')
 THEN RAISE EXCEPTION 'BOUNCE_SEMANTICS_INVALID'; END IF;
 RAISE NOTICE 'NIUBIZ_CONTRACT_BOUNCE_VS_PROVIDER_REJECT_PASS';
 IF NOT EXISTS(SELECT 1 FROM public.niubiz_test_proposals
   WHERE code='REG_CLIENT_NIUBIZ_UNIQUE_EMAIL_001'
     AND patch#>>'{changes,valor_config,hyphen_niubiz_sandbox}'='NOT_TESTED'
     AND patch#>>'{changes,valor_config,uniqueness_scope}'='CLIENT_GLOBAL'
     AND patch#>>'{changes,valor_config,reuse_same_client}'='true')
 THEN RAISE EXCEPTION 'UNIQUENESS_OR_HYPHEN_RISK_LOST'; END IF;
 RAISE NOTICE 'NIUBIZ_CONTRACT_UNIQUE_EMAIL_HYPHEN_NOT_TESTED_PASS';
 DELETE FROM public.niubiz_test_config
 WHERE config_key='NIUBIZ_EMAIL_DOMAIN';
 IF (SELECT count(*) FROM public.niubiz_test_config
    WHERE scope='PAGOS' AND config_key IN
      ('NIUBIZ_EMAIL_TEMPLATE','NIUBIZ_EMAIL_DOMAIN'))<>1
 THEN RAISE EXCEPTION 'CONFIG_NEGATIVE_SETUP_FAILED'; END IF;
 IF (SELECT count(*) FROM public.niubiz_test_config
    WHERE scope='PAGOS' AND config_key='NIUBIZ_EMAIL_DOMAIN')<>0
 THEN RAISE EXCEPTION 'NEGATIVE_DOMAIN_STILL_PRESENT'; END IF;
 IF (SELECT count(*) FROM public.niubiz_test_proposals p
    WHERE EXISTS(SELECT 1 FROM jsonb_array_elements(
      p.patch#>'{changes,valor_config,niubiz_email_config_refs}') e
      LEFT JOIN public.niubiz_test_config c
        ON c.scope=e->>'scope' AND c.config_key=e->>'config_key'
      WHERE c.scope IS NULL))<>3
 THEN RAISE EXCEPTION 'CONFIG_MISSING_DOMAIN_NOT_DETECTED_FOR_ALL'; END IF;
 RAISE NOTICE 'NIUBIZ_CONTRACT_MISSING_DOMAIN_IS_DETECTABLE_PASS';
 IF (SELECT count(*) FROM public.niubiz_test_proposals)<>3
 THEN RAISE EXCEPTION 'SYNTHETIC_PATCH_ROWS_CHANGED'; END IF;
 RAISE NOTICE 'NIUBIZ_CONTRACT_NO_CANONICAL_RULE_WRITES_PASS';
END $test$;
ROLLBACK;
"""
 r=pg(sql)
 log=r.stdout+"\n"+r.stderr
 (OUT/"transaction.log").write_text(log)
 tags=[
 "NIUBIZ_CONTRACT_3_DISTINCT_CODES_PASS",
 "NIUBIZ_CONTRACT_3_EXACT_STEP50_SHA_AND_DYNAMIC_REFS_PASS",
 "NIUBIZ_CONTRACT_CONFIG_VALUES_DYNAMIC_NO_PATCH_MUTATION_PASS",
 "NIUBIZ_CONTRACT_REAL_RECEIPT_CONFIRMED_ONLY_PASS",
 "NIUBIZ_CONTRACT_BOUNCE_VS_PROVIDER_REJECT_PASS",
 "NIUBIZ_CONTRACT_UNIQUE_EMAIL_HYPHEN_NOT_TESTED_PASS",
 "NIUBIZ_CONTRACT_MISSING_DOMAIN_IS_DETECTABLE_PASS",
 "NIUBIZ_CONTRACT_NO_CANONICAL_RULE_WRITES_PASS"]
 after=good(pre,"INDEPENDENT_SELECT_AFTER_ROLLBACK").stdout.strip()
 result={"status":"FAIL","real_pg17":True,"fixture":"SYNTHETIC_DATA_ONLY",
   "remote_supabase_written":False,"niubiz_hosted_form":"NOT_TESTED",
   "checks":{t:t in log for t in tags},"transaction_exit":r.returncode,
   "independent_readback":after,
   "log_sha256":hashlib.sha256(log.encode()).hexdigest(),
   "readback_sha256":hashlib.sha256(after.encode()).hexdigest(),
   "check_manifest_sha256":hashlib.sha256(json.dumps(tags,sort_keys=True).encode()).hexdigest(),
   "source_sha256":hashlib.sha256(SPEC.read_bytes()).hexdigest(),
   "patch_shas_from_live_step50":EXPECTED}
 ensure(r.returncode==0 and all(result["checks"].values()),"PG17_PATCH_CONTRACT_FAILED "+log[-1800:])
 ensure(after=="CLEAN","ROLLBACK_DIRTY "+after)
 result["status"]="PASS"
 (OUT/"report.json").write_text(json.dumps(result,indent=2,sort_keys=True)+"\n")
 print("IG_NIUBIZ_RULE_CONTRACT_REAL_PG17_8_OF_8_PASS")
 print(json.dumps({"status":result["status"],
   "report_log_sha256":result["log_sha256"],
   "readback_sha256":result["readback_sha256"],
   "manifest_sha256":result["check_manifest_sha256"]},sort_keys=True))
 return 0

if __name__=="__main__":
 try: sys.exit(main())
 except Exception as e:
   print("NIUBIZ_RULE_CONTRACT_PG17_BLOCKED "+str(e)[:1800],file=sys.stderr)
   sys.exit(1)
