#!/usr/bin/env python3
"""IG Chat9 global rate-limit refs: real ephemeral PG17 BEGIN/ROLLBACK and independent SELECT."""
import hashlib, json, os, re, subprocess, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/".lf_ci/chat9_global_rate_refs"
OUT.mkdir(parents=True,exist_ok=True)
GLOB="*_lf_ig_global_rate_limit_config_refs_v1.sql"

def insist(cond,msg):
    if not cond: raise AssertionError(msg)
def sql(q):
    return subprocess.run(["psql","-X","-v","ON_ERROR_STOP=1","-A","-t",
        "-h","127.0.0.1","-p","5432","-U","postgres","-d","postgres","-f","-"],
        input=q,text=True,capture_output=True,env=os.environ.copy(),timeout=125,check=False)
def sql_ok(q,what):
    r=sql(q)
    insist(r.returncode==0,what+":"+r.stderr[-1900:])
    return r
def readback():
    q="""SELECT jsonb_build_object(
      'config_rows',(SELECT count(*) FROM public.lf_global_config),
      'policy_rows',(SELECT count(*) FROM lf_ops.politicas_rate_limit),
      'rules',(SELECT count(*) FROM lf_ops.reglas),
      'view_exists',to_regclass('lf_ops.v_politicas_rate_limit_effective_v1') IS NOT NULL,
      'refs_exists',(SELECT count(*) FROM information_schema.columns WHERE table_schema='lf_ops' AND table_name='politicas_rate_limit' AND column_name='config_refs'),
      'config_md5',(SELECT md5(coalesce(jsonb_agg(to_jsonb(c) ORDER BY scope,config_key)::text,'[]')) FROM public.lf_global_config c),
      'policy_md5',(SELECT md5(coalesce(jsonb_agg(to_jsonb(p) ORDER BY rate_limit_policy_id)::text,'[]')) FROM lf_ops.politicas_rate_limit p),
      'rules_md5',(SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY codigo)::text,'[]')) FROM lf_ops.reglas r))::text;"""
    return json.loads(sql_ok(q,"INDEPENDENT_READBACK_QUERY").stdout.strip().splitlines()[-1])

def main():
    report={"status":"FAIL","test_engine":"REAL_EPHEMERAL_POSTGRESQL17",
      "remote_supabase_written":False,"backend_enforcement_e2e":"NOT_TESTED",
      "maintenance_ui_implemented":False}
    try:
        insist(os.environ.get("GITHUB_EVENT_NAME")=="pull_request","PR_ONLY")
        insist(os.environ.get("GITHUB_REPOSITORY")=="cristhianlujan/claude-persona-lf-patch","WRONG_REPO")
        head=subprocess.check_output(["git","-C",str(ROOT),"rev-parse","HEAD"],text=True).strip()
        insist(head==os.environ.get("CHAT9_REF_EXACT_HEAD"),"HEAD_MISMATCH")
        report["head"]=head
        paths=list((ROOT/"supabase/migrations").glob(GLOB))
        insist(len(paths)==1,"MIGRATION_SUFFIX_NOT_UNIQUE")
        source=paths[0].read_text()
        insist(source.count("\nBEGIN;")==1 and source.count("\nCOMMIT;")==1,"ONE_MIGRATION_TX")
        insist(not re.search(r"\b(?:UPDATE|DELETE\s+FROM|INSERT\s+INTO)\s+lf_ops\.reglas\b",source,re.I),
          "RULE_DML_OUT_OF_SCOPE")
        report["migration"]=str(paths[0].relative_to(ROOT))
        report["migration_sha256"]=hashlib.sha256(source.encode()).hexdigest()

        setup="""
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE supabase_read_only_user NOLOGIN;
CREATE SCHEMA lf_ops;
CREATE SCHEMA programacion;
CREATE TABLE lf_ops.reglas(codigo text PRIMARY KEY, estado text NOT NULL);
INSERT INTO lf_ops.reglas SELECT 'RULE_'||lpad(i::text,4,'0'),
       CASE WHEN i<=438 THEN 'VIGENTE' ELSE 'CANDIDATO' END
FROM generate_series(1,579) i;
CREATE TABLE public.lf_global_config(
 scope text NOT NULL,config_key text NOT NULL,config_value text NOT NULL,
 value_type text NOT NULL CHECK(value_type IN ('TEXT','INTEGER','DECIMAL','BOOLEAN','JSON','EMAIL')),
 value_status text NOT NULL CHECK(value_status IN ('REAL','FICTICIO')),
 description text,
 valid_from timestamptz NOT NULL DEFAULT now(),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(scope,config_key,valid_from));
ALTER TABLE public.lf_global_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lf_global_config FORCE ROW LEVEL SECURITY;
INSERT INTO public.lf_global_config(scope,config_key,config_value,value_type,value_status) VALUES
 ('AUTH','LOGIN_LOCKOUT_ATTEMPTS_1','5','INTEGER','REAL'),
 ('AUTH','LOGIN_LOCKOUT_ATTEMPTS_2','3','INTEGER','REAL'),
 ('AUTH','LOGIN_LOCKOUT_ATTEMPTS_3','3','INTEGER','REAL'),
 ('AUTH','LOGIN_LOCKOUT_MINUTES_1','15','INTEGER','REAL'),
 ('AUTH','LOGIN_LOCKOUT_MINUTES_2','60','INTEGER','REAL'),
 ('AUTH','LOGIN_LOCKOUT_MINUTES_3','1440','INTEGER','REAL'),
 ('AUTH','LOGIN_LOCKOUT_RESET_MINUTES','1440','INTEGER','REAL'),
 ('AUTH','MFA_DEVICE_IDLE_DAYS','30','INTEGER','REAL'),
 ('AUTH','MFA_PASSWORD_AGE_MONTHS','3','INTEGER','REAL'),
 ('AUTH','TEMP_KEY_TTL_HOURS','24','INTEGER','REAL'),
 ('PAGOS','NIUBIZ_EMAIL_DOMAIN','gmail.com','TEXT','REAL'),
 ('PAGOS','NIUBIZ_EMAIL_TEMPLATE','{nombre}.{apellido}.lf-{codigo}','TEXT','REAL');

CREATE TABLE lf_ops.politicas_rate_limit(
 policy_code text NOT NULL,resource_code text NOT NULL,
 window_seconds integer NOT NULL,max_requests integer NOT NULL,burst_limit integer NOT NULL,
 scope_key text NOT NULL,error_code text,status text NOT NULL DEFAULT 'CANDIDATO',
 source_decision_id text,created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 rate_limit_policy_id bigint PRIMARY KEY,error_id bigint,source_decision_number bigint,
 parameter_provenance jsonb NOT NULL DEFAULT '{}'::jsonb,
 CONSTRAINT politicas_rate_limit_values_ck CHECK(window_seconds>0 AND max_requests>0 AND burst_limit>=max_requests),
 CONSTRAINT politicas_rate_limit_status_ck CHECK(status IN ('CANDIDATO','EN_REVISION','VIGENTE','INACTIVO','ARCHIVADO')),
 CONSTRAINT politicas_rate_limit_uk UNIQUE(resource_code,scope_key));
INSERT INTO lf_ops.politicas_rate_limit
 (rate_limit_policy_id,policy_code,resource_code,scope_key,window_seconds,max_requests,burst_limit,status)
VALUES
 (1,'RATE-B2B-LOGIN','AUTH_LOGIN','USER',900,5,5,'VIGENTE'),
 (2,'RATE-B2B-UPLOAD','FILE_UPLOAD','TENANT_USER',3600,20,25,'CANDIDATO'),
 (3,'RATE-B2B-APPROVAL','APPROVAL_DECISION','TENANT_USER',60,30,30,'CANDIDATO'),
 (4,'RATE-B2B-DOWNLOAD','FILE_DOWNLOAD','TENANT_USER',60,60,80,'CANDIDATO'),
 (5,'RATE-B2B-API-READ','API_READ','TENANT_USER',60,300,400,'CANDIDATO'),
 (6,'RATE-B2B-SESSION-REFRESH','SESSION_REFRESH','USER',60,10,12,'CANDIDATO'),
 (7,'RATE-B2B-PASSWORD-RECOVERY-OTP','AUTH_PASSWORD_RECOVERY_OTP_SEND','USER',900,5,5,'CANDIDATO'),
 (8,'RATE-B2B-NEW-DEVICE-OTP','AUTH_NEW_DEVICE_OTP_SEND','USER',900,5,5,'CANDIDATO'),
 (9,'RATE-CLIENT-OTP-PHONE-CROSSSESSION','CLIENT_OTP_SEND','PHONE_HASH',3600,5,5,'VIGENTE'),
 (10,'RATE-B2B-LOGIN-FAILED-PASSWORD','AUTH_LOGIN_FAILED_PASSWORD','USER',900,5,5,'CANDIDATO');

CREATE FUNCTION lf_ops.fn_b2b_backoffice_login_contract(text,text,text)
RETURNS TABLE(policy_code text,max_requests integer)
LANGUAGE sql STABLE
AS $fx$ SELECT rp.policy_code,rp.max_requests from lf_ops.politicas_rate_limit rp $fx$;
CREATE FUNCTION lf_ops.fn_screen_contract_v1(text,text,text)
RETURNS TABLE(policy_code text,max_requests integer)
LANGUAGE sql STABLE
AS $fx$ SELECT rp.policy_code,rp.max_requests from lf_ops.politicas_rate_limit rp $fx$;
"""
        sql_ok(setup,"SETUP_FAILED")
        before=readback()
        insist((before["config_rows"],before["policy_rows"],before["rules"],before["view_exists"],before["refs_exists"])==
              (12,10,579,False,0),"PREIMAGE_COUNT_ERROR")
        body=source.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;",1)[0]
        verify="""
SELECT CASE WHEN
 (SELECT count(*) FROM lf_ops.v_politicas_rate_limit_effective_v1)=10
 AND (SELECT count(*) FROM lf_ops.v_politicas_rate_limit_effective_v1 WHERE resolution_status='READY')=10
 AND (SELECT count(*) FROM lf_ops.politicas_rate_limit WHERE window_seconds IS NULL
   AND max_requests IS NULL AND burst_limit IS NULL)=10
 AND (SELECT count(*) FROM lf_ops.fn_screen_contract_v1('a','b','c') WHERE max_requests IS NOT NULL)=10
 AND (SELECT count(*) FROM lf_ops.fn_b2b_backoffice_login_contract('a','b','c') WHERE max_requests IS NOT NULL)=10
 THEN 'POSITIVE_10_POLICIES_EFFECTIVE_READY' ELSE 'POSITIVE_FAIL' END;

-- Change ONE shared OTP variable (5 -> 4). Both B2B OTP rows must
-- change while password-failure keeps its independent value 5.
UPDATE public.lf_global_config SET config_value='4'
WHERE scope='AUTH' AND config_key='OTP_MAX_ATTEMPTS';
SELECT CASE WHEN
 (SELECT count(*) FROM lf_ops.v_politicas_rate_limit_effective_v1
   WHERE rate_limit_policy_id IN (7,8) AND max_requests=4 AND resolution_status='READY')=2
 AND (SELECT max_requests FROM lf_ops.v_politicas_rate_limit_effective_v1
   WHERE rate_limit_policy_id=10)=5
 AND (SELECT count(*) FROM lf_ops.politicas_rate_limit
   WHERE max_requests IS NULL)=10
 THEN 'DYNAMIC_OTP_5_TO_4_PASS' ELSE 'DYNAMIC_OTP_FAILED' END;

UPDATE public.lf_global_config SET config_value='1200'
WHERE scope='AUTH' AND config_key='PASSWORD_FAIL_WINDOW_SECONDS';
SELECT CASE WHEN
 (SELECT window_seconds FROM lf_ops.v_politicas_rate_limit_effective_v1
   WHERE rate_limit_policy_id=10)=1200
 AND (SELECT count(*) FROM lf_ops.v_politicas_rate_limit_effective_v1
   WHERE rate_limit_policy_id IN (7,8) AND window_seconds=900)=2
 THEN 'DYNAMIC_PASSWORD_900_TO_1200_PASS' ELSE 'DYNAMIC_PASSWORD_FAILED' END;
"""
        positive=sql_ok("BEGIN;\n"+body+"\n"+verify+"\nROLLBACK;\n",
                        "POSITIVE_REAL_PG_ROLLBACK_FAILED")
        for check in ("POSITIVE_10_POLICIES_EFFECTIVE_READY",
                      "DYNAMIC_OTP_5_TO_4_PASS","DYNAMIC_PASSWORD_900_TO_1200_PASS"):
            insist(check in positive.stdout,check+"_MISSING")
        insist(readback()==before,"INDEPENDENT_READBACK_NOT_RESTORED")
        checks={"positive_10_policies":True,"otp_value_dynamic":True,
                "password_window_dynamic":True,"independent_rollback_readback":True}
        # Failed reads are not silently replaced with cached numeric values.
        for label,tamper,query,expected in [
           ("missing_global","DELETE FROM public.lf_global_config WHERE scope='AUTH' AND config_key='OTP_MAX_ATTEMPTS';",
             "SELECT count(*) FROM lf_ops.v_politicas_rate_limit_effective_v1 WHERE rate_limit_policy_id IN (7,8) AND resolution_status='BLOCKED';","2"),
           ("invalid_status","UPDATE public.lf_global_config SET value_status='FICTICIO' WHERE scope='AUTH' AND config_key='OTP_MAX_ATTEMPTS';",
             "SELECT count(*) FROM lf_ops.v_politicas_rate_limit_effective_v1 WHERE rate_limit_policy_id IN (7,8) AND resolution_status='BLOCKED';","2"),
           ("burst_lt_requests","UPDATE public.lf_global_config SET config_value='3' WHERE scope='AUTH' AND config_key='OTP_BURST_LIMIT';",
             "SELECT count(*) FROM lf_ops.v_politicas_rate_limit_effective_v1 WHERE rate_limit_policy_id IN (7,8) AND resolution_status='BLOCKED';","2")
        ]:
            resp=sql_ok("BEGIN;\n"+body+"\n"+tamper+"\n"+query+"\nROLLBACK;\n",label)
            insist(expected in resp.stdout.splitlines(),label+"_DID_NOT_BLOCK")
            insist(readback()==before,label+"_LEFT_DIRTY_DB")
            checks[label]=True
        neg=sql("BEGIN;\n"+body+"""
UPDATE lf_ops.politicas_rate_limit SET max_requests=5 WHERE rate_limit_policy_id=10;
ROLLBACK;
""")
        insist(neg.returncode!=0 and "politicas_rate_limit_only_global_refs_ck" in neg.stderr,
          "LITERAL_REINTRODUCTION_ACCEPTED:"+neg.stderr[-700:])
        insist(readback()==before,"NUMERIC_NEGATIVE_LEFT_DIRTY_DB")
        checks["numeric_literal_reintroduction_rejected"]=True
        report.update(status="PASS",checks=checks,preimage=before,independent_readback=readback(),
          target={"config_rows":39,"rate_policy_rows":10,"all_policy_literals_null":True,
             "auth_rows":16,"rate_limit_rows":21,"rules":579},
          positive_sql_exit_code=positive.returncode,
          positive_sha256=hashlib.sha256((positive.stdout+positive.stderr).encode()).hexdigest())
    except Exception as exc:
        report["error"]=str(exc)[:2000]
    (OUT/"report.json").write_text(json.dumps(report,sort_keys=True,indent=2)+"\n")
    print(json.dumps(report,sort_keys=True))
    return 0 if report["status"]=="PASS" else 1
if __name__=="__main__":sys.exit(main())
