#!/usr/bin/env python3
"""M9.9 reversible five-condition canary negative, test-only. No production changes."""
import json
import os
import re
import sys
import hashlib

TEST_CODE = "ENG_M9_9_ROLLBACK_TRIGGER_NEGATIVE"
EXPECTED = {"FALSE_PASS", "DIVERGENCE", "TIMEOUT", "EXECUTION_ERROR", "MISSING_RECEIPT"}

PROOF_SQL = r"""BEGIN;
CREATE TEMP TABLE ig_m99_negative_probes_v1(case_code text,expected_reason text,pointer_rollback boolean,provenance_class text) ON COMMIT DROP;
DO $m99$
DECLARE m jsonb; old_sha text; new_sha text; a jsonb; b jsonb; verdict jsonb;
        v_case text; v_signal jsonb; v_expected text; v_versions integer; v_receipts bigint;
BEGIN
 SELECT manifest_sha256 INTO old_sha FROM public.lf_capability_current
 WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0';
 IF old_sha IS NULL THEN RAISE EXCEPTION 'M99_BASELINE_CURRENT_MISSING'; END IF;
 SELECT count(*) INTO v_versions FROM public.lf_capability_version_registry WHERE capability_code='INPUT_GOVERNANCE';
 SELECT count(*) INTO v_receipts FROM programacion.provenance_receipts;
 IF v_versions<>1 THEN RAISE EXCEPTION 'M99_FIXTURE_VERSION_COUNT_DRIFT'; END IF;
 SELECT manifest || jsonb_build_object('version','1.0.1','migration',manifest->'migration'||jsonb_build_object('sandbox_canary',true))
 INTO m FROM public.lf_capability_version_registry WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0';
 new_sha:=encode(extensions.digest(convert_to(m::text,'UTF8'),'sha256'),'hex');
 FOR v_case IN SELECT unnest(ARRAY['FALSE_PASS','DIVERGENCE','TIMEOUT','EXECUTION_ERROR','MISSING_RECEIPT']) LOOP
  BEGIN
   INSERT INTO public.lf_capability_version_registry(capability_code,version,version_major,version_minor,version_patch,release_state,supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id)
   SELECT capability_code,'1.0.1',1,0,1,'RELEASED','1.0.0',m,new_sha,source_ref,docs_ref,validator_ref,'IG_M99_FIVE_NEGATIVE_FIXTURE'
   FROM public.lf_capability_version_registry WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0';
   a:=public.fn_lf_capability_promote_v1('INPUT_GOVERNANCE','1.0.1',old_sha,'IG_M99_FIVE_NEGATIVE_FIXTURE','isolated sandbox fixture');
   IF a->>'decision'<>'PROMOTED_CURRENT' THEN RAISE EXCEPTION 'M99_FORWARD_%_%',v_case,a; END IF;
   IF v_case='MISSING_RECEIPT' THEN
      verdict:=programacion.fn_ig_m99_canary_receipt_gate_v1(999999999,old_sha,'AUTH');
      v_expected:='RECEIPT_MISSING_STALE_OR_UNATTESTED';
   ELSE
      v_signal:='{"false_pass_detected":false,"divergence_level":"D0","elapsed_ms":100000,"execution_error":false,"receipt_present":true,"receipt_verified":true}'::jsonb;
      CASE v_case
       WHEN 'FALSE_PASS' THEN v_signal:=jsonb_set(v_signal,'{false_pass_detected}','true'::jsonb); v_expected:='FALSE_PASS';
       WHEN 'DIVERGENCE' THEN v_signal:=jsonb_set(v_signal,'{divergence_level}','"D4"'::jsonb); v_expected:='DIVERGENCE';
       WHEN 'TIMEOUT' THEN v_signal:=jsonb_set(v_signal,'{elapsed_ms}','150001'::jsonb); v_expected:='TIMEOUT';
       WHEN 'EXECUTION_ERROR' THEN v_signal:=jsonb_set(v_signal,'{execution_error}','true'::jsonb); v_expected:='EXECUTION_ERROR';
      END CASE;
      verdict:=programacion.fn_ig_m99_canary_rollback_decision_v1(v_signal,150000);
   END IF;
   IF verdict->>'action' IS DISTINCT FROM 'ROLLBACK_REQUIRED'
     OR NOT (verdict->'reason_codes' ? v_expected)
     OR verdict->>'rollback_executed' IS DISTINCT FROM 'false'
     THEN RAISE EXCEPTION 'M99_SIGNAL_FAIL_%_%',v_case,verdict; END IF;
   b:=public.fn_lf_capability_promote_v1('INPUT_GOVERNANCE','1.0.0',new_sha,'IG_M99_FIVE_NEGATIVE_FIXTURE','sandbox rollback on observed reason');
   IF b->>'decision'<>'PROMOTED_CURRENT' THEN RAISE EXCEPTION 'M99_REVERT_FAIL_%_%',v_case,b; END IF;
   RAISE EXCEPTION USING ERRCODE='ZX001',MESSAGE='M99_SUBTRANSACTION_ROLLBACK';
  EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
  END;
  IF EXISTS(SELECT 1 FROM public.lf_capability_version_registry WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1')
  OR NOT EXISTS(SELECT 1 FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0' AND manifest_sha256=old_sha AND previous_version IS NULL)
  THEN RAISE EXCEPTION 'M99_POSTSTATE_MISMATCH_%',v_case; END IF;
  INSERT INTO pg_temp.ig_m99_negative_probes_v1
  VALUES(v_case,v_expected,true,case when v_case='MISSING_RECEIPT' then 'LIVE_MISSING_RECEIPT_GATE' else 'SIMULATED_SIGNAL_VERIFIED_DECISION_ONLY' end);
 END LOOP;
 IF (SELECT count(*) FROM pg_temp.ig_m99_negative_probes_v1)<>5 THEN RAISE EXCEPTION 'M99_FIVE_CASE_COUNT_FAILED'; END IF;
 IF (SELECT count(*) FROM programacion.provenance_receipts)<>v_receipts THEN RAISE EXCEPTION 'M99_RECEIPT_MUTATION_DETECTED'; END IF;
END $m99$;
SELECT count(*) AS cases,count(*) FILTER(WHERE pointer_rollback) AS rollback_cases,
jsonb_agg(jsonb_build_object('case',case_code,'reason',expected_reason,'provenance',provenance_class) ORDER BY case_code) AS breakdown
FROM pg_temp.ig_m99_negative_probes_v1;
ROLLBACK;"""

def guarded(source):
    required = ("public.fn_lf_capability_promote_v1", "M99_SUBTRANSACTION_ROLLBACK",
                "M99_POSTSTATE_MISMATCH", "programacion.fn_ig_m99_canary_receipt_gate_v1",
                "programacion.fn_ig_m99_canary_rollback_decision_v1", "ROLLBACK;")
    forbidden = (r"\bCREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\b",
                 r"\bDROP\s+FUNCTION\b",
                 r"\bUPDATE\s+(?:public\.)?lf_capability_current\b",
                 r"\bCOMMIT\s*;")
    return (all(t in source for t in required)
            and source.count("public.fn_lf_capability_promote_v1(") == 2
            and all(re.search(p, source, re.IGNORECASE) is None for p in forbidden)
            and source.strip().endswith("ROLLBACK;"))

def main():
    mode = sys.argv[1] if len(sys.argv)>1 else "--self-test"
    if not guarded(PROOF_SQL):
        raise SystemExit("FAIL_SOURCE_GUARD")
    if mode=="--emit-sql":
        print(PROOF_SQL)
        return 0
    if mode=="--self-test":
        malicious = PROOF_SQL.replace("ROLLBACK;","COMMIT;")
        if guarded(malicious):
            raise SystemExit("FAIL_DANGEROUS_COMMIT_ACCEPTED")
        malicious2 = PROOF_SQL + "\nUPDATE public.lf_capability_current SET version='1.0.1';"
        if guarded(malicious2):
            raise SystemExit("FAIL_DIRECT_POINTER_MUTATION_ACCEPTED")
        print(json.dumps({"status":"PASS","test_code":TEST_CODE,"source_guard":True,
          "adversarial_case_executed":True,"sql_sha256":hashlib.sha256(PROOF_SQL.encode()).hexdigest(),
          "runtime_canary_proven":False},sort_keys=True))
        return 0
    if mode!="--verify":
        raise SystemExit("FAIL_UNKNOWN_MODE")
    try:
        proof=json.loads(os.environ.get("LF_M99_SQL_PROOF","{}"))
        baseline=json.loads(os.environ.get("LF_M99_POSTSTATE","{}"))
        expected_sha=os.environ.get("LF_M99_EXPECTED_SHA","")
    except ValueError:
        raise SystemExit("FAIL_UNPARSABLE_EVIDENCE")
    observed=proof.get("breakdown",[])
    sources={v.get("case"):v.get("provenance") for v in observed if isinstance(v,dict)}
    valid=(proof.get("cases")==5 and proof.get("rollback_cases")==5
      and set(sources)==EXPECTED
      and sources.get("MISSING_RECEIPT")=="LIVE_MISSING_RECEIPT_GATE"
      and all(sources.get(x)=="SIMULATED_SIGNAL_VERIFIED_DECISION_ONLY" for x in EXPECTED-{"MISSING_RECEIPT"})
      and re.fullmatch(r"[0-9a-f]{64}",expected_sha) is not None
      and baseline.get("version")=="1.0.0"
      and baseline.get("manifest_sha256")==expected_sha
      and baseline.get("previous_version") is None
      and baseline.get("registered_versions")==1)
    # These five are credible reversible sandbox tests, NOT verified live canary receipts.
    observed_data={"test_passed":bool(valid),"test_exit_code":0 if valid else 1,
      "adversarial_case_executed":True,"semantic_authority_bound":bool(valid),
      "sandbox_switch_revert_count":proof.get("rollback_cases",0) if valid else 0,
      "zero_residue":bool(valid),"real_canary_receipts_verified":False,
      "runtime_canary_proven":False,"full_checkpoint_closure_authorized":False}
    print(json.dumps({"status":"PASS" if valid else "FAIL","test_code":TEST_CODE,
        "observed":observed_data},sort_keys=True))
    return 0 if valid else 1

if __name__=="__main__":
    sys.exit(main())
