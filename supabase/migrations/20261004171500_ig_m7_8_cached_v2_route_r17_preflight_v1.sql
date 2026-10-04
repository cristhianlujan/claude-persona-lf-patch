-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M7.8 / PAULO-054
-- R17 rollback-only preflight with behavior-first fixture selection.
-- Select any live target satisfying the stale-routing precondition; when several
-- qualify, prefer the highest-complexity target. No screen id is authoritative.

DO $preflight$
DECLARE
  v_sig constant regprocedure := 'programacion.fn_input_governance_recurate_source_stale_v1(integer,text,text,bigint)'::regprocedure;
  v_baseline_md5 constant text := '6066729809da6cc8ed05a89e5b4da222';
  v_candidate_md5 constant text := '996a6b3c0fc095ec714a70251adc14ef';
  v_old_def text;
  v_candidate_def text;
  v_curator_identity text := 'INPUT_CURATOR:EDGE:input-governance-curator-v1:'||gen_random_uuid()::text;
  v_validator_identity text := 'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:'||replace(gen_random_uuid()::text,'-','');
  v_dispatch jsonb;
  v_curator jsonb;
  v_validator jsonb;
  v_run_id bigint;
  v_target_screen integer;
  v_target_parent bigint;
  v_i integer;
  v_err text;
  v_rolled_back boolean := false;
BEGIN
  v_old_def := pg_get_functiondef(v_sig);
  IF md5(v_old_def) <> v_baseline_md5 THEN
    RAISE EXCEPTION 'BLOCK_M78_R17_BASELINE_DRIFT expected=% got=%',v_baseline_md5,md5(v_old_def);
  END IF;

  v_candidate_def := replace(
    v_old_def,
    'fn_input_governance_bootstrap_classify_v2_cached_v1',
    'fn_input_governance_bootstrap_classify_v2_cached_v2'
  );
  IF v_candidate_def = v_old_def OR md5(v_candidate_def) <> v_candidate_md5 THEN
    RAISE EXCEPTION 'BLOCK_M78_R17_CANDIDATE_BUILD expected=% got=%',v_candidate_md5,md5(v_candidate_def);
  END IF;

  -- Behavior-first selector: only a target that currently satisfies the stale
  -- routing contract may be used. Complexity breaks ties; identity never does.
  WITH latest AS (
    SELECT DISTINCT ON (r.pantalla_id)
           r.*
    FROM programacion.input_readiness_runs r
    JOIN lf_ops.pantallas p ON p.id=r.pantalla_id AND p.activa
    WHERE r.status='COMPLETED' AND r.invalidated_at IS NULL
    ORDER BY r.pantalla_id,r.id DESC
  ), eligible AS (
    SELECT l.pantalla_id,l.id AS run_id,
           coalesce((d.delta#>>'{summary,affected_family_count}')::integer,0) AS affected_families,
           coalesce(jsonb_array_length(l.source_manifest),0)
           + coalesce(sum(CASE WHEN jsonb_typeof(a.source_refs)='array' THEN jsonb_array_length(a.source_refs) ELSE 0 END),0)
           + coalesce(sum(CASE WHEN jsonb_typeof(a.blockers)='array' THEN jsonb_array_length(a.blockers) ELSE 0 END),0) AS complexity_score,
           sum(CASE WHEN x.value->>'state'='RESOLUTION_ERROR' THEN 1 ELSE 0 END) AS resolution_errors,
           d.delta
    FROM latest l
    CROSS JOIN LATERAL (SELECT programacion.fn_input_freshness_delta(l.id) AS delta) d
    JOIN programacion.input_family_assessments a ON a.run_id=l.id
    LEFT JOIN LATERAL jsonb_array_elements(coalesce(d.delta->'source_changes','[]'::jsonb)) x(value) ON true
    GROUP BY l.pantalla_id,l.id,l.source_manifest,d.delta
    HAVING d.delta->>'run_state'='STALE'
       AND coalesce((d.delta#>>'{summary,changed_source_count}')::integer,0)>0
       AND coalesce((d.delta#>>'{summary,affected_family_count}')::integer,0)>0
       AND not coalesce((d.delta#>>'{summary,use_successor_required}')::boolean,false)
       AND sum(CASE WHEN x.value->>'state'='RESOLUTION_ERROR' THEN 1 ELSE 0 END)=0
  )
  SELECT pantalla_id,run_id
    INTO v_target_screen,v_target_parent
  FROM eligible
  ORDER BY affected_families DESC,complexity_score DESC,run_id DESC
  LIMIT 1;

  IF v_target_screen IS NULL OR v_target_parent IS NULL THEN
    RAISE EXCEPTION 'BLOCK_M78_R17_NO_ELIGIBLE_STALE_BEHAVIOR_FIXTURE';
  END IF;

  -- PostgreSQL exception blocks are subtransactions. The deliberate terminal
  -- exception rolls back DDL + all run/assessment/proposal writes.
  BEGIN
    EXECUTE v_candidate_def;
    IF md5(pg_get_functiondef(v_sig)) <> v_candidate_md5 THEN
      RAISE EXCEPTION 'BLOCK_M78_R17_CANDIDATE_NOT_EXACT';
    END IF;

    v_dispatch := programacion.fn_input_governance_execute(v_target_screen,'STORY_CREATOR');
    IF coalesce(v_dispatch->>'status','') <> 'CURATOR_RUNTIME_REQUIRED' THEN
      RAISE EXCEPTION 'BLOCK_M78_R17_DISPATCH:screen=% payload=%',v_target_screen,left(v_dispatch::text,500);
    END IF;

    v_curator := public.fn_input_governance_curator_materialize_v1(v_target_screen,'STORY_CREATOR',v_curator_identity);
    v_run_id := coalesce((v_curator->>'run_id')::bigint,(v_curator->>'latest_run_id')::bigint);
    IF coalesce(v_curator->>'status','') <> 'VALIDATOR_RUNTIME_REQUIRED' OR v_run_id IS NULL THEN
      RAISE EXCEPTION 'BLOCK_M78_R17_CURATOR:screen=% payload=%',v_target_screen,left(v_curator::text,500);
    END IF;

    FOR v_i IN 1..8 LOOP
      v_validator := public.fn_input_governance_validator_validate_v1(v_run_id,v_validator_identity);
      EXIT WHEN coalesce(v_validator->>'status','') IN ('COMPLETED','NOOP_COMPLETED');
    END LOOP;

    IF coalesce(v_validator->>'status','') NOT IN ('COMPLETED','NOOP_COMPLETED') THEN
      RAISE EXCEPTION 'BLOCK_M78_R17_VALIDATOR_NOT_TERMINAL:%',left(coalesce(v_validator::text,''),500);
    END IF;
    IF (SELECT count(*) FROM programacion.input_family_assessments WHERE run_id=v_run_id) <> 47 THEN
      RAISE EXCEPTION 'BLOCK_M78_R17_FAMILY_CARDINALITY';
    END IF;
    IF (SELECT count(*) FROM programacion.input_family_assessments WHERE run_id=v_run_id AND validator_outcome='PASS') <> 47 THEN
      RAISE EXCEPTION 'BLOCK_M78_R17_VALIDATOR_PARITY';
    END IF;
    IF NOT programacion.fn_input_readiness_run_is_current(v_run_id) THEN
      RAISE EXCEPTION 'BLOCK_M78_R17_CANDIDATE_RUN_NOT_CURRENT';
    END IF;

    RAISE EXCEPTION 'M78_R17_ROLLBACK_OK:screen=% run=%',v_target_screen,v_run_id;
  EXCEPTION WHEN OTHERS THEN
    v_err := SQLERRM;
    IF v_err LIKE 'M78_R17_ROLLBACK_OK:%' THEN
      v_rolled_back := true;
    ELSE
      RAISE;
    END IF;
  END;

  IF NOT v_rolled_back THEN
    RAISE EXCEPTION 'BLOCK_M78_R17_ROLLBACK_NOT_OBSERVED';
  END IF;
  IF md5(pg_get_functiondef(v_sig)) <> v_baseline_md5 THEN
    RAISE EXCEPTION 'BLOCK_M78_R17_FUNCTION_RESIDUE expected=% got=%',v_baseline_md5,md5(pg_get_functiondef(v_sig));
  END IF;
  IF EXISTS (
    SELECT 1 FROM programacion.input_readiness_runs
    WHERE curator_identity=v_curator_identity OR validator_identity=v_validator_identity
  ) THEN
    RAISE EXCEPTION 'BLOCK_M78_R17_RUN_RESIDUE';
  END IF;
END
$preflight$;
