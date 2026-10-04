-- M7.8 permanent regression: exact VISUAL_EVIDENCE parity + zero cached_v1 live callers.
DO $test$
DECLARE
  v_version bigint;
  v_screen integer;
  v_graph jsonb;
  v_base jsonb;
  v_cached jsonb;
BEGIN
  v_version := public.fn_lf_version_compatibility_current_version_id_v1(
    'PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT'
  );
  FOREACH v_screen IN ARRAY ARRAY[1,2,3,5,43,51,52,53,54,55,56,57,58] LOOP
    v_graph:=programacion.fn_input_screen_canonical_graph(v_screen,v_version);
    v_base:=programacion.fn_input_governance_bootstrap_classify_v2(v_screen,'VISUAL_EVIDENCE',v_version);
    v_cached:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(v_screen,'VISUAL_EVIDENCE',v_version,v_graph);
    IF v_base IS DISTINCT FROM v_cached THEN
      RAISE EXCEPTION 'M7_8_VISUAL_CACHED_V2_PARITY_FAILED:%',v_screen;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('programacion','public','private')
      AND position('fn_input_governance_bootstrap_classify_v2_cached_v1' in p.prosrc)>0
  ) THEN
    RAISE EXCEPTION 'M7_8_CACHED_V1_LIVE_CALLER_FOUND';
  END IF;
END
$test$;
