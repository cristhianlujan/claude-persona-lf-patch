-- IG M10.13 CP3: rehome the NON-FROZEN T-REMED status reader only.
-- Retain frozen history, T-REMED recommendations/promotions, rules and scope.
-- No DROP/REVOKE, no new engine, no historical rule reclassification.
BEGIN;
DO $ig_tremed_reader$
DECLARE
  v_ident constant text := 'programacion.fn_t_remed_screen_status_v1(integer)';
  v_old constant text := 'programacion.fn_input_governance_bootstrap_classify_v2_cached_v2';
  v_new constant text := 'programacion.fn_input_governance_bootstrap_classify_v2_ctx';
  v_function oid;
  v_old_sql text; v_old_body text; v_new_body text;
  v_acl aclitem[]; v_owner oid; v_definer boolean; v_vol "char";
  v_before jsonb; v_after jsonb; v_cached jsonb; v_ctx jsonb;
  v_case record; v_graph jsonb; v_time timestamptz;
  v_old_ms numeric:=0; v_new_ms numeric:=0; v_cases jsonb:='[]'::jsonb;
  v_freeze_total integer; v_freeze_drift integer; v_rows integer;
  v_meta jsonb; v_new_hash text;
BEGIN
  IF (SELECT status FROM programacion.engineering_work_items WHERE id=474)<>'IN_PROGRESS'
  OR (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS')<>'PENDING'
  THEN RAISE EXCEPTION 'IG_TREMED_CP3_STATE_DRIFT'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure(
     'programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)'))
       <> '7257b9bbc86b1f61e5435a37479d63a1'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure(
     'programacion.fn_input_governance_bootstrap_classify_v2_ctx(integer,text,bigint,jsonb)'))
       <> '11bd4af470dffc3d2ae8c1316774c1ba'
  THEN RAISE EXCEPTION 'IG_TREMED_CLASSIFIER_SOURCE_DRIFT'; END IF;

  v_function:=to_regprocedure(v_ident);
  SELECT p.prosrc,pg_get_functiondef(p.oid),p.proacl,p.proowner,p.prosecdef,p.provolatile
   INTO STRICT v_old_body,v_old_sql,v_acl,v_owner,v_definer,v_vol
   FROM pg_proc p WHERE p.oid=v_function;
  IF md5(v_old_body)<>'71e87f70953e741029d00d8aec0b6339'
   OR (length(v_old_body)-length(replace(v_old_body,v_old,'')))<>length(v_old)
  THEN RAISE EXCEPTION 'IG_TREMED_READER_SOURCE_DRIFT'; END IF;

  -- Bounded 6-case comparison against the same supplied canonical graph.
  FOR v_case IN SELECT * FROM (VALUES
    (43,19::bigint,'ACTIONS'),(43,19::bigint,'ROUTING_NAVIGATION'),
    (2,19::bigint,'DESIGN_SYSTEM'),(2,19::bigint,'RESPONSIVE'),
    (43,19::bigint,'FIELDS'),(2,19::bigint,'VALIDATIONS')
  ) x(screen_id,version_id,family_code)
  LOOP
    v_graph:=programacion.fn_input_screen_canonical_graph(v_case.screen_id,v_case.version_id);
    v_time:=clock_timestamp();
    v_cached:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(
      v_case.screen_id,v_case.family_code,v_case.version_id,v_graph);
    v_old_ms:=v_old_ms+round((extract(epoch FROM clock_timestamp()-v_time)*1000)::numeric,3);
    v_time:=clock_timestamp();
    v_ctx:=programacion.fn_input_governance_bootstrap_classify_v2_ctx(
      v_case.screen_id,v_case.family_code,v_case.version_id,v_graph);
    v_new_ms:=v_new_ms+round((extract(epoch FROM clock_timestamp()-v_time)*1000)::numeric,3);
    IF v_cached IS DISTINCT FROM v_ctx
      THEN RAISE EXCEPTION 'IG_TREMED_CLASSIFIER_PARITY_FAIL:%',v_case.family_code;
    END IF;
    v_cases:=v_cases||jsonb_build_array(jsonb_build_object(
      'screen',v_case.screen_id,'family',v_case.family_code,'equal',true));
  END LOOP;
  IF jsonb_array_length(v_cases)<>6 OR v_new_ms>v_old_ms*2.5+200
   THEN RAISE EXCEPTION 'IG_TREMED_CLASSIFIER_PERF_OR_CASE_DRIFT:old=% new=%',
      v_old_ms,v_new_ms; END IF;

  -- One end-to-end diagnostic readback, no recommendation or rule write.
  SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.family_code),'[]'::jsonb)
  INTO v_before FROM programacion.fn_t_remed_screen_status_v1(43) t;
  v_new_body:=replace(v_old_body,v_old,v_new);
  EXECUTE replace(v_old_sql,v_old,v_new);
  SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.family_code),'[]'::jsonb)
  INTO v_after FROM programacion.fn_t_remed_screen_status_v1(43) t;
  IF v_before IS DISTINCT FROM v_after
     THEN RAISE EXCEPTION 'IG_TREMED_STATUS_OUTPUT_CHANGED'; END IF;

  SELECT md5(p.prosrc) INTO STRICT v_new_hash FROM pg_proc p WHERE p.oid=v_function;
  IF v_new_hash<>md5(v_new_body) OR NOT EXISTS (
    SELECT 1 FROM pg_proc p WHERE p.oid=v_function
      AND p.proacl IS NOT DISTINCT FROM v_acl
      AND p.proowner=v_owner AND p.prosecdef=v_definer AND p.provolatile=v_vol
  ) THEN RAISE EXCEPTION 'IG_TREMED_READER_POSTCHECK_FAIL'; END IF;

  -- The 26 frozen functions must remain identical to their stored baseline.
  WITH frozen AS (
    SELECT x.value->>'identity' identity,x.value->>'prosrc_md5' expected
    FROM programacion.engineering_plan_units u
    CROSS JOIN LATERAL jsonb_array_elements(
      u.unit_metadata#>'{m104_freeze_baseline_v1,legacy_functions}') x
    WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.4'
  ), live AS (
    SELECT f.expected,md5(p.prosrc) actual FROM frozen f LEFT JOIN LATERAL (
      SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname||'.'||p.proname||'('||
        pg_get_function_identity_arguments(p.oid)||')'=f.identity
    ) p ON true
  ) SELECT count(*),count(*) FILTER(WHERE expected IS DISTINCT FROM actual)
    INTO v_freeze_total,v_freeze_drift FROM live;
  IF v_freeze_total<>26 OR v_freeze_drift<>0
     THEN RAISE EXCEPTION 'IG_TREMED_FROZEN_SOURCE_DRIFT'; END IF;

  SELECT unit_metadata INTO STRICT v_meta FROM programacion.engineering_plan_units
   WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.13'
    AND work_item_id=474 FOR UPDATE;
  IF v_meta?'cp3_tremed_status_reader_rehome_v1'
     THEN RAISE EXCEPTION 'IG_TREMED_RECEIPT_ALREADY_EXISTS'; END IF;
  UPDATE programacion.engineering_plan_units SET unit_metadata=jsonb_set(
    unit_metadata,'{cp3_tremed_status_reader_rehome_v1}',jsonb_build_object(
      'consumer','programacion.fn_t_remed_screen_status_v1(integer)',
      'previous_hash',md5(v_old_body),'current_hash',v_new_hash,
      'changed_caller_edges',1,'paired_classifier_results',v_cases,
      'classifier_comparison_count',6,'baseline_ms',v_old_ms,'candidate_ms',v_new_ms,
      'tremed_screen_status_parity',true,'status_rows',jsonb_array_length(v_after),
      'frozen_function_count',v_freeze_total,'frozen_drift',v_freeze_drift,
      'legacy_zero',false,'cp3_complete',false,
      'promotions_modified',false,'scope_rules_modified',false),true)
   WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.13'
     AND work_item_id=474 AND unit_metadata=v_meta;
  GET DIAGNOSTICS v_rows=ROW_COUNT;
  IF v_rows<>1 OR (SELECT status FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS')<>'PENDING'
  THEN RAISE EXCEPTION 'IG_TREMED_FALSE_CLOSURE'; END IF;
END
$ig_tremed_reader$;
COMMIT;
