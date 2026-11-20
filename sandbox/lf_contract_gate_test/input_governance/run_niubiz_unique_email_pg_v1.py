#!/usr/bin/env python3
"""PR Niubiz: real ephemeral PostgreSQL 17/18 BEGIN/ROLLBACK + independent SELECT."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / ".lf_ci/niubiz_unique_email"
GLOB = "*_lf_niubiz_unique_client_email_params_v1.sql"
OUT.mkdir(parents=True, exist_ok=True)

def check(test, code):
    if not test:
        raise AssertionError(code)

def run_sql(sql):
    return subprocess.run(
        ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-A", "-t",
         "-h", "127.0.0.1", "-p", "5432", "-U", "postgres",
         "-d", "postgres", "-f", "-"],
        input=sql, text=True, capture_output=True,
        env=os.environ.copy(), timeout=110, check=False)

def sql_ok(sql, label):
    result = run_sql(sql)
    check(result.returncode == 0, label + ":" + result.stderr[-1200:])
    return result

def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()

def readback():
    query = """SELECT jsonb_build_object(
      'config',(SELECT count(*) FROM public.lf_global_config),
      'auth',(SELECT count(*) FROM public.lf_global_config WHERE scope='AUTH'),
      'pagos',(SELECT count(*) FROM public.lf_global_config WHERE scope='PAGOS'),
      'rules',(SELECT count(*) FROM lf_ops.reglas),
      'placeholder',(SELECT count(*) FROM public.lf_global_config WHERE scope='PAGOS' AND config_key='NIUBIZ_EMAIL_GENERICO'),
      'template',(SELECT count(*) FROM public.lf_global_config WHERE scope='PAGOS' AND config_key='NIUBIZ_EMAIL_TEMPLATE'),
      'domain',(SELECT count(*) FROM public.lf_global_config WHERE scope='PAGOS' AND config_key='NIUBIZ_EMAIL_DOMAIN'),
      'config_md5',(SELECT md5(coalesce(jsonb_agg(to_jsonb(g) ORDER BY scope,config_key,valid_from)::text,'[]')) FROM public.lf_global_config g),
      'rules_md5',(SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY codigo)::text,'[]')) FROM lf_ops.reglas r))::text;"""
    value = sql_ok(query, "INDEPENDENT_READBACK_FAILED").stdout.strip().splitlines()[-1]
    return json.loads(value)

def main():
    report = {"status":"FAIL","engine":"REAL_EPHEMERAL_POSTGRESQL",
              "remote_supabase_written":False,
              "niubiz_hyphen_sandbox":"NOT_TESTED",
              "rule_updates":"BLOCKED_ABSENT_CANONICAL_R_PAY_040_041",
              "receipt_delivery_r_pay_043":"NOT_CHANGED"}
    try:
        check(os.environ.get("GITHUB_EVENT_NAME")=="pull_request", "PR_ONLY")
        check(os.environ.get("GITHUB_REPOSITORY")=="cristhianlujan/claude-persona-lf-patch", "REPO_MISMATCH")
        head=os.environ.get("NIUBIZ_EXACT_HEAD")
        observed=subprocess.check_output(["git","-C",str(ROOT),"rev-parse","HEAD"],text=True).strip()
        check(bool(head) and head==observed, "EXACT_HEAD_MISMATCH")
        report["head"]=head
        files=list((ROOT/"supabase/migrations").glob(GLOB))
        check(len(files)==1, "ONE_MIGRATION_REQUIRED")
        sql=files[0].read_text()
        check(sql.startswith("-- IG Niubiz") and sql.count("\nCOMMIT;")==1 and
              sql.count("\nBEGIN;")==1 and sql.count("DELETE FROM public.lf_global_config")==1 and
              sql.count("INSERT INTO public.lf_global_config")==1, "MIGRATION_STRUCTURE_DRIFT")
        check(not re.search(r"\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+lf_ops\.reglas\b",sql,re.I),
              "CANONICAL_RULE_DML_FORBIDDEN")
        check("R-PAY-045 remains sandbox NOT_TESTED" in sql and
              "NIUBIZ_EMAIL_TEMPLATE" in sql and "NIUBIZ_EMAIL_DOMAIN" in sql,
              "SCOPE_GUARDS_MISSING")
        report["migration_sha256"]=digest(sql)
        report["migration"]=str(files[0].relative_to(ROOT))
        setup = """
CREATE SCHEMA lf_ops;
CREATE TABLE lf_ops.reglas(codigo text PRIMARY KEY,estado text);
INSERT INTO lf_ops.reglas SELECT 'FIXTURE_RULE_'||lpad(g::text,4,'0'),'VIGENTE'
 FROM generate_series(1,579) AS g;
CREATE TABLE public.lf_global_config(
 scope text NOT NULL,config_key text NOT NULL,config_value text NOT NULL,
 value_type text NOT NULL CHECK(value_type IN ('TEXT','INTEGER','DECIMAL','BOOLEAN','JSON','EMAIL')),
 value_status text NOT NULL CHECK(value_status IN ('REAL','FICTICIO')),
 description text,valid_from timestamptz NOT NULL DEFAULT now(),
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
 ('PAGOS','NIUBIZ_EMAIL_GENERICO','niubiz-generico@lf-ficticio.invalid','EMAIL','FICTICIO');
"""
        sql_ok(setup,"FIXTURE_SETUP_FAILED")
        before=readback()
        check((before["config"],before["auth"],before["pagos"],before["rules"],
               before["placeholder"],before["template"],before["domain"]) ==
              (11,10,1,579,1,0,0), "PREIMAGE_DRIFT")
        body=sql.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;",1)[0]
        projected = """
SELECT CASE WHEN (SELECT count(*) FROM public.lf_global_config)=12
 AND (SELECT count(*) FROM public.lf_global_config WHERE scope='AUTH')=10
 AND (SELECT count(*) FROM public.lf_global_config WHERE scope='PAGOS')=2
 AND (SELECT count(*) FROM public.lf_global_config WHERE value_status='REAL')=12
 AND (SELECT count(*) FROM lf_ops.reglas)=579
 AND (SELECT count(*) FROM public.lf_global_config WHERE config_key='NIUBIZ_EMAIL_GENERICO')=0
 AND (SELECT count(*) FROM public.lf_global_config WHERE scope='PAGOS'
     AND config_key='NIUBIZ_EMAIL_TEMPLATE' AND config_value='{nombre}.{apellido}.lf-{codigo}')=1
 AND (SELECT count(*) FROM public.lf_global_config WHERE scope='PAGOS'
     AND config_key='NIUBIZ_EMAIL_DOMAIN' AND config_value='gmail.com')=1
 THEN 'NIUBIZ_EMAIL_IN_TX_PASS_12_579' ELSE 'NIUBIZ_EMAIL_IN_TX_FAIL' END;
"""
        pos=sql_ok("BEGIN;\n"+body+"\n"+projected+"\nROLLBACK;\n", "POSITIVE_ROLLBACK_FAILED")
        check("NIUBIZ_EMAIL_IN_TX_PASS_12_579" in pos.stdout, "POSITIVE_READBACK_FAILED")
        check(readback()==before, "INDEPENDENT_READBACK_NOT_RESTORED")
        checks = {"POSITIVE_REAL_BEGIN_ROLLBACK":True,"INDEPENDENT_READBACK":True}
        adversarial = {
          "PLACEHOLDER_VALUE_DRIFT":("UPDATE public.lf_global_config SET config_value='different@invalid.invalid' WHERE scope='PAGOS';",
                                      "NIUBIZ_EMAIL_PREIMAGE_PLACEHOLDER_DRIFT"),
          "TARGET_PREEXISTS":("INSERT INTO public.lf_global_config(scope,config_key,config_value,value_type,value_status) VALUES('PAGOS','NIUBIZ_EMAIL_TEMPLATE','other','TEXT','REAL');",
                               "NIUBIZ_EMAIL_PREIMAGE_COUNT_DRIFT"),
          "AUTH_REMOVED":("DELETE FROM public.lf_global_config WHERE scope='AUTH' AND config_key='MFA_DEVICE_IDLE_DAYS';",
                          "NIUBIZ_EMAIL_PREIMAGE_COUNT_DRIFT"),
          "RULE_COUNT_DRIFT":("DELETE FROM lf_ops.reglas WHERE codigo='FIXTURE_RULE_0001';",
                             "NIUBIZ_EMAIL_PREIMAGE_COUNT_DRIFT")
        }
        for label,(tamper,reason) in adversarial.items():
            negative=run_sql("BEGIN;\n"+tamper+"\n"+body+"\nROLLBACK;\n")
            check(negative.returncode!=0 and reason in negative.stderr,
                  "NEGATIVE_NOT_BLOCKED_"+label+":"+negative.stderr[-450:])
            check(readback()==before,"NEGATIVE_LEFT_MUTATION_"+label)
            checks[label]=True
        report.update({"status":"PASS","checks":checks,
           "preimage":before,"projected":{"config":12,"auth":10,"pagos":2,"rules":579},
           "independent_readback":readback(),"positive_sql_sha256":digest(pos.stdout+pos.stderr),
           "positive_sql_exit":pos.returncode,
           "source_bound_gov_v2":"NOT_INVOKED_RULES_ABSENT",
           "niubiz_actual_gateway_test":"NOT_TESTED"})
    except Exception as exc:
        report["error"]=str(exc)[:900]
    (OUT/"report.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
    print(json.dumps(report,sort_keys=True))
    return 0 if report["status"]=="PASS" else 1

if __name__=="__main__":
    sys.exit(main())
