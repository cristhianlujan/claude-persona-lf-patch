-- LF Router ACT-0001 future architecture wave; plan-only, no runtime or Router mutation.
-- Governed source-first migration, not a new router/engine.
BEGIN;
DO $router_architecture_wave$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_stream_code constant text := 'WS-LF-ROUTER-ARCHITECTURE-WAVE-V1';
  v_origin constant text := 'MIGRATION_VIA_MERGE_TRAIN_LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_repo constant text := 'cristhianlujan/claude-persona-lf-patch';
  v_doc constant text := 'docs/programming-agent/LF_ROUTER_ARCHITECTURE_WAVE_V1.md';
  v_catalog jsonb := '[{"code":"RW1-01","work":"ROUTER-W1-01","name":"Necesidades y aceptación futura","kind":"ARCHITECTURE_RESEARCH","objective":"Definir resultados observables de derivación, aclaración, multiobjeto, simulación y extensibilidad sin asumir el cableado actual.","outcome":"Matriz congelada de necesidades actuales/futuras con oráculos de aceptación, riesgos, negativos y caso desconocido.","c1":"Recuperar necesidades, EKB, A16Q_C1 y fuente vigente; declarar supuestos y sesgos de selección sin repetir el inventario.","c2":"Construir una matriz trazable de necesidades y escenarios positivos, negativos, exploratorios, multiobjeto y futuros, con expected behavior independiente del sistema actual.","c3":"Crítica independiente de cobertura y sesgos: refutar omisiones y evitar sobreajuste a las once pruebas iniciales.","exit":"Matriz de necesidades completa y adversarial, oráculos versionados, ningún requisito derivado de un bloqueo observado por sí solo."},{"code":"RW1-02","work":"ROUTER-W1-02","name":"Competencia de arquitecturas","kind":"ARCHITECTURE_RESEARCH","objective":"Comparar críticamente por lo menos tres diseños, entre ellos Router mínimo con especialista semántico, Router con clasificación mínima y derivación compuesta, sin imponer uno de antemano.","outcome":"ADR comparativa con medidas de simplicidad, continuidad, seguridad, extensibilidad, rendimiento, fallos y compatibilidad de consumidores.","c1":"Releer únicamente inventario y restricciones necesarios; identificar tres alternativas reales y sus premisas falsables.","c2":"Ejecutar evaluación homogénea de alternativas sobre la matriz RW1-01, incluyendo solicitudes nunca usadas para diseñarlas y coste de nuevas capacidades.","c3":"Crítico adversarial independiente selecciona o rechaza arquitectura con falsificadores, omisiones y costes; ninguna aprobación por consenso.","exit":"Arquitectura elegida mediante evidencia comparativa y falsificadores, no por conservar código ni por complacer una propuesta previa."},{"code":"RW1-03","work":"ROUTER-W1-03","name":"Contrato y estrategia de transición","kind":"ARCHITECTURE_DESIGN","objective":"Congelar separación entre derivación, intención transportada y autorización, junto con interfaces y migración compatible solo cuando la compatibilidad sea legítima.","outcome":"Contrato versionado de entrada/salida, roles, composición, aclaraciones, autoridad, errores y plan de transición/reversión.","c1":"Precisar contratos de superficie, consumidores, permisos y EKB estrictamente afectados por la arquitectura ganadora; reutilizar mapeo A16Q.","c2":"Especificar ABI, contexto mínimo y handoff íntegro, responsabilidad de aclarar, seguridad pre-efecto, compatibilidad y migración/corte sin doble Router.","c3":"Revisión independiente de contrato con falsificadores de ruptura de Train, prompts sintéticos, restricciones negativas, fuentes obsoletas y consumidores legacy.","exit":"Contrato firmado por pruebas de consistencia, transición sin callejón circular de Train ni permiso de escritura inferido de discovery."},{"code":"RW1-04","work":"ROUTER-W1-04","name":"Refactor transversal del núcleo ACT-0001","kind":"SYSTEM_IMPLEMENTATION","objective":"Implementar únicamente los cambios transversales justificados por RW1-01..03, sin regex por caso, segundo Router, parches laterales o activación no autorizada.","outcome":"PRs gobernados del contrato/router mínimo más suite reusable; fuente versionada, recibos CI/PASE/Train y readback cuando haya DB.","c1":"Congelar head/ledger/source SHA y regresiones; desglosar diffs mínimos necesarios de arquitectura sin cambiarla para acomodar tests.","c2":"Aplicar implementación por operaciones canónicas y migraciones exactas; prueba positiva/negativa a nivel contrato y rollback.","c3":"Contraste independiente de diseño vs código, comportamiento invariante de seguridad, alcance y no-regresión bajo fuente actual.","exit":"El código reproduce el contrato objetivo, CI/PASE/Train/readback comprobados donde correspondan, sin claims de C2 E2E ajenos."},{"code":"RW1-05","work":"ROUTER-W1-05","name":"Consumidores y recorrido extremo a extremo","kind":"SYSTEM_INTEGRATION","objective":"Asegurar derivación real a responsables y operación gobernada sin confundir adición de ruta con permisos de efectos.","outcome":"Trazas reales Router→especialista→operación→evidencia para modos representativos y canarios de continuidad, incluyendo Train.","c1":"Releer consumidores realmente aplicables y A16Q_C2; comprobar qué contratos y receipts faltan tras el refactor, sin duplicar inventario.","c2":"Integrar y ejecutar rutas reales con conservación del texto/hash, scopes positivos/negativos, consumidores atestados y efecto autorizado o sin efecto según modo.","c3":"Verificación independiente de no-bypass, doble objeto, ausencia de preguntas redundantes, Train reserva/aplica/cierra y permisos de read-only.","exit":"Consumidores y Train acreditados end-to-end con identificadores/RAW/readback del mismo request; no PASS por simulación o receipt aislado."},{"code":"RW1-06","work":"ROUTER-W1-06","name":"Validación independiente y decisión de cierre","kind":"INDEPENDENT_ASSURANCE","objective":"Decidir con evidencia si la arquitectura satisface necesidades presentes y futuras, permite avance y no rompe seguridad, sin GOLDEN automático.","outcome":"Informe adversarial, métricas de continuidad/derivación y seguridad, matriz de hallazgos, condiciones de cierre y disposición gobernada.","c1":"Congelar versión exacta, corpus independiente/holdouts y umbrales de fallo antes de evaluar, preservando separación del implementador.","c2":"Ejecutar corpus funcional, nuevos tipos y modos, preguntas, negativos de autorización, regresiones de consumidores y mediciones de overhead completas.","c3":"Juez independiente contrasta resultados, EKB, recibos y desviaciones; PASS/FAIL/GAP explícito sin promoción por declaración.","exit":"Todos los checkpoints acreditados con evidencia real y decisión independiente; si hay defectos, reparación causal transversal y nueva prueba específica, no campañas indefinidas."}]'::jsonb;
  v_event_id bigint;
  v_stream_id bigint;
  v_work_id bigint;
  v_unit_id bigint;
  v_previous_work_id bigint;
  v_related_a16q bigint;
  v_record jsonb;
  v_no integer := 0;
  v_code text;
  v_work_code text;
  v_c1 text;
  v_c2 text;
  v_c3 text;
  v_now timestamptz := clock_timestamp();
BEGIN
  IF (SELECT count(*) FROM programacion.engineering_plan_units
      WHERE plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND unit_code='A16Q') <> 1
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE checkpoint_code='A16Q_C1' AND status='DONE') <> 1
  THEN RAISE EXCEPTION 'ROUTER_WAVE_A16Q_REFERENCE_UNVERIFIED'; END IF;
  SELECT w.id INTO STRICT v_related_a16q
  FROM programacion.engineering_work_items w
  JOIN programacion.engineering_plan_units u ON u.work_item_id=w.id
  WHERE u.plan_code='PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1' AND u.unit_code='A16Q';
  IF EXISTS(SELECT 1 FROM programacion.engineering_plan_units WHERE plan_code=v_plan)
     OR EXISTS(SELECT 1 FROM programacion.engineering_workstreams WHERE stream_code=v_stream_code)
     OR EXISTS(SELECT 1 FROM public.lf_eventos WHERE entidad_tipo='ENGINEERING_PLAN' AND entidad_codigo=v_plan)
     OR EXISTS(SELECT 1 FROM programacion.engineering_work_items WHERE work_code LIKE 'ROUTER-W1-%')
     OR EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints WHERE checkpoint_code LIKE 'RW1-%')
  THEN RAISE EXCEPTION 'ROUTER_WAVE_DUPLICATE_OR_PARTIAL_CONFLICT'; END IF;
  IF jsonb_array_length(v_catalog) <> 6
     OR (SELECT count(DISTINCT obj->>'code') FROM jsonb_array_elements(v_catalog) AS arr(obj)) <> 6
  THEN RAISE EXCEPTION 'ROUTER_WAVE_INVALID_CATALOG'; END IF;

  INSERT INTO public.lf_eventos(
      evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,
      payload,origen,created_by_execution_id
  ) VALUES (
      'PLAN_SNAPSHOT_DETALLADO','ENGINEERING_PLAN',v_plan,
      'Ola de arquitectura futura ACT-0001: 6 unidades/18 checkpoints PENDING, sin ejecución ni aceptación declarada.','INFO',
      jsonb_build_object(
          'evidence_schema_version','operational-event/v2',
          'producer','LF_MIGRATION_MERGE_TRAIN',
          'purpose','Register the canonical six-unit wave for future LF Router architecture with independent C1/C2/C3 and no premature acceptance.',
          'execution_id',v_origin,
          'occurred_at',to_char(v_now at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
          'acceptance_declared',false,
          'plan_code',v_plan,
          'unit_count',6,'checkpoint_count',18,'phase','PLANNED_NOT_EXECUTED',
          'source_ref','github://' || v_repo || '/' || v_doc,
          'existing_a16q_reference','PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1/A16Q',
          'no_runtime_activation',true,'no_production_activation',true
      ),
      'GOVERNED_MIGRATION_SOURCE_FIRST',v_origin
  ) RETURNING id INTO v_event_id;

  INSERT INTO programacion.engineering_workstreams(
      stream_code,name,objective,owner_ref,status,source_ref,created_by_execution_id
  ) VALUES (
      v_stream_code,'ACT-0001 — OLA 01 Arquitectura futura',
      'Decidir e implementar la arquitectura futura de Router LF por necesidades y evidencia, no por cableado heredado, sin duplicar A16Q.',
      'SUPER_ADMIN','ACTIVE','event://' || v_event_id,v_origin
  ) RETURNING id INTO v_stream_id;

  FOR v_record IN SELECT value FROM jsonb_array_elements(v_catalog) AS x(value)
  LOOP
      v_no := v_no+1;
      v_code := v_record->>'code';
      v_work_code := v_record->>'work';
      IF v_code IS DISTINCT FROM 'RW1-' || lpad(v_no::text,2,'0')
          OR v_work_code IS DISTINCT FROM 'ROUTER-W1-' || lpad(v_no::text,2,'0')
      THEN RAISE EXCEPTION 'ROUTER_WAVE_SEQUENCE_OR_IDENTITY_INVALID:%',v_no; END IF;
      IF coalesce(length(v_record->>'c1'),0)<35 OR coalesce(length(v_record->>'c2'),0)<35 OR coalesce(length(v_record->>'c3'),0)<35
      THEN RAISE EXCEPTION 'ROUTER_WAVE_UNVERIFIABLE_CHECKPOINT_CONTRACT:%',v_code; END IF;

      INSERT INTO programacion.engineering_work_items(
          work_code,workstream_id,title,objective,expected_result,
          work_type,priority,status,assignee_type,assignee_ref,
          target_repo,target_domain,target_component,source_ref,
          acceptance_criteria,created_by_execution_id
      ) VALUES(
          v_work_code,v_stream_id,v_code || ' — ' || (v_record->>'name'),
          v_record->>'objective',v_record->>'outcome',
          CASE WHEN v_no IN (1,2,3) THEN 'ARCHITECTURE'
               WHEN v_no=4 THEN 'BACKEND' WHEN v_no=5 THEN 'INTEGRATION'
               ELSE 'QA' END,
          'P0','BACKLOG','AGENT','SUPER_ADMIN',v_repo,
          'LF','ACT-0001','event://' || v_event_id,
          jsonb_build_array(v_record->>'c1',v_record->>'c2',v_record->>'c3',v_record->>'exit'),
          v_origin
      ) RETURNING id INTO v_work_id;

      v_c1:=v_code||'_C1'; v_c2:=v_code||'_C2'; v_c3:=v_code||'_C3';
      INSERT INTO programacion.engineering_plan_units(
          plan_code,unit_code,unit_class,lot_code,lot_from,lot_to,title,
          exit_criterion,plan_event_id,work_item_id,created_by_execution_id,unit_metadata
      ) VALUES(
          v_plan,v_code,v_record->>'kind','ACT0001-FUTURE-WAVE-01',v_no,v_no,
          v_code || ' — ' || (v_record->>'name'),v_record->>'exit',
          v_event_id,v_work_id,v_origin,
          jsonb_build_object(
              'schema','LF_ROUTER_ARCHITECTURE_WAVE_UNIT_V1',
              'scope','LF_ROUTER_ACT0001_ONLY','phase','PLANNED_NOT_EXECUTED',
              'unit_index',v_no,'checkpoint_count',3,
              'requires_future_action_spec_v3',true,'requires_future_source_pack_v2',true,
              'independent_review_required',true,
              'source_prior_a16q_c1','PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1/A16Q/A16Q_C1',
              'not_duplicate_of_a16q',true,
              'runtime_activation',false,'production_activation',false,'golden_promoted',false,
              'checkpoint_contracts',jsonb_build_object(
                v_c1,jsonb_build_object('expected',v_record->>'c1','evidence_class','VERIFIED_CURRENT_SOURCE',
                    'negative_controls',jsonb_build_array('missing_source','stale_source','cross_project')),
                v_c2,jsonb_build_object('expected',v_record->>'c2','evidence_class','TASK_RELEVANT_MATERIAL_EVIDENCE',
                    'negative_controls',jsonb_build_array('fixture_only','self_attested_completion','missing_producer')),
                v_c3,jsonb_build_object('expected',v_record->>'c3','evidence_class','INDEPENDENT_ADVERSARIAL_REVIEW',
                    'negative_controls',jsonb_build_array('same_producer_review','missing_negative_case','unsupported_PASS'))
              ),
              'exit_criterion',v_record->>'exit'
          )
      ) RETURNING id INTO v_unit_id;

      INSERT INTO programacion.engineering_work_checkpoints(
          work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id
      ) VALUES
          (v_work_id,v_c1,'C1 — Fuentes y autoridad',1,1,true,'PENDING',v_origin),
          (v_work_id,v_c2,'C2 — Resultado y evidencia material',2,1,true,'PENDING',v_origin),
          (v_work_id,v_c3,'C3 — Crítica y aseguramiento independiente',3,1,true,'PENDING',v_origin);

      IF v_previous_work_id IS NULL THEN
          INSERT INTO programacion.engineering_work_dependencies(work_item_id,depends_on_work_item_id,relation_type,created_by_execution_id)
          VALUES(v_work_id,v_related_a16q,'RELATED',v_origin);
      ELSE
          INSERT INTO programacion.engineering_work_dependencies(work_item_id,depends_on_work_item_id,relation_type,created_by_execution_id)
          VALUES(v_work_id,v_previous_work_id,'REQUIRES',v_origin);
      END IF;
      v_previous_work_id:=v_work_id;
  END LOOP;

  IF v_no<>6
     OR (SELECT count(*) FROM programacion.engineering_plan_units WHERE plan_code=v_plan)<>6
     OR (SELECT count(*) FROM programacion.engineering_work_items WHERE workstream_id=v_stream_id AND status='BACKLOG')<>6
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c
          JOIN programacion.engineering_work_items w ON c.work_item_id=w.id WHERE w.workstream_id=v_stream_id AND c.required AND c.status='PENDING')<>18
     OR (SELECT count(*) FROM programacion.engineering_work_dependencies d
          JOIN programacion.engineering_work_items w ON w.id=d.work_item_id WHERE w.workstream_id=v_stream_id AND d.relation_type='REQUIRES')<>5
     OR (SELECT count(*) FROM programacion.engineering_work_dependencies d
          JOIN programacion.engineering_work_items w ON w.id=d.work_item_id WHERE w.workstream_id=v_stream_id AND d.relation_type='RELATED' AND d.depends_on_work_item_id=v_related_a16q)<>1
     OR EXISTS (SELECT 1 FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND
             (unit_metadata->>'runtime_activation')::boolean IS DISTINCT FROM false)
  THEN RAISE EXCEPTION 'ROUTER_WAVE_EXACT_READBACK_FAILED'; END IF;
END;
$router_architecture_wave$;
COMMIT;
