#!/usr/bin/env python3
"""IG Chat8: exact-source PostgreSQL 17 transaction / rollback + independent readback."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / ".lf_ci/ig_chat8_auth_window"
PATH = ROOT / "supabase/migrations/20261118214500_lf_ig_create_candidate_auth_window_v1.sql"
KEY = "LOGIN_LOCKOUT_ATTEMPT_WINDOW_MINUTES"

def check(condition, label):
    if not condition:
        raise AssertionError(label)

def psql(sql):
    return subprocess.run(
        ["psql", "-X", "-v", "ON_ERROR_STOP=1", "-A", "-t",
         "-h", "127.0.0.1", "-p", "5432", "-U", "postgres",
         "-d", "postgres", "-f", "-"],
        input=sql, text=True, capture_output=True,
        env=os.environ.copy(), timeout=100, check=False
    )

def okay(sql, label):
    r = psql(sql)
    check(r.returncode == 0, label + " " + r.stderr[-1000:])
    return r

def readback():
    r = okay("""SELECT jsonb_build_object(
        'config',(SELECT count(*) FROM public.lf_global_config),
        'auth',(SELECT count(*) FROM public.lf_global_config WHERE scope='AUTH'),
        'window',(SELECT count(*) FROM public.lf_global_config
          WHERE scope='AUTH' AND config_key='LOGIN_LOCKOUT_ATTEMPT_WINDOW_MINUTES'),
        'rules',(SELECT count(*) FROM lf_ops.reglas),
        'config_hash',(SELECT md5(coalesce(jsonb_agg(to_jsonb(g) ORDER BY scope,config_key)::text,'[]'))
          FROM public.lf_global_config g),
        'rule_hash',(SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY codigo)::text,'[]'))
          FROM lf_ops.reglas r))::text;""", "SELECT_READBACK_FAILED")
    return json.loads(r.stdout.strip().splitlines()[-1])

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    src = PATH.read_text()
    check(src.startswith("-- IG CHAT 8:"), "WRONG_SOURCE_IDENTITY")
    check(src.count("BEGIN;\nDO $ig_window$") == 1 and src.count("\nCOMMIT;") == 1,
          "NOT_SINGLE_TRANSACTION")
    check(src.count("INSERT INTO public.lf_global_config") == 1,
          "CONFIG_INSERT_COUNT")
    check(not re.search(r"\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+lf_ops\.reglas\b",src,re.I),
          "RULE_DML_FORBIDDEN")
    check("'LOGIN_LOCKOUT_ATTEMPT_WINDOW_MINUTES','30','INTEGER','REAL'" in src,
          "WINDOW_30_SOURCE_MISSING")
    parameter_scope = src.split("BEGIN;\n",1)[1].split("\nDO $ig_create_pre$",1)[0]
    check("lf_ig_rule_owner_decide_v2" not in parameter_scope and
          "lf_regla_candidate_write_v1" not in parameter_scope,
          "PARAMETER_ONLY_SCOPE_WRITER_BYPASS_FORBIDDEN")

    fixture = r"""
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $$;
CREATE SCHEMA lf_ops;
CREATE TABLE lf_ops.reglas(codigo text PRIMARY KEY, estado text, updated_at timestamptz DEFAULT now());
INSERT INTO lf_ops.reglas(codigo,estado)
 SELECT 'CHAT8_SYNTH_'||lpad(i::text,4,'0'),'CANDIDATO' FROM generate_series(1,576) i;
INSERT INTO lf_ops.reglas(codigo,estado) VALUES
 ('B2B-RULE-AUTH-018','VIGENTE'),
 ('B2B-RULE-AUTH-019','VIGENTE'),
 ('B2B-RULE-AUTH-020','VIGENTE');
CREATE TABLE public.lf_global_config(
 scope text NOT NULL, config_key text NOT NULL, config_value text NOT NULL,
 value_type text NOT NULL, value_status text NOT NULL, description text,
 valid_from timestamptz NOT NULL DEFAULT now(), created_at timestamptz NOT NULL DEFAULT now(),
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
 ('AUTH','LOGIN_LOCKOUT_RESET_MINUTES','1440','INTEGER','REAL','fixture'),
 ('AUTH','MFA_DEVICE_IDLE_DAYS','30','INTEGER','REAL','fixture'),
 ('AUTH','MFA_PASSWORD_AGE_MONTHS','3','INTEGER','REAL','fixture'),
 ('AUTH','TEMP_KEY_TTL_HOURS','24','INTEGER','REAL','fixture'),
 ('PAGOS','NIUBIZ_EMAIL_GENERICO','fake@invalid.test','EMAIL','FICTICIO','fixture'),
 ('PAGOS','NIUBIZ_OTHER','fake2@invalid.test','EMAIL','FICTICIO','fixture');
"""
    okay(fixture, "FIXTURE_SETUP_FAILED")
    before = readback()
    check((before["config"],before["auth"],before["window"],before["rules"]) ==
          (12,10,0,579),"BASELINE_MISMATCH")
    tx_body = src.split("BEGIN;\n",1)[1].split("\nDO $ig_create_pre$",1)[0]
    post = """
DO $v$ BEGIN
 IF (SELECT count(*) FROM public.lf_global_config)<>13
    OR (SELECT count(*) FROM public.lf_global_config WHERE scope='AUTH')<>11
    OR (SELECT count(*) FROM lf_ops.reglas)<>579
    OR (SELECT count(*) FROM public.lf_global_config WHERE scope='AUTH'
        AND config_key='LOGIN_LOCKOUT_ATTEMPT_WINDOW_MINUTES'
        AND config_value='30' AND value_type='INTEGER' AND value_status='REAL')<>1
 THEN RAISE EXCEPTION 'IG_CHAT8_IN_TX_READBACK_INVALID'; END IF;
 RAISE NOTICE 'IG_CHAT8_IN_TX_13_11_579_PASS';
END $v$;
"""
    reader_marker = "-- One server-side AUTH integer resolver."
    check(src.count(reader_marker)==1,"ONE_AUTH_READER_SOURCE_REQUIRED")
    reader_sql=reader_marker+src.split(reader_marker,1)[1].rsplit("\nCOMMIT;",1)[0]
    reader_test="""
DO $reader_test$
BEGIN
 IF public.lf_auth_config_integer_v1('LOGIN_LOCKOUT_ATTEMPT_WINDOW_MINUTES')<>30
    OR public.lf_auth_config_integer_v1('LOGIN_LOCKOUT_RESET_MINUTES')<>1440
    OR public.lf_auth_config_integer_v1('MFA_DEVICE_IDLE_DAYS')<>30
    OR has_function_privilege('anon','public.lf_auth_config_integer_v1(text)','EXECUTE')
    OR has_function_privilege('authenticated','public.lf_auth_config_integer_v1(text)','EXECUTE')
    OR NOT has_function_privilege('service_role','public.lf_auth_config_integer_v1(text)','EXECUTE')
 THEN RAISE EXCEPTION 'IG_AUTH_READER_SOURCE_OR_ACL_FAILED'; END IF;
 BEGIN
  PERFORM public.lf_auth_config_integer_v1('MISSING_SETTING');
  RAISE EXCEPTION 'IG_AUTH_READER_UNKNOWN_KEY_ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'IG_AUTH_CONFIG_INTEGER_MISSING_OR_INVALID:%'
  THEN RAISE; END IF;
 END;
 RAISE NOTICE 'IG_AUTH_READER_PG17_SCOPE_ACL_AND_MISSING_KEY_PASS';
END $reader_test$;
"""
    result = okay("BEGIN;\n"+tx_body+"\n"+reader_sql+"\n"+post+"\n"+reader_test+"\nROLLBACK;","POSITIVE_FAILED")
    check("IG_CHAT8_IN_TX_13_11_579_PASS" in result.stderr,
          "POSITIVE_READBACK_MARKER_MISSING")
    check("IG_AUTH_READER_PG17_SCOPE_ACL_AND_MISSING_KEY_PASS" in result.stderr,
          "AUTH_READER_PG17_CHECKS_NOT_PASS")
    check(readback() == before,"POSITIVE_INDEPENDENT_ROLLBACK_FAILED")

    negatives = {
      "PREEXISTING_WINDOW": (
        "INSERT INTO public.lf_global_config(scope,config_key,config_value,value_type,value_status) VALUES ('AUTH','LOGIN_LOCKOUT_ATTEMPT_WINDOW_MINUTES','30','INTEGER','REAL');",
        "IG_WINDOW_PREIMAGE_DRIFT"),
      "WRONG_RESET_PARAMETER": (
        "UPDATE public.lf_global_config SET config_value='60' WHERE scope='AUTH' AND config_key='LOGIN_LOCKOUT_RESET_MINUTES';",
        "IG_WINDOW_AUTH_PARAMETER_SOURCE_DRIFT"),
      "RULE_COUNT_DRIFT": (
        "DELETE FROM lf_ops.reglas WHERE codigo='CHAT8_SYNTH_0001';",
        "IG_WINDOW_PREIMAGE_DRIFT"),
      "RLS_WEAKENED": (
        "ALTER TABLE public.lf_global_config NO FORCE ROW LEVEL SECURITY;",
        "IG_WINDOW_GLOBAL_CONFIG_AUTHORITY_DRIFT")
    }
    for name,(tamper,expected_error) in negatives.items():
        r = psql("BEGIN;\n"+tamper+"\n"+tx_body+"\nROLLBACK;")
        check(r.returncode != 0 and expected_error in r.stderr,
              "NEGATIVE_FAIL_OPEN_"+name+": "+r.stderr[-600:])
        check(readback() == before,"NEGATIVE_INDEPENDENT_ROLLBACK_FAILED_"+name)

    report = {
      "status":"PASS","engine":"POSTGRESQL_17_EPHEMERAL",
      "source":str(PATH.relative_to(ROOT)),
      "source_sha256":hashlib.sha256(src.encode()).hexdigest(),
      "positive":"BEGIN_13_11_579_THEN_ROLLBACK",
      "independent_readback":"RESTORED_12_10_0_579",
      "negative_checks":{x:"EXPECTED_BLOCK_AND_ROLLBACK" for x in negatives},
      "remote_supabase_tested":False,
      "auth_reader":"REAL_PG17_10_KEYS_ACL_MISSING_KEY_PASS",
      "candidate_rules_created":0,
      "production_authorized":False
    }
    (OUT/"report.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
    print("IG_CHAT8_WINDOW30_PG17_ROLLBACK_PASS 1_positive 4_negative")

if __name__ == "__main__":
    main()
