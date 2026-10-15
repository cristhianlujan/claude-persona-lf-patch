-- One authorized A16Q unit and exactly three PENDING checkpoints.
-- Router ACT-0001 -> ACTUALIZACION_DB_LF -> Migration Merge Train.
BEGIN;
DO $a16q$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_event constant bigint := 20302;
 v_stream constant bigint := 14;
 v_origin constant text := 'MIGRATION_VIA_MERGE_TRAIN_SOURCE_A16Q_V1';
 v_work bigint;
 v_unit bigint;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.lf_eventos WHERE id=v_event
    AND entidad_tipo='ENGINEERING_PLAN' AND entidad_codigo=v_plan)
 THEN RAISE EXCEPTION 'A16Q_PLAN_EVENT_MISMATCH'; END IF;
 IF NOT EXISTS (SELECT 1 FROM programacion.engineering_workstreams
    WHERE id=v_stream AND stream_code='WS-PROGRAMMING-AGENT-ANALYSIS-V1')
 THEN RAISE EXCEPTION 'A16Q_WORKSTREAM_MISMATCH'; END IF;
 IF NOT EXISTS (SELECT 1 FROM programacion.engineering_plan_units
    WHERE plan_code=v_plan AND unit_code='A15Q' AND disposition='ASSIGNED')
 THEN RAISE EXCEPTION 'A16Q_PLAN_PARENT_MISSING'; END IF;
 IF EXISTS (SELECT 1 FROM programacion.engineering_plan_units
    WHERE plan_code=v_plan AND unit_code='A16Q')
    OR EXISTS (SELECT 1 FROM programacion.engineering_work_items
    WHERE work_code='PA-AN-Q16')
    OR EXISTS (SELECT 1 FROM programacion.engineering_work_checkpoints
    WHERE checkpoint_code IN ('A16Q_C1','A16Q_C2','A16Q_C3'))
 THEN RAISE EXCEPTION 'A16Q_DUPLICATE_OR_CONFLICT'; END IF;

 INSERT INTO programacion.engineering_work_items (
  work_code,workstream_id,title,objective,expected_result,work_type,
  priority,status,assignee_type,assignee_ref,target_domain,target_component,
  source_ref,acceptance_criteria,created_by_execution_id
 ) VALUES (
  'PA-AN-Q16',v_stream,
  'A16Q — Arquitectura Router First y consumo real',
  'Investigar la arquitectura efectiva y demostrar que la solicitud recorre Router, operaciones, componentes y consumidores reales sin rutas paralelas.',
  'Arquitectura verificable y brechas explícitas, con revisión independiente antes de GOLDEN.',
  'ARCHITECTURE','P0','BACKLOG','AGENT','SUPER_ADMIN',
  'PROGRAMMING_AGENT','ROUTER_FIRST_ARCHITECTURE','event://20302',
  jsonb_build_array(
    'C1: inventario actual verificable de activos, Router, operaciones, perfiles, skills, adapters, contratos, guards, consumidores y bindings.',
    'C2: diagrama y traza de consumo real de solicitud a resultado/recibos/readback; un gráfico sin consumidor no es PASS.',
    'C2: casos DEMO parcial de pantalla, alcance completo y modificación puntual, seleccionando únicamente perfiles aplicables.',
    'C3: evaluación independiente, controles positivos y negativos/adversariales y rechazo de evidencia ausente, sintética o de otro sujeto.',
    'GOLDEN requiere decisión y evidencia independientes; esta unidad no activa producción ni promueve automáticamente.'
  ),v_origin
 ) RETURNING id INTO v_work;

 INSERT INTO programacion.engineering_plan_units (
  plan_code,unit_code,unit_class,lot_code,lot_from,lot_to,title,
  exit_criterion,plan_event_id,work_item_id,created_by_execution_id,unit_metadata
 ) VALUES (
  v_plan,'A16Q','ARCHITECTURE_RESEARCH','ANALYSIS-ARCHITECTURE-V1',16,16,
  'A16Q — Investigación de arquitectura Router First',
  'C1 inventario real, C2 consumo extremo a extremo y C3 validación independiente con pruebas positivas/negativas. Sin GOLDEN automático.',
  v_event,v_work,v_origin,
  jsonb_build_object(
    'schema','PROGRAMMING_A16Q_ARCHITECTURE_RESEARCH_V1',
    'scope','PROGRAMMING_AGENT_ANALYSIS_ONLY',
    'phase','ARCHITECTURE_RESEARCH',
    'checkpoint_count',3,
    'runtime_activation',false,
    'production_activation',false,
    'golden_promoted',false,
    'checkpoint_contracts',jsonb_build_object(
      'A16Q_C1',jsonb_build_object(
        'expected','Inventario de autoridad y conexiones reales',
        'evidence_required',jsonb_build_array(
          'exact_asset_refs','router_action_operation_map','consumer_bindings','documented_gaps')),
      'A16Q_C2',jsonb_build_object(
        'expected','Demostración de consumo real extremo a extremo, no solo diagrama',
        'mandatory_trace',jsonb_build_array(
          'literal_request','router','resolved_asset','action','operation',
          'scope_and_mode','selected_profiles_skills_adapters',
          'input_governance_if_applicable','applicable_contracts_and_guards',
          'real_consumer','authorized_result','receipts','readback'),
        'cases',jsonb_build_array(
          'PARTIAL_SCREEN_DEMO','FULL_SCOPE','TARGETED_MODIFICATION'),
        'failure_rule','MISSING_CONSUMER_OR_BINDING_IS_GAP_NOT_PASS'),
      'A16Q_C3',jsonb_build_object(
        'expected','Verificación independiente de la ruta y de sus límites',
        'positive_and_negative_tests',true,
        'independent_review_required',true,
        'golden_auto_promotion',false)
    )
  )
 ) RETURNING id INTO v_unit;

 INSERT INTO programacion.engineering_work_checkpoints (
  work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id
 ) VALUES
  (v_work,'A16Q_C1','Fuente y autoridad vigente',1,1,true,'PENDING',v_origin),
  (v_work,'A16Q_C2','Salida real gobernada',2,1,true,'PENDING',v_origin),
  (v_work,'A16Q_C3','Aseguramiento independiente',3,1,true,'PENDING',v_origin);

 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=v_work AND status='PENDING' AND required) <> 3
   OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=v_work) <> 3
   OR (SELECT count(*) FROM programacion.engineering_plan_units
     WHERE id=v_unit AND work_item_id=v_work AND plan_event_id=v_event) <> 1
 THEN RAISE EXCEPTION 'A16Q_READBACK_FAILED'; END IF;
END;
$a16q$;
COMMIT;
