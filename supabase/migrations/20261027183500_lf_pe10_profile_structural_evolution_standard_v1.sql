-- LF PE10 Profile structural evolution: atomic extension to existing 20261027 operational plan.
-- PLAN ONLY: 1 new unit / 12 PENDING checkpoints / 6 new REQUIRES dependencies.
-- 27 existing units, 132 checkpoints, PE10_C6/C7 and all prior receipts unchanged.
-- ACTUALIZACION_DB_LF / LF Migration Merge Train required. No profile/edge/runtime cutover.
BEGIN;
DO $lf_pe10_structural$
DECLARE
 v_exec text;
 v_stream_id bigint;
 v_parent_id bigint;
 v_ready_id bigint;
 v_work_id bigint;
 v_pre bigint;
 v_plan_event_id bigint;
 v_dep text;
 v_deps jsonb := '["PE10A_CONTRACTS","PE10A_JUDGES","PE10A_PIPELINE","PE10A_METHODS","PE10A_SRCR"]'::jsonb;
 v_checks jsonb := '[["Autoridad/versiones del perfil objetivo y SRCR","Readback compara lf_activos, descriptor CURRENT, manifest, SKILL, runtime binding, method_revision y fuentes exact-head; clasifica v0.6 pack vs SRCR_V0_7R1 método","Una versión declarada como vigente solo por nombre, candidato o rama es rechazada","PE10A_CT01, PE10A_GH01"],["Extraer topología real y capacidades preservables del perfil","Grafo de pasos funcionales, entradas, salidas, contratos, firmas, jueces, validators, consumers, dependencia, terminalidad y coste es material y evidencia sus fuentes","Un paso inventado o una mención textual sin ejecución/propietario no se clasifica como componente operativo","PE10A_CT02, PE10A_PL02"],["Determinar operación diferencial por nodo con pruebas de necesidad","Cada paso recibe KEEP, ADD, REPLACE, REMOVE, MERGE, SPLIT, REORDER, DEPRECATE, CONDITIONAL o NO_CHANGE según caso, con razón, alcance, dependencia, antes/después y aceptación","Una operación por plantilla o porcentaje, no justificada por evidencia causal, queda bloqueada","PE2B_C3, PE3B_C1, PE10A_ME02"],["Agregar pasos funcionales cuando la naturaleza lo requiera","Paso ADD añade contrato, input/output, propietario, juez, fuente, calificación, error y ruta autorizada, con test positivo de su necesidad","ADD sin consumidor, sin contrato o que duplique capacidad reutilizable no se acepta","PE5A_C2, PE10A_CT04"],["Eliminar o deprecar pasos y limpiar las referencias","REMOVE/DEPRECATE prueba ausencia de consumidor requerido, elimina referencias huérfanas, conserva migración y compatibilidad de ejecuciones previas","Eliminar un paso consumido sin migración/binding de retiro, o dejar un salto colgado, falla","PE5A_C4, PE10A_CT05"],["Reemplazar pasos, firmas y jueces preservando semántica autorizada","REPLACE vincula old/new paso+contrato+firma+schema+binding+judge y verifica equivalencia, adaptación y deprecación segura","Si se pierde un campo requerido, una condición de bloqueo o una función del perfil se rechaza","PE6_C4, PE10A_JD01"],["Fusionar, separar o reordenar sin romper el grafo","MERGE/SPLIT/REORDER produce grafo acíclico y transiciones válidas, sin duplicación, fase omitida ni ruta huérfana; pruebas ejecutadas","Un cambio que ejecute semántico antes del determinista o salte un gate falla","PE10A_PL02, PE10A_PL03"],["Seleccionar secuencia interna condicionada por naturaleza y señales","Pipeline del perfil elige módulos y métodos por señales tipadas y precondiciones, no usa número fijo de pasos ni aplica todos los módulos","Ruta dependiente de nombre de producto, método no calificado o subflujo no autorizado bloquea","PE3B_C2, PE10A_ME02, SRCR_V0_7R1"],["Actualizar paquete transversal afectado y sus consumidores","SKILL, manifest, contratos, firmas, JSON schemas, judges, validadores, tests, imports, runtime binding, ejemplos, proyección/context budget actualizados según impacto","Actualizar solo SKILL o PR sin despliegue/consumidor verificado no produce APTO","PE10A_CT04, PE10A_GH05, PE10A_OP02"],["Probar casos reales comparados: agregar, quitar, sustituir y NO_CHANGE","Cuatro casos representativos provider-bound con baseline congelado, ejecución de perfil real, pruebas positivas/negativas, holdout y calidad preservada; registrar receipts","Mock, fixture aislada, auto-evaluación o texto PASS no admiten cierre","PE10E_C1, PE10A_OP03, PE10A_OP04"],["Reverificar efectos de segundo orden, estado durable y reversión","Identifica rutas alternas/consumidores antiguos, estado persistente, replay y rollback; valida reconstrucción/recuperación de perfil anterior","No permite perfil parcialmente evolucionado, loops de autorreparación, cursor inservible ni función deprecated accesible","PE10A_PL06, PE10A_GH06, PE10A_OP06"],["Handoff Reparador→Updater y aceptación de perfil utilizable","SRCR (pack v0.6, método SRCR_V0_7R1) entrega solicitud estructurada mediante orquestador gobernado con autoridad exacta; resultado APTO solo con readback runtime/Supabase/GitHub y comprobación independiente","SRCR no invoca directamente otro perfil, ni usa intent no autorizado REPAIR_MISSING_PRODUCT_STRUCTURE como permiso general de Updater; sin E2E retorna próxima acción","PE10A_SR03, PE10A_SR04, PE10A_OP08"]]'::jsonb;
 v_meta jsonb;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
  AND target_code LIKE '%lf_pe10_profile_structural_evolution_standard_v1'
  AND status='IN_PROGRESS'
 ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'PE10_STRUCTURE_TRAIN_TRANSPORT_REQUIRED'; END IF;
 SELECT id INTO STRICT v_stream_id FROM programacion.engineering_workstreams
 WHERE stream_code='PROFILE_UPDATER_EVOLUTION_V1' AND status='ACTIVE';
 SELECT id INTO STRICT v_parent_id FROM programacion.engineering_work_items
 WHERE work_code='PEVO-PE10' AND workstream_id=v_stream_id AND status='IN_PROGRESS';
 SELECT id INTO STRICT v_ready_id FROM programacion.engineering_work_items
 WHERE work_code='PEVO-PE10A_READY' AND parent_work_item_id=v_parent_id;
 SELECT plan_event_id INTO STRICT v_plan_event_id FROM programacion.engineering_plan_units
 WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND unit_code='PE10';
 IF jsonb_array_length(v_checks)<>12 OR jsonb_array_length(v_deps)<>5
   OR (SELECT count(*) FROM programacion.engineering_plan_units WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1')<>27
   OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c
       JOIN programacion.engineering_plan_units u ON c.work_item_id=u.work_item_id
       WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1')<>132
   OR EXISTS(SELECT 1 FROM programacion.engineering_work_items WHERE work_code='PEVO-PE10A_STRUCTURE')
   OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=v_parent_id AND checkpoint_code IN ('PE10_C6','PE10_C7') AND status='PENDING')<>2
   OR (SELECT version FROM public.lf_operation_registry WHERE operation_code='ACTUALIZACION_PERFIL_LF')<>'v0.1'
 THEN RAISE EXCEPTION 'PE10_STRUCTURE_PRESTATE_STALE_OR_DUPLICATE'; END IF;

 INSERT INTO programacion.engineering_work_items
  (work_code,workstream_id,parent_work_item_id,title,objective,expected_result,
   work_type,priority,status,assignee_type,assignee_ref,target_repo,target_domain,
   target_component,source_ref,acceptance_criteria,created_by_execution_id)
 VALUES ('PEVO-PE10A_STRUCTURE',v_stream_id,v_parent_id,
  'Evolución estructural dinámica del perfil objetivo — referencia SRCR V0.7R1',
  'Qualify context-specific addition, removal, replacement, merge, split and reordering of target-profile procedures and dependencies under governed Profile Updater',
  '12 provider-bound verified checks, no fixed target-profile step count, exact before/after evidence, functional operability and fallback',
  'QA','P1','BACKLOG','AGENT','PROFILE_EVOLUTION_ORCHESTRATOR',
  'cristhianlujan/claude-persona-lf-patch','LF_PE10','PROFILE_TARGET_TOPOLOGY',
  'github://cristhianlujan/claude-persona-lf-patch@main/profiles/systemic_root_cause_repair_lf',
  jsonb_build_array('Preserve legacy/updater governance operation steps independently from target internal steps',
  'Do not confuse SRCR V0.6 pack with method revision SRCR_V0_7R1 or promote candidate',
  'One exact current positive/negative provider-bound receipt for each atomic checkpoint',
  'No direct SRCR profile invocation or bypass of orchestration',
  'Preserve last known good profile, contracts, consumers and runtime parity',
  'Do not activate v0.2, write profile, or claim APTO on registration'),v_exec)
 RETURNING id INTO v_work_id;

 INSERT INTO programacion.engineering_work_checkpoints
  (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT v_work_id,'PE10A_ST'||lpad(ord::text,2,'0'),item->>0,
        ord::integer,1,true,'PENDING',v_exec
 FROM jsonb_array_elements(v_checks) WITH ORDINALITY AS e(item,ord);

 SELECT jsonb_build_object(
  'schema','PE10_STRUCTURAL_EVOLUTION_CHECKPOINTS_V1',
  'purpose','TARGET_PROFILE_DYNAMIC_TOPOLOGY_NOT_PROFILE_UPDATER_GOVERNANCE_SEQUENCE',
  'origin_srcr_pack','SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6',
  'origin_srcr_method_revision','SRCR_V0_7R1',
  'srcr_default_mode','READ_ONLY',
  'srcr_profile_update_invocation','GOVERNED_ORCHESTRATOR_HANDOFF_ONLY',
  'registration_mode','PLAN_ONLY',
  'current_step_count_is_not_target_profile_step_count',true,
  'procedure_mutations',jsonb_build_array('KEEP','ADD','REPLACE','REMOVE','MERGE','SPLIT','REORDER','DEPRECATE','CONDITIONAL','NO_CHANGE'),
  'prior_work_reused',jsonb_build_array('PE5A','PE6','PE10E','PE10A_CONTRACTS','PE10A_JUDGES','PE10A_PIPELINE','PE10A_METHODS','PE10A_SRCR','PE10A_READY'),
  'checkpoint_ordering',(
    SELECT jsonb_agg('PE10A_ST'||lpad(ord::text,2,'0') ORDER BY ord)
    FROM jsonb_array_elements(v_checks) WITH ORDINALITY e(item,ord)),
  'checkpoint_inputs',(
    SELECT jsonb_object_agg('PE10A_ST'||lpad(ord::text,2,'0'),
      jsonb_build_object('purpose',item->>0,'pass_when',item->>1,
        'negative_falsifier',item->>2,'reuses',item->>3,
        'readback_required',true,'provider_receipt_required',true))
    FROM jsonb_array_elements(v_checks) WITH ORDINALITY e(item,ord)),
  'action_specs_v1',(
    SELECT jsonb_object_agg('PE10A_ST'||lpad(ord::text,2,'0'),
      jsonb_build_object('status','BLOCK_PENDING_IMPLEMENTATION_AND_INDEPENDENT_RECEIPT',
      'requires_material_execution',true,'recipe_mode','EVIDENCE_FIRST',
      'action_kind','GOVERNED_MATERIAL_VERIFICATION',
      'positive_test',item->>1,'negative_test',item->>2,
      'validator_contract_status','EXACT_EXISTING_VALIDATOR_TO_BE_BOUND_PER_CHECKPOINT',
      'closure_route','AUTHORIZED_OPERATION_THEN_TRAIN_AND_POST_READBACK',
      'forbidden',jsonb_build_array('HARD_CODE_TARGET_STEP_COUNT','CLAIM_PASS_WITHOUT_EXECUTION',
      'BYPASS_SRCR_OR_GOVERNED_TRANSPORT','DIRECT_SRCR_PROFILE_INVOKE',
      'AUTO_ACTIVATE_V02','REWRITE_COMPLETED_EVIDENCE')))
    FROM jsonb_array_elements(v_checks) WITH ORDINALITY e(item,ord))
 ) INTO v_meta;

 INSERT INTO programacion.engineering_plan_units
  (plan_code,unit_code,unit_class,lot_code,lot_from,lot_to,title,exit_criterion,
  plan_event_id,work_item_id,created_by_execution_id,unit_metadata)
 VALUES ('PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10A_STRUCTURE','EXECUTION',
  'E10_ATOMIC_STRUCTURE',10,10,
  'Evolución estructural del perfil por naturaleza, con adición/remoción/reemplazo de pasos',
  '12 checkpoints de diseño y ejecución verificados contra perfil real, incluidos add/remove/replace y salida apta; sin activar automáticamente',
  v_plan_event_id,v_work_id,v_exec,v_meta);

 FOR v_dep IN SELECT jsonb_array_elements_text(v_deps)
 LOOP
   SELECT id INTO STRICT v_pre FROM programacion.engineering_work_items
   WHERE work_code='PEVO-'||v_dep AND parent_work_item_id=v_parent_id;
   INSERT INTO programacion.engineering_work_dependencies
    (work_item_id,depends_on_work_item_id,relation_type,created_by_execution_id)
   VALUES (v_work_id,v_pre,'REQUIRES',v_exec);
 END LOOP;
 INSERT INTO programacion.engineering_work_dependencies
   (work_item_id,depends_on_work_item_id,relation_type,created_by_execution_id)
 VALUES (v_ready_id,v_work_id,'REQUIRES',v_exec);

 IF (SELECT count(*) FROM programacion.engineering_plan_units WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1')<>28
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_plan_units u
   ON u.work_item_id=c.work_item_id WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1')<>144
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_work_id AND status='PENDING')<>12
 OR (SELECT count(*) FROM programacion.engineering_work_dependencies WHERE work_item_id=v_work_id)<>5
 OR (SELECT count(*) FROM programacion.engineering_work_dependencies
   WHERE work_item_id=v_ready_id AND depends_on_work_item_id=v_work_id)<>1
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
   WHERE work_item_id=v_parent_id AND checkpoint_code IN ('PE10_C6','PE10_C7') AND status='PENDING')<>2
 OR (SELECT version FROM public.lf_operation_registry WHERE operation_code='ACTUALIZACION_PERFIL_LF')<>'v0.1'
 THEN RAISE EXCEPTION 'PE10_STRUCTURE_POST_REGISTER_FAILED'; END IF;
END $lf_pe10_structural$;
COMMIT;
