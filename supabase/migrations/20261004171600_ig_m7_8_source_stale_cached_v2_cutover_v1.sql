-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M7.8 / PAULO-054
-- Runtime repair: the only live caller of cached_v1 is moved to cached_v2.
-- Fixture selection is behavior/cohort driven, never pinned to screen identities.
-- Does not relax Validator checks and does not change screen semantic states.

DO $cutover$
DECLARE
  v_sig constant regprocedure := 'programacion.fn_input_governance_recurate_source_stale_v1(integer,text,text,bigint)'::regprocedure;
  v_baseline_md5 constant text := '6066729809da6cc8ed05a89e5b4da222';
  v_candidate_md5 constant text := '996a6b3c0fc095ec714a70251adc14ef';
  v_def text;
  v_candidate text;
  v_screen integer;
  v_version bigint;
  v_graph jsonb;
  v_base jsonb;
  v_cached jsonb;
  v_target_count integer:=0;
BEGIN
  v_def := pg_get_functiondef(v_sig);
  IF md5(v_def) <> v_baseline_md5 THEN
    RAISE EXCEPTION 'BLOCK_M78_CUTOVER_BASELINE_DRIFT expected=% got=%',v_baseline_md5,md5(v_def);
  END IF;

  v_candidate := replace(
    v_def,
    'fn_input_governance_bootstrap_classify_v2_cached_v1',
    'fn_input_governance_bootstrap_classify_v2_cached_v2'
  );
  IF v_candidate=v_def OR md5(v_candidate)<>v_candidate_md5 THEN
    RAISE EXCEPTION 'BLOCK_M78_CUTOVER_CANDIDATE_DRIFT expected=% got=%',v_candidate_md5,md5(v_candidate);
  END IF;

  v_version := public.fn_lf_version_compatibility_current_version_id_v1(
    'PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT'
  );

  -- Bounded parity uses governed representative coverage plus one strongest
  -- current eligible screen by structural complexity. Screen identity is incidental.
  FOR v_screen IN
    WITH latest AS (
      SELECT DISTINCT ON (r.pantalla_id)
             r.pantalla_id,r.id,r.source_manifest
      FROM programacion.input_readiness_runs r
      JOIN lf_ops.pantallas p ON p.id=r.pantalla_id AND p.activa
      WHERE r.version_id=v_version AND r.status='COMPLETED' AND r.invalidated_at IS NULL
      ORDER BY r.pantalla_id,r.id DESC
    ), complexity AS (
      SELECT l.pantalla_id,
             coalesce(jsonb_array_length(l.source_manifest),0)
             + coalesce(sum(CASE WHEN jsonb_typeof(a.source_refs)='array' THEN jsonb_array_length(a.source_refs) ELSE 0 END),0)
             + coalesce(sum(CASE WHEN jsonb_typeof(a.blockers)='array' THEN jsonb_array_length(a.blockers) ELSE 0 END),0) AS complexity_score
      FROM latest l
      JOIN programacion.input_family_assessments a ON a.run_id=l.id
      WHERE programacion.fn_input_readiness_run_is_current(l.id)
      GROUP BY l.pantalla_id,l.source_manifest
      ORDER BY complexity_score DESC,l.pantalla_id
      LIMIT 1
    ), targets AS (
      SELECT pantalla_id
      FROM programacion.v_input_governance_representative_cohort_v1
      WHERE representative_rank=1
      UNION
      SELECT pantalla_id FROM complexity
    )
    SELECT DISTINCT pantalla_id FROM targets ORDER BY pantalla_id
  LOOP
    v_target_count:=v_target_count+1;
    v_graph := programacion.fn_input_screen_canonical_graph(v_screen,v_version);
    v_base := programacion.fn_input_governance_bootstrap_classify_v2(v_screen,'VISUAL_EVIDENCE',v_version);
    v_cached := programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(v_screen,'VISUAL_EVIDENCE',v_version,v_graph);
    IF v_base IS DISTINCT FROM v_cached THEN
      RAISE EXCEPTION 'BLOCK_M78_CUTOVER_CACHED_V2_VISUAL_PARITY:%',v_screen;
    END IF;
  END LOOP;

  IF v_target_count=0 THEN
    RAISE EXCEPTION 'BLOCK_M78_CUTOVER_NO_ELIGIBLE_BEHAVIOR_FIXTURE';
  END IF;

  EXECUTE v_candidate;

  IF md5(pg_get_functiondef(v_sig)) <> v_candidate_md5 THEN
    RAISE EXCEPTION 'BLOCK_M78_CUTOVER_READBACK';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('programacion','public','private')
      AND position('fn_input_governance_bootstrap_classify_v2_cached_v1' in p.prosrc)>0
  ) THEN
    RAISE EXCEPTION 'BLOCK_M78_CACHED_V1_LIVE_CALLER_REMAINS';
  END IF;

  INSERT INTO public.lf_test_suite_cases(
    suite_code,test_code,test_order,story_code,rule_codes,title,test_type,execution_mode,severity,
    preconditions,input_payload,expected_output,prohibited_output,status,metadata,
    created_by_execution_id,updated_by_execution_id
  ) VALUES (
    'INPUT_GOVERNANCE_REGRESSION','M7_8_VISUAL_CACHED_V2_PARITY',780,null,ARRAY[]::text[],
    'M7.8 behavior-driven cached/base VISUAL_EVIDENCE parity and zero cached_v1 live callers',
    'DETERMINISTIC','AUTOMATED','CRITICAL',
    jsonb_build_object(
      'contract_revision','5.13',
      'fixture_selection','BEHAVIOR_PRECONDITION_THEN_COMPLEXITY',
      'representative_cohort_required',true,
      'highest_complexity_current_required',true
    ),
    jsonb_build_object(
      'target_ref','sandbox/ig_cv/m7_8_cached_v2_route_parity_v1.sql',
      'consumer','IG_CURATOR_VALIDATOR_REFACTOR_V2:M7.8'
    ),
    jsonb_build_object(
      'cached_base_visual_parity',true,
      'cached_v1_live_callers',0,
      'fixed_screen_ids',false
    ),
    jsonb_build_object(
      'cached_v1_live_callers','>0',
      'visual_parity_mismatch',true,
      'fixed_screen_fixture_for_generic_control',true
    ),
    'CANDIDATO',
    jsonb_build_object(
      'consumer','IG_CURATOR_VALIDATOR_REFACTOR_V2:M7.8',
      'equivalence_capability','CONTROL_EQUIVALENCE_JUDGE@1.0.0',
      'policy_mode','EXACT_ONLY_ALL_DIVERGENCE_BLOCKS',
      'fixture_selection','BEHAVIOR_PRECONDITION_THEN_COMPLEXITY',
      'fixed_screen_ids',false,
      'root_cause','cached_v1 omitted CURRENT_VISUAL_ARTIFACT source_ref while cached_v2 matches base',
      'rollback','sandbox/ig_cv/m7_8_source_stale_cached_v2_rollback_v1.sql',
      'schema_adapter','LF_TEST_SUITE_CASES_CURRENT_SCHEMA_V1'
    ),
    'CHATGPT-IG-M7-8-PAULO054-20261004','CHATGPT-IG-M7-8-PAULO054-20261004'
  ) ON CONFLICT(suite_code,test_code) DO UPDATE SET
    test_order=excluded.test_order,
    story_code=excluded.story_code,
    rule_codes=excluded.rule_codes,
    title=excluded.title,
    test_type=excluded.test_type,
    execution_mode=excluded.execution_mode,
    severity=excluded.severity,
    preconditions=excluded.preconditions,
    input_payload=excluded.input_payload,
    expected_output=excluded.expected_output,
    prohibited_output=excluded.prohibited_output,
    status=excluded.status,
    metadata=excluded.metadata,
    updated_at=clock_timestamp(),
    updated_by_execution_id=excluded.updated_by_execution_id;
END
$cutover$;
