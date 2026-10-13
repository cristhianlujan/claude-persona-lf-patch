-- Operational qualification A1Q-A15Q, backed by 15 existing historical A1-A15 DONE units.
-- New actual qualification checkpoints: 45 all PENDING, never forged historical DONE.
-- Must be executed ONLY through ACT-0001 -> ACTUALIZACION_DB_LF -> authorized LF Merge Train.
-- Does not mutate historical DONE statuses, activate runtime, or claim operational PASS.
-- Source catalog: docs/programming-agent/ANALYSIS_QUALIFICATION_CHECKPOINT_CATALOG_V1.json
-- Source baseline git main: b526951438e86c18a8bf6947d0fb40b169d484a0
BEGIN;
DO $analysis_qualification$
DECLARE
  v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
  v_actor constant text := 'EXEC-ANALYSIS-QUAL-CHECKPOINTS-20261013-MERGE-TRAIN';
  v_catalog jsonb := '[{"unit_code":"A1","qualification_unit_code":"A1Q","title":"Intake y normalización","objective":"Acreditar intake tipado sin solución inferida","checkpoints":[{"code":"A1Q_C1","order":1,"title":"Fuente y autoridad vigente","evidence_class":"ATTESTED_SOURCE_BINDING","required_proof":"Fuente de REQUEST_CONTEXT vigente y binding exacto","forbidden":"ONLY_MANIFEST_OR_DECLARED_CURRENTNESS"},{"code":"A1Q_C2","order":2,"title":"Salida real gobernada","evidence_class":"REAL_EXECUTION_RECEIPT","required_proof":"Ejecución real de normalización con contexto trazable","forbidden":"FIXTURE_REPLAY_OR_SELF_DECLARED_MODEL_EXECUTION"},{"code":"A1Q_C3","order":3,"title":"Aseguramiento independiente","evidence_class":"INDEPENDENT_REVIEW_OR_CONSUMER_RECEIPT","required_proof":"Revisor ajeno al productor confirma intención y ambigüedad sin invención","forbidden":"PRODUCER_SELF_JUDGMENT_OR_STRUCTURAL_PASS_AS_SEMANTIC_PASS"}]},{"unit_code":"A2","qualification_unit_code":"A2Q","title":"Clasificación y profundidad","objective":"Acreditar L1/L2/L3 según riesgo gobernado","checkpoints":[{"code":"A2Q_C1","order":1,"title":"Fuente y autoridad vigente","evidence_class":"ATTESTED_SOURCE_BINDING","required_proof":"Política de señales L1/L2/L3 vigente, sin pesos arbitrarios","forbidden":"ONLY_MANIFEST_OR_DECLARED_CURRENTNESS"},{"code":"A2Q_C2","order":2,"title":"Salida real gobernada","evidence_class":"REAL_EXECUTION_RECEIPT","required_proof":"Clasificación real con justificación y fuentes de señales","forbidden":"FIXTURE_REPLAY_OR_SELF_DECLARED_MODEL_EXECUTION"},{"code":"A2Q_C3","order":3,"title":"Aseguramiento independiente","evidence_class":"INDEPENDENT_REVIEW_OR_CONSUMER_RECEIPT","required_proof":"Juicio independiente sobre clasificación y unknown material no L1","forbidden":"PRODUCER_SELF_JUDGMENT_OR_STRUCTURAL_PASS_AS_SEMANTIC_PASS"}]},{"unit_code":"A3","qualification_unit_code":"A3Q","title":"Research dirigido","objective":"Acreditar consulta real de EKB y fuentes current","checkpoints":[{"code":"A3Q_C1","order":1,"title":"Fuente y autoridad vigente","evidence_class":"ATTESTED_SOURCE_BINDING","required_proof":"Fuente/permiso/currentness de cada referencia recuperada","forbidden":"ONLY_MANIFEST_OR_DECLARED_CURRENTNESS"},{"code":"A3Q_C2","order":2,"title":"Salida real gobernada","evidence_class":"REAL_EXECUTION_RECEIPT","required_proof":"Lecturas atestadas con trazabilidad de fuente, AS-IS y delta","forbidden":"FIXTURE_REPLAY_OR_SELF_DECLARED_MODEL_EXECUTION"},{"code":"A3Q_C3","order":3,"title":"Aseguramiento independiente","evidence_class":"INDEPENDENT_REVIEW_OR_CONSUMER_RECEIPT","required_proof":"Revisor verifica suficiencia y ausencia de búsqueda/invención","forbidden":"PRODUCER_SELF_JUDGMENT_OR_STRUCTURAL_PASS_AS_SEMANTIC_PASS"}]},{"unit_code":"A4","qualification_unit_code":"A4Q","title":"Change Impact","objective":"Acreditar impacto directo/indirecto y consumers","checkpoints":[{"code":"A4Q_C1","order":1,"title":"Fuente y autoridad vigente","evidence_class":"ATTESTED_SOURCE_BINDING","required_proof":"Binding CURRENT RELEASED del core SHARED_CHANGE_IMPACT_ANALYSIS","forbidden":"ONLY_MANIFEST_OR_DECLARED_CURRENTNESS"},{"code":"A4Q_C2","order":2,"title":"Salida real gobernada","evidence_class":"REAL_EXECUTION_RECEIPT","required_proof":"Mapa de impacto generado por el agente y refs verificables","forbidden":"FIXTURE_REPLAY_OR_SELF_DECLARED_MODEL_EXECUTION"},{"code":"A4Q_C3","order":3,"title":"Aseguramiento independiente","evidence_class":"INDEPENDENT_REVIEW_OR_CONSUMER_RECEIPT","required_proof":"Juez valida cero omisiones críticas y desconocidos visibles","forbidden":"PRODUCER_SELF_JUDGMENT_OR_STRUCTURAL_PASS_AS_SEMANTIC_PASS"}]},{"unit_code":"A5","qualification_unit_code":"A5Q","title":"Decisiones y ADR","objective":"Acreditar distinción entre autoridad, hechos y decisiones","checkpoints":[{"code":"A5Q_C1","order":1,"title":"Fuente y autoridad vigente","evidence_class":"ATTESTED_SOURCE_BINDING","required_proof":"Políticas CURRENT de ADR/DECISION_CONTEXT_ASOF","forbidden":"ONLY_MANIFEST_OR_DECLARED_CURRENTNESS"},{"code":"A5Q_C2","order":2,"title":"Salida real gobernada","evidence_class":"REAL_EXECUTION_RECEIPT","required_proof":"Decisiones pendientes y decisiones vigentes producidas con refs","forbidden":"FIXTURE_REPLAY_OR_SELF_DECLARED_MODEL_EXECUTION"},{"code":"A5Q_C3","order":3,"title":"Aseguramiento independiente","evidence_class":"INDEPENDENT_REVIEW_OR_CONSUMER_RECEIPT","required_proof":"Independiente rechaza ADR autodecidida y escalamiento innecesario","forbidden":"PRODUCER_SELF_JUDGMENT_OR_STRUCTURAL_PASS_AS_SEMANTIC_PASS"}]},{"unit_code":"A6","qualification_unit_code":"A6Q","title":"Requirements e implementability","objective":"Acreditar IMPLEMENTABILITY_SCHEMA_V1 completo y WHAT separado de HOW","checkpoints":[{"code":"A6Q_C1","order":1,"title":"Fuente y autoridad vigente","evidence_class":"ATTESTED_SOURCE_BINDING","required_proof":"Schema fuente vigente con permisos, estados y efectos exigidos","forbidden":"ONLY_MANIFEST_OR_DECLARED_CURRENTNESS"},{"code":"A6Q_C2","order":2,"title":"Salida real gobernada","evidence_class":"REAL_EXECUTION_RECEIPT","required_proof":"Especificaciones tipadas producidas realmente, bindings y acceptance","forbidden":"FIXTURE_REPLAY_OR_SELF_DECLARED_MODEL_EXECUTION"},{"code":"A6Q_C3","order":3,"title":"Aseguramiento independiente","evidence_class":"INDEPENDENT_REVIEW_OR_CONSUMER_RECEIPT","required_proof":"Juicio independiente no encuentra obligación material omitida ni HOW impuesto","forbidden":"PRODUCER_SELF_JUDGMENT_OR_STRUCTURAL_PASS_AS_SEMANTIC_PASS"}]},{"unit_code":"A7","qualification_unit_code":"A7Q","title":"Invariantes y material fronts","objective":"Acreditar inventario dinámico de frentes materiales","checkpoints":[{"code":"A7Q_C1","order":1,"title":"Fuente y autoridad vigente","evidence_class":"ATTESTED_SOURCE_BINDING","required_proof":"Fuente CURRENT del contrato MATERIAL_FRONT_COVERAGE_V1","forbidden":"ONLY_MANIFEST_OR_DECLARED_CURRENTNESS"},{"code":"A7Q_C2","order":2,"title":"Salida real gobernada","evidence_class":"REAL_EXECUTION_RECEIPT","required_proof":"Cobertura de frentes derivada de impactos, requisitos e incógnitas","forbidden":"FIXTURE_REPLAY_OR_SELF_DECLARED_MODEL_EXECUTION"},{"code":"A7Q_C3","order":3,"title":"Aseguramiento independiente","evidence_class":"INDEPENDENT_REVIEW_OR_CONSUMER_RECEIPT","required_proof":"Juez comprueba cobertura, evidencias de NA/REUSE y frentes BLOCKED","forbidden":"PRODUCER_SELF_JUDGMENT_OR_STRUCTURAL_PASS_AS_SEMANTIC_PASS"}]},{"unit_code":"A8","qualification_unit_code":"A8Q","title":"Stop Rule","objective":"Acreditar que STOP requiere estabilidad y cobertura material","checkpoints":[{"code":"A8Q_C1","order":1,"title":"Fuente y autoridad vigente","evidence_class":"ATTESTED_SOURCE_BINDING","required_proof":"Contrato STOP_RULE_V1 y fronteras de evidencia vigente","forbidden":"ONLY_MANIFEST_OR_DECLARED_CURRENTNESS"},{"code":"A8Q_C2","order":2,"title":"Salida real gobernada","evidence_class":"REAL_EXECUTION_RECEIPT","required_proof":"Decisión STOP/CONTINUE/REQUIRES_DECISION/BLOCKED con trace","forbidden":"FIXTURE_REPLAY_OR_SELF_DECLARED_MODEL_EXECUTION"},{"code":"A8Q_C3","order":3,"title":"Aseguramiento independiente","evidence_class":"INDEPENDENT_REVIEW_OR_CONSUMER_RECEIPT","required_proof":"Control adversarial rechaza STOP prematuro y búsquedas sin gatillo","forbidden":"PRODUCER_SELF_JUDGMENT_OR_STRUCTURAL_PASS_AS_SEMANTIC_PASS"}]},{"unit_code":"A9","qualification_unit_code":"A9Q","title":"Assembly y handoff PG-01","objective":"Acreditar paquete lossless y consumo real exacto por PG-01","checkpoints":[{"code":"A9Q_C1","order":1,"title":"Fuente y autoridad vigente","evidence_class":"ATTESTED_SOURCE_BINDING","required_proof":"Fuentes A9/PG-01 y guard/receipt actuales reconciliados","forbidden":"ONLY_MANIFEST_OR_DECLARED_CURRENTNESS"},{"code":"A9Q_C2","order":2,"title":"Salida real gobernada","evidence_class":"REAL_EXECUTION_RECEIPT","required_proof":"Snapshot real A9 persistido con identidad y huellas verificables","forbidden":"FIXTURE_REPLAY_OR_SELF_DECLARED_MODEL_EXECUTION"},{"code":"A9Q_C3","order":3,"title":"Aseguramiento independiente","evidence_class":"INDEPENDENT_REVIEW_OR_CONSUMER_RECEIPT","required_proof":"PG-01 consume exacto recibo; negativos de drift/bloqueo rechazan","forbidden":"PRODUCER_SELF_JUDGMENT_OR_STRUCTURAL_PASS_AS_SEMANTIC_PASS"}]},{"unit_code":"A10","qualification_unit_code":"A10Q","title":"Campaña histórica de fuego","objective":"Acreditar cobertura heterogénea mediante ejecución real","checkpoints":[{"code":"A10Q_C1","order":1,"title":"Fuente y autoridad vigente","evidence_class":"ATTESTED_SOURCE_BINDING","required_proof":"Corpus y oráculo separados, congelados y versionados","forbidden":"ONLY_MANIFEST_OR_DECLARED_CURRENTNESS"},{"code":"A10Q_C2","order":2,"title":"Salida real gobernada","evidence_class":"REAL_EXECUTION_RECEIPT","required_proof":"Ejecuciones reales heterogéneas con evidencias por caso","forbidden":"FIXTURE_REPLAY_OR_SELF_DECLARED_MODEL_EXECUTION"},{"code":"A10Q_C3","order":3,"title":"Aseguramiento independiente","evidence_class":"INDEPENDENT_REVIEW_OR_CONSUMER_RECEIPT","required_proof":"Auditor independiente comprueba cero omisiones críticas","forbidden":"PRODUCER_SELF_JUDGMENT_OR_STRUCTURAL_PASS_AS_SEMANTIC_PASS"}]},{"unit_code":"A11","qualification_unit_code":"A11Q","title":"Validación adversarial","objective":"Acreditar fail-closed real y no falsos READY","checkpoints":[{"code":"A11Q_C1","order":1,"title":"Fuente y autoridad vigente","evidence_class":"ATTESTED_SOURCE_BINDING","required_proof":"Categorías de fallos y controles negativos versionados","forbidden":"ONLY_MANIFEST_OR_DECLARED_CURRENTNESS"},{"code":"A11Q_C2","order":2,"title":"Salida real gobernada","evidence_class":"REAL_EXECUTION_RECEIPT","required_proof":"Ejecuciones reales adversariales sobre ruta gobernada","forbidden":"FIXTURE_REPLAY_OR_SELF_DECLARED_MODEL_EXECUTION"},{"code":"A11Q_C3","order":3,"title":"Aseguramiento independiente","evidence_class":"INDEPENDENT_REVIEW_OR_CONSUMER_RECEIPT","required_proof":"Auditor verifica cero falsos READY críticos y trazabilidad","forbidden":"PRODUCER_SELF_JUDGMENT_OR_STRUCTURAL_PASS_AS_SEMANTIC_PASS"}]},{"unit_code":"A12","qualification_unit_code":"A12Q","title":"Benchmark comparativo","objective":"Acreditar mejora frente al baseline sin proxy de contrato","checkpoints":[{"code":"A12Q_C1","order":1,"title":"Fuente y autoridad vigente","evidence_class":"ATTESTED_SOURCE_BINDING","required_proof":"Muestra pareada, baseline e indicadores congelados","forbidden":"ONLY_MANIFEST_OR_DECLARED_CURRENTNESS"},{"code":"A12Q_C2","order":2,"title":"Salida real gobernada","evidence_class":"REAL_EXECUTION_RECEIPT","required_proof":"Inferencia real de ambos brazos con latencia y tokens observables","forbidden":"FIXTURE_REPLAY_OR_SELF_DECLARED_MODEL_EXECUTION"},{"code":"A12Q_C3","order":3,"title":"Aseguramiento independiente","evidence_class":"INDEPENDENT_REVIEW_OR_CONSUMER_RECEIPT","required_proof":"Juez independiente calcula calidad, costo y sobreanálisis sin proxies","forbidden":"PRODUCER_SELF_JUDGMENT_OR_STRUCTURAL_PASS_AS_SEMANTIC_PASS"}]},{"unit_code":"A13","qualification_unit_code":"A13Q","title":"Remediación del modelo","objective":"Acreditar corrección generalizable ligada a hallazgo causal","checkpoints":[{"code":"A13Q_C1","order":1,"title":"Fuente y autoridad vigente","evidence_class":"ATTESTED_SOURCE_BINDING","required_proof":"Finding real reproducible y método/candidato congelados","forbidden":"ONLY_MANIFEST_OR_DECLARED_CURRENTNESS"},{"code":"A13Q_C2","order":2,"title":"Salida real gobernada","evidence_class":"REAL_EXECUTION_RECEIPT","required_proof":"Cambio del método no especializado al caso y nueva ejecución","forbidden":"FIXTURE_REPLAY_OR_SELF_DECLARED_MODEL_EXECUTION"},{"code":"A13Q_C3","order":3,"title":"Aseguramiento independiente","evidence_class":"INDEPENDENT_REVIEW_OR_CONSUMER_RECEIPT","required_proof":"Regresión adversarial y semántica confirma mejora sin pérdidas","forbidden":"PRODUCER_SELF_JUDGMENT_OR_STRUCTURAL_PASS_AS_SEMANTIC_PASS"}]},{"unit_code":"A14","qualification_unit_code":"A14Q","title":"Fresh validation independiente","objective":"Acreditar holdout intacto y resultados del modelo real","checkpoints":[{"code":"A14Q_C1","order":1,"title":"Fuente y autoridad vigente","evidence_class":"ATTESTED_SOURCE_BINDING","required_proof":"Holdout/oráculo inmutables separados del productor y currentness","forbidden":"ONLY_MANIFEST_OR_DECLARED_CURRENTNESS"},{"code":"A14Q_C2","order":2,"title":"Salida real gobernada","evidence_class":"REAL_EXECUTION_RECEIPT","required_proof":"Respuestas reales en holdout con identidad del proveedor y costos","forbidden":"FIXTURE_REPLAY_OR_SELF_DECLARED_MODEL_EXECUTION"},{"code":"A14Q_C3","order":3,"title":"Aseguramiento independiente","evidence_class":"INDEPENDENT_REVIEW_OR_CONSUMER_RECEIPT","required_proof":"Juez independiente exige 0 críticos, >=95% clasificación y usabilidad","forbidden":"PRODUCER_SELF_JUDGMENT_OR_STRUCTURAL_PASS_AS_SEMANTIC_PASS"}]},{"unit_code":"A15","qualification_unit_code":"A15Q","title":"Freeze y admisión final","objective":"Acreditar cierre únicamente tras 14 unidades calificadas","checkpoints":[{"code":"A15Q_C1","order":1,"title":"Fuente y autoridad vigente","evidence_class":"ATTESTED_SOURCE_BINDING","required_proof":"Manifiesto de autoridad y recibos exactos A1Q-A14Q","forbidden":"ONLY_MANIFEST_OR_DECLARED_CURRENTNESS"},{"code":"A15Q_C2","order":2,"title":"Salida real gobernada","evidence_class":"REAL_EXECUTION_RECEIPT","required_proof":"Reconciliación Git-Supabase/juez/PG-01 con huellas actuales","forbidden":"FIXTURE_REPLAY_OR_SELF_DECLARED_MODEL_EXECUTION"},{"code":"A15Q_C3","order":3,"title":"Aseguramiento independiente","evidence_class":"INDEPENDENT_REVIEW_OR_CONSUMER_RECEIPT","required_proof":"Aprobación independiente de freeze; no inferirla de DONE documental","forbidden":"PRODUCER_SELF_JUDGMENT_OR_STRUCTURAL_PASS_AS_SEMANTIC_PASS"}]}]'::jsonb;
  v_record jsonb;
  v_checkpoint jsonb;
  v_parent record;
  v_child bigint;
  v_code text;
  v_expected integer := 0;
  v_created integer := 0;
  v_count integer := 0;
  v_meta jsonb;
  v_specs jsonb;
  v_inputs jsonb;
BEGIN
  -- Exact prestate, no blind backfill or parallel registry.
  IF jsonb_array_length(v_catalog) <> 15
     OR (SELECT count(*) FROM programacion.engineering_plan_units u
         JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
         WHERE u.plan_code=v_plan AND u.unit_code ~ '^A([1-9]|1[0-5])$'
           AND u.disposition='ASSIGNED' AND w.status='DONE') <> 15
     OR EXISTS (SELECT 1 FROM programacion.engineering_plan_units u
       JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
       WHERE u.plan_code=v_plan AND u.unit_code ~ '^A([1-9]|1[0-5])$')
     OR EXISTS (SELECT 1 FROM programacion.engineering_plan_units
       WHERE plan_code=v_plan AND unit_code ~ '^A([1-9]|1[0-5])Q$')
     OR EXISTS (SELECT 1 FROM programacion.engineering_work_items
       WHERE work_code ~ '^PA-AN-Q(0[1-9]|1[0-5])$')
  THEN RAISE EXCEPTION 'ANALYSIS_QUALIFICATION_PRESTATE_DRIFT'; END IF;

  FOR v_record IN SELECT item FROM jsonb_array_elements(v_catalog) AS x(item) LOOP
    v_code := v_record->>'unit_code';
    IF (v_record->>'qualification_unit_code') IS DISTINCT FROM v_code||'Q'
       OR jsonb_array_length(v_record->'checkpoints') <> 3
       OR (SELECT count(distinct c->>'code') FROM jsonb_array_elements(v_record->'checkpoints') c) <> 3
    THEN RAISE EXCEPTION 'ANALYSIS_QUALIFICATION_CATALOG_INVALID:%',v_code; END IF;

    SELECT u.id,u.work_item_id,u.lot_from,u.lot_to,u.plan_event_id,w.workstream_id,w.priority,
           w.status,w.work_code,w.source_ref,w.target_domain
    INTO STRICT v_parent
    FROM programacion.engineering_plan_units u
    JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
    WHERE u.plan_code=v_plan AND u.unit_code=v_code
      AND u.disposition='ASSIGNED' AND w.status='DONE'
    FOR UPDATE OF u,w;

    v_specs := '{}'::jsonb;
    v_inputs := '{}'::jsonb;
    FOR v_checkpoint IN SELECT item FROM jsonb_array_elements(v_record->'checkpoints') AS x(item) LOOP
      IF (v_checkpoint->>'code') IS DISTINCT FROM v_code||'Q_C'||(v_checkpoint->>'order')
         OR (v_checkpoint->>'order')::int NOT BETWEEN 1 AND 3
         OR coalesce(v_checkpoint->>'required_proof','')=''
      THEN RAISE EXCEPTION 'ANALYSIS_QUALIFICATION_CHECKPOINT_CONTRACT_INVALID:%',v_code; END IF;
      v_specs := v_specs || jsonb_build_object(v_checkpoint->>'code',
        jsonb_build_object(
          'status','BLOCK_VERIFIED_OPERATIONAL_EVIDENCE_REQUIRED',
          'precision','EXPLICIT_ACTUAL_PROOF_ONLY',
          'action_kind','READBACK_ONCE',
          'recipe_mode','READBACK_EXACT',
          'requires_material_execution',false,
          'expected_evidence_class',v_checkpoint->>'evidence_class',
          'pass_when','VERIFIED_CURRENT_EXTERNAL_RECEIPT_AND_CANONICAL_JUDGE',
          'forbidden',jsonb_build_array(v_checkpoint->>'forbidden','SYNTHETIC_PASS','LEGACY_DONE_AS_OPERATING_PROOF'),
          'target',jsonb_build_object('current_unit',v_code||'Q','legacy_parent',v_code),
          'next_action','BIND_CANONICAL_EXECUTOR_AND_CURRENT_RECEIPT_BEFORE_READY'));
      v_inputs := v_inputs || jsonb_build_object(v_checkpoint->>'code',
        jsonb_build_object(
          'inputs',jsonb_build_object('queries','[]'::jsonb,'db_objects','[]'::jsonb,
                    'assets','[]'::jsonb,'events','[]'::jsonb,'artifacts','[]'::jsonb),
          'expected_result',v_checkpoint->>'required_proof',
          'missing_typed',jsonb_build_array(jsonb_build_object(
               'blocking',true,
               'code','OPERATIONAL_ATTESTED_EVIDENCE_NOT_YET_CAPTURED',
               'required_evidence_class',v_checkpoint->>'evidence_class'))));
    END LOOP;

    v_meta := jsonb_build_object(
      'schema','PROGRAMMING_ANALYSIS_QUALIFICATION_CHILD_V1',
      'phase','OPERATIONAL_QUALIFICATION',
      'legacy_parent_unit_code',v_code,
      'legacy_parent_work_item_id',v_parent.work_item_id,
      'legacy_parent_status_at_creation','DONE',
      'legacy_parent_evidence_not_reused_as_qualification',true,
      'qualifier_state','EVIDENCE_PENDING',
      'scope','ANALYSIS_ONLY',
      'no_parallel_engine',true,
      'operational_ready',false,
      'runtime_activated',false,
      'checkpoint_contracts',v_record->'checkpoints',
      'action_specs_v1',v_specs,
      'source_pack_v2',jsonb_build_object('checkpoint_inputs',v_inputs),
      'source_catalog_ref','docs/programming-agent/ANALYSIS_QUALIFICATION_CHECKPOINT_CATALOG_V1.json');

    INSERT INTO programacion.engineering_work_items(
      work_code,workstream_id,parent_work_item_id,title,objective,expected_result,
      work_type,priority,status,assignee_type,assignee_ref,target_domain,source_ref,
      acceptance_criteria,created_by_execution_id)
    VALUES (
      'PA-AN-Q'||lpad(substring(v_code from 2),2,'0'),
      v_parent.workstream_id,v_parent.work_item_id,
      v_code||'Q — Cualificación operativa de '||v_code,
      v_record->>'objective',
      'Evidence-attested, independently judged Analysis readiness; historical DONE untouched.',
      'QA',v_parent.priority,'BACKLOG','AGENT','SUPER_ADMIN',
      v_parent.target_domain,
      'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/ANALYSIS_QUALIFICATION_CHECKPOINT_CATALOG_V1.json',
      (SELECT jsonb_agg(c->>'required_proof' ORDER BY (c->>'order')::int)
       FROM jsonb_array_elements(v_record->'checkpoints') c),v_actor)
    RETURNING id INTO v_child;

    INSERT INTO programacion.engineering_plan_units(
      plan_code,unit_code,unit_class,lot_code,lot_from,lot_to,
      title,exit_criterion,plan_event_id,work_item_id,
      created_by_execution_id,unit_metadata)
    VALUES (
      v_plan,v_code||'Q','OPERATIONAL_QUALIFICATION','ANALYSIS-QUALIFICATION-V1',
      v_parent.lot_from,v_parent.lot_to,
      v_code||'Q — Cualificación operativa de '||v_code,
      '3 current, real, independently verifiable checkpoint receipts, no false READY',
      v_parent.plan_event_id,v_child,v_actor,v_meta);

    INSERT INTO programacion.engineering_work_dependencies(
      work_item_id,depends_on_work_item_id,relation_type,created_by_execution_id)
    VALUES (v_child,v_parent.work_item_id,'REQUIRES',v_actor);

    INSERT INTO programacion.engineering_work_checkpoints(
      work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
    SELECT v_child,c->>'code',c->>'title',(c->>'order')::int,1.0,true,'PENDING',v_actor
    FROM jsonb_array_elements(v_record->'checkpoints') c
    ORDER BY (c->>'order')::int;
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>3 THEN RAISE EXCEPTION 'ANALYSIS_QUALIFICATION_CHECKPOINT_COUNT_DRIFT:%',v_code; END IF;
    v_expected := v_expected + 3;
    v_created := v_created + 1;

    INSERT INTO programacion.engineering_work_updates(
      work_item_id,update_type,summary,detail,next_action,evidence_refs,
      reported_by,created_by_execution_id)
    VALUES (v_child,'NEXT_STEP','Cualificación operativa separada de cierre documental',
      '3 checkpoints PENDING: fuente actual atestada; ejecución real; aseguramiento independiente.',
      'Bind per-checkpoint governed source/executor/judge evidence before transition',
      jsonb_build_array('PROGRAMMING-ANALYSIS-STAGE-SOURCE-ATTESTATION-GAP-001',
                        'PROGRAMMING-ANALYSIS-A14-EVIDENCE-TIER-FALSE-READY-001'),
      'ANALYSIS_QUALIFICATION_CATALOG',v_actor);
  END LOOP;

  IF v_created<>15 OR v_expected<>45
    OR (SELECT count(*) FROM programacion.engineering_plan_units
      WHERE plan_code=v_plan AND unit_code ~ '^A([1-9]|1[0-5])Q$')<>15
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c
        JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
        WHERE u.plan_code=v_plan AND u.unit_code ~ '^A([1-9]|1[0-5])Q$'
          AND c.status='PENDING' AND c.required)=0
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c
        JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
        WHERE u.plan_code=v_plan AND u.unit_code ~ '^A([1-9]|1[0-5])Q$'
          AND c.status='PENDING' AND c.required)<>45
    OR (SELECT count(*) FROM programacion.engineering_plan_units u
        JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
        WHERE u.plan_code=v_plan AND u.unit_code ~ '^A([1-9]|1[0-5])$'
          AND w.status='DONE')<>15
  THEN RAISE EXCEPTION 'ANALYSIS_QUALIFICATION_POSTSTATE_DIVERGENCE'; END IF;
END;
$analysis_qualification$;
COMMIT;
