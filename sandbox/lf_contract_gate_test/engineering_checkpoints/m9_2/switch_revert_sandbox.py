#!/usr/bin/env python3
"""IG M9.2 — live sandbox CURRENT/canary/revert test, no durable candidate fixture."""
import hashlib
import json
import os
import re
import sys

TEST_CODE = "ENG_M9_2_SWITCH_REVERT_SANDBOX"
BASELINE_SHA = "d1f5947613ef7e6d74d8763e39da534f79d70d61a2eab65e4765579fa4028e44"
PROOF_SQL = "DO $t$\nDECLARE m jsonb; old_sha text; new_sha text; a jsonb; b jsonb;\nBEGIN\n SELECT manifest_sha256 INTO old_sha FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0';\n IF old_sha IS NULL THEN RAISE EXCEPTION 'BASELINE_MISSING'; END IF;\n SELECT manifest || jsonb_build_object('version','1.0.1','migration',manifest->'migration'||jsonb_build_object('sandbox_canary',true)) INTO m\n FROM public.lf_capability_version_registry WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0';\n new_sha:=encode(extensions.digest(convert_to(m::text,'UTF8'),'sha256'),'hex');\n BEGIN\n  INSERT INTO public.lf_capability_version_registry(capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id)\n  SELECT capability_code,'1.0.1',1,0,1,'RELEASED','1.0.0',m,new_sha,source_ref,docs_ref,validator_ref,'IG_M92_ROLLBACK_CANARY'\n  FROM public.lf_capability_version_registry WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0';\n  a:=public.fn_lf_capability_promote_v1('INPUT_GOVERNANCE','1.0.1',old_sha,'IG_M92_ROLLBACK_CANARY','temporary sandbox switch');\n  IF a->>'decision'<>'PROMOTED_CURRENT' OR NOT EXISTS(SELECT 1 FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1' AND manifest_sha256=new_sha) THEN RAISE EXCEPTION 'SWITCH_FAILED:%',a; END IF;\n  b:=public.fn_lf_capability_promote_v1('INPUT_GOVERNANCE','1.0.0',new_sha,'IG_M92_ROLLBACK_CANARY','temporary sandbox revert');\n  IF b->>'decision'<>'PROMOTED_CURRENT' OR NOT EXISTS(SELECT 1 FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0' AND manifest_sha256=old_sha) THEN RAISE EXCEPTION 'REVERT_FAILED:%',b; END IF;\n  RAISE EXCEPTION USING ERRCODE='ZX001',MESSAGE='ROLLBACK_AFTER_SWITCH_AND_REVERT';\n EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;\n END;\n IF EXISTS(SELECT 1 FROM public.lf_capability_version_registry WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1') THEN RAISE EXCEPTION 'CANARY_RESIDUE'; END IF;\n IF NOT EXISTS(SELECT 1 FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0' AND manifest_sha256=old_sha) THEN RAISE EXCEPTION 'POINTER_DRIFT'; END IF;\nEND $t$;"

def guarded(test_sql):
    required = ("public.fn_lf_capability_promote_v1", "public.lf_capability_current",
                "ROLLBACK_AFTER_SWITCH_AND_REVERT", "CANARY_RESIDUE")
    denied = (r"\bCREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\b",
              r"\bDROP\s+FUNCTION\b",
              r"\bUPDATE\s+(?:public\.)?lf_capability_current\b")
    return (all(v in test_sql for v in required)
            and test_sql.count("public.fn_lf_capability_promote_v1(") == 2
            and not any(re.search(p, test_sql, re.IGNORECASE) for p in denied))

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "--self-test"
    if not guarded(PROOF_SQL):
        raise SystemExit("FAIL_CANARY_SOURCE_GUARD")
    if mode == "--emit-sql":
        print(PROOF_SQL)
        return 0
    if mode == "--self-test":
        malicious = PROOF_SQL + "\nCREATE OR REPLACE FUNCTION programacion.fn_input_governance_validator_v1() RETURNS void LANGUAGE sql AS 'SELECT 1';"
        if guarded(malicious):
            raise SystemExit("FAIL_MALICIOUS_REWRITE_ACCEPTED")
        print(json.dumps({"status": "PASS", "test_code": TEST_CODE, "source_guard": True,
                          "adversarial_case_executed": True, "sql_sha256": hashlib.sha256(PROOF_SQL.encode()).hexdigest()}))
        return 0
    if mode != "--verify":
        raise SystemExit("FAIL_UNKNOWN_MODE")
    readback = json.loads(os.environ.get("LF_M9_2_LIVE_READBACK", "{}"))
    authority = os.environ.get("LF_M9_2_ADR") == "DEC-INPUT-GOV-M1.7-RELEASE-BINDING-001:VIGENTE"
    live_success = os.environ.get("LF_M9_2_SUPABASE_SQL_RESULT") == "PASS"
    valid = (live_success and authority
             and readback.get("capability_code") == "INPUT_GOVERNANCE"
             and readback.get("version") == "1.0.0"
             and readback.get("manifest_sha256") == BASELINE_SHA
             and readback.get("registered_versions") == 1
             and readback.get("previous_version") is None)
    observed = {"test_passed": bool(valid), "test_exit_code": 0 if valid else 1,
                "semantic_authority_bound": authority, "switch_revert_sql_executed": live_success,
                "rollback_no_residue": readback.get("registered_versions") == 1,
                "readback_version": readback.get("version"),
                "canary_sql_sha256": hashlib.sha256(PROOF_SQL.encode()).hexdigest()}
    print(json.dumps({"status": "PASS" if valid else "FAIL", "test_code": TEST_CODE,
                      "observed": observed}, sort_keys=True))
    return 0 if valid else 1

if __name__ == "__main__":
    sys.exit(main())
