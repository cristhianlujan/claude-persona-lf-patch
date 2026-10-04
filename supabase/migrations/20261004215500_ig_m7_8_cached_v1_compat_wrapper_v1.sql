-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M7.8 / PAULO-054
-- Demonstrated drift only: bootstrap_classify_v2_cached_v1 omitted CURRENT_VISUAL_ARTIFACT.
-- Preserve the v1 signature as a compatibility alias to the already-proven cached_v2 implementation.
-- T-EQUIV policy for IG remains exact-only; no non-semantic exception list is introduced.

DO $m78$
DECLARE
  v_execution_id constant text := 'CHATGPT-IG-M7-8-PAULO054-COMPAT-20261004';
  v_expected_old_prosrc_md5 constant text := 'd2069b41cec7fe5f540dfcfc9076172b';
  v_current_md5 text;
  v_version bigint;
  v_screen integer;
  v_graph jsonb;
  v_base jsonb;
  v_cached jsonb;
  v_target_count integer := 0;
BEGIN
  SELECT md5(p.prosrc) INTO v_current_md5
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='programacion' AND p.proname='fn_input_governance_bootstrap_classify_v2_cached_v1';
  IF v_current_md5 IS DISTINCT FROM v_expected_old_prosrc_md5 THEN
    RAISE EXCEPTION 'BLOCK_M78_CACHED_V1_BASELINE_DRIFT expected=% got=%',v_expected_old_prosrc_md5,v_current_md5;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='CONTROL_EQUIVALENCE_JUDGE' AND version='1.0.0'
  ) THEN
    RAISE EXCEPTION 'BLOCK_M78_TEQUIV_NOT_CURRENT';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution
    WHERE execution_id='T-EQUIV-IG-M7-8-20261004-V1' AND status='COMPLETED'
  ) THEN
    RAISE EXCEPTION 'BLOCK_M78_TEQUIV_BINDING_NOT_COMPLETED';
  END IF;

  -- The old implementation must no longer be a live dependency before it becomes a compatibility alias.
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('programacion','public','private')
      AND p.proname<>'fn_input_governance_bootstrap_classify_v2_cached_v1'
      AND position('fn_input_governance_bootstrap_classify_v2_cached_v1' in p.prosrc)>0
  ) THEN
    RAISE EXCEPTION 'BLOCK_M78_CACHED_V1_LIVE_CALLER_REAPPEARED';
  END IF;

  CREATE OR REPLACE FUNCTION programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(
    p_pantalla_id integer, p_family_code text, p_version_id bigint, p_graph jsonb
  ) RETURNS jsonb
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path TO 'pg_catalog','programacion','lf_ops'
  AS $compat$
    SELECT programacion.fn_input_governance_bootstrap_classify_v2_cached_v2($1,$2,$3,$4)
  $compat$;

  v_version := public.fn_lf_version_compatibility_current_version_id_v1(
    'PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT'
  );

  -- Refresh only the demonstrated drift surface. Fixture identity is incidental.
  FOR v_screen IN
    WITH latest AS (
      SELECT DISTINCT ON (r.pantalla_id) r.pantalla_id,r.id,r.source_manifest
      FROM programacion.input_readiness_runs r
      JOIN lf_ops.pantallas p ON p.id=r.pantalla_id AND p.activa
      WHERE r.version_id=v_version AND r.status='COMPLETED' AND r.invalidated_at IS NULL
      ORDER BY r.pantalla_id,r.id DESC
    ), complexity AS (
      SELECT l.pantalla_id,
             coalesce(jsonb_array_length(l.source_manifest),0)
             + coalesce(sum(CASE WHEN jsonb_typeof(a.source_refs)='array' THEN jsonb_array_length(a.source_refs) ELSE 0 END),0)
             + coalesce(sum(CASE WHEN jsonb_typeof(a.blockers)='array' THEN jsonb_array_length(a.blockers) ELSE 0 END),0) AS score
      FROM latest l JOIN programacion.input_family_assessments a ON a.run_id=l.id
      WHERE programacion.fn_input_readiness_run_is_current(l.id)
      GROUP BY l.pantalla_id,l.source_manifest
      ORDER BY score DESC,l.pantalla_id LIMIT 1
    ), targets AS (
      SELECT pantalla_id FROM programacion.v_input_governance_representative_cohort_v1 WHERE representative_rank=1
      UNION SELECT pantalla_id FROM complexity
    )
    SELECT pantalla_id FROM targets ORDER BY pantalla_id
  LOOP
    v_target_count:=v_target_count+1;
    v_graph:=programacion.fn_input_screen_canonical_graph(v_screen,v_version);
    v_base:=programacion.fn_input_governance_bootstrap_classify_v2(v_screen,'VISUAL_EVIDENCE',v_version);
    v_cached:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v1(v_screen,'VISUAL_EVIDENCE',v_version,v_graph);
    IF v_base IS DISTINCT FROM v_cached THEN
      RAISE EXCEPTION 'BLOCK_M78_CACHED_V1_COMPAT_PARITY:screen=%',v_screen;
    END IF;
  END LOOP;
  IF v_target_count=0 THEN RAISE EXCEPTION 'BLOCK_M78_NO_BEHAVIOR_FIXTURE'; END IF;

  UPDATE public.lf_test_suite_cases
  SET status='ACTIVE',
      expected_output=coalesce(expected_output,'{}'::jsonb)||jsonb_build_object(
        'cached_v1_compat_alias',true,
        'cached_v2_live_parity',true,
        'non_semantic_exceptions',jsonb_build_array()
      ),
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'compat_wrapper','fn_input_governance_bootstrap_classify_v2_cached_v1->cached_v2',
        'reuse_policy','UNCHANGED_PAIR_EVIDENCE_REUSED_WHILE_SOURCE_FINGERPRINTS_UNCHANGED',
        'refresh_scope','DEMONSTRATED_DRIFT_ONLY',
        't_equiv_binding_execution','T-EQUIV-IG-M7-8-20261004-V1'
      ),
      updated_at=clock_timestamp(),updated_by_execution_id=v_execution_id
  WHERE suite_code='INPUT_GOVERNANCE_REGRESSION' AND test_code='M7_8_VISUAL_CACHED_V2_PARITY';

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_test_suite_cases
    WHERE suite_code='INPUT_GOVERNANCE_REGRESSION' AND test_code='M7_8_VISUAL_CACHED_V2_PARITY' AND status='ACTIVE'
  ) THEN RAISE EXCEPTION 'BLOCK_M78_PERMANENT_CASE_NOT_ACTIVE'; END IF;
END
$m78$;
