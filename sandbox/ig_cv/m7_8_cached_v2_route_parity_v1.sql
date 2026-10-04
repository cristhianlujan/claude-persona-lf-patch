-- M7.8 permanent regression: behavior-first fixture selection.
-- The control is tested against the governed representative cohort plus the
-- highest-complexity current eligible screen. No screen identity is authoritative.
DO $test$
DECLARE
  v_version bigint;
  v_screen integer;
  v_graph jsonb;
  v_base jsonb;
  v_cached jsonb;
  v_target_count integer:=0;
BEGIN
  v_version := public.fn_lf_version_compatibility_current_version_id_v1(
    'PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT'
  );

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
    v_graph:=programacion.fn_input_screen_canonical_graph(v_screen,v_version);
    v_base:=programacion.fn_input_governance_bootstrap_classify_v2(v_screen,'VISUAL_EVIDENCE',v_version);
    v_cached:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(v_screen,'VISUAL_EVIDENCE',v_version,v_graph);
    IF v_base IS DISTINCT FROM v_cached THEN
      RAISE EXCEPTION 'M7_8_VISUAL_CACHED_V2_PARITY_FAILED:screen=%',v_screen;
    END IF;
  END LOOP;

  IF v_target_count=0 THEN
    RAISE EXCEPTION 'M7_8_NO_ELIGIBLE_BEHAVIOR_FIXTURE';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('programacion','public','private')
      AND position('fn_input_governance_bootstrap_classify_v2_cached_v1' in p.prosrc)>0
  ) THEN
    RAISE EXCEPTION 'M7_8_CACHED_V1_LIVE_CALLER_FOUND';
  END IF;
END
$test$;
