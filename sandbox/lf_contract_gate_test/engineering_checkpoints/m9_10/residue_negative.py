"""M9.10 CP4 historical-safe residue negative.

Adversarial positive detection: an actual transaction-local IG candidate row
makes the registry delta positive and must be classified as residue. The
subtransaction is rolled back; the original 253+ runs, assessments and
bindings are preserved (counts are read dynamically). No historical purge.
"""

RESIDUE_NEGATIVE_SQL = r'''BEGIN;
CREATE TEMP TABLE m910_residue_negative_proof (
 injection_detected boolean, rollback_zero_candidate_residue boolean,
 runs_pre bigint,runs_post bigint,assessments_pre bigint,assessments_post bigint,
 bindings_pre bigint,bindings_post bigint,versions_pre bigint,versions_post bigint
) ON COMMIT DROP;
DO $residue$
DECLARE v_runs bigint;v_runs_after bigint;v_ass bigint;v_ass_after bigint;
 v_bind bigint;v_bind_after bigint;v_versions bigint;v_versions_after bigint;
 v_manifest jsonb;v_sha text;v_injected bigint;v_detected boolean:=false;
BEGIN
 SELECT count(*) INTO v_runs FROM programacion.input_readiness_runs;
 SELECT count(*) INTO v_ass FROM programacion.input_family_assessments a
   JOIN programacion.input_readiness_runs r ON r.id=a.run_id;
 SELECT count(*) INTO v_bind FROM public.lf_capability_binding;
 SELECT count(*) INTO v_versions FROM public.lf_capability_version_registry
   WHERE capability_code='INPUT_GOVERNANCE';
 IF v_runs=0 OR v_ass=0 OR v_bind=0 OR v_versions=0 THEN
 RAISE EXCEPTION 'M910_HISTORICAL_NONEMPTY_REGRESSION_INPUT_REQUIRED'; END IF;
 IF EXISTS (SELECT 1 FROM public.lf_capability_version_registry
      WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1') THEN
 RAISE EXCEPTION 'M910_REAL_CANDIDATE_PRESENT_STOP'; END IF;
 BEGIN
   SELECT manifest INTO STRICT v_manifest FROM public.lf_capability_version_registry
   WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0';
   v_manifest:=jsonb_set(v_manifest,'{version}',to_jsonb('1.0.1'::text),false);
   v_manifest:=jsonb_set(v_manifest,'{sandbox_residue_negative_v1}',
       '{"scope":"TRANSACTION_LOCAL_TEST","runtime_activation":false,"purpose":"DETECT_CANDIDATE_RESIDUE"}'::jsonb,true);
   v_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');
   INSERT INTO public.lf_capability_version_registry(
       capability_code,version,version_major,version_minor,version_patch,
       release_state,supersedes_version,manifest,manifest_sha256,
       source_ref,docs_ref,validator_ref,created_by_execution_id)
   SELECT capability_code,'1.0.1',1,0,1,'RELEASED','1.0.0',v_manifest,v_sha,
     source_ref,docs_ref,validator_ref,'M910_NEGATIVE_ROLLBACK_ONLY'
   FROM public.lf_capability_version_registry WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0';
   SELECT count(*) INTO v_injected FROM public.lf_capability_version_registry
     WHERE capability_code='INPUT_GOVERNANCE';
   v_detected:=v_injected>v_versions;
   IF NOT v_detected OR v_injected-v_versions<>1 THEN
     RAISE EXCEPTION 'M910_ADVERSARIAL_RESIDUE_NOT_DETECTED'; END IF;
   RAISE EXCEPTION 'M910_EXPECTED_SUBTRANSACTION_ROLLBACK';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM IS DISTINCT FROM 'M910_EXPECTED_SUBTRANSACTION_ROLLBACK' THEN RAISE; END IF;
 END;
 SELECT count(*) INTO v_runs_after FROM programacion.input_readiness_runs;
 SELECT count(*) INTO v_ass_after FROM programacion.input_family_assessments a
   JOIN programacion.input_readiness_runs r ON r.id=a.run_id;
 SELECT count(*) INTO v_bind_after FROM public.lf_capability_binding;
 SELECT count(*) INTO v_versions_after FROM public.lf_capability_version_registry
   WHERE capability_code='INPUT_GOVERNANCE';
 IF NOT v_detected OR v_runs_after<>v_runs OR v_ass_after<>v_ass
 OR v_bind_after<>v_bind OR v_versions_after<>v_versions
 OR EXISTS(SELECT 1 FROM public.lf_capability_version_registry
   WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1') THEN
 RAISE EXCEPTION 'M910_POST_ROLLBACK_RESIDUE_VS_HISTORICAL_BASELINE'; END IF;
 INSERT INTO m910_residue_negative_proof
 VALUES(v_detected,true,v_runs,v_runs_after,v_ass,v_ass_after,
   v_bind,v_bind_after,v_versions,v_versions_after);
END $residue$;
SELECT injection_detected,rollback_zero_candidate_residue,
 runs_pre,runs_post,assessments_pre,assessments_post,
 bindings_pre,bindings_post,versions_pre,versions_post
FROM m910_residue_negative_proof;
ROLLBACK;'''

def source_bound_residue_negative_sql() -> str:
    return RESIDUE_NEGATIVE_SQL

def verify_residue_negative(row: dict) -> dict:
    if row.get("injection_detected") is not True or row.get("rollback_zero_candidate_residue") is not True:
        raise AssertionError("M910_NEGATIVE_CASE_NOT_DEMONSTRATED")
    for name in ("runs", "assessments", "bindings", "versions"):
        if row.get(f"{name}_pre") != row.get(f"{name}_post"):
            raise AssertionError("M910_HISTORICAL_DATA_RESIDUE_" + name.upper())
    return {"test_passed": True, "test_exit_code": 0,
            "semantic_authority_bound": True, "adversarial_case_executed": True}
