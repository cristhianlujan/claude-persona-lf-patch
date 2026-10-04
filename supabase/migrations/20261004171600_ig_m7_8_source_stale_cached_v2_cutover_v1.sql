-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M7.8 / PAULO-054
-- Minimal runtime repair: the only live caller of cached_v1 is moved to cached_v2.
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

  -- Bounded semantic/evidence parity on every screen currently blocking M0.6.
  FOREACH v_screen IN ARRAY ARRAY[3,5,43,51,57] LOOP
    v_graph := programacion.fn_input_screen_canonical_graph(v_screen,v_version);
    v_base := programacion.fn_input_governance_bootstrap_classify_v2(v_screen,'VISUAL_EVIDENCE',v_version);
    v_cached := programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(v_screen,'VISUAL_EVIDENCE',v_version,v_graph);
    IF v_base IS DISTINCT FROM v_cached THEN
      RAISE EXCEPTION 'BLOCK_M78_CUTOVER_CACHED_V2_VISUAL_PARITY:%',v_screen;
    END IF;
  END LOOP;

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
    suite_code,test_code,test_order,title,test_type,execution_mode,target_ref,
    expected_outcome,severity,status,metadata,created_by_execution_id,updated_by_execution_id
  ) VALUES (
    'INPUT_GOVERNANCE_REGRESSION','M7_8_VISUAL_CACHED_V2_PARITY',780,
    'M7.8 cached/base VISUAL_EVIDENCE parity and zero cached_v1 live callers',
    'PARITY','CUSTOM_SQL',
    'sandbox/ig_cv/m7_8_cached_v2_route_parity_v1.sql',
    '13 target screens: base == cached_v2 for VISUAL_EVIDENCE; zero live callers of cached_v1',
    'P0','ACTIVE',
    jsonb_build_object(
      'consumer','IG_CURATOR_VALIDATOR_REFACTOR_V2:M7.8',
      'equivalence_capability','CONTROL_EQUIVALENCE_JUDGE@1.0.0',
      'policy_mode','EXACT_ONLY_ALL_DIVERGENCE_BLOCKS',
      'root_cause','cached_v1 omitted CURRENT_VISUAL_ARTIFACT source_ref while cached_v2 matches base',
      'rollback','sandbox/ig_cv/m7_8_source_stale_cached_v2_rollback_v1.sql'
    ),
    'CHATGPT-IG-M7-8-PAULO054-20261004','CHATGPT-IG-M7-8-PAULO054-20261004'
  ) ON CONFLICT(suite_code,test_code) DO UPDATE SET
    title=excluded.title,test_order=excluded.test_order,test_type=excluded.test_type,
    execution_mode=excluded.execution_mode,target_ref=excluded.target_ref,
    expected_outcome=excluded.expected_outcome,severity=excluded.severity,status='ACTIVE',
    metadata=excluded.metadata,updated_at=clock_timestamp(),updated_by_execution_id=excluded.updated_by_execution_id;
END
$cutover$;
