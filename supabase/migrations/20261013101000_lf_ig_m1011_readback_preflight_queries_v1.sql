-- M10.11 only. Repair READ_QUERY_MISSING on CP3, CP4, CP5.
-- No mutation to permission grants, runtime, checkpoint statuses, or other units.
DO $pre$
DECLARE c text; a jsonb; v int;
BEGIN
 IF (SELECT count(*) FROM programacion.engineering_work_blockers
     WHERE work_item_id=197 AND status='OPEN') IS DISTINCT FROM 0
 THEN RAISE EXCEPTION 'M1011_PRESTATE_BLOCKER_DRIFT'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=197 AND status IN ('DONE','NOT_APPLICABLE'))
     IS DISTINCT FROM 2 THEN RAISE EXCEPTION 'M1011_CHECKPOINT_PRESTATE_DRIFT'; END IF;
 FOREACH c IN ARRAY ARRAY['REVOKE_MIGRATION','NEG_CALLER_DENIED','REVOKE_READBACK'] LOOP
   a:=programacion.fn_engineering_checkpoint_action_spec_v3(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.11',c);
   IF a->>'status' IS DISTINCT FROM 'READY'
      OR a->>'action_kind' IS DISTINCT FROM 'READBACK_ONCE'
      OR a->>'requires_material_execution' IS DISTINCT FROM 'false' THEN
     RAISE EXCEPTION 'M1011_ACTION_PRESTATE_NOT_CONDITIONAL:%',c;
   END IF;
   IF programacion.fn_engineering_checkpoint_execution_readiness_v1(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.11',c)->'reasons'
      IS DISTINCT FROM '["READ_QUERY_MISSING"]'::jsonb THEN
     RAISE EXCEPTION 'M1011_NONQUERY_PREFLIGHT_DRIFT:%',c;
   END IF;
 END LOOP;
END;
$pre$;

-- Each checkpoint must supply actual SQL queries to the READ execution packet.
-- Copy is derived from authoritative current classifier, catalog and suite,
-- without fixed inventory counts or inferred caller liveness from names.
UPDATE programacion.engineering_plan_units u
SET unit_metadata = jsonb_set(
 jsonb_set(
  jsonb_set(u.unit_metadata,
   '{action_specs_v1,REVOKE_MIGRATION,verification_queries}',
   to_jsonb(ARRAY[
    'SELECT e.id,e.created_at,count(*) FILTER (WHERE x->>''class''=''REMOVE_READY'') AS remove_ready_count,count(*) AS classified_count FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->''matrix'') x WHERE e.entidad_codigo=''IG_CURATOR_VALIDATOR_REFACTOR_V2.M10.10.PAULO-160'' GROUP BY e.id,e.created_at ORDER BY e.id DESC LIMIT 1',
    'SELECT suite_run_id,status,tests_total,tests_passed,completed_at,metadata FROM public.lf_test_suite_runs WHERE suite_code=''IG_M1011_ZERO_TARGET_FINAL_V1'' ORDER BY completed_at DESC LIMIT 1'
   ]::text[]),true),
   '{action_specs_v1,NEG_CALLER_DENIED,verification_queries}',
   to_jsonb(ARRAY[
    'SELECT f->>''observed_signature'' AS signature,p.oid::regprocedure::text AS catalog_signature,has_function_privilege(''anon'',p.oid,''EXECUTE'') AS anon_exec,has_function_privilege(''authenticated'',p.oid,''EXECUTE'') AS auth_exec,has_function_privilege(''service_role'',p.oid,''EXECUTE'') AS service_exec FROM programacion.engineering_plan_units u CROSS JOIN LATERAL jsonb_array_elements(u.unit_metadata#>''{m1011_live_sql_recheck_v2,functions}'') f LEFT JOIN pg_proc p ON p.oid=to_regprocedure(f->>''observed_signature'') WHERE u.plan_code=''IG_CURATOR_VALIDATOR_REFACTOR_V2'' AND u.unit_code=''M10.11'' ORDER BY 1',
    'SELECT suite_run_id,status,tests_total,tests_passed,completed_at FROM public.lf_test_suite_runs WHERE suite_code=''IG_M1011_ZERO_TARGET_FINAL_V1'' ORDER BY completed_at DESC LIMIT 1'
   ]::text[]),true),
   '{action_specs_v1,REVOKE_READBACK,verification_queries}',
   to_jsonb(ARRAY[
    'SELECT e.id,e.created_at,count(*) FILTER (WHERE x->>''class''=''REMOVE_READY'') AS remove_ready_count FROM public.lf_eventos e CROSS JOIN LATERAL jsonb_array_elements(e.payload->''matrix'') x WHERE e.entidad_codigo=''IG_CURATOR_VALIDATOR_REFACTOR_V2.M10.10.PAULO-160'' GROUP BY e.id,e.created_at ORDER BY e.id DESC LIMIT 1',
    'SELECT f->>''observed_signature'' AS signature,md5(p.prosrc) AS source_md5,has_function_privilege(''anon'',p.oid,''EXECUTE'') AS anon_exec,has_function_privilege(''authenticated'',p.oid,''EXECUTE'') AS auth_exec,has_function_privilege(''service_role'',p.oid,''EXECUTE'') AS service_exec FROM programacion.engineering_plan_units u CROSS JOIN LATERAL jsonb_array_elements(u.unit_metadata#>''{m1011_live_sql_recheck_v2,functions}'') f LEFT JOIN pg_proc p ON p.oid=to_regprocedure(f->>''observed_signature'') WHERE u.plan_code=''IG_CURATOR_VALIDATOR_REFACTOR_V2'' AND u.unit_code=''M10.11'' ORDER BY 1',
    'SELECT suite_run_id,status,tests_total,tests_passed,completed_at,metadata FROM public.lf_test_suite_runs WHERE suite_code=''IG_M1011_ZERO_TARGET_FINAL_V1'' ORDER BY completed_at DESC LIMIT 1'
   ]::text[]),true)
WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  AND u.unit_code='M10.11';

-- Exactly the original failure must be removed across all three checkpoints,
-- without changing the zero-target admission rules or checkpoint progress.
DO $readback$
DECLARE c text; a jsonb; readiness jsonb; packet jsonb;
BEGIN
 FOREACH c IN ARRAY ARRAY['REVOKE_MIGRATION','NEG_CALLER_DENIED','REVOKE_READBACK'] LOOP
   a:=programacion.fn_engineering_checkpoint_action_spec_v3(
     'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.11',c);
   readiness:=programacion.fn_engineering_checkpoint_execution_readiness_v1(
     'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.11',c);
   IF readiness->>'status' IS DISTINCT FROM 'READY'
      OR readiness#>>'{gates,ACTION_EXACT}' IS DISTINCT FROM 'true' THEN
     RAISE EXCEPTION 'M1011_READ_QUERY_STILL_BLOCKED:%:%',c,readiness;
   END IF;
   packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
     'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.11',c,a,'{}'::jsonb);
   IF packet->>'status' IS DISTINCT FROM 'READY'
      OR jsonb_array_length(coalesce(packet#>'{connector_plan,0,queries}','[]'::jsonb)) IS DISTINCT FROM 1
   THEN RAISE EXCEPTION 'M1011_READ_PACKET_NOT_ONE_BUNDLE:%',c; END IF;
 END LOOP;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=197 AND status IN ('DONE','NOT_APPLICABLE')) IS DISTINCT FROM 2
 THEN RAISE EXCEPTION 'M1011_PREMATURE_CLOSURE'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_blockers
     WHERE work_item_id=197 AND status='OPEN') IS DISTINCT FROM 0
 THEN RAISE EXCEPTION 'M1011_REGRESSED_TO_BLOCKED'; END IF;
END;
$readback$;

-- EKB append-only: avoiding second stalled checkpoint from missing exact query.
INSERT INTO transversal.error_knowledge(
 codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,evidencia,
 source_ref,lote_origen,estado,lifecycle_phase,consumer_role)
SELECT
 'IG-M1011-NONMATERIAL-READBACK-MISSING-QUERY-001',
 'INPUT_GOVERNANCE',
 'No basta transformar checkpoint material a readback: se exige consulta exacta',
 'Tras reparar contrato y blocker M10.11 PR2404, el bootstrap siguio STOP_EXECUTION_PREFLIGHT con READ_QUERY_MISSING. El modo READBACK_ONCE compilaba READY pero el packet conector tenia queries=[]. El mismo fallo existia en CP3, CP4 y CP5.',
 'La reparacion local cambio action_kind y requires_material_execution, pero no definio verification_queries en los action_specs. El preflight valida consultas reales dentro de connector_plan, no solo la presencia de objetos target ni source_pack separado.',
 'Al cambiar MATERIALIZE a READBACK_ONCE, preflight de los siguientes checkpoints en el mismo owner. Para cada uno exigir verification_queries en action_spec, packet READ query no vacia y fn_engineering_checkpoint_execution_readiness_v1.status=READY; pruebas reversibles/negative para admision por separado. No inferir PASS ni N/A por modificar un contrato.',
 'PR2404 sano la causa del blocker (open 1->0, CP3 action READY), pero preflight CP3/CP4/CP5 READ_QUERY_MISSING. Nueva migracion valida dinamicamente 3/3 READINESS READY, 3 packets de consultas reales y 0 transiciones.',
 'github://cristhianlujan/claude-persona-lf-patch/pull/2404;supabase://programacion.fn_engineering_checkpoint_execution_readiness_v1',
 'programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.11',
 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.11',
 'ACTIVO','CONTRACT_PREFLIGHT',
 ARRAY['Architect','Builder','Judge','Auditor']::text[]
WHERE NOT EXISTS(SELECT 1 FROM transversal.error_knowledge
  WHERE codigo='IG-M1011-NONMATERIAL-READBACK-MISSING-QUERY-001');
