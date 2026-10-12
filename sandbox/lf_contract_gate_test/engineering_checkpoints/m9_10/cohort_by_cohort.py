"""M9.10: one governed SQL-only sandbox matrix, not a live cutover engine.

All members and their authority refs are read from canonical ACTIVE cohort data.
Every transient candidate is created only inside an exception-backed SQL
subtransaction and the entire matrix is enclosed by BEGIN/ROLLBACK.
No persistent version, domain record, runtime activation or live receipt.
The M9.9 six-case matrix is reused, never retested by this checkpoint.
The candidate exercises actual versioned-pointer mechanics only; it is not a
qualification of a new functional IG service release.
"""

SANDBOX_MATRIX_SQL = r'''BEGIN;
CREATE TEMP TABLE m910_source_bound_cohort_proof (
 cohort_type_code text, pantalla_id bigint, authority_ref text,
 promoted boolean, guarded_negative boolean, promoter_reverted boolean,
 exact_rollback boolean, candidate_version_residue bigint,
 historical_runs_delta bigint, historical_assessments_delta bigint,
 binding_delta bigint, live_canary_claim boolean
) ON COMMIT DROP;
DO $m910$
DECLARE c record; v_baseline public.lf_capability_current%rowtype;
 v_current public.lf_capability_current%rowtype;
 v_manifest jsonb; v_candidate_sha text; v_reply jsonb; v_negative jsonb; v_revert jsonb;
 v_expected int; v_count int; v_version_residue bigint;
 v_runs bigint; v_assessments bigint; v_bindings bigint;
 v_runs_post bigint; v_assessments_post bigint; v_bindings_post bigint;
BEGIN
 SELECT * INTO STRICT v_baseline FROM public.lf_capability_current
 WHERE capability_code='INPUT_GOVERNANCE';
 SELECT count(*) INTO v_expected
 FROM programacion.input_governance_cohort_memberships cm
 JOIN programacion.input_governance_cohort_types ct USING(cohort_type_code)
 WHERE cm.status='ACTIVE' AND ct.status='ACTIVE';
 IF v_expected=0 THEN RAISE EXCEPTION 'M910_NO_ACTIVE_GOVERNED_MEMBERSHIPS'; END IF;
 IF v_baseline.version IS DISTINCT FROM '1.0.0' THEN
 RAISE EXCEPTION 'M910_INPUT_GOVERNANCE_BASELINE_DRIFT'; END IF;
 SELECT count(*) INTO v_runs FROM programacion.input_readiness_runs;
 SELECT count(*) INTO v_assessments FROM programacion.input_family_assessments;
 SELECT count(*) INTO v_bindings FROM public.lf_capability_binding;
 FOR c IN
   SELECT ct.cohort_type_code,cm.pantalla_id,cm.authority_ref
   FROM programacion.input_governance_cohort_types ct
   JOIN programacion.input_governance_cohort_memberships cm USING(cohort_type_code)
   WHERE ct.status='ACTIVE' AND cm.status='ACTIVE'
   ORDER BY ct.display_order,cm.representative_rank,cm.pantalla_id
 LOOP
  IF EXISTS (SELECT 1 FROM public.lf_capability_version_registry
      WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1') THEN
    RAISE EXCEPTION 'M910_UNEXPECTED_REAL_CANDIDATE_PRESENT'; END IF;
  BEGIN
   SELECT manifest INTO STRICT v_manifest
   FROM public.lf_capability_version_registry WHERE capability_code='INPUT_GOVERNANCE'
   AND version=v_baseline.version;
   v_manifest:=jsonb_set(v_manifest,'{version}',to_jsonb('1.0.1'::text),false);
   v_manifest:=jsonb_set(v_manifest,'{sandbox_cohort_qualification_v1}',
     jsonb_build_object('cohort_type_code',c.cohort_type_code,
      'pantalla_id',c.pantalla_id,'authority_ref',c.authority_ref,
      'test_source','github://cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m9_10/cohort_by_cohort.py',
      'candidate_scope','TRANSIENT_TRANSACTION_LOCAL',
      'no_operational_release',true,'no_runtime_activation',true),true);
   v_candidate_sha:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');
   INSERT INTO public.lf_capability_version_registry (
    capability_code,version,version_major,version_minor,version_patch,
    release_state,supersedes_version,manifest,manifest_sha256,source_ref,
    docs_ref,validator_ref,created_by_execution_id)
   SELECT capability_code,'1.0.1',1,0,1,'RELEASED','1.0.0',
    v_manifest,v_candidate_sha,source_ref,docs_ref,validator_ref,
    'M910_TRANSIENT_SANDBOX_NO_OPERATIONAL_RELEASE'
   FROM public.lf_capability_version_registry
   WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0';
   IF NOT FOUND THEN RAISE EXCEPTION 'M910_GOVERNED_SOURCE_MISSING'; END IF;
   v_reply:=public.fn_lf_capability_promote_v1('INPUT_GOVERNANCE','1.0.1',
      v_baseline.manifest_sha256,'M910_TRANSIENT_SANDBOX','per-cohort sandbox qualification');
   SELECT * INTO STRICT v_current FROM public.lf_capability_current
      WHERE capability_code='INPUT_GOVERNANCE';
   IF v_reply->>'decision' IS DISTINCT FROM 'PROMOTED_CURRENT'
      OR v_current.version IS DISTINCT FROM '1.0.1'
      OR v_current.manifest_sha256 IS DISTINCT FROM v_candidate_sha THEN
      RAISE EXCEPTION 'M910_REAL_GOVERNED_PROMOTION_NOT_OBSERVED'; END IF;
   v_negative:=public.fn_lf_capability_promote_v1('INPUT_GOVERNANCE','1.0.0',
       v_baseline.manifest_sha256,'M910_TRANSIENT_SANDBOX','stale currentness negative');
   IF v_negative->>'decision' IS DISTINCT FROM 'BLOCK_CURRENTNESS_MISMATCH'
     OR NOT EXISTS (SELECT 1 FROM public.lf_capability_current
       WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1'
         AND manifest_sha256=v_candidate_sha) THEN
     RAISE EXCEPTION 'M910_NEGATIVE_STALE_MANIFEST_FAILED'; END IF;
   v_revert:=public.fn_lf_capability_promote_v1('INPUT_GOVERNANCE','1.0.0',
       v_candidate_sha,'M910_TRANSIENT_SANDBOX','per-cohort promoter revert');
   IF v_revert->>'decision' IS DISTINCT FROM 'PROMOTED_CURRENT'
     OR NOT EXISTS (SELECT 1 FROM public.lf_capability_current
        WHERE capability_code='INPUT_GOVERNANCE' AND version=v_baseline.version
          AND manifest_sha256=v_baseline.manifest_sha256) THEN
     RAISE EXCEPTION 'M910_VERSIONED_REVERT_FAILED'; END IF;
   RAISE EXCEPTION 'M910_EXPECTED_SUBTRANSACTION_ROLLBACK';
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM IS DISTINCT FROM 'M910_EXPECTED_SUBTRANSACTION_ROLLBACK' THEN RAISE; END IF;
  END;
  SELECT * INTO STRICT v_current FROM public.lf_capability_current
  WHERE capability_code='INPUT_GOVERNANCE';
  SELECT count(*) INTO v_version_residue FROM public.lf_capability_version_registry
     WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1';
  SELECT count(*) INTO v_runs_post FROM programacion.input_readiness_runs;
  SELECT count(*) INTO v_assessments_post FROM programacion.input_family_assessments;
  SELECT count(*) INTO v_bindings_post FROM public.lf_capability_binding;
  IF to_jsonb(v_current) IS DISTINCT FROM to_jsonb(v_baseline)
    OR v_version_residue<>0 OR v_runs_post<>v_runs
    OR v_assessments_post<>v_assessments OR v_bindings_post<>v_bindings THEN
    RAISE EXCEPTION 'M910_POSTSTATE_MISMATCH_FOR_COHORT:%',c.cohort_type_code; END IF;
  INSERT INTO m910_source_bound_cohort_proof VALUES
    (c.cohort_type_code,c.pantalla_id,c.authority_ref,true,true,true,true,
     v_version_residue,v_runs_post-v_runs,v_assessments_post-v_assessments,
     v_bindings_post-v_bindings,false);
 END LOOP;
 SELECT count(*) INTO v_count FROM m910_source_bound_cohort_proof;
 IF v_count<>v_expected THEN RAISE EXCEPTION 'M910_COHORT_COVERAGE_MISMATCH'; END IF;
END $m910$;
SELECT cohort_type_code,pantalla_id,authority_ref,promoted,guarded_negative,
 promoter_reverted,exact_rollback,candidate_version_residue,historical_runs_delta,
 historical_assessments_delta,binding_delta,live_canary_claim
FROM m910_source_bound_cohort_proof ORDER BY cohort_type_code,pantalla_id;
ROLLBACK;'''


def source_bound_sandbox_matrix_sql() -> str:
    """Supply this exact source to the governed SQL connector."""
    return SANDBOX_MATRIX_SQL


def verify_sandbox_matrix(rows: list[dict], active_memberships: list[dict]) -> dict:
    """Reject missing/duplicate/unexpected cohorts and falsely claimed results."""
    def ident(row: dict) -> tuple:
        return (row["cohort_type_code"], row["pantalla_id"], row["authority_ref"])

    expected = [ident(x) for x in active_memberships]
    observed = [ident(x) for x in rows]
    if not expected or len(expected) != len(set(expected)):
        raise AssertionError("M910_INVALID_GOVERNED_COHORT_INPUT")
    if len(observed) != len(set(observed)) or set(observed) != set(expected):
        raise AssertionError("M910_INCOMPLETE_OR_DUPLICATE_COHORT_COVERAGE")
    for result in rows:
        if not all(result.get(field) is True for field in
                   ("promoted", "guarded_negative", "promoter_reverted", "exact_rollback")):
            raise AssertionError("M910_POSITIVE_OR_NEGATIVE_CONTROL_FAILED")
        if result.get("live_canary_claim") is not False:
            raise AssertionError("M910_SANDBOX_MUST_NOT_CLAIM_LIVE")
        if any(result.get(field) != 0 for field in
               ("candidate_version_residue", "historical_runs_delta",
                "historical_assessments_delta", "binding_delta")):
            raise AssertionError("M910_ROLLBACK_RESIDUE_DETECTED")
    return {"status": "PASS_SANDBOX_ONLY", "coverage": len(rows),
            "all_governed_members_verified": True,
            "live_signed_receipts_verified": False,
            "operational_release_authorized": False}
