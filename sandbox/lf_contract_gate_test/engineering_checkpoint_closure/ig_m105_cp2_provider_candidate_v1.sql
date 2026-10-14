-- CANDIDATE only. Domain-specific evidence provider, not a generic engine change.
-- No DML outside the future, authorized installation. No new screen runs.

CREATE OR REPLACE FUNCTION programacion.fn_ig_m105_cp2_closure_proof_v1(
 p_plan_code text,p_unit_code text,p_checkpoint_code text
) RETURNS jsonb
LANGUAGE plpgsql STABLE
SET search_path=pg_catalog,programacion,public
AS $provider$
DECLARE
 v programacion.v_ig_m105_cp2_sample_readback_v1%rowtype;
 v_valid int;
 v_stale bigint;
 v_families text[];
BEGIN
 IF p_plan_code IS DISTINCT FROM 'IG_CURATOR_VALIDATOR_REFACTOR_V2'
    OR p_unit_code IS DISTINCT FROM 'M10.5'
    OR p_checkpoint_code IS DISTINCT FROM 'NEW_RUNS_VNEXT'
 THEN RAISE EXCEPTION 'M105_SAMPLE_PROVIDER_WRONG_TARGET'; END IF;
 SELECT * INTO STRICT v FROM programacion.v_ig_m105_cp2_sample_readback_v1;
 IF v.sample_screen_id IS DISTINCT FROM 1
   OR v.sample_run_id IS NULL
   OR v.run_status IS DISTINCT FROM 'COMPLETED'
   OR v.source_current IS DISTINCT FROM true
   OR v.sampled_screen_count IS DISTINCT FROM 1
   OR v.sample_family_count IS DISTINCT FROM 5
   OR v.valid_family_count IS DISTINCT FROM 5
   OR v.sample_verdict IS DISTINCT FROM 'PASS_CP2_MUESTRA'
   OR v.stale_negative_verified IS DISTINCT FROM true
   OR v.authorizes_production IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'M105_SAMPLE_PROVIDER_NO_REAL_PASS'; END IF;

 SELECT array_agg(f.family ORDER BY f.family) INTO v_families
 FROM jsonb_to_recordset(v.sample_families) AS f(
  family text,valid_evidence boolean);
 IF v_families IS DISTINCT FROM ARRAY[
  'ACCESSIBILITY','API_DATA_CONTRACT','FRESHNESS_INVALIDATION','SECURITY','STATES'
 ]::text[] THEN RAISE EXCEPTION 'M105_SAMPLE_PROVIDER_STRATA_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_to_recordset(v.sample_families)
   AS f(family text,valid_evidence boolean)
   WHERE f.valid_evidence IS DISTINCT FROM true)
 THEN RAISE EXCEPTION 'M105_SAMPLE_PROVIDER_INVALID_EVIDENCE_FLAG'; END IF;

 SELECT count(*) INTO v_valid FROM programacion.input_family_assessments a
 WHERE a.run_id=v.sample_run_id
 AND a.family_code IN ('ACCESSIBILITY','API_DATA_CONTRACT',
       'FRESHNESS_INVALIDATION','SECURITY','STATES')
 AND a.validator_outcome IN ('PASS','FAIL','BLOCKED')
 AND a.validator_identity IS NOT NULL
 AND a.validator_sha256 ~ '^[0-9a-f]{64}$'
 AND a.validator_assessed_at IS NOT NULL
 AND jsonb_typeof(a.validator_findings)='array';
 IF v_valid<>5 THEN RAISE EXCEPTION 'M105_SAMPLE_PROVIDER_INDEPENDENT_EVIDENCE_MISSING'; END IF;
 SELECT r.id INTO v_stale FROM programacion.input_readiness_runs r
 WHERE r.pantalla_id=1 AND r.status='COMPLETED' AND r.id<v.sample_run_id
 AND NOT programacion.fn_input_run_is_source_current(r.id)
 ORDER BY r.id DESC LIMIT 1;
 IF v_stale IS NULL OR NOT programacion.fn_input_run_is_source_current(v.sample_run_id)
 THEN RAISE EXCEPTION 'M105_SAMPLE_PROVIDER_CURRENT_OR_STALE_NEGATIVE_FAILED'; END IF;

 RETURN jsonb_build_object(
  'status','PASS',
  'evidence_ref','supabase://programacion.v_ig_m105_cp2_sample_readback_v1'
    ||'#screen=1&run='||v.sample_run_id||'&stale_negative='||v_stale,
  'observed',jsonb_build_object(
   'sampled_screen_count',1,'sample_family_count',5,'valid_family_count',v_valid,
   'sample_verdict',v.sample_verdict,'source_current',v.source_current,
   'stale_negative_verified',v.stale_negative_verified,
   'authorizes_production',false,
   'sample_run_id',v.sample_run_id,
   'semantic_observation_count',v.semantic_observation_count)
 );
END $provider$;

-- Candidate-only registry entry; NOT ACTIVE. Only owner can activate after
-- Router/operation/guard, grant and exact-identity checks are admitted.
INSERT INTO programacion.engineering_checkpoint_closure_providers_v1
(plan_code,unit_code,checkpoint_code,provider_fn,binding_state,contract_ref)
VALUES(
 'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.5','NEW_RUNS_VNEXT',
 'programacion.fn_ig_m105_cp2_closure_proof_v1(text,text,text)'::regprocedure,
 'CANDIDATE','M105_CP2_REPRESENTATIVE_SAMPLE_V1')
ON CONFLICT(plan_code,unit_code,checkpoint_code) DO NOTHING;

REVOKE ALL ON FUNCTION programacion.fn_ig_m105_cp2_closure_proof_v1(
 text,text,text) FROM PUBLIC,anon,authenticated;
