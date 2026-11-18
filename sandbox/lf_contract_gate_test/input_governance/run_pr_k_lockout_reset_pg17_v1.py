#!/usr/bin/env python3
"""PR-K ephemeral PostgreSQL 17: governed config source, rollback, negative controls."""
from pathlib import Path
import hashlib, json, os, re, subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / ".lf_ci/pr_k_lockout_reset"
GLOB = "*_lf_auth_lockout_reset_minutes_pr_k_v1.sql"

def check(ok, code):
    if not ok: raise AssertionError(code)

def db(sql):
    return subprocess.run(
        ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-A", "-t",
         "-h", "127.0.0.1", "-p", "5432", "-U", "postgres",
         "-d", "postgres", "-f", "-"],
        input=sql, text=True, capture_output=True,
        env=os.environ.copy(), timeout=120, check=False)

def sql_ok(sql, code):
    r=db(sql)
    check(r.returncode==0, code+": "+r.stderr[-900:])
    return r

def readback():
    r=sql_ok("""SELECT jsonb_build_object(
     'total',(SELECT count(*) FROM public.lf_global_config),
     'auth',(SELECT count(*) FROM public.lf_global_config WHERE scope='AUTH'),
     'new',(SELECT count(*) FROM public.lf_global_config WHERE scope='AUTH'
       AND config_key='LOGIN_LOCKOUT_RESET_MINUTES'),
     'rules',(SELECT count(*) FROM lf_ops.reglas),
     'old_hash',(SELECT md5(coalesce(jsonb_agg(to_jsonb(g) ORDER BY scope,config_key)::text,'[]'))
       FROM public.lf_global_config g))::text;""","READBACK_FAILED")
    return json.loads(r.stdout.strip().splitlines()[-1])

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    files=list((ROOT/"supabase/migrations").glob(GLOB))
    check(len(files)==1,"MIGRATION_SUFFIX_UNIQUE_REQUIRED")
    source=files[0].read_text()
    check(source.count("BEGIN;\nDO $pr_k$")==1 and source.count("\nCOMMIT;")==1,
          "SINGLE_TRANSACTION_REQUIRED")
    check(source.count("INSERT INTO public.lf_global_config")==1,
          "SINGLE_CONFIG_INSERT_REQUIRED")
    check("'1440','INTEGER','REAL'" in source and
          "LOGIN_LOCKOUT_RESET_MINUTES" in source, "1440_REAL_INTEGER_MISSING")
    check(not re.search(r"\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+lf_ops\.reglas\b",
                        source, re.I), "DIRECT_RULE_DML_FORBIDDEN")
    newer=json.loads((ROOT/"docs/input-governance/PR_K_LOGIN_LOCKOUT_RESET_AND_FOUR_RULES_DOCUMENT_ONLY_20261118.json").read_text())
    older=json.loads((ROOT/"docs/input-governance/PR_F_AUTH_CANDIDATE_PROPOSALS_ONLY_20261118.json").read_text())
    a,b=newer["candidates"],older["new_rule_proposals"]
    check(len(a)==len(b)==4 and a[:3]==b[:3]
          and [x["proposed_code"] for x in a]==[x["proposed_code"] for x in b],
          "FOUR_SOURCE_BOUND_DOC_ONLY_RULES_REQUIRED")
    v=a[3]["valor_config"]
    check(newer["status"]=="DOCUMENT_ONLY_NO_CANONICAL_RULE_WRITE"
          and v["counter_subject"]=="USER_ACCOUNT"
          and v["counter_reset_anchor"]=="LAST_LOCKOUT_AT_SERVER_TIME"
          and "AUTH/LOGIN_LOCKOUT_RESET_MINUTES" in v["parameter_refs"]
          and v["enforcement_enabled"] is False
          and v["measurement_window"].startswith("PENDING"),"RESET_SCOPE_NOT_SOURCE_BOUND")

    setup=r"""
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
END $$;
CREATE SCHEMA lf_ops;
CREATE TABLE lf_ops.reglas(codigo text PRIMARY KEY,estado text,updated_at timestamptz DEFAULT now());
INSERT INTO lf_ops.reglas(codigo,estado) SELECT 'PRK_SYNTH_'||lpad(i::text,4,'0'),'CANDIDATO'
 FROM generate_series(1,576) i;
INSERT INTO lf_ops.reglas(codigo,estado) VALUES
 ('B2B-RULE-AUTH-018','VIGENTE'),('B2B-RULE-AUTH-019','VIGENTE'),('B2B-RULE-AUTH-020','VIGENTE');
CREATE TABLE public.lf_global_config(
 scope text NOT NULL,config_key text NOT NULL,config_value text NOT NULL,
 value_type text NOT NULL,value_status text NOT NULL,description text,
 valid_from timestamptz NOT NULL DEFAULT now(),created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(scope,config_key,valid_from),
 CHECK(value_type IN ('TEXT','INTEGER','DECIMAL','BOOLEAN','JSON','EMAIL')),
 CHECK(value_status IN ('REAL','FICTICIO')));
ALTER TABLE public.lf_global_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lf_global_config FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.lf_global_config FROM anon,authenticated;
INSERT INTO public.lf_global_config(scope,config_key,config_value,value_type,value_status,description)
 VALUES
 ('AUTH','LOGIN_LOCKOUT_ATTEMPTS_1','5','INTEGER','REAL','fixture'),
 ('AUTH','LOGIN_LOCKOUT_ATTEMPTS_2','3','INTEGER','REAL','fixture'),
 ('AUTH','LOGIN_LOCKOUT_ATTEMPTS_3','3','INTEGER','REAL','fixture'),
 ('AUTH','LOGIN_LOCKOUT_MINUTES_1','15','INTEGER','REAL','fixture'),
 ('AUTH','LOGIN_LOCKOUT_MINUTES_2','60','INTEGER','REAL','fixture'),
 ('AUTH','LOGIN_LOCKOUT_MINUTES_3','1440','INTEGER','REAL','fixture'),
 ('AUTH','MFA_DEVICE_IDLE_DAYS','30','INTEGER','REAL','fixture'),
 ('AUTH','MFA_PASSWORD_AGE_MONTHS','3','INTEGER','REAL','fixture'),
 ('AUTH','TEMP_KEY_TTL_HOURS','24','INTEGER','REAL','fixture'),
 ('PAGOS','NIUBIZ_EMAIL_GENERICO','fake@invalid.test','EMAIL','FICTICIO','fixture');
"""
    sql_ok(setup,"SYNTHETIC_PG17_FIXTURE_FAILED")
    before=readback()
    check((before["total"],before["auth"],before["new"],before["rules"])==(10,9,0,579),
          "BASELINE_NOT_10_9_0_579")
    body=source.split("BEGIN;\n",1)[1].rsplit("\nCOMMIT;",1)[0]
    in_tx=r"""
DO $verify$ BEGIN
 IF (SELECT count(*) FROM public.lf_global_config)<>11
    OR (SELECT count(*) FROM public.lf_global_config WHERE scope='AUTH')<>10
    OR (SELECT count(*) FROM lf_ops.reglas)<>579
    OR (SELECT count(*) FROM public.lf_global_config WHERE scope='AUTH'
        AND config_key='LOGIN_LOCKOUT_RESET_MINUTES'
        AND config_value='1440' AND value_type='INTEGER' AND value_status='REAL')<>1
 THEN RAISE EXCEPTION 'PR_K_PG17_IN_TX_READBACK_FAILED'; END IF;
 RAISE NOTICE 'PR_K_PG17_IN_TX_11_579_PASS';
END $verify$;
"""
    positive=sql_ok("BEGIN;\n"+body+"\n"+in_tx+"\nROLLBACK;\n","PG17_POSITIVE_FAILED")
    check("PR_K_PG17_IN_TX_11_579_PASS" in positive.stderr,"POSITIVE_READBACK_MARKER_MISSING")
    check(readback()==before,"PG17_INDEPENDENT_ROLLBACK_NOT_RESTORED")

    adversarial={
      "DUPLICATE_KEY":(
        "INSERT INTO public.lf_global_config(scope,config_key,config_value,value_type,value_status) VALUES ('AUTH','LOGIN_LOCKOUT_RESET_MINUTES','1440','INTEGER','REAL');",
        "PR_K_GLOBAL_CONFIG_PREIMAGE_10_9_MISSING_OR_DUPLICATE"),
      "MISSING_OLD_PARAMETER":(
        "DELETE FROM public.lf_global_config WHERE scope='AUTH' AND config_key='MFA_DEVICE_IDLE_DAYS';",
        "PR_K_GLOBAL_CONFIG_PREIMAGE_10_9_MISSING_OR_DUPLICATE"),
      "RLS_WEAKENED":(
        "ALTER TABLE public.lf_global_config NO FORCE ROW LEVEL SECURITY;",
        "PR_K_GLOBAL_CONFIG_RLS_OR_PRIVILEGE_DRIFT"),
      "RULE_COUNT_DRIFT":(
        "DELETE FROM lf_ops.reglas WHERE codigo='PRK_SYNTH_0001';",
        "PR_K_RULE_PREIMAGE_OR_PROPOSAL_PREEXISTENCE_DRIFT")
    }
    for name,(tamper,code) in adversarial.items():
        result=db("BEGIN;\n"+tamper+"\n"+body+"\nROLLBACK;")
        check(result.returncode!=0 and code in result.stderr,"NEGATIVE_FAIL_OPEN_"+name+
              " "+result.stderr[-400:])
        check(readback()==before,"NEGATIVE_TRANSACTION_DIRTIED_SOURCE_"+name)
    report={
      "status":"PASS","engine":"REAL_POSTGRESQL_17_EPHEMERAL",
      "migration":str(files[0].relative_to(ROOT)),
      "migration_sha256":hashlib.sha256(source.encode()).hexdigest(),
      "positive":"BEGIN_IN_TX_11_579_ROLLBACK",
      "independent_readback":"RESTORED_10_9_0_579",
      "negative_checks":{k:"EXPECTED_BLOCK_AND_ROLLBACK" for k in adversarial},
      "four_rules":"DOCUMENT_ONLY_NO_RUN","remote_supabase_tested":False
    }
    (OUT/"report.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
    print("PR_K_REAL_PG17_BEGIN_ROLLBACK_PASS positive=1 negative=4 doc=4/4")

if __name__=="__main__": main()
