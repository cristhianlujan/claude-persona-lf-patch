-- IG M10.13 CP3: broader representative cached-vs-alternative regression
-- plus fresh runtime external-boundary readback. Observational evidence only.
-- NO DROP/REVOKE/runtime mutation/Router mutation/checkpoint transition/rehome.
-- Candidate source remains DRAFT while ACT-0001 scope semantics guard is blocked.
BEGIN;
DO $ig_m1013_cp3_rep$
DECLARE
  v_item constant bigint := 474;
  v_plan constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
  v_unit constant text := 'M10.13';
  v_name constant text := 'lf_ig_m1013_cp3_representative_regression_external_boundary_v1';
  v_execution_id text;
  v_expected record;
  v_case record;
  v_variant text;
  v_family text;
  v_graph jsonb;
  v_graph_error text;
  v_graph_sha text;
  v_left jsonb;
  v_right jsonb;
  v_left_error text;
  v_right_error text;
  v_start timestamptz;
  v_left_ms numeric;
  v_right_ms numeric;
  v_match boolean;
  v_results jsonb := '[]'::jsonb;
  v_case_out jsonb;
  v_pre jsonb;
  v_state jsonb;
  v_readback jsonb;
  v_perf jsonb := '{}'::jsonb;
  v_success integer := 0;
  v_equal integer := 0;
  v_error integer := 0;
  v_rows integer;
  v_sql_callers integer;
  v_view_refs integer;
  v_matview_refs integer;
  v_anon_exec boolean;
  v_auth_exec boolean;
  v_anon_schema boolean;
  v_auth_schema boolean;
  v_service_schema boolean;
  v_api_direct_blocked boolean;
BEGIN
  -- Official effect may only occur inside the Merge Train execution for PR #3126.
  SELECT e.execution_id INTO v_execution_id
  FROM public.lf_operation_execution e
  WHERE e.operation_code='ACTUALIZACION_DB_LF'
    AND e.target_type='MIGRATION'
    AND e.target_code ~ ('^[0-9]{14}_'||v_name||'$')
    AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
    AND e.target_path='supabase/migrations/'||e.target_code||'.sql'
    AND e.manifest->>'producer'='lf-migration-merge-train'
    AND e.manifest->>'pr'='3126'
    AND e.status='IN_PROGRESS'
  ORDER BY e.created_at DESC LIMIT 1;
  IF v_execution_id IS NULL THEN
    RAISE EXCEPTION 'IG_CP3_REP_OFFICIAL_EXECUTION_REQUIRED';
  END IF;

  IF (SELECT status FROM programacion.engineering_work_items WHERE id=v_item)
       IS DISTINCT FROM 'IN_PROGRESS'
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_item AND checkpoint_code='GIT_RUNTIME_PARITY')
       IS DISTINCT FROM 'DONE'
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_item AND checkpoint_code='ZERO_LEGACY_CALLERS')
       IS DISTINCT FROM 'PENDING'
  THEN
    RAISE EXCEPTION 'IG_CP3_REP_CANONICAL_STATE_DRIFT';
  END IF;

  -- Exact current definitions observed after the #3110 pilot.
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
       'b107626672364dd5c832800b4f168f01'),
      ('programacion.fn_input_run_semantic_revalidation_v1(bigint)',
       '44a7f21a3c01411662ab568af58c4091')
    ) x(signature,body_md5)
  LOOP
    IF to_regprocedure(v_expected.signature) IS NULL
       OR (SELECT md5(p.prosrc) FROM pg_proc p
           WHERE p.oid=to_regprocedure(v_expected.signature))
          IS DISTINCT FROM v_expected.body_md5
    THEN
      RAISE EXCEPTION 'IG_CP3_REP_SOURCE_DRIFT:%',v_expected.signature;
    END IF;
  END LOOP;

  SELECT unit_metadata INTO STRICT v_pre
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit
    AND work_item_id=v_item AND disposition='ASSIGNED'
  FOR UPDATE;

  IF NOT (v_pre ? 'cp3_cached_rehome_macro_v1')
     OR v_pre#>>'{cp3_cached_rehome_macro_v1,expected_comparisons}' <> '12'
     OR v_pre#>>'{cp3_cached_rehome_macro_v1,exact_equal_count}' <> '12'
     OR v_pre#>>'{cp3_cached_rehome_macro_v1,errored_cases}' <> '0'
     OR v_pre ? 'cp3_representative_regression_external_boundary_v1'
  THEN
    RAISE EXCEPTION 'IG_CP3_REP_METADATA_PRESTATE_DRIFT';
  END IF;

  -- Fresh runtime consumer boundary for the candidate historical function.
  SELECT count(*) INTO v_sql_callers
  FROM pg_proc p
  WHERE p.oid <> to_regprocedure(
          'programacion.fn_input_run_semantic_revalidation_v1(bigint)')
    AND p.prosrc ILIKE '%fn_input_run_semantic_revalidation_v1%';

  SELECT count(*) INTO v_view_refs
  FROM pg_views
  WHERE definition ILIKE '%fn_input_run_semantic_revalidation_v1%';

  SELECT count(*) INTO v_matview_refs
  FROM pg_matviews
  WHERE definition ILIKE '%fn_input_run_semantic_revalidation_v1%';

  v_anon_exec := has_function_privilege(
    'anon','programacion.fn_input_run_semantic_revalidation_v1(bigint)','EXECUTE');
  v_auth_exec := has_function_privilege(
    'authenticated','programacion.fn_input_run_semantic_revalidation_v1(bigint)','EXECUTE');
  v_anon_schema := has_schema_privilege('anon','programacion','USAGE');
  v_auth_schema := has_schema_privilege('authenticated','programacion','USAGE');
  v_service_schema := has_schema_privilege('service_role','programacion','USAGE');
  v_api_direct_blocked := NOT v_anon_schema AND NOT v_auth_schema;

  -- 7 representative screens, two cohort-relevant families each.
  -- Graph is built ONCE per screen and reused across both families/three variants.
  FOR v_case IN
    SELECT * FROM (VALUES
      ('AUTH',51,19::bigint,ARRAY['MFA_OTP_SSO','SECURITY']::text[]),
      ('FORMS',57,19::bigint,ARRAY['FIELDS','VALIDATIONS']::text[]),
      ('NAVIGATION',4,19::bigint,ARRAY['ROUTING_NAVIGATION','ACTIONS']::text[]),
      ('DESIGN',62,19::bigint,ARRAY['DESIGN_SYSTEM','RESPONSIVE']::text[]),
      ('ONBOARDING',1,19::bigint,ARRAY['ACTIONS','FIELDS']::text[]),
      ('RECOVERY',58,19::bigint,ARRAY['SECURITY','ROUTING_NAVIGATION']::text[]),
      ('API',2,19::bigint,ARRAY['API_DATA_CONTRACT','ERRORS']::text[])
    ) x(cohort_type,screen_id,version_id,families)
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM programacion.v_input_governance_representative_cohort_v1 c
      WHERE c.cohort_type_code=v_case.cohort_type
        AND c.pantalla_id=v_case.screen_id
    ) THEN
      RAISE EXCEPTION 'IG_CP3_REP_COHORT_DRIFT:%:%',
        v_case.cohort_type,v_case.screen_id;
    END IF;

    v_graph:=NULL;
    v_graph_error:=NULL;
    BEGIN
      v_graph:=programacion.fn_input_screen_canonical_graph(
        v_case.screen_id,v_case.version_id);
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_graph_error=MESSAGE_TEXT;
    END;
    v_graph_sha:=CASE WHEN v_graph IS NULL THEN NULL
      ELSE programacion.fn_v09_sha256_jsonb(v_graph) END;

    FOREACH v_family IN ARRAY v_case.families LOOP
      IF NOT EXISTS (
        SELECT 1
        FROM programacion.input_family_assessments a
        JOIN programacion.input_readiness_runs r ON r.id=a.run_id
        WHERE r.pantalla_id=v_case.screen_id
          AND r.version_id=v_case.version_id
          AND a.family_code=v_family
      ) THEN
        RAISE EXCEPTION 'IG_CP3_REP_FAMILY_CASE_MISSING:%:%',
          v_case.screen_id,v_family;
      END IF;

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
                  v_case.screen_id,v_family,v_case.version_id,v_graph);
              WHEN 'SEMANTIC_V3' THEN
                v_left:=programacion.fn_input_governance_semantic_probe_v3_cached_v1(
                  v_case.screen_id,v_family,v_case.version_id,v_graph);
              WHEN 'CLASSIFIER_V2' THEN
                v_left:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(
                  v_case.screen_id,v_family,v_case.version_id,v_graph);
            END CASE;
          EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_left_error=MESSAGE_TEXT;
          END;
          v_left_ms:=round(
            (extract(epoch from clock_timestamp()-v_start)*1000)::numeric,3);

          v_start:=clock_timestamp();
          BEGIN
            CASE v_variant
              WHEN 'SEMANTIC_V2' THEN
                v_right:=programacion.fn_input_governance_semantic_probe_v2(
                  v_case.screen_id,v_family,v_case.version_id);
              WHEN 'SEMANTIC_V3' THEN
                v_right:=programacion.fn_input_governance_semantic_probe_v3_ctx(
                  v_case.screen_id,v_family,v_case.version_id,v_graph);
              WHEN 'CLASSIFIER_V2' THEN
                v_right:=programacion.fn_input_governance_bootstrap_classify_v2(
                  v_case.screen_id,v_family,v_case.version_id);
            END CASE;
          EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_right_error=MESSAGE_TEXT;
          END;
          v_right_ms:=round(
            (extract(epoch from clock_timestamp()-v_start)*1000)::numeric,3);
        END IF;

        v_match:=v_left_error IS NULL AND v_right_error IS NULL
          AND v_left IS NOT DISTINCT FROM v_right;

        IF v_left_error IS NULL AND v_right_error IS NULL THEN
          v_success:=v_success+1;
          IF v_match THEN v_equal:=v_equal+1; END IF;
          IF v_left IS NOT NULL
             AND jsonb_typeof(v_left)='object'
             AND v_left IS NOT DISTINCT FROM
                 (v_left||jsonb_build_object('__ig_cp3_negative_mutation',true))
          THEN
            RAISE EXCEPTION 'IG_CP3_REP_NEGATIVE_ORACLE_FAILURE';
          END IF;
        ELSE
          v_error:=v_error+1;
        END IF;

        v_case_out:=jsonb_build_object(
          'cohort',v_case.cohort_type,
          'screen_id',v_case.screen_id,
          'version_id',v_case.version_id,
          'family',v_family,
          'variant',v_variant,
          'graph_sha256',v_graph_sha,
          'cached_sha256',CASE WHEN v_left IS NULL THEN NULL
            ELSE programacion.fn_v09_sha256_jsonb(v_left) END,
          'alternative_sha256',CASE WHEN v_right IS NULL THEN NULL
            ELSE programacion.fn_v09_sha256_jsonb(v_right) END,
          'cached_ms',v_left_ms,
          'alternative_ms',v_right_ms,
          'jsonb_exact_equal',v_match,
          'cached_error',left(v_left_error,200),
          'alternative_error',left(v_right_error,200),
          'disposition',CASE
            WHEN v_left_error IS NOT NULL OR v_right_error IS NOT NULL
              THEN 'ERROR_NO_REHOME_AUTHORITY'
            WHEN v_match THEN 'REPRESENTATIVE_EQUAL_NO_REHOME_AUTHORITY'
            ELSE 'DIVERGENCE_BLOCK_REHOME' END
        );
        v_results:=v_results||jsonb_build_array(v_case_out);
      END LOOP;
    END LOOP;
  END LOOP;

  IF jsonb_array_length(v_results)<>42
     OR v_success+v_error<>42
  THEN
    RAISE EXCEPTION 'IG_CP3_REP_RESULTS_INCOMPLETE:%:%:%',
      jsonb_array_length(v_results),v_success,v_error;
  END IF;

  SELECT coalesce(jsonb_object_agg(s.variant,s.payload),'{}'::jsonb)
  INTO v_perf
  FROM (
    SELECT r.variant,
      jsonb_build_object(
        'pairs',count(*),
        'cached_total_ms',round(sum(r.cached_ms),3),
        'alternative_total_ms',round(sum(r.alternative_ms),3),
        'cached_faster_count',count(*) FILTER (
          WHERE r.cached_ms IS NOT NULL AND r.alternative_ms IS NOT NULL
            AND r.cached_ms<r.alternative_ms),
        'alternative_faster_count',count(*) FILTER (
          WHERE r.cached_ms IS NOT NULL AND r.alternative_ms IS NOT NULL
            AND r.alternative_ms<r.cached_ms),
        'exact_equal_count',count(*) FILTER (WHERE r.jsonb_exact_equal)
      ) AS payload
    FROM jsonb_to_recordset(v_results) AS r(
      variant text,
      cached_ms numeric,
      alternative_ms numeric,
      jsonb_exact_equal boolean
    )
    GROUP BY r.variant
  ) s;

  v_state:=jsonb_build_object(
    'schema_version','ig-m1013-cp3-representative-regression-external-boundary/v1',
    'execution_id',v_execution_id,
    'evidence_source',
      'sandbox/lf_contract_gate_test/transversal_assets/asset_retirement_governance/evidence/ig_m1013_cp3_representative_regression_external_boundary_20261023.json',
    'expected_comparisons',42,
    'completed_comparisons',jsonb_array_length(v_results),
    'successful_pair_calls',v_success,
    'exact_equal_count',v_equal,
    'errored_cases',v_error,
    'screens_sampled',7,
    'family_cases',14,
    'variant_pairs',3,
    'graph_policy','BUILD_ONCE_PER_SCREEN_AND_REUSE',
    'cases',v_results,
    'performance_summary',v_perf,
    'semantic_revalidation_boundary',jsonb_build_object(
      'signature','programacion.fn_input_run_semantic_revalidation_v1(bigint)',
      'sql_callers',v_sql_callers,
      'view_refs',v_view_refs,
      'matview_refs',v_matview_refs,
      'anon_execute',v_anon_exec,
      'authenticated_execute',v_auth_exec,
      'anon_schema_usage_programacion',v_anon_schema,
      'authenticated_schema_usage_programacion',v_auth_schema,
      'service_role_schema_usage_programacion',v_service_schema,
      'public_api_client_direct_invocation_blocked_by_schema_usage',
        v_api_direct_blocked,
      'open_pr_diff_audit_count_at_source',100,
      'open_pr_exact_semantic_revalidation_refs_at_source',0,
      'open_pr_audit_apply_time_currentness_proven',false,
      'external_consumer_absence_proven',false
    ),
    'open_pr_cleanup',jsonb_build_array(
      jsonb_build_object(
        'pr',1930,
        'status','CLOSED_2026-10-23',
        'disposition','DUPLICATE_STALE_SUPERSEDED_BY_MAIN',
        'main_source','supabase/migrations/20261007193445_ig_m5_4_remove_legacy_resolver_calls.sql'),
      jsonb_build_object(
        'pr',1922,
        'status','CLOSED_2026-10-23',
        'disposition','DUPLICATE_STALE_SUPERSEDED_BY_MAIN',
        'main_source','supabase/migrations/20261007194445_ig_m5_5_explicit_fingerprint.sql'),
      jsonb_build_object(
        'pr',1484,
        'status','OPEN',
        'disposition','CACHED_ALLOWED_CANDIDATE_NOT_FORBIDDEN_LEGACY_REEVALUATE_SEPARATELY')
    ),
    'overall_verdict',CASE
      WHEN v_error>0 THEN 'REPRESENTATIVE_ERRORS_NO_REHOME_AUTHORITY'
      WHEN v_equal<>42 THEN 'REPRESENTATIVE_DIVERGENCE_BLOCK_REHOME'
      ELSE 'REPRESENTATIVE_EQUIVALENT_PERFORMANCE_OBSERVED_NO_REHOME_AUTHORITY'
    END,
    'retention_recommendation',
      'KEEP_CURRENT_CACHED_PATHS_UNTIL_FULL_REGRESSION_AND_CONSUMER_CLOSURE',
    'sufficient_for_rehome',false,
    'zero_legacy_callers_proven',false,
    'legacy_frozen_sources_preserved',true,
    'cp3_transition_authorized',false
  );

  UPDATE programacion.engineering_plan_units
  SET unit_metadata=jsonb_set(
    unit_metadata,
    '{cp3_representative_regression_external_boundary_v1}',
    v_state,true)
  WHERE plan_code=v_plan
    AND unit_code=v_unit
    AND work_item_id=v_item
    AND disposition='ASSIGNED'
    AND unit_metadata=v_pre;
  GET DIAGNOSTICS v_rows=ROW_COUNT;
  IF v_rows<>1 THEN
    RAISE EXCEPTION 'IG_CP3_REP_NOT_ATOMIC';
  END IF;

  SELECT unit_metadata->'cp3_representative_regression_external_boundary_v1'
  INTO STRICT v_readback
  FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=v_item;

  IF v_readback IS DISTINCT FROM v_state
     OR (SELECT status FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_item AND checkpoint_code='ZERO_LEGACY_CALLERS')
        IS DISTINCT FROM 'PENDING'
  THEN
    RAISE EXCEPTION 'IG_CP3_REP_READBACK_FAILED';
  END IF;
END
$ig_m1013_cp3_rep$;
COMMIT;
