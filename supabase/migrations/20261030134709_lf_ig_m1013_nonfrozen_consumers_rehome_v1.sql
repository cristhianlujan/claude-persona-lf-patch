-- IG M10.13 CP3: rehome three NON-FROZEN consumers only.
-- The 26 historical M10.4 function sources remain immutable.
-- No new API, DROP, REVOKE, 47-family recuration, or checkpoint closure.
BEGIN;
DO $ig_m1013_nonfrozen$
DECLARE
  v_old text := 'programacion.fn_input_governance_bootstrap_classify_v2_cached_v2';
  v_new text := 'programacion.fn_input_governance_bootstrap_classify_v2_ctx';
  v_consumer record;
  v_fn oid; v_src text; v_ddl text; v_new_source text;
  v_acl aclitem[]; v_owner oid; v_secdef boolean; v_vol "char";
  v_old_ms numeric := 0; v_new_ms numeric := 0;
  v_start timestamptz; v_old_output jsonb; v_new_output jsonb;
  v_case record; v_graph jsonb; v_samples jsonb := '[]'::jsonb;
  v_updates jsonb := '[]'::jsonb; v_total integer := 0;
  v_frozen integer; v_drift integer; v_meta jsonb; v_rows integer;
BEGIN
  IF (SELECT status FROM programacion.engineering_work_items WHERE id=474)<>'IN_PROGRESS'
  OR (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS')<>'PENDING'
  THEN RAISE EXCEPTION 'IG_NONFROZEN_CP3_STATE_DRIFT'; END IF;

  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=to_regprocedure(
       'programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(integer,text,bigint,jsonb)'))
      <> '7257b9bbc86b1f61e5435a37479d63a1'
     OR (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=to_regprocedure(
       'programacion.fn_input_governance_bootstrap_classify_v2_ctx(integer,text,bigint,jsonb)'))
      <> '11bd4af470dffc3d2ae8c1316774c1ba'
  THEN RAISE EXCEPTION 'IG_NONFROZEN_CLASSIFIER_SOURCE_DRIFT'; END IF;

  -- A bounded existing pilot (6 real cases), measured BEFORE any mutation.
  FOR v_case IN SELECT * FROM (VALUES
    (43,19::bigint,'ACTIONS'),(43,19::bigint,'ROUTING_NAVIGATION'),
    (2,19::bigint,'DESIGN_SYSTEM'),(2,19::bigint,'RESPONSIVE'),
    (43,19::bigint,'FIELDS'),(2,19::bigint,'VALIDATIONS')
  ) x(screen_id,version_id,family_code)
  LOOP
    v_graph:=programacion.fn_input_screen_canonical_graph(v_case.screen_id,v_case.version_id);
    v_start:=clock_timestamp();
    v_old_output:=programacion.fn_input_governance_bootstrap_classify_v2_cached_v2(
      v_case.screen_id,v_case.family_code,v_case.version_id,v_graph);
    v_old_ms:=v_old_ms + round((extract(epoch FROM clock_timestamp()-v_start)*1000)::numeric,3);
    v_start:=clock_timestamp();
    v_new_output:=programacion.fn_input_governance_bootstrap_classify_v2_ctx(
      v_case.screen_id,v_case.family_code,v_case.version_id,v_graph);
    v_new_ms:=v_new_ms + round((extract(epoch FROM clock_timestamp()-v_start)*1000)::numeric,3);
    IF v_old_output IS DISTINCT FROM v_new_output
    THEN RAISE EXCEPTION 'IG_NONFROZEN_SEMANTIC_DRIFT:%:%',
      v_case.screen_id,v_case.family_code; END IF;
    v_samples:=v_samples||jsonb_build_array(jsonb_build_object(
      'screen_id',v_case.screen_id,'family',v_case.family_code,'equal',true));
  END LOOP;
  IF jsonb_array_length(v_samples)<>6 OR v_new_ms>v_old_ms*2.5+200
  THEN RAISE EXCEPTION 'IG_NONFROZEN_PERFORMANCE_OR_COVERAGE_REGRESSION old=% new=%',
    v_old_ms,v_new_ms; END IF;

  -- Only these three non-frozen current consumers, each has ONE callsite.
  FOR v_consumer IN SELECT * FROM (VALUES
    ('fn_input_governance_bootstrap_classify_v2_cached_v1',
      'integer,text,bigint,jsonb','5b0012dd443674ec0a94fe18ef0792e9'),
    ('fn_input_governance_recurate_v2',
      'integer,text,text','a6aea69926e51e6e208636946f6dce94'),
    ('fn_input_governance_recurate_source_stale_v1',
      'integer,text,text,bigint','0b9449ee5fe6867262702d5a05be7dfc')
  ) x(fn,args,expected_md5)
  LOOP
    v_fn:=to_regprocedure('programacion.'||v_consumer.fn||'('||v_consumer.args||')');
    IF v_fn IS NULL THEN RAISE EXCEPTION 'IG_NONFROZEN_CONSUMER_MISSING:%',v_consumer.fn; END IF;

    -- Strict: no historical frozen source may be changed.
    IF EXISTS (
      SELECT 1 FROM programacion.engineering_plan_units u
      CROSS JOIN LATERAL jsonb_array_elements(
        u.unit_metadata#>'{m104_freeze_baseline_v1,legacy_functions}') z
      WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.4'
        AND z.value->>'identity'=(
          SELECT n.nspname||'.'||p.proname||'('||
            pg_get_function_identity_arguments(p.oid)||')'
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.oid=v_fn)
    ) THEN RAISE EXCEPTION 'IG_NONFROZEN_FROZEN_TARGET:%',v_consumer.fn; END IF;

    SELECT p.prosrc,pg_get_functiondef(p.oid),p.proacl,p.proowner,p.prosecdef,p.provolatile
      INTO STRICT v_src,v_ddl,v_acl,v_owner,v_secdef,v_vol
    FROM pg_proc p WHERE p.oid=v_fn;
    IF md5(v_src)<>v_consumer.expected_md5 OR
       length(v_src)-length(replace(v_src,v_old,''))<>length(v_old)
    THEN RAISE EXCEPTION 'IG_NONFROZEN_CONSUMER_SOURCE_DRIFT:%',v_consumer.fn; END IF;
    v_new_source:=replace(v_src,v_old,v_new);
    EXECUTE replace(v_ddl,v_old,v_new);
    IF NOT EXISTS(
      SELECT 1 FROM pg_proc p WHERE p.oid=v_fn
       AND md5(p.prosrc)=md5(v_new_source)
       AND p.proacl IS NOT DISTINCT FROM v_acl
       AND p.proowner=v_owner AND p.prosecdef=v_secdef AND p.provolatile=v_vol
    ) THEN RAISE EXCEPTION 'IG_NONFROZEN_CONSUMER_POSTCHECK:%',v_consumer.fn; END IF;
    v_updates:=v_updates||jsonb_build_array(jsonb_build_object(
      'function',v_consumer.fn,'pre_md5',v_consumer.expected_md5,
      'post_md5',md5(v_new_source),'changed_calls',1));
    v_total:=v_total+1;
  END LOOP;
  IF v_total<>3 THEN RAISE EXCEPTION 'IG_NONFROZEN_UPDATE_CARDINALITY'; END IF;

  WITH frozen AS(
    SELECT z.value->>'identity' ident,z.value->>'prosrc_md5' expected
    FROM programacion.engineering_plan_units u
    CROSS JOIN LATERAL jsonb_array_elements(u.unit_metadata#>'{m104_freeze_baseline_v1,legacy_functions}') z
    WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M10.4'
  ), live AS(
    SELECT f.expected,md5(p.prosrc) actual FROM frozen f LEFT JOIN LATERAL (
      SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname||'.'||p.proname||'('||
        pg_get_function_identity_arguments(p.oid)||')'=f.ident
    ) p ON true
  )
  SELECT count(*),count(*) FILTER(WHERE expected IS DISTINCT FROM actual)
   INTO v_frozen,v_drift FROM live;
  IF v_frozen<>26 OR v_drift<>0
  THEN RAISE EXCEPTION 'IG_NONFROZEN_M104_FROZEN_DRIFT'; END IF;

  SELECT unit_metadata INTO STRICT v_meta FROM programacion.engineering_plan_units
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.13'
    AND work_item_id=474 FOR UPDATE;
  IF v_meta?'cp3_nonfrozen_consumer_rehome_v1'
  THEN RAISE EXCEPTION 'IG_NONFROZEN_DUPLICATE_EVIDENCE'; END IF;
  UPDATE programacion.engineering_plan_units
  SET unit_metadata=jsonb_set(unit_metadata,'{cp3_nonfrozen_consumer_rehome_v1}',
    jsonb_build_object('source','live pg_proc','consumers_changed',v_total,
      'changed_consumers',v_updates,'test_cases',v_samples,
      'exact_equal_cases',6,'legacy_ms',v_old_ms,'alternative_ms',v_new_ms,
      'frozen_functions_checked',v_frozen,'frozen_drifts',v_drift,
      'external_consumers_proven_absent',false,'legacy_closed',false,
      'checkpoint_closed',false,'full_47_family_regression_executed',false),true)
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.13'
    AND work_item_id=474 AND unit_metadata=v_meta;
  GET DIAGNOSTICS v_rows=ROW_COUNT;
  IF v_rows<>1 OR
   (SELECT status FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS')<>'PENDING'
  THEN RAISE EXCEPTION 'IG_NONFROZEN_FALSE_CLOSURE'; END IF;
END
$ig_m1013_nonfrozen$;
COMMIT;
