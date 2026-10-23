-- IG M10.13 CP3 MACRO LOTE: compare three existing cached chains versus
-- existing alternatives, four real input cases / 12 pairs. Bounded pilot.
-- NOT a functional rehome, NOT a performance approval, NOT checkpoint DONE.
-- Result is evidence in the existing M10.13 unit_metadata, no new runtime.
BEGIN;
DO $ig_m1013_cp3_macro$
DECLARE
  v_item constant bigint := 474;
  v_plan constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
  v_unit constant text := 'M10.13';
  v_name constant text := 'lf_ig_m1013_cp3_cached_rehome_macro_proof_v1';
  v_execution_id text;
  v_sig text;
  v_md5 text;
  v_expected record;
  v_case record;
  v_variant text;
  v_graph jsonb;
  v_left jsonb;
  v_right jsonb;
  v_left_error text;
  v_right_error text;
  v_graph_error text;
  v_start timestamptz;
  v_left_ms numeric;
  v_right_ms numeric;
  v_match boolean;
  v_results jsonb:='[]'::jsonb;
  v_case_out jsonb;
  v_graph_sha text;
  v_pre jsonb;
  v_verdict text;
  v_success integer:=0;
  v_equal integer:=0;
  v_error integer:=0;
  v_rows integer;
  v_readback jsonb;
  v_state jsonb;
BEGIN
  -- Real official execution is required; Train may reassign the 14-digit
  -- migration version, but cannot change suffix/PR/project/target path.
  SELECT e.execution_id INTO v_execution_id
  FROM public.lf_operation_execution e
  WHERE e.operation_code='ACTUALIZACION_DB_LF'
    AND e.target_type='MIGRATION'
    AND e.target_code ~ ('^[0-9]{14}_'||v_name||'$')
    AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
    AND e.target_path='supabase/migrations/'||e.target_code||'.sql'
    AND e.manifest->>'producer'='lf-migration-merge-train'
    AND e.manifest->>'pr'='3110'
    AND e.status='IN_PROGRESS'
  ORDER BY e.created_at DESC LIMIT 1;
  IF v_execution_id IS NULL THEN
    RAISE EXCEPTION 'IG_CP3_MACRO_OFFICIAL_EXECUTION_REQUIRED';
  END IF;

  IF (SELECT status FROM programacion.engineering_work_items WHERE id=v_item)
      IS DISTINCT FROM 'IN_PROGRESS'
    OR (SELECT status FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=v_item AND checkpoint_code='GIT_RUNTIME_PARITY')
      IS DISTINCT FROM 'DONE'
    OR (SELECT status FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=v_item AND checkpoint_code='ZERO_LEGACY_CALLERS')
      IS DISTINCT FROM 'PENDING'
    OR (SELECT raw_payload->>'members_sha256' FROM public.lf_activos WHERE id=289)
      IS DISTINCT FROM '124639d2ef4bd4d6d7af9739e12a523ecd309676c71f8d43215f30e240f05bf3'
    OR NOT EXISTS (
      SELECT 1 FROM public.lf_eventos WHERE id=20193
        AND jsonb_array_length(payload->'matrix')=147
    )
  THEN RAISE EXCEPTION 'IG_CP3_MACRO_CANONICAL_BASELINE_DRIFT'; END IF;

  -- Six exact current function definitions plus graph constructor.
  FOR v_expected IN
    SELECT * FROM (VALUES
      ('programacion.fn_input_governance_semantic_probe_v2_cached_v1(integer,text,bigint,jsonb)',
        '05d39a40acfbe0619b6c32253bf45d97'),
      ('programacion.fn_input_governance_semantic_probe_v2(integer,text,bigint)',
        'c2832adc0b4d9e510b83bf4e3e533256'),
      ('programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)',
        'ff726ab1c658769389b65c8479af84fb'),
      ('programacion.fn_input_governance_semantic_probe_v3_ctx(integer,text,bigint,jsonb)',
        '2eec94aaeafcd10ac38519d1ca0d53b0'),
      ('programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)',
        '7257b9bbc86b1f61e5435a37479d63a1'),
      ('programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)',
        'f991bf655a7b4f2a89d68138c6862012'),
      ('programacion.fn_input_screen_canonical_graph(integer,bigint)',
        'b107626672364dd5c832800b4f168f01')
    ) x(signature,body_md5)
  LOOP
    IF to_regprocedure(v_expected.signature) IS NULL
      OR (SELECT md5(p.prosrc) FROM pg_proc p
          WHERE p.oid=to_regprocedure(v_expected.signature))
         IS DISTINCT FROM v_expected.body_md5
    THEN RAISE EXCEPTION 'IG_CP3_MACRO_SOURCE_DRIFT:%',v_expected.signature; END IF;
  END LOOP;

  -- Security boundary: no physical retirement of this definer/PUBLIC function.
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid=to_regprocedure(
       'programacion.fn_input_run_semantic_revalidation_v1(bigint)')
      AND md5(p.prosrc)='44a7f21a3c01411662ab568af58c4091'
      AND p.prosecdef AND p.proacl IS NULL
  ) OR NOT has_function_privilege(
       'authenticated',
       'programacion.fn_input_run_semantic_revalidation_v1(bigint)','EXECUTE')
  THEN RAISE EXCEPTION 'IG_CP3_MACRO_EXTERNAL_API_BOUNDARY_DRIFT'; END IF;

  SELECT unit_metadata INTO STRICT v_pre
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit
    AND work_item_id=v_item AND disposition='ASSIGNED'
  FOR UPDATE;
  IF v_pre ? 'cp3_cached_rehome_macro_v1'
    OR v_pre#>>'{cp3_current_caller_classification_provenance_v1,total_sql_callers}'<>'21'
  THEN RAISE EXCEPTION 'IG_CP3_MACRO_METADATA_PRESTATE_DRIFT'; END IF;

  -- 4 bounded real cases, deliberately not a full 47-family or full-screen
  -- migration. Each graph is built ONCE per case and reused by cached paths.
  FOR v_case IN
    SELECT * FROM (VALUES
      (43,19::bigint,'ACTIONS'),
      (43,19::bigint,'ROUTING_NAVIGATION'),
      (2,19::bigint,'DESIGN_SYSTEM'),
      (2,19::bigint,'RESPONSIVE')
    ) x(screen_id,version_id,family_code)
  LOOP
    v_graph:=NULL;
    v_graph_error:=NULL;
    BEGIN
      v_graph:=programacion.fn_input_screen_canonical_graph(
        v_case.screen_id,v_case.version_id);
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_graph_error=MESSAGE_TEXT;
    END;
    v_graph_sha:=CASE WHEN v_graph IS NOT NULL
      THEN programacion.fn_v09_sha256_jsonb(v_graph) ELSE NULL END;

    FOREACH v_variant IN ARRAY ARRAY[
      'SEMANTIC_V2','SEMANTIC_V3','CLASSIFIER_V2'
    ] LOOP
      v_left:=NULL; v_right:=NULL;
      v_left_error:=NULL; v_right_error:=NULL;
      v_left_ms:=NULL; v_right_ms:=NULL;
      IF v_graph_error IS NOT NULL THEN
        v_left_error:='GRAPH_BUILD_FAILED:'||v_graph_error;
        v_right_error:=v_left_error;
      ELSE
        v_start:=clock_timestamp();
        BEGIN
          CASE v_variant
            WHEN 'SEMANTIC_V2' THEN
              v_left:=programacion.fn_input_governance_semantic_probe_v2_cached_v1(
                v_case.screen_id,v_case.family_code,v_case.version_id,v_graph);
            WHEN 'SEMANTIC_V3' THEN
              v_left:=programacion.fn_input_governance_semantic_probe_v3_cached_v1(
                v_case.screen_id,v_case.family_code,v_case.version_id,v_graph);
            WHEN 'CLASSIFIER_V2' THEN
              v_left:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(
                v_case.screen_id,v_case.family_code,v_case.version_id,v_graph);
          END CASE;
        EXCEPTION WHEN OTHERS THEN
          GET STACKED DIAGNOSTICS v_left_error=MESSAGE_TEXT;
        END;
        v_left_ms:=round((extract(epoch from clock_timestamp()-v_start)*1000)::numeric,3);

        v_start:=clock_timestamp();
        BEGIN
          CASE v_variant
            WHEN 'SEMANTIC_V2' THEN
              v_right:=programacion.fn_input_governance_semantic_probe_v2(
                v_case.screen_id,v_case.family_code,v_case.version_id);
            WHEN 'SEMANTIC_V3' THEN
              v_right:=programacion.fn_input_governance_semantic_probe_v3_ctx(
                v_case.screen_id,v_case.family_code,v_case.version_id,v_graph);
            WHEN 'CLASSIFIER_V2' THEN
              v_right:=programacion.fn_input_governance_bootstrap_classify_v2(
                v_case.screen_id,v_case.family_code,v_case.version_id);
          END CASE;
        EXCEPTION WHEN OTHERS THEN
          GET STACKED DIAGNOSTICS v_right_error=MESSAGE_TEXT;
        END;
        v_right_ms:=round((extract(epoch from clock_timestamp()-v_start)*1000)::numeric,3);
      END IF;

      v_match:=v_left_error IS NULL AND v_right_error IS NULL
        AND v_left IS NOT DISTINCT FROM v_right;
      IF v_left_error IS NULL AND v_right_error IS NULL THEN
        v_success:=v_success+1;
        IF v_match THEN v_equal:=v_equal+1; END IF;
        -- Negative oracle: mutation of either object must be visible.
        IF v_left IS NOT NULL
          AND jsonb_typeof(v_left)='object'
          AND v_left IS NOT DISTINCT FROM
             (v_left||jsonb_build_object('__ig_cp3_negative_mutation',true))
        THEN RAISE EXCEPTION 'IG_CP3_MACRO_NEGATIVE_ORACLE_FAILURE'; END IF;
      ELSE
        v_error:=v_error+1;
      END IF;

      v_case_out:=jsonb_build_object(
        'screen_id',v_case.screen_id,
        'version_id',v_case.version_id,
        'family',v_case.family_code,
        'variant',v_variant,
        'graph_sha256',v_graph_sha,
        'left_sha256',CASE WHEN v_left IS NULL THEN NULL
          ELSE programacion.fn_v09_sha256_jsonb(v_left) END,
        'right_sha256',CASE WHEN v_right IS NULL THEN NULL
          ELSE programacion.fn_v09_sha256_jsonb(v_right) END,
        'left_ms',v_left_ms,'right_ms',v_right_ms,
        'jsonb_exact_equal',v_match,
        'left_error',left(v_left_error,200),
        'right_error',left(v_right_error,200),
        'disposition',CASE
          WHEN v_left_error IS NOT NULL OR v_right_error IS NOT NULL
            THEN 'ERROR_BLOCK_REHOME'
          WHEN v_match THEN 'PILOT_ONLY_FURTHER_REGRESSION_REQUIRED'
          ELSE 'DIVERGENCE_BLOCK_REHOME' END
      );
      v_results:=v_results||jsonb_build_array(v_case_out);
    END LOOP;
  END LOOP;

  IF jsonb_array_length(v_results)<>12
    OR v_success+v_error<>12
  THEN RAISE EXCEPTION 'IG_CP3_MACRO_RESULTS_INCOMPLETE'; END IF;

  v_verdict:=CASE
    WHEN v_error>0 THEN 'ERRORS_REHOME_BLOCKED'
    WHEN v_equal<>12 THEN 'SEMANTIC_DIVERGENCE_REHOME_BLOCKED'
    ELSE 'PILOT_EQUIVALENT_FULL_REGRESSION_AND_PERFORMANCE_PENDING'
  END;
  v_state:=jsonb_build_object(
    'schema_version','ig-m1013-cp3-rehome-macro-observed/v1',
    'execution_id',v_execution_id,
    'expected_comparisons',12,'completed_comparisons',jsonb_array_length(v_results),
    'successful_pair_calls',v_success,'exact_equal_count',v_equal,'errored_cases',v_error,
    'screens_sampled',2,'families_sampled',4,'variant_pairs',3,
    'cases',v_results,
    'overall_verdict',v_verdict,
    'sufficient_for_rehome',false,
    'semantic_revalidation_public_execute_still_present',true,
    'external_consumer_absence_proven',false,
    'legacy_frozen_sources_preserved',true,
    'cp3_transition_authorized',false
  );

  UPDATE programacion.engineering_plan_units
  SET unit_metadata=jsonb_set(unit_metadata,
    '{cp3_cached_rehome_macro_v1}',v_state,true)
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_item
    AND disposition='ASSIGNED' AND unit_metadata=v_pre;
  GET DIAGNOSTICS v_rows=ROW_COUNT;
  IF v_rows<>1 THEN RAISE EXCEPTION 'IG_CP3_MACRO_NOT_ATOMIC'; END IF;

  SELECT unit_metadata->'cp3_cached_rehome_macro_v1'
  INTO STRICT v_readback
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit;
  IF v_readback IS DISTINCT FROM v_state
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_item AND checkpoint_code='ZERO_LEGACY_CALLERS')
         IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'IG_CP3_MACRO_READBACK_FAILED'; END IF;
END
$ig_m1013_cp3_macro$;
COMMIT;
