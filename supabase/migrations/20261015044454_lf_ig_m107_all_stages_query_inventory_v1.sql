-- IG M10.7: append-only diagnostic evidence covering all known execution phases.
-- Only EKB insert, no execution/contract/validator/trigger/index/cron changes.
DO $audit$
DECLARE
  v_code constant text:='IG-M107-ALL-STAGES-QUERY-INVENTORY-007';
  v_triggers jsonb;
  v_counts jsonb;
  v_count int;
  v_families int;
  v_pass int;
  v_props int;
  v_rules int;
  v_tokens int;
  v_trial int;
  v_evidence jsonb;
BEGIN
  IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code)
    THEN RAISE EXCEPTION 'IG_M107_AUDIT_EKB_DUPLICATE'; END IF;
  SELECT count(*),count(*) filter(where validator_outcome='PASS')
    INTO v_families,v_pass FROM programacion.input_family_assessments WHERE run_id=933;
  SELECT count(*) INTO v_props FROM programacion.input_gap_proposals WHERE run_id=933;
  IF (SELECT status FROM programacion.input_readiness_runs WHERE id=933)<>'COMPLETED'
     OR v_families<>47 OR v_pass<>47 OR v_props<>20
  THEN RAISE EXCEPTION 'IG_M107_AUDIT_MATERIAL_BASELINE_DRIFT'; END IF;

  WITH items AS (
    SELECT t.tgrelid::regclass::text relation, t.tgname trigger_name,
       CASE WHEN t.tgtype&4=4 THEN 'INSERT'
            WHEN t.tgtype&16=16 THEN 'UPDATE' ELSE 'OTHER' END event,
       p.proname function_name,
       md5(pg_get_functiondef(p.oid)) source_md5,
       pg_get_functiondef(p.oid) body
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid=t.tgfoid
    WHERE NOT t.tgisinternal AND t.tgenabled IN ('O','A')
      AND t.tgrelid IN (
       'programacion.input_family_assessments'::regclass,
       'programacion.input_gap_proposals'::regclass,
       'programacion.input_readiness_runs'::regclass)
  )
  SELECT jsonb_agg(jsonb_build_object(
   'table',relation,'trigger',trigger_name,'event',event,
   'function',function_name,'source_md5',source_md5,
   'calls_full_manifest',body ILIKE '%fn_input_build_source_manifest%',
   'calls_currentness',body ILIKE '%fn_input_governance_continuation_currentness%',
   'calls_assertion',body ILIKE '%fn_input_evaluate_assertion%',
   'calls_source_resolver',body ILIKE '%fn_input_resolve_source_ref%',
   'calls_semantic_depth',body ILIKE '%fn_input_subject_depth_expected%'
  ) ORDER BY relation,event,trigger_name),count(*)
  INTO v_triggers,v_count FROM items;
  IF v_count<>21 THEN RAISE EXCEPTION 'IG_M107_AUDIT_TRIGGER_TOPOLOGY_CHANGED:%',v_count; END IF;

  SELECT count(*) INTO v_rules
    FROM programacion.fn_input_effective_rule_links_v1(43,'INPUT_GOVERNANCE');
  WITH bind AS (
    SELECT component_token_id token FROM lf_ops.campos_pantallas WHERE pantalla_id=43
    UNION ALL SELECT layout_component_token_id FROM lf_ops.pantalla_variantes WHERE pantalla_id=43
    UNION ALL SELECT component_token_id FROM lf_ops.pantalla_elementos WHERE pantalla_id=43 AND status<>'DEPRECATED'
  ) SELECT count(distinct token) INTO v_tokens FROM bind WHERE token IS NOT NULL;

  v_evidence:=jsonb_build_object(
    'schema_version','IG_M107_ALL_STAGES_QUERY_INVENTORY_V1',
    'run_id',933,'screen_id',43,
    'status','READ_ONLY_AUDIT_NO_CODE_OPTIMIZATION',
    'source_current_at_audit',false,
    'families',v_families,'family_pass',v_pass,'proposals',v_props,
    'active_trigger_inventory',v_triggers,
    'rules_effective_at_audit',v_rules,
    'distinct_design_tokens_at_audit',v_tokens,
    'phase_wall_ms',jsonb_build_object(
       'curator',66531,'validator',229436,'validator_compute',205179,
       'validator_wait',21231,
       'validator_assertions',48773,'validator_update_and_guard',122115,
       'validator_gap_proposals',34041,
       'curator_deterministic_resolvers',30018,
       'curator_semantic_resolvers',9106),
    'read_only_sql_probes',jsonb_build_array(
       jsonb_build_object('query','SOURCE_MANIFEST','n',3,'times_ms',jsonb_build_array(438,436,428)),
       jsonb_build_object('query','CONTINUATION_CURRENTNESS','n',3,'times_ms',jsonb_build_array(452,451,451)),
       jsonb_build_object('query','RESOLVE_SCREEN_GRAPH','n',3,'times_ms',jsonb_build_array(404,408,403)),
       jsonb_build_object('query','SCREEN_CANONICAL_GRAPH','n',3,'times_ms',jsonb_build_array(225,225,220)),
       jsonb_build_object('query','SCREEN_CONTRACT','n',3,'times_ms',jsonb_build_array(47,46,46)),
       jsonb_build_object('query','SCREEN_STATES','n',3,'times_ms',jsonb_build_array(1,1,1)),
       jsonb_build_object('query','MANIFEST_IDENTITY','n',3,'times_ms',jsonb_build_array(0,0,0)),
       jsonb_build_object('query','EFFECTIVE_RULE_LINKS','n',3,'times_ms',jsonb_build_array(39.502,32.561,36.277)),
       jsonb_build_object('query','EFFECTIVE_RULE_LINKS_COLD_OBSERVATION','n',1,'time_ms',365.582),
       jsonb_build_object('query','FAMILY_RUN_AND_ORDER_PK','n',1,'time_ms',0.225),
       jsonb_build_object('query','PROPOSAL_RUN_PK','n',1,'time_ms',0.387),
       jsonb_build_object('query','QUEUE_QUEUED_ORDER','n',1,'time_ms',3.285)),
    'source_kinds',jsonb_build_object(
       'SCREEN_CANONICAL_GRAPH',38,'EKB_DECISION_SET',5,
       'SCREEN_STATE_SET',2,'EKB_PREVENTION_SET',1,'CONTRACT',1),
    'limitations',jsonb_build_array(
       'NO_INDIVIDUAL_TRIGGER_TIMING_YET',
       'NO_QUERY_OMITTED_FROM_REVIEW_POLICY_BUT_NOT_ALL_NESTED_QUERIES_PROFILED',
       'PG_STAT_STATEMENTS_TRACK_TOP_OMITS_NESTED_SQL',
       'NO_EXACT_SOURCE_COMPARABLE_BENCHMARK',
       'NO_ESTIMATED_SAVINGS_CLAIMED',
       'NOT_AUTHORIZED_TO_CHANGE_CHECKPOINT'));
  FOR v_trial IN 1..2 LOOP
    BEGIN
     INSERT INTO public.lf_error_knowledge(
      id,codigo,categoria,titulo,descripcion,causa_raiz,patron,
      prevencion,validacion,severidad,frecuencia,primera_vez,ultima_vez,
      lote_origen,estado,evidencia,created_at,updated_at,lifecycle_phase,
      root_cause_family,detectability,source_context,source_ref
     ) VALUES (
      gen_random_uuid(),v_code,'GOVERNANCE',
      'Inventario de consultas y 21 triggers para optimizacion IG sin omitir consultas rapidas',
      'Se reviso cola, Curator, EKB, 47 familias, 30 semantic resolvers, contrato 269KB, 246 reglas, grafo, manifiesto, aserciones, source resolvers, 21 triggers, 20 propuestas, currentness y recibos. Se documentan planes SQL con EXPLAIN y microbenchmark de 21 lecturas; cada query se considera tanto por costo unitario como frecuencia. Los triggers sin medicion individual quedan explicitamente PENDIENTES DE INSTRUMENTACION, no descartados.',
      'Multiplicacion de lecturas de manifiesto de fuente y grafo en controles independientes de updates de filas y propuestas; alta multiplicidad de links globales y bindings. El Validator no comparte contexto de grafo entre transacciones como Curator. Diseno de binding v2 ejecuta consultas de componente multiples veces por token; pantalla tiene 40 ocurrencias de bindings en 12 tokens. No es valido atribuir 122115ms a un unico trigger o retirar checks de seguridad.',
      'IG_QUERY_COST_X_INVOCATION_COUNT',
      'Orden de reparacion propuesto: (1) medir individualmente los 21 triggers y consultas anidadas, con opt-in y transaction rollback; (2) reusar resolucion de links y 246 reglas dentro de instantanea consistente con source hash y currentness fail-closed; (3) evitar redigest y resolucion redundante del grafo por familia entre Curator/Validator sin compartir decisiones ni omitir readbacks independientes; (4) agrupar recibos de 40 bindings por 12 tokens conservando integridad; (5) revisar 2 lecturas de effective links en API y 7 fuentes del manifiesto; (6) desglosar validacion de 20 propuestas y sus triggers; (7) preservar y revisar cada consulta rapida, indice, coste acumulado de planificacion, serializacion y buffer; (8) probar exact-source, negativos, cambio de fuente durante ejecucion, p50/p90 y diff semantico antes de cambio de contrato. No asumir 45s como target empirico.',
      'Auditoria READONLY en 1 pantalla: 21 triggers enumerados con fingerprints, 47 PASS, 20 propuestas, 246 reglas efectivas, 214 DERIVED_GLOBAL, 31 LEGACY_EXPLICIT, 1 DECLARATIVE, 40 bindings/12 tokens; fn_input_effective_rule_links_v1 medido 32.561/36.277/39.502ms warm y 365.582ms cold; source manifest 428..438ms. Sin cambios de runtime ni prueba de ganancia. M10.7 permanece 45%, CP3 PENDING.',
      'HIGH',1,clock_timestamp(),clock_timestamp(),
      'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7',
      'ACTIVO',v_evidence::text,clock_timestamp(),clock_timestamp(),
      'PREFLIGHT','R4_NO_CUESTIONA','LOUD_EARLY',
      'M10.7 full query path audit; diagnostic only, no transversal changes',
      'supabase://programacion.input_readiness_runs/933'
     );
     IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1
     THEN RAISE EXCEPTION 'IG_M107_QUERY_AUDIT_EKB_READBACK_FAIL'; END IF;
     IF v_trial=1 THEN
       RAISE EXCEPTION 'IG_M107_QUERY_AUDIT_ROLLBACK_CHECK'
         USING ERRCODE='PZ126';
     END IF;
    EXCEPTION WHEN SQLSTATE 'PZ126' THEN
      IF v_trial<>1 THEN RAISE; END IF;
    END;
    IF v_trial=1 AND EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code)
    THEN RAISE EXCEPTION 'IG_M107_QUERY_AUDIT_ROLLBACK_RESIDUE'; END IF;
  END LOOP;
END $audit$;
