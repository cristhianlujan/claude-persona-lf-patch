-- LF IG M10.13 CP3: remove an active SQL consumer from frozen M10.4 currentness wrapper.
-- Governed through existing ACTUALIZACION_DB_LF/DB_WRITE_TRANSPORT/LF Migration Merge Train PR #3790.
-- Existing frozen wrapper is a direct delegate to fn_input_run_is_source_current, with no transformations.
-- No new function, Router, profile or evidence writer. Does not close CP3.
BEGIN;
SET LOCAL lock_timeout='2000ms';
SET LOCAL statement_timeout='30000ms';
DO $lf_ig_cp3_gold_b$
DECLARE
 v_exec text;
 v_source text;
 v_post text;
 v_definition text;
 v_original_call constant text:='programacion.fn_input_readiness_run_is_current_cached_v2(p_run_id)';
 v_rehome_call constant text:='programacion.fn_input_run_is_source_current(p_run_id)';
 v_uses integer;
 v_run record;
 v_old boolean;
 v_new boolean;
 v_pairs int:=0;
 v_payload jsonb;
 v_event_id bigint;
BEGIN
 SELECT e.execution_id INTO v_exec
 FROM public.lf_operation_execution e
 WHERE e.operation_code='ACTUALIZACION_DB_LF'
  AND e.target_type='MIGRATION'
  AND e.target_code ~ '^[0-9]{14}_lf_ig_m1013_cp3_gold_b_currentness_rehome_v1$'
  AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
  AND e.target_path='supabase/migrations/'||e.target_code||'.sql'
  AND e.manifest->>'producer'='lf-migration-merge-train'
  AND e.manifest->>'pr'='3790'
  AND e.status='IN_PROGRESS'
 ORDER BY e.created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'IG_CP3_GOLDB_GOVERNED_TRAIN_REQUIRED'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS') IS DISTINCT FROM 'PENDING'
 THEN RAISE EXCEPTION 'IG_CP3_GOLDB_CHECKPOINT_DRIFT'; END IF;

 SELECT p.prosrc INTO STRICT v_source
 FROM pg_proc p WHERE p.oid=
  'programacion.fn_input_gov_gold_b_prepare_review_v1(bigint,text,jsonb)'::regprocedure;
 IF md5(v_source) IS DISTINCT FROM '212ebc254d8a1f3a0bffb7724f246f08'
 OR (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=
  'programacion.fn_input_readiness_run_is_current_cached_v2(bigint)'::regprocedure)
    IS DISTINCT FROM '99d54f5dcc27617831b0eb6098000777'
 OR (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=
  'programacion.fn_input_run_is_source_current(bigint)'::regprocedure)
    IS DISTINCT FROM '2da27107c85d593ca54068658c3cc7d4'
 THEN RAISE EXCEPTION 'IG_CP3_GOLDB_SOURCE_PIN_DRIFT'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=
  'programacion.fn_input_readiness_run_is_current_cached_v2(bigint)'::regprocedure)
  IS DISTINCT FROM
  (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=
    'programacion.fn_input_readiness_run_is_current_cached_v1(bigint)'::regprocedure)
 THEN RAISE EXCEPTION 'IG_CP3_GOLDB_WRAPPER_PARITY_NOT_DIRECT'; END IF;
 v_uses:=(length(v_source)-length(replace(v_source,v_original_call,'')))/length(v_original_call);
 IF v_uses<>1 THEN RAISE EXCEPTION 'IG_CP3_GOLDB_CALLSITE_COUNT:%',v_uses; END IF;

 -- Pair parity across true/current, false/stale, false/missing branches.
 FOR v_run IN SELECT id,expected FROM (VALUES
   (951::bigint,true),(944::bigint,true),(949::bigint,false),
   (9223372036854775807::bigint,false)) AS cases(id,expected)
 LOOP
  v_old:=programacion.fn_input_readiness_run_is_current_cached_v2(v_run.id);
  v_new:=programacion.fn_input_run_is_source_current(v_run.id);
  IF v_old IS DISTINCT FROM v_new OR v_new IS DISTINCT FROM v_run.expected
  THEN RAISE EXCEPTION 'IG_CP3_GOLDB_FUNCTIONAL_DIVERGENCE:run_id=%',v_run.id; END IF;
  v_pairs:=v_pairs+1;
 END LOOP;
 IF v_pairs<>4 THEN RAISE EXCEPTION 'IG_CP3_GOLDB_PARITY_UNDERCOUNT'; END IF;

 SELECT replace(pg_get_functiondef(
   'programacion.fn_input_gov_gold_b_prepare_review_v1(bigint,text,jsonb)'::regprocedure),
   v_original_call,v_rehome_call) INTO v_definition;
 EXECUTE v_definition;
 SELECT p.prosrc INTO STRICT v_post FROM pg_proc p WHERE p.oid=
   'programacion.fn_input_gov_gold_b_prepare_review_v1(bigint,text,jsonb)'::regprocedure;
 IF v_post IS DISTINCT FROM replace(v_source,v_original_call,v_rehome_call)
 OR v_post LIKE '%fn_input_readiness_run_is_current_cached_v2(%'
 OR v_post NOT LIKE '%fn_input_run_is_source_current(%'
 THEN RAISE EXCEPTION 'IG_CP3_GOLDB_CURRENT_CALLSITE_NOT_REHOMED'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=
  'programacion.fn_input_readiness_run_is_current_cached_v2(bigint)'::regprocedure)
 IS DISTINCT FROM '99d54f5dcc27617831b0eb6098000777'
 THEN RAISE EXCEPTION 'IG_CP3_GOLDB_FROZEN_M104_CHANGED'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS') IS DISTINCT FROM 'PENDING'
 THEN RAISE EXCEPTION 'IG_CP3_GOLDB_FALSE_CHECKPOINT_TRANSITION'; END IF;

 v_payload:=jsonb_build_object(
  'evidence_schema_version','operational-event/v2',
  'execution_id',v_exec,
  'producer','LF_MIGRATION_TRAIN_IG_CP3_GOLD_B_CURRENTNESS',
  'purpose','Disconnect one nonfrozen Gold B currentness caller from M10.4 using same canonical function',
  'acceptance_declared',false,
  'occurred_at',clock_timestamp(),
  'paired_runs',v_pairs,
  'matching_currentness_cases',v_pairs,
  'changed_function','programacion.fn_input_gov_gold_b_prepare_review_v1(bigint,text,jsonb)',
  'replacement_call','programacion.fn_input_run_is_source_current(bigint)',
  'frozen_source_unchanged',true,
  'checkpoint_code','ZERO_LEGACY_CALLERS',
  'checkpoint_pass',false,
  'semantic_independence_credited',false,
  'production_code_mutation','CURRENT_GOLD_B_CALLSITE_REHOMED');
 IF private.fn_lf_event_acceptance_signal_v2(
  'ARTIFACT_RECONCILED','IG_M1013_CP3_GOLD_B_CURRENTNESS_REHOME_V1',
  'Gold B currentness legacy call disconnected; CP3 remains pending',v_payload) IS NOT NULL
 THEN RAISE EXCEPTION 'IG_CP3_GOLDB_FALSE_ACCEPTANCE_SIGNAL'; END IF;
 INSERT INTO public.lf_eventos(
  evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,
  created_by_execution_id,payload)
 VALUES('ARTIFACT_RECONCILED','PROGRAM_PLAN',
  'IG_M1013_CP3_GOLD_B_CURRENTNESS_REHOME_V1',
  'Gold B currentness legacy call disconnected; CP3 remains pending',
  'INFO','DERIVE_FROM_EXECUTION_ID',v_exec,v_payload)
 RETURNING id INTO v_event_id;
 IF NOT EXISTS(SELECT 1 FROM public.lf_eventos WHERE id=v_event_id
  AND payload->>'paired_runs'='4'
  AND payload->>'checkpoint_pass'='false'
  AND payload->>'acceptance_declared'='false')
 THEN RAISE EXCEPTION 'IG_CP3_GOLDB_EVIDENCE_READBACK_FAILED'; END IF;
END;
$lf_ig_cp3_gold_b$;
COMMIT;
