-- M10.5 ONLY: prevent false PASS before post-cutover evidence exists.
-- CP1: replace inaccessible readback wrapper with authorized source-current function;
--      freeze 13-screen cohort using historical event 19622 plus explicitly evidenced 51;
--      execute a fresh source-current readback, record actual result, and close CP1 only.
-- CP4: consume real M8 timing metrics rather than the unrelated M7 suite.
-- CP5/CP6: replace inaccessible query and expose release provenance explicitly.
-- No runtime changes, permission grants, release promotion or production cutover.
DO $m105$
DECLARE
  v_plan CONSTANT text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
  v_unit CONSTANT text := 'M10.5';
  v_actor CONSTANT text := 'LF_IG_M105_PREFLIGHT_TRAIN_20261013';
  v_meta jsonb;
  v_scope jsonb;
  v_historical jsonb;
  v_old_action jsonb;
  v_q_as text;
  v_q_perf text;
  v_q_suite text;
  v_q_release text;
  v_q_terminal text;
  v_q_columns text;
  v_n integer;
  v_current integer;
  v_latest_count integer;
  v_boot jsonb;
  v_readiness jsonb;
  v_result jsonb;
BEGIN
  SELECT unit_metadata INTO STRICT v_meta
    FROM programacion.engineering_plan_units
   WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=477
   FOR UPDATE;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=477) <> 6
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=477 AND status IN ('DONE','NOT_APPLICABLE')) <> 0
  THEN RAISE EXCEPTION 'M105_PRESTATE_CHECKPOINT_DRIFT'; END IF;

  v_boot := programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
  IF v_boot->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
     OR v_boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'POST_CUTOVER_ASIS'
     OR v_boot#>>'{state,unmet_deps}' IS DISTINCT FROM '0'
  THEN RAISE EXCEPTION 'M105_PRESTATE_BOOTSTRAP_DRIFT'; END IF;

  SELECT payload#>'{finding_1,pantallas_por_contrato}'
    INTO STRICT v_historical
    FROM public.lf_eventos WHERE id=19622;
  IF jsonb_array_length(v_historical)<>12
     OR NOT EXISTS (
       SELECT 1 FROM public.lf_eventos
       WHERE id=19622 AND payload#>>'{finding_1,causa_clasificador}' LIKE 'pantalla 51 run %'
     )
  THEN RAISE EXCEPTION 'M105_SCOPE_HISTORICAL_EVIDENCE_DRIFT'; END IF;

  -- Frozen unit-specific scope, not a cross-product 13-screen rule.
  SELECT to_jsonb(array_agg(screen ORDER BY screen)) INTO v_scope
  FROM (
    SELECT jsonb_array_elements_text(v_historical)::integer AS screen
    UNION SELECT 51 AS screen
  ) s;
  IF jsonb_array_length(v_scope)<>13 THEN
    RAISE EXCEPTION 'M105_SCOPE_NOT_THIRTEEN'; END IF;

  v_meta:=jsonb_set(v_meta,'{m105_scope_v1}',
   jsonb_build_object(
     'schema_version','M105_SCOPE_SNAPSHOT_V1',
     'screen_ids',v_scope,
     'source_event_id',19622,
     'reason','12 pantallas en finding_1.pantallas_por_contrato mas pantalla 51 observada en finding_1.causa_clasificador',
     'scope_kind','UNIT_SPECIFIC_FROZEN_POST_CUTOVER_COHORT',
     'release_provenance','NOT_VERIFIED',
     'no_production_admission',true),true);

  v_q_as:=$query$
WITH cohort AS (
 SELECT jsonb_array_elements_text(unit_metadata#>'{m105_scope_v1,screen_ids}')::integer AS pantalla_id
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5'
), latest AS (
 SELECT c.pantalla_id,r.id AS run_id,r.created_at,r.status,r.contract_revision,r.scope,r.source_manifest
 FROM cohort c LEFT JOIN LATERAL (
  SELECT id,created_at,status,contract_revision,scope,source_manifest
  FROM programacion.input_readiness_runs WHERE pantalla_id=c.pantalla_id
  ORDER BY id DESC LIMIT 1
 ) r ON true
)
SELECT pantalla_id,run_id,created_at,status,contract_revision,
 CASE WHEN run_id IS NULL THEN false
      ELSE programacion.fn_input_run_is_source_current(run_id) END AS is_current,
 scope->>'release_id' AS scoped_release_id,
 source_manifest->>'release_id' AS manifest_release_id
FROM latest ORDER BY pantalla_id
$query$;

  v_q_columns:=$query$
SELECT column_name FROM information_schema.columns
 WHERE table_schema='programacion' AND table_name='input_readiness_runs'
 AND column_name IN ('release_id','scope','source_manifest','contract_revision','version_id')
 ORDER BY column_name
$query$;

  v_q_perf:=$query$
WITH metrics AS (
 SELECT scope,phase,sample_count,p95_ms,status
 FROM programacion.fn_ig_performance_timing_metrics_v1()
)
SELECT CASE WHEN count(*) FILTER (
 WHERE scope='SUMMARY' AND status='PUBLISHED' AND sample_count>0)>0
 AND count(*) FILTER (
 WHERE phase='VALIDATOR' AND status='MEASURED'
   AND sample_count>0 AND p95_ms<=150000)>0
 THEN 'PASS' ELSE 'FAIL' END AS verdict,
 max(sample_count) FILTER(WHERE scope='SUMMARY') AS total_receipts,
 max(p95_ms) FILTER(WHERE phase='VALIDATOR') AS validator_p95_ms
FROM metrics
$query$;

  -- M7 suite consumer: require real full evaluation, source/version/commit binding.
  -- The newest historically PASSED suite is a single checkpoint case, not M7 global.
  v_q_suite:=$query$
WITH qualified_suite AS (
 SELECT s.suite_run_id,s.status,s.commit_sha,s.tests_total,s.tests_passed,
        s.tests_failed,s.tests_blocked,s.metadata
 FROM public.lf_test_suite_runs s
 WHERE s.suite_code='INPUT_GOVERNANCE_REGRESSION'
   AND s.status='PASSED' AND s.commit_sha IS NOT NULL
   AND s.metadata->>'full_catalog_evaluated'='true'
 ORDER BY s.started_at DESC NULLS LAST LIMIT 1
), binding AS (
 SELECT version,previous_version,manifest_sha256
 FROM public.lf_capability_current
 WHERE capability_code='INPUT_GOVERNANCE'
)
SELECT CASE WHEN EXISTS(
 SELECT 1 FROM qualified_suite s CROSS JOIN binding b
 WHERE b.previous_version IS NOT NULL
   AND s.tests_total>0 AND s.tests_passed=s.tests_total
   AND s.tests_failed=0 AND s.tests_blocked=0
   AND s.metadata->>'source_manifest_sha256'=b.manifest_sha256
   AND s.metadata->>'source_version'=('INPUT_GOVERNANCE@'||b.version)
) THEN 'PASS' ELSE 'FAIL' END AS verdict,
coalesce((SELECT count(*) FROM qualified_suite),0) AS qualifying_suite_count,
(SELECT version FROM binding) AS current_version
$query$;

  v_q_release:=$query$
WITH cohort AS (
 SELECT jsonb_array_elements_text(unit_metadata#>'{m105_scope_v1,screen_ids}')::integer AS pantalla_id
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5'
), latest AS (
 SELECT c.pantalla_id,r.id AS run_id,r.status,r.scope,r.source_manifest
 FROM cohort c LEFT JOIN LATERAL (
  SELECT id,status,scope,source_manifest
  FROM programacion.input_readiness_runs WHERE pantalla_id=c.pantalla_id
  ORDER BY id DESC LIMIT 1
 ) r ON true
)
SELECT l.pantalla_id,l.run_id,l.status,
 CASE WHEN l.run_id IS NULL THEN false
      ELSE programacion.fn_input_run_is_source_current(l.run_id) END AS source_current,
 l.scope->>'release_id' AS scoped_release_id,
 l.source_manifest->>'release_id' AS manifest_release_id,
 c.version AS capability_current_version,c.manifest_sha256 AS capability_manifest_sha256
 FROM latest l CROSS JOIN public.lf_capability_current c
 WHERE c.capability_code='INPUT_GOVERNANCE'
 ORDER BY l.pantalla_id
$query$;

  -- CP6: terminal validator MUST reject absent vNext release provenance
  -- (current live snapshot is expected FAIL, not a synthetic PASS).
  v_q_terminal:=$query$
WITH cohort AS (
 SELECT jsonb_array_elements_text(unit_metadata#>'{m105_scope_v1,screen_ids}')::integer AS pantalla_id
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.5'
), latest AS (
 SELECT c.pantalla_id,r.id AS run_id,r.scope,r.source_manifest
 FROM cohort c LEFT JOIN LATERAL (
  SELECT id,scope,source_manifest FROM programacion.input_readiness_runs
  WHERE pantalla_id=c.pantalla_id ORDER BY id DESC LIMIT 1
 ) r ON true
), evidence AS (
 SELECT l.*,CASE WHEN l.run_id IS NULL THEN false
   ELSE programacion.fn_input_run_is_source_current(l.run_id) END AS source_current,
 p.version,p.previous_version
 FROM latest l CROSS JOIN public.lf_capability_current p
 WHERE p.capability_code='INPUT_GOVERNANCE'
)
SELECT CASE WHEN count(*)=13
 AND bool_and(source_current AND previous_version IS NOT NULL
   AND scope->>'release_id'=version AND source_manifest->>'release_id'=version)
 THEN 'PASS' ELSE 'FAIL' END AS verdict,
 count(*) AS screen_count,
 count(*) FILTER(WHERE source_current) AS source_current_count,
 count(*) FILTER(WHERE scope->>'release_id'=version
   AND source_manifest->>'release_id'=version) AS release_bound_count,
 max(version) AS bound_version,
 max(previous_version) AS prior_version
FROM evidence
$query$;

  -- CP1: make action and its authoritative source executable by this readonly connector.
  v_old_action:=coalesce(v_meta#>'{action_specs_v1,POST_CUTOVER_ASIS}','{}'::jsonb);
  IF v_old_action <> '{}'::jsonb THEN RAISE EXCEPTION 'M105_CP1_EXISTING_ACTION_DRIFT'; END IF;
  v_meta:=jsonb_set(v_meta,'{action_specs_v1,POST_CUTOVER_ASIS}',
    jsonb_build_object(
      'status','READY','schema_version','ENGINEERING_ACTION_SPEC_V3',
      'checkpoint_code','POST_CUTOVER_ASIS',
      'action_kind','READBACK_ONCE','recipe_mode','READBACK_EXACT',
      'contract_source','EXPLICIT_ACTION_SPEC',
      'requires_material_execution',false,'mutation_policy','NO_DOMAIN_MUTATION',
      'expected','Observe exact 13-screen latest-run source currentness AS-IS; no vNext PASS inference',
      'verification_queries',jsonb_build_array(v_q_as,v_q_columns),
      'target',jsonb_build_object('checkpoint','POST_CUTOVER_ASIS',
        'declared_objects',jsonb_build_array('programacion.input_readiness_runs','programacion.fn_input_run_is_source_current'),
        'declared_events',jsonb_build_array(19622)),
      'forbidden',jsonb_build_array('TREAT_LEGACY_CURRENT_AS_VNEXT','REQUIRE_PRODUCTION_CUTOVER_FOR_ASIS','INFER_RELEASE_FROM_CONTRACT_REVISION')),
      true);
  v_meta:=jsonb_set(v_meta,'{source_pack_v1,checkpoint_inputs,POST_CUTOVER_ASIS}',
    jsonb_build_object('inputs',
      jsonb_build_object('events',jsonb_build_array(19622),
        'assets','[]'::jsonb,'artifacts','[]'::jsonb,
        'db_objects',jsonb_build_array('programacion.input_readiness_runs','programacion.fn_input_run_is_source_current'),
        'queries',jsonb_build_array(v_q_as,v_q_columns)),
      'missing','[]'::jsonb,'missing_typed','[]'::jsonb),true);

  -- CP3: explicit M7 full-regression verifier; a scoped subcase or NULL SHA
  -- cannot qualify a 13-screen post-cutover suite.
  IF coalesce(v_meta#>'{action_specs_v1,SUITE_M7_GREEN}','{}'::jsonb)<>'{}'::jsonb
  THEN RAISE EXCEPTION 'M105_CP3_ACTION_DRIFT'; END IF;
  v_meta:=jsonb_set(v_meta,'{action_specs_v1,SUITE_M7_GREEN}',
    jsonb_build_object(
      'status','READY','schema_version','ENGINEERING_ACTION_SPEC_V3',
      'checkpoint_code','SUITE_M7_GREEN',
      'action_kind','READBACK_ONCE','recipe_mode','READBACK_EXACT',
      'requires_material_execution',false,'mutation_policy','NO_DOMAIN_MUTATION',
      'expected','Require full M7 global suite PASSED with exact current-release manifest SHA, version, nonnull Git commit, all assertions green',
      'verification_queries',jsonb_build_array(v_q_suite),
      'target',jsonb_build_object('checkpoint','SUITE_M7_GREEN',
         'declared_objects',jsonb_build_array('public.lf_test_suite_runs','public.lf_capability_current')),
      'forbidden',jsonb_build_array('SCOPED_SINGLE_CASE_COUNTS_AS_FULL_SUITE','NULL_COMMIT_SHA_COUNTS_AS_BOUND','HISTORICAL_RELEASE_COUNTS_AS_VNEXT')),true);
  v_meta:=jsonb_set(v_meta,'{source_pack_v1,checkpoint_inputs,SUITE_M7_GREEN}',
    jsonb_build_object('inputs',jsonb_build_object(
       'events','[]'::jsonb,'assets','[]'::jsonb,'artifacts','[]'::jsonb,
       'db_objects',jsonb_build_array('public.lf_test_suite_runs','public.lf_capability_current'),
       'queries',jsonb_build_array(v_q_suite)),
       'missing','[]'::jsonb,'missing_typed','[]'::jsonb),true);

  -- CP4: a suite PASS is not a performance metric. Compare published M8 p95
  -- to the stronger-than-p90 150000ms absolute Edge budget, with no relative gate inference.
  IF v_meta#>>'{action_specs_v1,PERF_M8_GREEN,action_kind}' <> 'READBACK_ONCE'
  THEN RAISE EXCEPTION 'M105_CP4_KIND_DRIFT'; END IF;
  v_meta:=jsonb_set(v_meta,'{action_specs_v1,PERF_M8_GREEN,verification_queries}',
    jsonb_build_array(v_q_perf),true);
  v_meta:=jsonb_set(v_meta,'{action_specs_v1,PERF_M8_GREEN,target,declared_objects}',
    jsonb_build_array('programacion.fn_ig_performance_timing_metrics_v1'),true);
  v_meta:=jsonb_set(v_meta,'{action_specs_v1,PERF_M8_GREEN,expected}',
    to_jsonb('Require SUMMARY=PUBLISHED, nonempty verified receipts, VALIDATOR p95_ms <= 150000; relative baseline M8.11 remains independently deferred; no live release claim'::text),true);
  v_meta:=jsonb_set(v_meta,'{source_pack_v1,checkpoint_inputs,PERF_M8_GREEN}',
    jsonb_build_object('inputs',jsonb_build_object(
      'events','[]'::jsonb,'assets','[]'::jsonb,'artifacts','[]'::jsonb,
      'db_objects',jsonb_build_array('programacion.fn_ig_performance_timing_metrics_v1'),
      'queries',jsonb_build_array(v_q_perf)),
      'missing','[]'::jsonb,'missing_typed','[]'::jsonb),true);

  -- CP5 remains material negative test; change only its readback source,
  -- not the assertion, result, or execution authorization.
  IF v_meta#>>'{action_specs_v1,NEG_STALE_RUN,action_kind}'
       <> 'BOUNDED_CHECKPOINT_TEST_AUTHORING'
  THEN RAISE EXCEPTION 'M105_CP5_KIND_DRIFT'; END IF;
  v_meta:=jsonb_set(v_meta,'{action_specs_v1,NEG_STALE_RUN,verification_queries}',
    jsonb_build_array(v_q_release),true);
  v_meta:=jsonb_set(v_meta,'{action_specs_v1,NEG_STALE_RUN,test_execution_contract,declared_queries}',
    jsonb_build_array(v_q_release),true);
  v_meta:=jsonb_set(v_meta,'{source_pack_v1,checkpoint_inputs,NEG_STALE_RUN,inputs,queries}',
    jsonb_build_array(v_q_release),true);

  -- Terminal must independently see 13/13 real provenance records, not just
  -- COMPLETED or an old source-current flag.
  v_meta:=jsonb_set(v_meta,'{action_specs_v1,E2E_READBACK}',
    jsonb_build_object(
      'status','READY','schema_version','ENGINEERING_ACTION_SPEC_V3',
      'checkpoint_code','E2E_READBACK',
      'action_kind','READBACK_ONCE','recipe_mode','READBACK_EXACT',
      'requires_material_execution',false,'mutation_policy','NO_DOMAIN_MUTATION',
      'expected','13/13 latest runs source-current and release vNext authenticated by release binding; never accept NULL release_id',
      'verification_queries',jsonb_build_array(v_q_terminal),
      'target',jsonb_build_object('checkpoint','E2E_READBACK',
         'declared_objects',jsonb_build_array('programacion.input_readiness_runs','public.lf_capability_current')),
      'forbidden',jsonb_build_array('NULL_RELEASE_ID_COUNTS_AS_VNEXT','CONTRACT_REVISION_COUNTS_AS_RELEASE','POST_CUTOVER_ASIS_COUNTS_AS_TERMINAL_PASS')),true);
  v_meta:=jsonb_set(v_meta,'{source_pack_v1,checkpoint_inputs,E2E_READBACK}',
    jsonb_build_object('inputs',jsonb_build_object(
       'events','[]'::jsonb,'assets','[]'::jsonb,'artifacts','[]'::jsonb,
       'db_objects',jsonb_build_array('programacion.input_readiness_runs','public.lf_capability_current'),
       'queries',jsonb_build_array(v_q_terminal)),
       'missing','[]'::jsonb,'missing_typed','[]'::jsonb),true);

  v_meta:=jsonb_set(v_meta,'{m105_preflight_v1}',jsonb_build_object(
     'status','PARTIAL_REPAIRED_NOT_CUTOVER',
     'positive_test','current-run sample true run 930',
     'negative_test','12 source-stale latest cohort runs',
     'cp2_producer','MISSING_VERIFIED_VNEXT_RELEASE_AND_EDGE_DISPATCH_RECEIPTS',
     'cp3_producer','LATEST_SUITE_PASS_IS_SCOPED_CASE_OR_NULL_COMMIT_SHA; CURRENT_RELEASE_FULL_SUITE_NOT_PROVEN',
     'cp4_producer','fn_ig_performance_timing_metrics_v1',
     'cp5_negative','PENDING_MATERIAL_EXECUTION',
     'cp6_terminal','MUST_ENFORCE_REAL_VNEXT_RUN_RELEASE_ID',
     'no_production_approval',true),true);

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=v_meta
   WHERE plan_code=v_plan AND unit_code=v_unit AND work_item_id=477;

  v_readiness:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,v_unit,'POST_CUTOVER_ASIS');
  IF v_readiness->>'status' IS DISTINCT FROM 'READY'
  THEN RAISE EXCEPTION 'M105_CP1_READINESS_FAILED:%',v_readiness; END IF;

  -- Fresh positive/negative observations over exactly the event-derived cohort.
  WITH cohort AS (
    SELECT jsonb_array_elements_text(v_scope)::integer AS pantalla_id
  ), latest AS (
    SELECT c.pantalla_id, r.id AS run_id
    FROM cohort c LEFT JOIN LATERAL (
      SELECT id FROM programacion.input_readiness_runs
       WHERE pantalla_id=c.pantalla_id ORDER BY id DESC LIMIT 1
    ) r ON true
  ), measured AS (
    SELECT run_id, CASE WHEN run_id IS NULL THEN false
          ELSE programacion.fn_input_run_is_source_current(run_id) END AS current
    FROM latest
  )
  SELECT count(*), count(*) FILTER(WHERE current), count(*) FILTER(WHERE NOT current)
  INTO v_n,v_current,v_latest_count FROM measured;

  IF v_n<>13 OR v_current + v_latest_count <> 13
  THEN RAISE EXCEPTION 'M105_CP1_COHORT_READBACK_INCOMPLETE'; END IF;
  IF v_current=13 THEN
    -- CP1 is an AS-IS observation and can record 13/13; no cutover inference.
    NULL;
  END IF;

  v_result:=programacion.fn_engineering_checkpoint_transition_v1(
     v_plan,v_unit,'POST_CUTOVER_ASIS','DONE',
     format('supabase://programacion.input_readiness_runs/M10.5#ASIS_SCOPE_EVENT_19622_CURRENT_%s_STALE_%s_TOTAL_13',v_current,v_latest_count),
     v_actor,
     format('Executed 13 currentness functions on latest runs; current=%s, stale=%s. release_id vNext NOT VERIFIED. CP4 metric source repaired; CP2/CP3/CP5/CP6 remain pending.',v_current,v_latest_count));
  IF v_result#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
  THEN RAISE EXCEPTION 'M105_CP1_TRANSITION_REJECTED:%',v_result; END IF;

  v_boot:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
  IF v_boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'NEW_RUNS_VNEXT'
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=477 AND status='DONE')<>1
  THEN RAISE EXCEPTION 'M105_AFTER_CP1_STATE_DRIFT'; END IF;
  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=477 AND checkpoint_code<>'POST_CUTOVER_ASIS'
         AND status<>'PENDING')<>0
  THEN RAISE EXCEPTION 'M105_UNAUTHORIZED_LATER_CHECKPOINT_TRANSITION'; END IF;
END $m105$;

-- This learning is new; public.lf_error_knowledge is a view of this canonical registry.
INSERT INTO transversal.error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,evidencia,
  source_ref,lote_origen,estado,lifecycle_phase,consumer_role)
SELECT
 'IG-M105-PREFLIGHT-RELEASE-PROVENANCE-AND-READBACK-001','INPUT_GOVERNANCE',
 'M10.5: ASIS currentness inaccessible and performance suite is wrong validator',
 'A readback-only checkpoint attempted a denied function; 13-screen historical scope was not explicit. M8 performance checkpoint read M7 suite rather than published timings. A suite PASSED with NULL commit SHA cannot prove release-bound regression. No authentic vNext release_id exists in 253 historical runs.',
 'Incoherent unit contract/source pack/validator and lack of post-cutover provenance producer; M10.2 sandbox completion was confused with real vNext execution readiness.',
 'For every checkpoint preflight bind source to callable authority, freeze exact producer-backed scope, check positive and stale negative, require release identity and Edge execution receipts, and use M8 timing receipt function for budget. Never infer vNext from contract revision or suite PASS without SHA.',
 'Train executes exact source readback of 13 latest runs; CP1 DONE only after current+stale count=13 and canonical transition; CP3 refuses scoped PASSED without manifest/commit; CP4 validates actual M8 metrics; CP2/3/5/6 remain PENDING without authentic receipts.',
 'supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5;supabase://public.lf_eventos/19622',
 'programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5',
 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5',
 'ACTIVO','CONTRACT_PREFLIGHT',ARRAY['Architect','Builder','Judge','Auditor']::text[]
WHERE NOT EXISTS (
 SELECT 1 FROM transversal.error_knowledge
 WHERE codigo='IG-M105-PREFLIGHT-RELEASE-PROVENANCE-AND-READBACK-001'
);