-- LF IG M10.13 CP3 / lot 2. SOURCE-FIRST deterministic transform of exact pg_proc revision.
-- Governed only by ACTUALIZACION_DB_LF + DB_WRITE_TRANSPORT + LF Migration Merge Train PR #3789.
-- Source hashes frozen at creation: v3ctx 60465360, frozen v1 dc6dca92, v2 05d39a40, field b4fe5f85.
-- The source texts are fully pinned below; the migration does NOT alter any frozen M10.4 function.
-- All SQL effects (3 ACTIVE graph-aware overloads, 1 ACTIVE callsite + audit event) are atomic.
BEGIN;
SET LOCAL lock_timeout='2000ms';
SET LOCAL statement_timeout='150000ms';
DO $ig_cp3_rehome$
DECLARE
 v_op text; v_ddl text; v_run record; a record; v_graph jsonb;
 v_old_sem jsonb; v_new_sem jsonb; v_old_field jsonb; v_new_field jsonb;
 v_sem integer:=0; v_field integer:=0; v_count integer:=0;
 v_start timestamptz; v_old_ms numeric:=0; v_new_ms numeric:=0;
 v_payload jsonb; v_event_id bigint;
BEGIN
 SELECT e.execution_id INTO v_op
 FROM public.lf_operation_execution e
 WHERE e.operation_code='ACTUALIZACION_DB_LF'
   AND e.target_type='MIGRATION'
   AND e.target_code ~ '^[0-9]{14}_lf_ig_m1013_cp3_curator_semantic_field_rehome_v1$'
   AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
   AND e.target_path='supabase/migrations/'||e.target_code||'.sql'
   AND e.manifest->>'producer'='lf-migration-merge-train'
   AND e.manifest->>'pr'='3789'
   AND e.status='IN_PROGRESS'
 ORDER BY e.created_at DESC LIMIT 1;
 IF v_op IS NULL THEN RAISE EXCEPTION 'IG_CP3_GOVERNED_OPERATION_NOT_ADMITTED'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS') IS DISTINCT FROM 'PENDING'
 THEN RAISE EXCEPTION 'IG_CP3_STATE_DRIFT'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_proc p
     WHERE p.oid='programacion.fn_input_governance_semantic_probe_v3_ctx(integer,text,bigint,jsonb)'::regprocedure)
       IS DISTINCT FROM '60465360cf3b0a4eced2fd7b424d5041'
 OR (SELECT md5(p.prosrc) FROM pg_proc p
     WHERE p.oid='programacion.fn_input_governance_semantic_probe_v2_cached_v1(integer,text,bigint,jsonb)'::regprocedure)
       IS DISTINCT FROM '05d39a40acfbe0619b6c32253bf45d97'
 OR (SELECT md5(p.prosrc) FROM pg_proc p
     WHERE p.oid='programacion.fn_input_governance_semantic_probe_v1_cached_v1(integer,text,bigint,jsonb)'::regprocedure)
       IS DISTINCT FROM 'dc6dca92f3a5f877415985fa7cba4027'
 OR (SELECT md5(p.prosrc) FROM pg_proc p
     WHERE p.oid='programacion.fn_input_governance_field_reference_probe_v1_cached_v1(integer,text,bigint,jsonb)'::regprocedure)
       IS DISTINCT FROM 'b4fe5f8581c12596fd9e2a1642269099'
 THEN RAISE EXCEPTION 'IG_CP3_SOURCE_FINGERPRINT_DRIFT'; END IF;
 IF to_regprocedure('programacion.fn_input_governance_semantic_probe_v1(integer,text,bigint,jsonb)') IS NOT NULL
 OR to_regprocedure('programacion.fn_input_governance_semantic_probe_v2(integer,text,bigint,jsonb)') IS NOT NULL
 OR to_regprocedure('programacion.fn_input_governance_field_reference_probe_v1(integer,text,bigint,jsonb)') IS NOT NULL
 THEN RAISE EXCEPTION 'IG_CP3_OVERLOAD_ALREADY_EXISTS'; END IF;
 IF (SELECT count(*) FROM programacion.input_family_assessments WHERE run_id=951)<>47
 OR programacion.fn_input_run_is_source_current(951) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'IG_CP3_REFERENCE_RUN951_STALE'; END IF;

 -- Exact frozen function source is pinned to a hash before deterministic transformation.
 -- Create overload of ACTIVE/current v1; source body unchanged.
 SELECT replace(pg_get_functiondef(
  'programacion.fn_input_governance_semantic_probe_v1_cached_v1(integer,text,bigint,jsonb)'::regprocedure),
  'programacion.fn_input_governance_semantic_probe_v1_cached_v1(',
  'programacion.fn_input_governance_semantic_probe_v1(') INTO v_ddl;
 EXECUTE v_ddl;

 -- ACTIVE/current v2 overload invokes ACTIVE/current v1 overload, never frozen v1.
 SELECT replace(replace(pg_get_functiondef(
  'programacion.fn_input_governance_semantic_probe_v2_cached_v1(integer,text,bigint,jsonb)'::regprocedure),
  'programacion.fn_input_governance_semantic_probe_v2_cached_v1(',
  'programacion.fn_input_governance_semantic_probe_v2('),
  'programacion.fn_input_governance_semantic_probe_v1_cached_v1(',
  'programacion.fn_input_governance_semantic_probe_v1(') INTO v_ddl;
 EXECUTE v_ddl;

 SELECT replace(pg_get_functiondef(
  'programacion.fn_input_governance_field_reference_probe_v1_cached_v1(integer,text,bigint,jsonb)'::regprocedure),
  'programacion.fn_input_governance_field_reference_probe_v1_cached_v1(',
  'programacion.fn_input_governance_field_reference_probe_v1(') INTO v_ddl;
 EXECUTE v_ddl;

 IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=
   'programacion.fn_input_governance_semantic_probe_v1(integer,text,bigint,jsonb)'::regprocedure)
   IS DISTINCT FROM 'dc6dca92f3a5f877415985fa7cba4027'
 OR (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=
   'programacion.fn_input_governance_field_reference_probe_v1(integer,text,bigint,jsonb)'::regprocedure)
   IS DISTINCT FROM 'b4fe5f8581c12596fd9e2a1642269099'
 THEN RAISE EXCEPTION 'IG_CP3_ACTIVE_OVERLOAD_BODY_NOT_IDENTICAL'; END IF;
 EXECUTE 'REVOKE ALL ON FUNCTION programacion.fn_input_governance_semantic_probe_v1(integer,text,bigint,jsonb) FROM PUBLIC,anon,authenticated';
 EXECUTE 'REVOKE ALL ON FUNCTION programacion.fn_input_governance_semantic_probe_v2(integer,text,bigint,jsonb) FROM PUBLIC,anon,authenticated';
 EXECUTE 'REVOKE ALL ON FUNCTION programacion.fn_input_governance_field_reference_probe_v1(integer,text,bigint,jsonb) FROM PUBLIC,anon,authenticated';
 EXECUTE 'GRANT EXECUTE ON FUNCTION programacion.fn_input_governance_semantic_probe_v1(integer,text,bigint,jsonb) TO service_role';
 EXECUTE 'GRANT EXECUTE ON FUNCTION programacion.fn_input_governance_semantic_probe_v2(integer,text,bigint,jsonb) TO service_role';
 EXECUTE 'GRANT EXECUTE ON FUNCTION programacion.fn_input_governance_field_reference_probe_v1(integer,text,bigint,jsonb) TO service_role';

 SELECT pantalla_id,version_id INTO STRICT v_run
 FROM programacion.input_readiness_runs WHERE id=951;
 v_graph:=programacion.fn_input_screen_canonical_graph(v_run.pantalla_id,v_run.version_id);
 FOR a IN SELECT family_code FROM programacion.input_family_assessments
   WHERE run_id=951 ORDER BY family_code
 LOOP
  v_start:=clock_timestamp();
  v_old_sem:=programacion.fn_input_governance_semantic_probe_v2_cached_v1(
    v_run.pantalla_id,a.family_code,v_run.version_id,v_graph);
  v_old_field:=programacion.fn_input_governance_field_reference_probe_v1_cached_v1(
    v_run.pantalla_id,a.family_code,v_run.version_id,v_graph);
  v_old_ms:=v_old_ms+extract(epoch from(clock_timestamp()-v_start))*1000;
  v_start:=clock_timestamp();
  v_new_sem:=programacion.fn_input_governance_semantic_probe_v2(
    v_run.pantalla_id,a.family_code,v_run.version_id,v_graph);
  v_new_field:=programacion.fn_input_governance_field_reference_probe_v1(
    v_run.pantalla_id,a.family_code,v_run.version_id,v_graph);
  v_new_ms:=v_new_ms+extract(epoch from(clock_timestamp()-v_start))*1000;
  v_count:=v_count+1;
  IF v_old_sem IS NOT DISTINCT FROM v_new_sem THEN v_sem:=v_sem+1; END IF;
  IF v_old_field IS NOT DISTINCT FROM v_new_field THEN v_field:=v_field+1; END IF;
 END LOOP;
 IF v_count<>47 OR v_sem<>47 OR v_field<>47 THEN
   RAISE EXCEPTION 'IG_CP3_94_PARITY_FAILED:count=%,sem=%,field=%',v_count,v_sem,v_field;
 END IF;
 IF v_new_ms>greatest(v_old_ms*3,v_old_ms+150) THEN
  RAISE EXCEPTION 'IG_CP3_PARITY_PERFORMANCE_REGRESSION:old_ms=%,new_ms=%',round(v_old_ms,3),round(v_new_ms,3);
 END IF;

 -- Only after exact behavioral equivalence, mutate existing ACTIVE Curator caller.
 SELECT replace(replace(pg_get_functiondef(
 'programacion.fn_input_governance_semantic_probe_v3_ctx(integer,text,bigint,jsonb)'::regprocedure),
 'programacion.fn_input_governance_semantic_probe_v2_cached_v1(',
 'programacion.fn_input_governance_semantic_probe_v2('),
 'programacion.fn_input_governance_field_reference_probe_v1_cached_v1(',
 'programacion.fn_input_governance_field_reference_probe_v1(') INTO v_ddl;
 EXECUTE v_ddl;

 IF EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=
   'programacion.fn_input_governance_semantic_probe_v3_ctx(integer,text,bigint,jsonb)'::regprocedure
   AND (p.prosrc LIKE '%fn_input_governance_semantic_probe_v2_cached_v1(%'
     OR p.prosrc LIKE '%fn_input_governance_field_reference_probe_v1_cached_v1(%'))
 OR EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=
   'programacion.fn_input_governance_semantic_probe_v2(integer,text,bigint,jsonb)'::regprocedure
   AND p.prosrc LIKE '%fn_input_governance_semantic_probe_v1_cached_v1(%')
 THEN RAISE EXCEPTION 'IG_CP3_FROZEN_EDGE_NOT_REMOVED'; END IF;
 IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid IN(
    'programacion.fn_input_governance_semantic_probe_v1(integer,text,bigint,jsonb)'::regprocedure,
    'programacion.fn_input_governance_semantic_probe_v2(integer,text,bigint,jsonb)'::regprocedure,
    'programacion.fn_input_governance_field_reference_probe_v1(integer,text,bigint,jsonb)'::regprocedure)
    AND (has_function_privilege('anon',p.oid,'EXECUTE')
      OR has_function_privilege('authenticated',p.oid,'EXECUTE')
      OR NOT has_function_privilege('service_role',p.oid,'EXECUTE')))
 THEN RAISE EXCEPTION 'IG_CP3_NEW_OVERLOAD_ACL_VIOLATION'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=
  'programacion.fn_input_governance_semantic_probe_v2_cached_v1(integer,text,bigint,jsonb)'::regprocedure)
  IS DISTINCT FROM '05d39a40acfbe0619b6c32253bf45d97'
 OR (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=
  'programacion.fn_input_governance_semantic_probe_v1_cached_v1(integer,text,bigint,jsonb)'::regprocedure)
  IS DISTINCT FROM 'dc6dca92f3a5f877415985fa7cba4027'
 OR (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=
  'programacion.fn_input_governance_field_reference_probe_v1_cached_v1(integer,text,bigint,jsonb)'::regprocedure)
  IS DISTINCT FROM 'b4fe5f8581c12596fd9e2a1642269099'
 THEN RAISE EXCEPTION 'IG_CP3_M104_FROZEN_SOURCE_MUTATION'; END IF;
 v_payload:=jsonb_build_object(
   'evidence_schema_version','operational-event/v2',
   'execution_id',v_op,'producer','LF_MIGRATION_TRAIN_IG_CP3_CURATOR_SEMANTIC_FIELD',
   'purpose','Rehome two live Curator frozen dependencies using active graph-aware functions with exact parity',
   'acceptance_declared',false,'occurred_at',clock_timestamp(),
   'family_count',v_count,'semantic_equal_pairs',v_sem,'field_equal_pairs',v_field,
   'old_total_ms',round(v_old_ms,3),'new_total_ms',round(v_new_ms,3),
   'production_code_mutation','CURRENT_CURATOR_CALLSITE_REHOMED',
   'checkpoint_code','ZERO_LEGACY_CALLERS','checkpoint_pass',false,
   'semantic_independence_credited',false);
 IF private.fn_lf_event_acceptance_signal_v2('ARTIFACT_RECONCILED',
   'IG_M1013_CP3_SEMANTIC_FIELD_REHOME_V1',
   'Curator dependencies rehomed; CP3 remains PENDING',v_payload) IS NOT NULL
 THEN RAISE EXCEPTION 'IG_CP3_FALSE_ACCEPTANCE_SIGNAL'; END IF;
 INSERT INTO public.lf_eventos(
  evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,created_by_execution_id,payload)
 VALUES ('ARTIFACT_RECONCILED','PROGRAM_PLAN',
  'IG_M1013_CP3_SEMANTIC_FIELD_REHOME_V1',
  'Curator dependencies rehomed; CP3 remains PENDING',
  'INFO','DERIVE_FROM_EXECUTION_ID',v_op,v_payload)
 RETURNING id INTO v_event_id;
 IF NOT EXISTS(SELECT 1 FROM public.lf_eventos WHERE id=v_event_id
  AND payload->>'semantic_equal_pairs'='47'
  AND payload->>'field_equal_pairs'='47'
  AND payload->>'checkpoint_pass'='false')
 THEN RAISE EXCEPTION 'IG_CP3_EVIDENCE_READBACK_FAILED'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=474 AND checkpoint_code='ZERO_LEGACY_CALLERS') IS DISTINCT FROM 'PENDING'
 THEN RAISE EXCEPTION 'IG_CP3_PREMATURE_CHECKPOINT_CLOSURE'; END IF;
END;
$ig_cp3_rehome$;
COMMIT;
