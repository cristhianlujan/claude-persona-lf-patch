-- IG package 4 (slice 6): live Curator comparison against the latest COMPLETED run of a screen.
-- programacion.fn_input_live_compare_run_v1(p_pantalla_id) recomputes the Curator for the screen inside an always-rolled-back
-- subtransaction (SQLSTATE P0099) and diffs the six Curator-side status fields per family against the screen's latest COMPLETED run.
-- It writes nothing durable. ~20-50 s per screen. VOLATILE because the Curator materialization writes inside the subtransaction.
-- Known, intentional drift (accepted ONLY as an upgrade): family RUNTIME_CONFIG coverage/well_defined MISSING->PARTIAL->COMPLETE
-- after migration 20261008104319 ig_runtime_config_existing_authority_reuse_v1 ("reuse an already-governed current architecture
-- decision referenced by a current screen rule before declaring RUNTIME_CONFIG source missing"). Observed 2026-10-09 on screens
-- 1,3,4,5,6,11,18 (baselines from the 5.13 era); screens 2,54,55 (5.13.1-era baselines) were identical.
-- Any other family differing, any RUNTIME_CONFIG downgrade, or a RUNTIME_CONFIG change outside coverage/well_defined is unexpected.
-- passed = families=47 AND no unexpected differences. Validator-side outcome is not compared (the validator close is slow and iterative).
CREATE OR REPLACE FUNCTION programacion.fn_input_live_compare_run_v1(p_pantalla_id integer)
 RETURNS TABLE(pantalla_id integer, baseline_run_id bigint, families integer, drift_known text[], drift_unexpected text[], passed boolean, detail text)
 LANGUAGE plpgsql
 VOLATILE
 SET search_path TO 'pg_catalog'
 SET statement_timeout TO '170s'
AS $fn$
DECLARE
  v_base bigint; v_res jsonb; v_msg text;
BEGIN
  SELECT r.id INTO v_base FROM programacion.input_readiness_runs r
   WHERE r.pantalla_id=p_pantalla_id AND r.status='COMPLETED' ORDER BY r.id DESC LIMIT 1;
  IF v_base IS NULL THEN
    RETURN QUERY SELECT p_pantalla_id, NULL::bigint, 0, '{}'::text[], '{}'::text[], false, 'NO_COMPLETED_BASELINE_RUN';
    RETURN;
  END IF;
  BEGIN
    DECLARE v_mat jsonb; v_new bigint; v_n int; v_known text[]; v_unexp text[];
    BEGIN
      v_mat := programacion.fn_input_governance_curator_materialize_v1(p_pantalla_id,'MANUAL',
                 'INPUT_CURATOR:SQL:ig-governed-dispatch-v1:LIVE_COMPARE_'||p_pantalla_id, true);
      v_new := (v_mat->>'run_id')::bigint;
      SELECT count(*) INTO v_n FROM programacion.input_family_assessments WHERE run_id=v_new;
      WITH d AS (
        SELECT b.family_code,
               (b.coverage_status,b.well_defined_status,b.story_ready_status,b.implementation_ready_status,b.qa_ready_status,b.production_ready_status)
                 IS DISTINCT FROM
               (l.coverage_status,l.well_defined_status,l.story_ready_status,l.implementation_ready_status,l.qa_ready_status,l.production_ready_status) AS differs,
               (b.family_code='RUNTIME_CONFIG'
                AND (b.story_ready_status,b.implementation_ready_status,b.qa_ready_status,b.production_ready_status)
                    IS NOT DISTINCT FROM (l.story_ready_status,l.implementation_ready_status,l.qa_ready_status,l.production_ready_status)
                AND (CASE b.coverage_status WHEN 'MISSING' THEN 0 WHEN 'PARTIAL' THEN 1 WHEN 'COMPLETE' THEN 2 END)
                    <= (CASE l.coverage_status WHEN 'MISSING' THEN 0 WHEN 'PARTIAL' THEN 1 WHEN 'COMPLETE' THEN 2 END)
                AND (CASE b.well_defined_status WHEN 'MISSING' THEN 0 WHEN 'PARTIAL' THEN 1 WHEN 'COMPLETE' THEN 2 END)
                    <= (CASE l.well_defined_status WHEN 'MISSING' THEN 0 WHEN 'PARTIAL' THEN 1 WHEN 'COMPLETE' THEN 2 END)) AS known_upgrade
          FROM programacion.input_family_assessments b
          JOIN programacion.input_family_assessments l ON l.family_code=b.family_code AND l.run_id=v_new
         WHERE b.run_id=v_base)
      SELECT coalesce(array_agg(family_code ORDER BY family_code) FILTER (WHERE differs AND known_upgrade),'{}'),
             coalesce(array_agg(family_code ORDER BY family_code) FILTER (WHERE differs AND NOT known_upgrade),'{}')
        INTO v_known, v_unexp FROM d;
      RAISE EXCEPTION USING ERRCODE='P0099', MESSAGE=jsonb_build_object('families',v_n,'known',to_jsonb(v_known),'unexpected',to_jsonb(v_unexp))::text;
    EXCEPTION WHEN SQLSTATE 'P0099' THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    END;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT p_pantalla_id, v_base, 0, '{}'::text[], '{}'::text[], false, 'RUN_ERROR:'||left(SQLERRM,200);
    RETURN;
  END;
  v_res := v_msg::jsonb;
  RETURN QUERY SELECT p_pantalla_id, v_base, (v_res->>'families')::int,
    ARRAY(SELECT jsonb_array_elements_text(v_res->'known')), ARRAY(SELECT jsonb_array_elements_text(v_res->'unexpected')),
    ((v_res->>'families')::int = 47 AND jsonb_array_length(v_res->'unexpected') = 0),
    'ROLLED_BACK_LIVE_RECOMPUTE_VS_LATEST_COMPLETED_RUN';
END
$fn$;
COMMENT ON FUNCTION programacion.fn_input_live_compare_run_v1(integer) IS
 'Live Curator recompute (rolled back) vs the screen''s latest COMPLETED run. Accepts only the known RUNTIME_CONFIG upgrade from migration 20261008104319.';
