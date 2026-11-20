#!/usr/bin/env python3
"""IG Chat9 D1/D1b/D1c: isolated real PG17 rollback; never connects to Supabase."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / ".lf_ci/chat9_d1_rate_limits"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE_GLOB = "*_lf_ig_chat9_d1_b2b_rate_limits_v1.sql"

def check(ok, name):
    if not ok:
        raise AssertionError(name)

def sql(query):
    return subprocess.run(
        ["psql","-X","-v","ON_ERROR_STOP=1","-A","-t",
         "-h","127.0.0.1","-p","5432","-U","postgres",
         "-d","postgres","-f","-"],
        input=query, text=True, capture_output=True,
        env=os.environ.copy(), timeout=120, check=False
    )

def ok_sql(query, name):
    r = sql(query)
    check(r.returncode==0, name+":"+r.stderr[-1500:])
    return r

def readback():
    q = """SELECT jsonb_build_object(
        'policy_rows',(SELECT count(*) FROM lf_ops.politicas_rate_limit),
        'rules',(SELECT count(*) FROM lf_ops.reglas),
        'vigente_rules',(SELECT count(*) FROM lf_ops.reglas WHERE estado='VIGENTE'),
        'candidate_rules',(SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO'),
        'target',(SELECT count(*) FROM lf_ops.politicas_rate_limit WHERE resource_code='AUTH_LOGIN_FAILED_PASSWORD'),
        'login_scope',(SELECT scope_key FROM lf_ops.politicas_rate_limit WHERE rate_limit_policy_id=1),
        'otp7',(SELECT max_requests FROM lf_ops.politicas_rate_limit WHERE rate_limit_policy_id=7),
        'otp8',(SELECT max_requests FROM lf_ops.politicas_rate_limit WHERE rate_limit_policy_id=8),
        'policy_md5',(SELECT md5(coalesce(jsonb_agg(to_jsonb(p) ORDER BY rate_limit_policy_id)::text,'[]'))
                FROM lf_ops.politicas_rate_limit p),
        'rules_md5',(SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY codigo)::text,'[]'))
                FROM lf_ops.reglas r))::text;"""
    out=ok_sql(q,"INDEPENDENT_READBACK_SQL_FAILED").stdout.strip()
    return json.loads(out.splitlines()[-1])

def main():
    report={"status":"FAIL","remote_supabase_written":False,
            "actual_password_lockout_runtime":"NOT_TESTED",
            "test_database":"EPHEMERAL_POSTGRESQL17",
            "owner_v2_rule_run":"NOT_APPLICABLE_POLICIES_ONLY"}
    try:
        check(os.environ.get("GITHUB_REPOSITORY")=="cristhianlujan/claude-persona-lf-patch","REPO_MISMATCH")
        check(os.environ.get("GITHUB_EVENT_NAME")=="pull_request","PR_EVENT_REQUIRED")
        head=subprocess.check_output(["git","-C",str(ROOT),"rev-parse","HEAD"],text=True).strip()
        check(head==os.environ.get("CHAT9_EXACT_HEAD"),"EXACT_HEAD_DRIFT")
        report["head"]=head
        files=list((ROOT/"supabase/migrations").glob(SOURCE_GLOB))
        check(len(files)==1,"MIGRATION_UNIQUE_SUFFIX_REQUIRED")
        source=files[0].read_text()
        check(source.count("\nBEGIN;")==1 and source.count("\nCOMMIT;")==1
              and source.count("UPDATE lf_ops.politicas_rate_limit")==2
              and source.count("INSERT INTO lf_ops.politicas_rate_limit")==1,
              "MIGRATION_WRITER_SHAPE_DRIFT")
        check(not re.search(r"\b(?:UPDATE|INSERT\s+INTO|DELETE\s+FROM)\s+lf_ops\.reglas\b",source,re.I),
              "RULE_DML_OUT_OF_SCOPE")
        report["migration"]=str(files[0].relative_to(ROOT))
        report["migration_sha256"]=hashlib.sha256(source.encode()).hexdigest()

        setup = """
CREATE SCHEMA lf_ops;
CREATE TABLE lf_ops.reglas(codigo text PRIMARY KEY, estado text NOT NULL);
INSERT INTO lf_ops.reglas
SELECT 'RULE_'||lpad(i::text,4,'0'),
       CASE WHEN i<=438 THEN 'VIGENTE' ELSE 'CANDIDATO' END
FROM generate_series(1,579) i;
CREATE TABLE lf_ops.politicas_rate_limit(
  policy_code text NOT NULL,
  resource_code text NOT NULL,
  window_seconds integer NOT NULL CHECK(window_seconds>0),
  max_requests integer NOT NULL CHECK(max_requests>0),
  burst_limit integer NOT NULL CHECK(burst_limit>=max_requests),
  scope_key text NOT NULL,
  status text NOT NULL CHECK(status IN ('CANDIDATO','EN_REVISION','VIGENTE','INACTIVO','ARCHIVADO')),
  source_decision_id text,
  source_decision_number bigint,
  error_code text,
  error_id bigint,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  rate_limit_policy_id bigint PRIMARY KEY,
  parameter_provenance jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE(resource_code,scope_key)
);
INSERT INTO lf_ops.politicas_rate_limit
 (policy_code,resource_code,window_seconds,max_requests,burst_limit,scope_key,status,rate_limit_policy_id)
VALUES
 ('RATE-B2B-LOGIN','AUTH_LOGIN',900,5,5,'IP_USER','VIGENTE',1),
 ('RATE-B2B-UPLOAD','FILE_UPLOAD',3600,20,25,'TENANT_USER','CANDIDATO',2),
 ('RATE-B2B-APPROVAL','APPROVAL_DECISION',60,30,30,'TENANT_USER','CANDIDATO',3),
 ('RATE-B2B-DOWNLOAD','FILE_DOWNLOAD',60,60,80,'TENANT_USER','CANDIDATO',4),
 ('RATE-B2B-API-READ','API_READ',60,300,400,'TENANT_USER','CANDIDATO',5),
 ('RATE-B2B-SESSION-REFRESH','SESSION_REFRESH',60,10,12,'USER','CANDIDATO',6),
 ('RATE-B2B-PASSWORD-RECOVERY-OTP','AUTH_PASSWORD_RECOVERY_OTP_SEND',900,6,6,'USER','CANDIDATO',7),
 ('RATE-B2B-NEW-DEVICE-OTP','AUTH_NEW_DEVICE_OTP_SEND',900,6,6,'USER','CANDIDATO',8),
 ('RATE-CLIENT-OTP-PHONE-CROSSSESSION','CLIENT_OTP_SEND',3600,5,5,'PHONE_HASH','VIGENTE',9);
"""
        ok_sql(setup,"SCHEMA_FIXTURE_SETUP")
        # Install EXACT source functions of the live provenance guard, not a
        # hand-written permissive mock. The previous Train attempt exposed
        # the missing trigger (PARAMETER_PROVENANCE_REQUIRED).
        canonical=(ROOT/"supabase/migrations"/
                   "20260826185924_lf_input_governance_stage_parameter_authority_v1.sql").read_text()
        def function_ddl(marker):
            start=canonical.index(marker)
            end=canonical.index("$function$;",start)+len("$function$;")
            return canonical[start:end]
        validator=function_ddl(
            "create or replace function programacion.fn_input_parameter_provenance_valid_v1(")
        trigger_fn=function_ddl(
            "create or replace function programacion.fn_guard_input_parameter_provenance_v1()")
        ok_sql("CREATE SCHEMA programacion;\n"+validator+"\n"+trigger_fn+"""
ALTER TABLE lf_ops.politicas_rate_limit
 ADD CONSTRAINT politicas_rate_limit_parameter_provenance_ck
 CHECK(programacion.fn_input_parameter_provenance_valid_v1(parameter_provenance));
CREATE TRIGGER trg_politicas_rate_limit_parameter_provenance
 BEFORE INSERT OR UPDATE ON lf_ops.politicas_rate_limit
 FOR EACH ROW EXECUTE FUNCTION programacion.fn_guard_input_parameter_provenance_v1();
""","CANONICAL_PROVENANCE_TRIGGER_SETUP_FAILED")
        before=readback()
        check((before["policy_rows"],before["rules"],before["vigente_rules"],
               before["candidate_rules"],before["target"],before["login_scope"],
               before["otp7"],before["otp8"]) == (9,579,438,141,0,"IP_USER",6,6),"PREIMAGE_MISMATCH")
        body=source.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;",1)[0]
        projection = """SELECT CASE WHEN
          (SELECT count(*) FROM lf_ops.politicas_rate_limit)=10
          AND (SELECT count(*) FROM lf_ops.reglas)=579
          AND (SELECT count(*) FROM lf_ops.politicas_rate_limit WHERE
               resource_code='AUTH_LOGIN_FAILED_PASSWORD' AND status='CANDIDATO'
               AND window_seconds=900 AND max_requests=5 AND burst_limit=5 AND scope_key='USER')=1
          AND (SELECT count(*) FROM lf_ops.politicas_rate_limit WHERE
               rate_limit_policy_id=1 AND scope_key='USER')=1
          AND (SELECT count(*) FROM lf_ops.politicas_rate_limit WHERE
               rate_limit_policy_id IN (7,8) AND max_requests=5 AND burst_limit=5)=2
          THEN 'CHAT9_D1_POSITIVE_IN_TX_PASS' ELSE 'CHAT9_D1_PROJECTION_FAIL' END;"""
        positive=ok_sql("BEGIN;\n"+body+"\n"+projection+"\nROLLBACK;\n",
                        "REAL_POSITIVE_ROLLBACK_FAILED")
        check("CHAT9_D1_POSITIVE_IN_TX_PASS" in positive.stdout,"POSTIMAGE_IN_TX_MISMATCH")
        check(readback()==before,"POSITIVE_SEPARATE_READBACK_NOT_RESTORED")
        checks={"positive_begin_rollback":True,"independent_readback":True}
        # Every preimage tamper must itself obey the live provenance guard;
        # otherwise the fixture only tests the tamper's rejection, not the migration.
        legacy_provenance=("jsonb_build_object("
                           "'origin_type','UNCLASSIFIED_LEGACY',"
                           "'value_status','LEGACY_UNCLASSIFIED')")
        negatives={
            "wrong_login_scope":(
                f"UPDATE lf_ops.politicas_rate_limit SET scope_key='IP', "
                f"parameter_provenance=jsonb_build_object('scope_key',{legacy_provenance}) "
                f"WHERE rate_limit_policy_id=1;",
                "CHAT9_D1_EXACT_SOURCE_POLICY_DRIFT"),
            "wrong_otp_burst":(
                f"UPDATE lf_ops.politicas_rate_limit SET burst_limit=7, "
                f"parameter_provenance=jsonb_build_object('burst_limit',{legacy_provenance}) "
                f"WHERE rate_limit_policy_id=7;",
                "CHAT9_D1_EXACT_SOURCE_POLICY_DRIFT"),
            "duplicate_target":(
                "INSERT INTO lf_ops.politicas_rate_limit("
                "policy_code,resource_code,window_seconds,max_requests,burst_limit,"
                "scope_key,status,rate_limit_policy_id,parameter_provenance) "
                "VALUES('EXISTING','AUTH_LOGIN_FAILED_PASSWORD',900,5,5,'USER','CANDIDATO',10,"
                f"jsonb_build_object('window_seconds',{legacy_provenance},"
                f"'max_requests',{legacy_provenance},"
                f"'burst_limit',{legacy_provenance},"
                f"'scope_key',{legacy_provenance}));",
                "CHAT9_D1_RATE_POLICY_COUNT_OR_TARGET_DRIFT"),
            "rules_count_drift":(
                "DELETE FROM lf_ops.reglas WHERE codigo='RULE_0579';",
                "CHAT9_D1_RULE_BASELINE_DRIFT"),
            "rate_count_drift":(
                "DELETE FROM lf_ops.politicas_rate_limit WHERE rate_limit_policy_id=9;",
                "CHAT9_D1_RATE_POLICY_COUNT_OR_TARGET_DRIFT"),
            "missing_parameter_provenance":(
                "UPDATE lf_ops.politicas_rate_limit SET scope_key='USER' WHERE rate_limit_policy_id=1;",
                "PARAMETER_PROVENANCE_REQUIRED")
        }
        for name,(tamper,error_code) in negatives.items():
            neg=sql("BEGIN;\n"+tamper+"\n"+body+"\nROLLBACK;\n")
            check(neg.returncode!=0 and error_code in neg.stderr,
                  name+":"+neg.stderr[-700:])
            check(readback()==before,"NEGATIVE_READBACK_FAILED:"+name)
            checks[name]=True
        report.update(status="PASS", checks=checks, preimage=before,
          canonical_provenance_trigger_installed=True,
          projected={"policy_rows":10,"new_candidate_policy":1,
                     "modified_policies":3,"rule_rows":579},
          separate_readback=readback(),
          positive_sql_exit_code=positive.returncode,
          positive_stdout_sha256=hashlib.sha256((positive.stdout+positive.stderr).encode()).hexdigest())
    except Exception as exc:
        report["error"]=str(exc)[:1600]
    (OUT/"report.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
    print(json.dumps(report,sort_keys=True))
    return 0 if report["status"]=="PASS" else 1

if __name__=="__main__":
    sys.exit(main())
