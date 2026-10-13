-- M10.4 CP1 FROZEN_SET_ASIS — exact live legacy-only fingerprint; non-destructive.
-- Historical classification is used ONLY to nominate legacy freeze identities.
-- Do not infer safe retirement or liveness from LEGACY_UNREFERENCED.
-- EKB: IG-EKB-READ-WITHOUT-SEMANTIC-PREFLIGHT-001,
-- IG-M1011-HISTORICAL-UNREFERENCED-LIVE-SQL-CALLER-001,
-- IG-M100-GIT-HEAD-DOES-NOT-FREEZE-DB-COMPONENTS-001.
BEGIN;
DO $m104$
DECLARE
 v_plan constant text := 'IG_CURATOR_VALIDATOR_REFACTOR_V2';
 v_cp constant text := 'FROZEN_SET_ASIS';
 v_expected_source_md5 constant text := '76131fb54294aea7cb98eb0a299abee8';
 v_total integer;
 v_matched integer;
 v_unique integer;
 v_edge_legacy integer;
 v_edge_active integer;
 v_manifest jsonb;
 v_excluded_edges jsonb;
 v_digest text;
 v_metadata jsonb;
 v_state jsonb;
 v_ready jsonb;
 v_out jsonb;
 v_evidence text;
BEGIN
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=476) NOT IN ('BACKLOG','IN_PROGRESS')
 THEN RAISE EXCEPTION 'M104_CP1_UNEXPECTED_WORK_STATUS'; END IF;
 v_state:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,'M10.4');
 IF v_state->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT'
    OR v_state#>>'{current_checkpoint,checkpoint_code}'<>v_cp
 THEN RAISE EXCEPTION 'M104_CP1_WRONG_CURRENT_CHECKPOINT'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=199)<>'DONE'
 THEN RAISE EXCEPTION 'M104_CP1_M102_DEPENDENCY_NOT_DONE'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM public.lf_eventos e
   WHERE e.id=20193 AND e.entidad_codigo='IG_CURATOR_VALIDATOR_REFACTOR_V2.M10.10.PAULO-160'
     AND e.payload->>'classification_only'='true'
 )
 THEN RAISE EXCEPTION 'M104_CP1_CLASSIFICATION_SOURCE_MISSING'; END IF;

 WITH source_rows AS (
   SELECT m->>'item_identity' AS identity,m->>'class' AS legacy_class
   FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'matrix') m
   WHERE e.id=20193 AND m->>'class' IN ('LEGACY_REFERENCED','LEGACY_UNREFERENCED')
     AND m->>'item_type'='FUNCTION'
 ), live AS (
   SELECT s.identity,s.legacy_class,x.oid,x.md5_source
   FROM source_rows s
   LEFT JOIN LATERAL (
     SELECT p.oid,md5(p.prosrc) md5_source
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname=split_part(split_part(s.identity,'(',1),'.',1)
       AND p.proname=split_part(split_part(s.identity,'(',1),'.',2)
       AND n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'=s.identity
   ) x ON true
 )
 SELECT count(*),count(*) FILTER(WHERE oid IS NOT NULL),count(DISTINCT oid),
   coalesce(jsonb_agg(jsonb_build_object(
      'identity',identity,'historical_class',legacy_class,'prosrc_md5',md5_source
   ) ORDER BY identity),'[]'::jsonb),
   md5(string_agg(identity||':'||coalesce(md5_source,'MISSING'),'|' ORDER BY identity))
 INTO v_total,v_matched,v_unique,v_manifest,v_digest
 FROM live;
 SELECT
   count(*) FILTER (WHERE m->>'class' IN ('LEGACY_REFERENCED','LEGACY_UNREFERENCED') AND m->>'item_type'='EDGE'),
   count(*) FILTER (WHERE m->>'class'='ACTIVE_VNEXT' AND m->>'item_type'='EDGE'),
   coalesce(jsonb_agg(m->>'item_identity' ORDER BY m->>'item_identity')
     FILTER (WHERE m->>'class'='ACTIVE_VNEXT' AND m->>'item_type'='EDGE'),'[]'::jsonb)
 INTO v_edge_legacy,v_edge_active,v_excluded_edges
 FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->'matrix') m
 WHERE e.id=20193;

 IF v_total=0 OR v_total<>v_matched OR v_unique<>v_total
    OR v_digest<>v_expected_source_md5
 THEN RAISE EXCEPTION 'M104_CP1_IDENTITY_OR_FINGERPRINT_DRIFT total:% resolved:% unique:% md5:%',
      v_total,v_matched,v_unique,v_digest; END IF;
 IF v_edge_legacy<>0 OR v_edge_active<>3
 THEN RAISE EXCEPTION 'M104_CP1_EDGE_SCOPE_CONTRADICTION legacy:% vnext:%',v_edge_legacy,v_edge_active; END IF;
 -- Negative probe: a naïve Edge-by-prefix freeze would wrongly capture ACTIVE_VNEXT.
 IF NOT (v_edge_active>0 AND v_edge_legacy=0)
 THEN RAISE EXCEPTION 'M104_CP1_NEGATIVE_ACTIVE_EDGE_EXCLUSION_FAILED'; END IF;

 SELECT unit_metadata INTO v_metadata
 FROM programacion.engineering_plan_units
 WHERE plan_code=v_plan AND unit_code='M10.4' AND work_item_id=476
 FOR UPDATE;
 IF v_metadata ? 'm104_freeze_baseline_v1'
 THEN RAISE EXCEPTION 'M104_CP1_BASELINE_ALREADY_PRESENT'; END IF;
 v_metadata:=jsonb_set(v_metadata,'{m104_freeze_baseline_v1}',
    jsonb_build_object(
      'schema_version','M104_LEGACY_FREEZE_BASELINE_V1',
      'classification_event_id',20193,
      'classification_authority','M10.10 historical nominations; LIVE pg_proc exact signature source',
      'scope','LEGACY_REFERENCED + LEGACY_UNREFERENCED SQL ONLY',
      'legacy_functions',v_manifest,
      'legacy_function_count',v_total,
      'sql_aggregate_md5',v_digest,
      'legacy_edge_count',v_edge_legacy,
      'excluded_active_vnext_edge',v_excluded_edges,
      'excluded_edge_count',v_edge_active,
      'captured_at',clock_timestamp(),
      'freeze_ci_guard','PENDING_FREEZE_RULE_CP2',
      'freeze_admitted',false,
      'runtime_activated',false,
      'does_not_authorize_retirement',true
    ),true);
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=v_metadata
 WHERE plan_code=v_plan AND unit_code='M10.4' AND work_item_id=476;

 v_evidence:='supabase://programacion.engineering_plan_units/M10.4#m104_freeze_baseline_v1;'
    ||'supabase://public.lf_eventos/20193;supabase://pg_catalog.pg_proc/legacy-exact-md5:'
    ||v_digest||';supabase://programacion.engineering_work_items/M10.2/DONE';
 v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(v_plan,'M10.4',v_cp);
 IF v_ready->>'status'<>'READY' OR v_ready->>'execution_ready'<>'true'
 THEN RAISE EXCEPTION 'M104_CP1_EXECUTION_READINESS_NOT_READY %',v_ready; END IF;
 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,'M10.4',v_cp,
    'ACTION_STARTED',NULL,'{}'::jsonb,v_evidence,'IG_M104_CP1_TRAIN',true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'M104_CP1_START_HEARTBEAT_FAILED %',v_out; END IF;
 v_out:=programacion.fn_engineering_heartbeat_normalize_v1(v_plan,'M10.4',v_cp,
    'ACTION_DONE',NULL,'{}'::jsonb,v_evidence,'IG_M104_CP1_TRAIN',true);
 IF v_out->>'status'<>'REPAIRED' THEN RAISE EXCEPTION 'M104_CP1_DONE_HEARTBEAT_FAILED %',v_out; END IF;
 v_out:=programacion.fn_engineering_checkpoint_transition_v1(v_plan,'M10.4',v_cp,
    'DONE',v_evidence,'IG_M104_CP1_TRAIN',
    'Legacy-only exact-signature 26/26 fingerprint freeze baseline; 3 ACTIVE_VNEXT Edge excluded; CI guard pending CP2');
 IF v_out#>>'{transition,status}'<>'APPLIED'
 THEN RAISE EXCEPTION 'M104_CP1_TRANSITION_FAILED %',v_out; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=476 AND status='DONE')<>1
 THEN RAISE EXCEPTION 'M104_CP1_POSTSTATE_FAILED'; END IF;

 IF NOT EXISTS (SELECT 1 FROM public.lf_error_knowledge
                WHERE codigo='IG-M104-LEGACY-ACTIVE-FREEZE-SCOPE-001')
 THEN
 INSERT INTO public.lf_error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,lote_origen,source_ref,evidencia)
 VALUES
 ('IG-M104-LEGACY-ACTIVE-FREEZE-SCOPE-001','INPUT_GOVERNANCE',
 'M10.4 no puede congelar todos los fn_input_governance ni Edge activos',
 'FROZEN_SET_ASIS/FREEZE_READBACK inspeccionaban prefijo SQL y 3 Edge actuales aunque M10.10 los clasifica ACTIVE_VNEXT. Baseline historico sin pin ni control de mutacion no prueba freeze.',
 'Se uso source_pack de consulta amplia sin identidad legacy tipada ni contratacion del guard de CI.',
 'Prefijo de familia confundido con lista cerrada legacy',
 'Derivar conjunto de identidad por clasificacion canonica, validar cada firma exacta en pg_proc; excluir ACTIVE_VNEXT; congelar fuente+MD5 con lectura de drift. CP2 exige guard CI real y CP3 mutante negativo; CP4 debe comparar contra baseline persistida. No retirar ni cambiar ACL.',
 'Preflight M10.4: 26/26 firmas reales, 0 Edge legacy, 3 Edge ACTIVE_VNEXT excluidos, MD5 agregado '||v_digest||'; CP1 no habilita guard ni cierre total.',
 'HIGH','ACTIVO','IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.4',
 'programacion.engineering_plan_units/M10.4',
 v_evidence);
 END IF;
END $m104$;
COMMIT;
