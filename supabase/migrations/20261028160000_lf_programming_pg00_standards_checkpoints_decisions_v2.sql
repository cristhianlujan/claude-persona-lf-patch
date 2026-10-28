-- Fase 2 (Programación): unidad PG-00, 108 checkpoints PENDING de PG-00..PG-20
-- y decisiones D1-D17 aprobadas por Paulo (owner Fase 2), 21-22/10/2026.
-- v2 (28/10/2026): regenerada desde v1 (sha256 0dcd4a6fa1bd86c3e3e47950f36dcd1382623e721548234849e70d542e3fcfc8) con 6 textos actualizados:
--   PG-00_C2 D1-D17 (GO Paulo 28/10); PG-00_C4, PG-11_C2, PG-12_C2 (glosario, plan 22/10); ADR-PROG-STD-015 (infra-terraform subido 21/10).
-- Fuente: plan Fase 2 (base 21/10 + ajustes 22/10) en plan-fase2-programacion-completo-2026-10-27.md sha256 e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874; propuestas C.1/C.2 del 27/10 NO incluidas.
-- Excepción al paso previo por Router (BLOCK_UNSTRUCTURED_MUTATION_INTENT_UNATTESTED, 21/10 y 28/10): GO de Cristhian 28/10, acotada a esta migración.
-- Ruta: Router ACT-0001 -> ACTUALIZACION_DB_LF -> Migration Merge Train. Sin activación runtime ni producción.
BEGIN;
DO $pg00$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_PROGRAMMING_REMEDIATION_V1';
 v_event constant bigint := 20304;
 v_stream constant bigint := 15;
 v_origin constant text := 'MIGRATION_VIA_MERGE_TRAIN_SOURCE_PG00_STD_V2';
 v_work bigint; v_unit bigint;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.lf_eventos WHERE id=v_event AND entidad_tipo='ENGINEERING_PLAN' AND entidad_codigo=v_plan)
 THEN RAISE EXCEPTION 'PG00_PLAN_EVENT_MISMATCH'; END IF;
 IF NOT EXISTS (SELECT 1 FROM programacion.engineering_workstreams WHERE id=v_stream AND stream_code='WS-PROGRAMMING-AGENT-PROGRAMMING-V1')
 THEN RAISE EXCEPTION 'PG00_WORKSTREAM_MISMATCH'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_items WHERE work_code ~ '^PROG-REM-0(0[1-9]|1[0-9]|20)$') <> 20
 THEN RAISE EXCEPTION 'PG00_PG01_PG20_WORK_ITEMS_MISSING'; END IF;
 IF EXISTS (SELECT 1 FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_code='PG-00')
    OR EXISTS (SELECT 1 FROM programacion.engineering_work_items WHERE work_code='PROG-REM-000')
    OR EXISTS (SELECT 1 FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_work_items w ON w.id=c.work_item_id WHERE w.work_code ~ '^PROG-REM-0')
    OR EXISTS (SELECT 1 FROM transversal.decision_log WHERE adr LIKE 'ADR-PROG-STD-%')
 THEN RAISE EXCEPTION 'PG00_DUPLICATE_OR_CONFLICT'; END IF;
 INSERT INTO programacion.engineering_work_items (work_code,workstream_id,title,objective,expected_result,work_type,priority,status,assignee_type,assignee_ref,target_domain,target_component,source_ref,acceptance_criteria,created_by_execution_id)
 VALUES ('PROG-REM-000',v_stream,'Catálogo de estándares técnicos',
  'Reglamento técnico versionado (STD-*), ejecutable por herramientas y legible por el LLM, previo a PG-01..PG-20; no corre por solicitud.',
  'Catálogo, glosario, kit base, skills, linters, waivers, circuito de cambio y política de consumo versionados, con aseguramiento medido.',
  'AGENT_PLATFORM','P0','BACKLOG','AGENT','PROGRAMMING_AGENT','PROGRAMMING_AGENT','PROGRAMMING_STANDARDS_CATALOG','event://20304',
  jsonb_build_array('C1: Cada ítem tiene fuente y métrica (acceso a libertad-financiera obtenido 21/10)', 'C2: Las 17 registradas (decididas 21/10; registro preparado, pendiente del Router y del GO de Cristhian)', 'C3: Catálogo versionado legible por PG-03 y por las skills', 'C4: Glosario versionado y consultable por PG-03 y PG-11; check en sombra con caso negativo; cobertura positiva lista para PG-11', 'C5: El kit crea un esquema vacío que pasa todos los STD-DB', 'C6: Cada skill cita la versión del catálogo', 'C7: Cada STD BLOCK tiene un check que falla con su caso negativo', 'C8: Un waiver de prueba visible para PG-03 y PG-11', 'C9: Circuito probado con un cambio de prueba', 'C10: Informe con tasa de FP y ajustes', 'C11: Tabla y política con versión; esquema listo para el Train'),v_origin)
 RETURNING id INTO v_work;
 INSERT INTO programacion.engineering_plan_units (plan_code,unit_code,unit_class,lot_code,lot_from,lot_to,title,exit_criterion,plan_event_id,work_item_id,created_by_execution_id,unit_metadata)
 VALUES (v_plan,'PG-00','TARGET_MODEL_V1','PG-00',0,0,'Catálogo de estándares técnicos',
  'C1..C11 cerrados con evidencia; catálogo versionado consumible por PG-03, PG-08 y PG-11.',
  v_event,v_work,v_origin,
  jsonb_build_object('phase','STANDARDS','reuse_policy','NO_PARALLEL_ENGINE','runs_per_request',false,'checkpoint_count',11,
   'decision_refs',jsonb_build_array('ADR-PROG-STD-001', 'ADR-PROG-STD-002', 'ADR-PROG-STD-003', 'ADR-PROG-STD-004', 'ADR-PROG-STD-005', 'ADR-PROG-STD-006', 'ADR-PROG-STD-007', 'ADR-PROG-STD-008', 'ADR-PROG-STD-009', 'ADR-PROG-STD-010', 'ADR-PROG-STD-011', 'ADR-PROG-STD-012', 'ADR-PROG-STD-013', 'ADR-PROG-STD-014', 'ADR-PROG-STD-015', 'ADR-PROG-STD-016', 'ADR-PROG-STD-017'),
   'source_doc_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874','supersedes_package_sha256','0dcd4a6fa1bd86c3e3e47950f36dcd1382623e721548234849e70d542e3fcfc8','router_exception','GO Cristhian 2026-10-28; Router BLOCK_UNSTRUCTURED_MUTATION_INTENT_UNATTESTED 21/10 y 28/10','runtime_activation',false,'production_activation',false))
 RETURNING id INTO v_unit;
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-00_C1','Inventario: reglas vigentes, convenciones medidas, stack real (incluye leer libertad-financiera)',1,1,true,'PENDING',v_origin),
  ('PG-00_C2','Decisiones D1–D17 registradas como ADR en transversal.decision_log (donde programming-agent/docs/DECISIONS.md ubica las decisiones canónicas; programacion.human_decisions exige una ejecución y un head_sha, así que queda para los GO ligados a una corrida)',2,1,true,'PENDING',v_origin),
  ('PG-00_C3','Catálogo STD-* publicado en transversal y en el repo, con versión y digest, en dos formatos: legible por herramientas y para el LLM con ejemplos OK/NO',3,1,true,'PENDING',v_origin),
  ('PG-00_C4','Glosario base ES→EN (solo términos de semántica estable: status, amount, currency, user…) en transversal + glosario por proyecto (L3; LF primero). Cada término con term_id, forma canónica, formas rechazadas, formas heredadas atadas a contratos concretos, contextos, ejemplos OK/NO, fuentes y decision_ref. Precedencia de nombres: contrato existente > glosario del proyecto > glosario base > propuesta (REQUIRES_DECISION)',4,1,true,'PENDING',v_origin),
  ('PG-00_C5','Kit base de proyecto: tablas comunes en inglés (errores con los técnicos mínimos de D2, ocurrencias, mensajes, auditoría, navegación, legal_documents, consents), trigger de updated_at y consultas de soporte, como migraciones del stack',5,1,true,'PENDING',v_origin),
  ('PG-00_C6','Skills por stack (Spring, Next.js, Postgres/Flyway; Supabase y Python para la plataforma) que cargan el catálogo en su versión fijada, sin copiarlo',6,1,true,'PENDING',v_origin),
  ('PG-00_C7','Configuración de linters por repo, la misma para CI y agente; primero en sombra y luego bloqueando sobre el diff',7,1,true,'PENDING',v_origin),
  ('PG-00_C8','Waivers: aprobador, caducidad, registro e id citable',8,1,true,'PENDING',v_origin),
  ('PG-00_C9','Circuito de cambio del catálogo: hallazgo → propuesta → GO → versión nueva; los cambios de seguridad invalidan el pin de versión',9,1,true,'PENDING',v_origin),
  ('PG-00_C10','Aseguramiento: aplicar el catálogo a código existente y medir falsos positivos',10,1,true,'PENDING',v_origin),
  ('PG-00_C11','Consumo (D16/D17): tabla de precios por modelo y política de optimización, versionadas; esquema del registro de consumo',11,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-000';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-00_C1','Cada ítem tiene fuente y métrica (acceso a libertad-financiera obtenido 21/10)', 'PG-00_C2','Las 17 registradas (decididas 21/10; registro preparado, pendiente del Router y del GO de Cristhian)', 'PG-00_C3','Catálogo versionado legible por PG-03 y por las skills', 'PG-00_C4','Glosario versionado y consultable por PG-03 y PG-11; check en sombra con caso negativo; cobertura positiva lista para PG-11', 'PG-00_C5','El kit crea un esquema vacío que pasa todos los STD-DB', 'PG-00_C6','Cada skill cita la versión del catálogo', 'PG-00_C7','Cada STD BLOCK tiene un check que falla con su caso negativo', 'PG-00_C8','Un waiver de prueba visible para PG-03 y PG-11', 'PG-00_C9','Circuito probado con un cambio de prueba', 'PG-00_C10','Informe con tasa de FP y ajustes', 'PG-00_C11','Tabla y política con versión; esquema listo para el Train'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-00' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-01_C1','Contrato receptor alineado con el productor (schema digest d2e347ef…)',1,1,true,'PENDING',v_origin),
  ('PG-01_C2','Resolver el context_id exacto y recomputar context_sha256',2,1,true,'PENDING',v_origin),
  ('PG-01_C3','Validar material paths y la matriz scope-frente; solo admite scopes READY con frente limpio',3,1,true,'PENDING',v_origin),
  ('PG-01_C4','Fijar el marco técnico con versión: (1) standards_catalog_version; (2) el perfil técnico del proyecto (manifiesto de reglas L3 tipo B en el repo destino, con su huella; el contenido se resuelve en el esquema del proyecto, nunca lf_ops por defecto); (3) el mecanismo de control del repo destino (Train + PASE en la plataforma LF; CI + Flyway + pipeline en el producto); (4) el perfil de arquitectura del proyecto (D15: repo + commit exacto); además el modo de optimización y el presupuesto del pedido (D17). No toca las reglas tipo A: vienen en el paquete',4,1,true,'PENDING',v_origin),
  ('PG-01_C5','8 negativos dan BLOCK; cero redescubrimiento con el mismo fingerprint',5,1,true,'PENDING',v_origin),
  ('PG-01_C6','Recibo PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1 persistido y releído; un positivo real',6,1,true,'PENDING',v_origin),
  ('PG-01_C7','Suficiencia para Programación (movido desde PG-03·C6): el paquete trae lo que el reglamento exige y el agente no puede inventar: textos de mensajes, códigos de error, eventos de navegación, respuesta sobre historial y consentimientos aplicables. Si falta algo → MISSING, vuelve a la Fase 1 en la puerta',7,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-001';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-01_C1','Los digests coinciden o la diferencia queda registrada', 'PG-01_C2','Readback igual al recibo', 'PG-01_C3','Admisión por scope con motivo', 'PG-01_C4','Los cuatro, más modo y presupuesto, quedan en el recibo; sin manifiesto ni perfil de arquitectura vigentes → BLOCK', 'PG-01_C5','Tabla de negativos', 'PG-01_C6','Nivel PG01_CONSUMED_AND_RECONCILED. Depende de la Fase 1 (los 3 snapshots existentes no son admisibles)', 'PG-01_C7','0 huecos o retorno a la Fase 1 antes de planificar'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-01' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-02_C1','Tabla automática: granularidad (A2) + frentes (A7) + capas del stack destino → dominios STD activos por scope. Ej.: frente UI_VISUAL → STD-FE, NAV, MSG; DATA_CONTRACT → DB y pregunta de historial (AUD-02); API_CONTRACT → API, SEC; PERMISSION → SEC',1,1,true,'PENDING',v_origin),
  ('PG-02_C2','Prohibido reclasificar: se usan A2 y A7 tal cual',2,1,true,'PENDING',v_origin),
  ('PG-02_C3','Paquete ambiguo o contradictorio → CONTRADICTION, vuelve a la Fase 1 (no se pregunta a una persona ni se adivina)',3,1,true,'PENDING',v_origin),
  ('PG-02_C4','Determinismo: el mismo paquete produce siempre la misma tabla',4,1,true,'PENDING',v_origin),
  ('PG-02_C5','Aseguramiento independiente sobre una muestra',5,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-002';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-02_C1','Tabla versionada y dominios activos por scope', 'PG-02_C2','0 reclasificaciones', 'PG-02_C3','Negativo probado', 'PG-02_C4','Repetición idéntica', 'PG-02_C5','Veredicto'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-02' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-03_C1','Resolver el stack real del repo destino desde fuentes verificables (pom.xml, package.json, lockfiles, versiones); nunca suponerlo',1,1,true,'PENDING',v_origin),
  ('PG-03_C2','Armar el conjunto de reglas del pedido: catálogo L1+L2 de los dominios activos + perfil técnico del proyecto (tipo B, fijado en PG-01) + reglas del paquete (tipo A, applicable_rules[]/applicable_invariants[], tal cual); resolver choques con la precedencia de 1.5; seleccionar las skills de forma determinista (stack + matriz de PG-02). Si se sospecha una regla de negocio no citada, no se aplica ni se busca: MISSING → vuelve a la Fase 1',2,1,true,'PENDING',v_origin),
  ('PG-03_C3','Estrategia de implementación y de partición según los criterios originales, con CAPABILITY_SELECTOR, razones, alternativas consideradas y fallback',3,1,true,'PENDING',v_origin),
  ('PG-03_C4','La evaluación de reutilización de la Fase 1 (capacidades y activos a reusar, REUSE_AS_IS) es vinculante; PG-03 solo decide la reutilización técnica (qué clase, componente o módulo extender) antes de construir',4,1,true,'PENDING',v_origin),
  ('PG-03_C5','Decisiones técnicas por dominio activo, contrato primero (STD-API-06): esquema y migraciones, contrato de API, estructura de servicios y frontend; si el proyecto es nuevo, instanciar el kit base',5,1,true,'PENDING',v_origin),
  ('PG-03_C6','Usa el resultado de suficiencia de PG-01·C7. Si al diseñar aparece un faltante nuevo, se trata como MATERIAL_NEW_QUESTION con resolver tipado o vuelve a la Fase 1; nunca se inventa',6,1,true,'PENDING',v_origin),
  ('PG-03_C7','Desviaciones del estándar solo con waiver; reglas citadas con pendiente_decision = true que afecten el cambio → REQUIRES_DECISION',7,1,true,'PENDING',v_origin),
  ('PG-03_C8','Handoff a PG-04: estrategia de partición + STD + skills + contratos',8,1,true,'PENDING',v_origin),
  ('PG-03_C9','Aseguramiento: revisor independiente sobre una muestra',9,1,true,'PENDING',v_origin),
  ('PG-03_C10','Conformidad con el perfil de arquitectura (D15): cada pieza se ubica en su unidad desplegable y módulo; declara qué recursos de infraestructura necesita (o ninguno, D14). Servicio, unidad o patrón fuera del perfil → REQUIRES_DECISION con propuesta de ADR',10,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-003';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-03_C1','stack_profile con fuentes', 'PG-03_C2','STD, reglas del proyecto y skills aplicables con versión; 0 reglas tipo A agregadas por el agente', 'PG-03_C3','Estrategia explicada y trazable', 'PG-03_C4','Reutilización técnica registrada; 0 contradicciones con la del paquete', 'PG-03_C5','Borradores de contrato conformes', 'PG-03_C6','0 faltantes inventados', 'PG-03_C7','0 desviaciones sin waiver', 'PG-03_C8','Paquete completo', 'PG-03_C9','Veredicto con evidencia', 'PG-03_C10','Ubicación y recursos declarados; 0 desvíos sin decisión'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-03' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-04_C1','Base: contrato de partición del PR #1912 + núcleo extraído de J02, rehecho sobre main actual; sin motor paralelo',1,1,true,'PENDING',v_origin),
  ('PG-04_C2','Partición por solución (cambio más pequeño, coherente y válido; puede abarcar FE/BE/BD) según la estrategia de PG-03; primero por significado, luego dependencias y riesgo; nunca solo por número de archivos o tokens',2,1,true,'PENDING',v_origin),
  ('PG-04_C3','Cobertura 100 % de requisitos y obligaciones de aceptación; 0 huérfanos, 0 dueños duplicados; dependencias entre lotes explícitas; contratos compartidos referenciados, no copiados',3,1,true,'PENDING',v_origin),
  ('PG-04_C4','Usa implementation_state del paquete, sin volver a determinarlo. EXISTING: solo el delta. NEW: sin duplicar autoridades compartidas (Shell, Design System, decisiones de reutilización) por lote',4,1,true,'PENDING',v_origin),
  ('PG-04_C5','Definition of done por lote: los STD y checks que debe pasar',5,1,true,'PENDING',v_origin),
  ('PG-04_C6','Vuelta desde PG-07 cuando un lote excede el presupuesto de contexto: se reparte de nuevo (arista de reparación, no ciclo)',6,1,true,'PENDING',v_origin),
  ('PG-04_C7','Aseguramiento independiente de la cobertura',7,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-004';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-04_C1','Fuente reutilizada y trazada', 'PG-04_C2','Cada lote cita la estrategia', 'PG-04_C3','Trazabilidad bidireccional al 100 %', 'PG-04_C4','Sin reconstrucción ni duplicados', 'PG-04_C5','Cada lote con su lista de checks', 'PG-04_C6','Caso de prueba de reparto', 'PG-04_C7','0 huérfanos'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-04' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-05_C1','Toma repo_full_name y base_head_sha del paquete (target_binding; inferirlos está prohibido) y crea la rama lf/prog-<work_code>/<slug>',1,1,true,'PENDING',v_origin),
  ('PG-05_C2','Write-scope por solución (paths y objetos de BD derivados del lote, carpeta correcta según la estructura L3); lo compartido entre soluciones es de solo lectura por defecto',2,1,true,'PENDING',v_origin),
  ('PG-05_C3','Lock y detección de choques entre writers; dos lotes en paralelo solo sin choque material sin resolver',3,1,true,'PENDING',v_origin),
  ('PG-05_C4','Negativos: escribir fuera de scope da BLOCK; el desvío bloquea solo la solución afectada',4,1,true,'PENDING',v_origin),
  ('PG-05_C5','Aseguramiento independiente',5,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-005';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-05_C1','Base del paquete + rama registradas', 'PG-05_C2','Allowlist por solución', 'PG-05_C3','Prueba de choque → BLOCK', 'PG-05_C4','Probado', 'PG-05_C5','Veredicto'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-05' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-06_C1','Reutiliza la decisión de vigencia de PG-01; solo vuelve a evaluarla con un motivo tipado (SOURCE_DRIFT, STALE); nunca re-enlaza a mitad de ejecución (mid_execution_rebind_forbidden)',1,1,true,'PENDING',v_origin),
  ('PG-06_C2','Toolchain y entorno disponibles en las versiones del catálogo (V1: Maven/JDK, pnpm/Node, docker compose con PostgreSQL 17 + Floci); si falta, BLOCKED_TOOL_UNAVAILABLE *(PRV-TOOL-004)*',2,1,true,'PENDING',v_origin),
  ('PG-06_C3','La obligación de reversibilidad viene del paquete (frentes MIGRATION_CUTOVER / ROLLBACK_RECOVERY de A7); PG-06 arma el plan técnico (migración reversible, expand/contract)',3,1,true,'PENDING',v_origin),
  ('PG-06_C4','Línea base: build + lint del target sin cambios; se registran las violaciones previas',4,1,true,'PENDING',v_origin),
  ('PG-06_C5','Aseguramiento independiente',5,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-006';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-06_C1','Decisión de PG-01 citada o revalidación con motivo', 'PG-06_C2','Versiones registradas', 'PG-06_C3','Plan de rollback ligado al frente del paquete', 'PG-06_C4','Línea base con digest', 'PG-06_C5','Veredicto'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-06' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-07_C1','Constructor = Worker v0.8 con proveedor y modelo fijados por corrida; el ejecutor por carriles corre los lotes en paralelo según las reglas de PG-05; cada llamada registra tokens de entrada, salida y caché y su costo (D16)',1,1,true,'PENDING',v_origin),
  ('PG-07_C2','Tarea por lote generada con fn_agent_task_worker_spec: objetivo, referencias, write-scope, comandos de aceptación y referencia al oráculo oculto (fuera del repo)',2,1,true,'PENDING',v_origin),
  ('PG-07_C3','Presupuesto de contexto (CONTEXT_BUDGET_GOVERNANCE): proyección por tarea con las referencias materiales obligatorias; nunca repo completo ni spec completo; nunca truncar contexto material; si no cabe → repartir en PG-04 o traer la referencia exacta bajo demanda; límite según el perfil del modelo, nunca fijo; el contexto estable (reglamento, perfil técnico, paquete) va en caché entre lotes (D17)',3,1,true,'PENDING',v_origin),
  ('PG-07_C4','Contrato primero (STD-API-06); skills y STD con ejemplos OK/NO en el contexto; formateadores antes de entregar el patch',4,1,true,'PENDING',v_origin),
  ('PG-07_C5','Cada iteración explicable y ligada al objetivo; si hay que cambiar objetivo, aceptación o scope → PG-10, nunca en silencio',5,1,true,'PENDING',v_origin),
  ('PG-07_C6','Evidencia por lote: recibo sellado del Worker (diff, inputs, STD aplicados)',6,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-007';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-07_C1','Runtime e identidad de modelo registrados; consumo por llamada en el recibo', 'PG-07_C2','Tarea fijada con hash', 'PG-07_C3','Recibo de presupuesto sin truncamiento; tasa de acierto de caché registrada', 'PG-07_C4','Diff formateado y contrato antes que el código', 'PG-07_C5','0 redefiniciones silenciosas', 'PG-07_C6','Paquete para PG-12'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-07' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-08_C1','Build/compilación (V1: ./mvnw verify, pnpm build)',1,1,true,'PENDING',v_origin),
  ('PG-08_C2','Formato + lint (incluye nombres) sobre el diff, con la configuración del CI',2,1,true,'PENDING',v_origin),
  ('PG-08_C3','Typecheck (tsc strict, javac, mypy en la plataforma)',3,1,true,'PENDING',v_origin),
  ('PG-08_C4','Unitarias focales + smoke; migraciones Flyway contra el PostgreSQL local (apply/rollback/reapply, *PRV-SQL-001*)',4,1,true,'PENDING',v_origin),
  ('PG-08_C5','Lint de contratos: Spectral sobre OpenAPI, oasdiff (breaking), lint de catálogo de la BD migrada',5,1,true,'PENDING',v_origin),
  ('PG-08_C6','Recibos de cada check con herramienta, versión, digest de configuración y SHA; marcados como feedback, no veredicto',6,1,true,'PENDING',v_origin),
  ('PG-08_C7','Fronteras de arquitectura (D15): pruebas que verifican que los módulos solo se usan por su API pública o eventos (LF: Spring Modulith verify() / ArchUnit)',7,1,true,'PENDING',v_origin),
  ('PG-08_C8','IaC y contenedores (D14, STD-IAC/CONT): terraform fmt/validate, lint de IaC, plan/apply contra Floci; build de imágenes y docker compose up con healthchecks verdes',8,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-008';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-08_C1','PASS con versión de herramienta', 'PG-08_C2','0 BLOCK nuevos frente a la línea base', 'PG-08_C3','PASS', 'PG-08_C4','PASS', 'PG-08_C5','0 BLOCK', 'PG-08_C6','Recibos completos', 'PG-08_C7','PASS', 'PG-08_C8','PASS sin tocar la nube'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-08' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-09_C1','Límites de iteración y costo por lote y presupuesto por pedido medido con consumo real (D16/D17): aviso al 80 %, REQUIRES_DECISION al 100 %; reutiliza el límite de intentos del Worker',1,1,true,'PENDING',v_origin),
  ('PG-09_C2','Convergencia: una iteración repetida sin evidencia nueva ni reducción de findings se detiene y se reclasifica',2,1,true,'PENDING',v_origin),
  ('PG-09_C3','Prohibido desactivar reglas, agregar supresiones sin waiver o borrar tests para pasar',3,1,true,'PENDING',v_origin),
  ('PG-09_C4','Escalamiento tipado: RETURN o BLOCKED con diagnóstico',4,1,true,'PENDING',v_origin),
  ('PG-09_C5','Aseguramiento con casos de bucle adversariales',5,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-009';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-09_C1','Política fijada; prueba de presupuesto agotado → se detiene sin recortar calidad', 'PG-09_C2','Detector probado', 'PG-09_C3','Negativo → BLOCK', 'PG-09_C4','Salida tipada', 'PG-09_C5','Veredicto'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-09' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-10_C1','Detección de conflictos requisito ↔ estándar ↔ contrato existente ↔ REUSE_AS_IS del spec',1,1,true,'PENDING',v_origin),
  ('PG-10_C2','Precedencia de 1.5; nunca renombrar legado sin migración aprobada',2,1,true,'PENDING',v_origin),
  ('PG-10_C3','Ruteo: solo va a una persona la decisión verdaderamente humana; una decisión técnica → PG-03; falta de implementación → no es pregunta. Un hueco de evidencia o de requisito no se investiga aquí: con motivo tipado y resolver tipado se consulta lo exacto; si es investigación de requisito → vuelve a la Fase 1 (A3). Antes de preguntar se reutiliza una decisión vigente; prohibido preguntar dos veces',3,1,true,'PENDING',v_origin),
  ('PG-10_C4','Paquete de decisión (PROGRAMMING_HUMAN_DECISION_PACKET_V1): pregunta, opciones, recomendación, riesgo de no decidir, referencias y condición de reanudación; al resolverse se reanuda solo el scope afectado y lo demás READY sigue',4,1,true,'PENDING',v_origin),
  ('PG-10_C5','Aseguramiento con negativos',5,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-010';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-10_C1','Conflicto tipado', 'PG-10_C2','Decisión trazable', 'PG-10_C3','0 preguntas duplicadas o evitables; 0 investigaciones sin motivo', 'PG-10_C4','Reanudación parcial probada', 'PG-10_C5','Veredicto'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-10' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-11_C1','0 archivos fuera de scope; 0 residuos (debug, código muerto, TODO sin ticket); dependencias y compatibilidad preservadas',1,1,true,'PENDING',v_origin),
  ('PG-11_C2','Rúbrica: nombres semánticos e idioma según glosario (STD-GEN-01); códigos de catálogo literales (STD-GEN-07); textos no inventados (STD-MSG-02); consistencia con el módulo vecino; cobertura positiva del glosario: cada identificador de dominio nuevo cita sus term_id y se verifica sí/no que existan y coincidan',2,1,true,'PENDING',v_origin),
  ('PG-11_C3','Toda supresión tiene waiver válido (STD-GEN-05)',3,1,true,'PENDING',v_origin),
  ('PG-11_C4','Trazabilidad diff ↔ requisito ↔ lote',4,1,true,'PENDING',v_origin),
  ('PG-11_C5','El revisor es distinto del constructor',5,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-011';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-11_C1','Checklist PASS', 'PG-11_C2','Checklist del catálogo', 'PG-11_C3','0 sin waiver', 'PG-11_C4','100 %', 'PG-11_C5','Identidades distintas registradas'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-11' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-12_C1','Base SHA, SHA/tree del candidato, digest del diff, paths y objetos cambiados, builder',1,1,true,'PENDING',v_origin),
  ('PG-12_C2','Inputs: context_id, versión del catálogo, versiones de skills, stack_profile, proveedor/modelo, foto de la EKB, versiones de toolchain y digest de la configuración de linters; consumo total y por etapa (tokens, caché, costo, gasto desperdiciado) y modo de optimización usado; registro de consultas extra (cada una con su motivo tipado y su resolver); mapa identificador → term_id de los identificadores de dominio nuevos',2,1,true,'PENDING',v_origin),
  ('PG-12_C3','Resultados de checks de PG-08 y PG-11 enlazados',3,1,true,'PENDING',v_origin),
  ('PG-12_C4','Persistido y releído',4,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-012';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-12_C1','Manifest', 'PG-12_C2','Inputs completos', 'PG-12_C3','Enlaces resolubles', 'PG-12_C4','Readback igual; identidad reconstruible sin inferencias'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-12' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-13_C1','Congelar el SHA exacto',1,1,true,'PENDING',v_origin),
  ('PG-13_C2','Reproducibilidad: un rebuild desde el SHA da los mismos digests (o la diferencia queda documentada)',2,1,true,'PENDING',v_origin),
  ('PG-13_C3','Negativo: intento de mutar da BLOCK',3,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-013';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-13_C1','Inmutable', 'PG-13_C2','Comparación', 'PG-13_C3','Probado'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-13' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-14_C1','Conforme al modo EXECUTION de testing_admission_contract_v1',1,1,true,'PENDING',v_origin),
  ('PG-14_C2','Incluye versión del catálogo, obligaciones de prueba del spec (en LF: *B2B-RULE-TEST-001*), contrato de pruebas a ciegas (fn_submit_blind_test_contract) y lista de textos "pendiente de copy"',2,1,true,'PENDING',v_origin),
  ('PG-14_C3','Testing admite o bloquea, con readback',3,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-014';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-14_C1','frozen_candidate_ref/sha256', 'PG-14_C2','Paquete completo', 'PG-14_C3','Recibo de Testing'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-14' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-15_C1','Findings tipados (incluye violaciones de estándar) → candidato N+1 con nuevo SHA; lo que dependía de N se invalida',1,1,true,'PENDING',v_origin),
  ('PG-15_C2','Trazabilidad finding → cambio',2,1,true,'PENDING',v_origin),
  ('PG-15_C3','Se re-ejecutan todos los checks sobre N+1, no solo los que fallaron',3,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-015';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-15_C1','N intacto; dependientes invalidados', 'PG-15_C2','100 %', 'PG-15_C3','Recibos nuevos'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-15' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-16_C1','Dos corpus versionados: A. Método (cambios de programación reales de LF, ~30; independiente del stack) y B. Stack (hitos M0–M4 del plan del producto + comportamientos de LF reescritos como pruebas de caja negra)',1,1,true,'PENDING',v_origin),
  ('PG-16_C2','Métricas comparables, incluida la tasa de violaciones de estándar en código nuevo y de waivers pedidos',2,1,true,'PENDING',v_origin),
  ('PG-16_C3','Oráculo ciego',3,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-016';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-16_C1','Ambos corpus versionados', 'PG-16_C2','Informe y findings persistidos', 'PG-16_C3','Veredicto'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-16' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-17_C1','Desvío de scope, base stale, choque de writers, cambio de contrato silencioso, reparación superficial, bucle improductivo, contaminación del candidato, reinvestigar sin motivo tipado',1,1,true,'PENDING',v_origin),
  ('PG-17_C2','Adversarial de estándares y de spec: pedido de columna FechaPago, legado en conflicto, intento de desactivar el linter, idiomas mezclados, fetch a mano, spec sin texto de un mensaje (debe detenerse, no inventar)',2,1,true,'PENDING',v_origin),
  ('PG-17_C3','Aseguramiento independiente',3,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-017';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-17_C1','Todos BLOCK o estado correcto', 'PG-17_C2','Todos detectados', 'PG-17_C3','Veredicto; 0 false-ready críticos'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-17' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-18_C1','Línea base de cómo se programa hoy sobre las mismas tareas del corpus B (persona o GPT)',1,1,true,'PENDING',v_origin),
  ('PG-18_C2','Calidad, conformidad con estándares, tamaño de lote, iteraciones improductivas, fuera de scope, tiempo y costo, con costo medido en tokens y dinero por pedido (D16); evaluar si conviene activar el modelo según dificultad (D17·5)',2,1,true,'PENDING',v_origin),
  ('PG-18_C3','Reproducibilidad',3,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-018';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-18_C1','Baseline', 'PG-18_C2','Comparación con trade-offs visibles', 'PG-18_C3','Re-ejecución igual'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-18' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-19_C1','Disposición de cada finding: corregir, waiver o descartar con razón',1,1,true,'PENDING',v_origin),
  ('PG-19_C2','Cambios generales al modelo, no parches puntuales; si el estándar estaba mal, nueva versión de PG-00 (circuito C9)',2,1,true,'PENDING',v_origin),
  ('PG-19_C3','Regresión',3,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-019';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-19_C1','0 sin disposición', 'PG-19_C2','Changelog', 'PG-19_C3','PASS'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-19' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO programacion.engineering_work_checkpoints (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 SELECT w.id, x.code, x.title, x.seq, x.weight, x.req, x.status, x.origin FROM programacion.engineering_work_items w,
 (VALUES
  ('PG-20_C1','Muestra fresca no usada antes, ejecutada en el repo oficial por el camino normal (PR, CI, revisión); tamaño de muestra y evaluador ciego fijados antes de correr',1,1,true,'PENDING',v_origin),
  ('PG-20_C2','Gates originales: 0 scope drift material, 0 mutaciones de candidato congelado, 0 redefiniciones silenciosas, 0 false-ready críticos, identidad reproducible, ≥95 % de acierto de estrategia; más los nuestros: 0 violaciones BLOCK nuevas y 0 supresiones sin waiver; consumo por pedido dentro del presupuesto fijado tras PG-16',2,1,true,'PENDING',v_origin),
  ('PG-20_C3','Freeze del modelo V1 junto con la versión del catálogo y de las skills',3,1,true,'PENDING',v_origin),
  ('PG-20_C4','Aseguramiento independiente',4,1,true,'PENDING',v_origin)) AS x(code,title,seq,weight,req,status,origin)
 WHERE w.work_code='PROG-REM-020';
 UPDATE programacion.engineering_plan_units SET unit_metadata = coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object('checkpoint_exit_criteria', jsonb_build_object('PG-20_C1','Muestra sellada', 'PG-20_C2','Todos en PASS', 'PG-20_C3','Versión registrada', 'PG-20_C4','Veredicto'), 'checkpoint_source_sha256','e70b9fe3cc81c384e53756a24e91f6927354103e8c9217848bb53a96f9369874')
 WHERE plan_code=v_plan AND unit_code='PG-20' AND NOT (coalesce(unit_metadata,'{}'::jsonb) ? 'checkpoint_exit_criteria');
 INSERT INTO transversal.decision_log (adr,titulo,decision,razon,impacto,estado) VALUES
  ('ADR-PROG-STD-001','Formato de error: REG_TEC_003 (envelope {success,data,error,meta}, VIGENTE) frente al plan M1 del producto (ProblemDetail, RFC 9457)','(b) para proyectos nuevos: nativo de Spring 6, estándar de la industria, admite varios errores por campo. LF no cambia','Decidido por Paulo, owner de la Fase 2 (OK Decidido B como defecto L2, Paulo 21/10 (LF mantiene REG_TEC_003)). Fuente: plan Fase 2 sha256 0514e0071b73.','Estándar por defecto del catálogo del agente de Programación (L1/L2); las reglas propias de cada proyecto (L3) prevalecen según la precedencia del plan.','vigente'),
  ('ADR-PROG-STD-002','Códigos de error. Los códigos los crea la Fase 1 en el catálogo del proyecto; el agente no los inventa','(1) Relación en BD por error_id numérico + código de texto único. (2) La API expone el código de texto y el trace_code, nunca el id interno. (3) Si falta un error en el spec → REQUIRES_DECISION. (4) El kit base trae errores técnicos mínimos (interno, servicio no disponible, timeout, datos inválidos, sin permiso, no encontrado); su texto visible es de la Fase 1 y, mientras falte, queda marcado "pendiente de copy", lo que bloquea producción','Decidido por Paulo, owner de la Fase 2 (OK Decidido, Paulo 21/10). Fuente: plan Fase 2 sha256 0514e0071b73.','Estándar por defecto del catálogo del agente de Programación (L1/L2); las reglas propias de cada proyecto (L3) prevalecen según la precedencia del plan.','vigente'),
  ('ADR-PROG-STD-003','Mayúsculas en campos JSON de la API','snake_case en request, response, path y query params: Supabase lo devuelve así de forma nativa, coincide con las reglas de LF y en Spring es una línea de configuración (Jackson SNAKE_CASE). En TypeScript, los tipos generados de la API conservan snake_case; las variables propias del frontend siguen en camelCase','Decidido por Paulo, owner de la Fase 2 (OK Decidido (a) snake_case, Paulo 21/10). Fuente: plan Fase 2 sha256 0514e0071b73.','Estándar por defecto del catálogo del agente de Programación (L1/L2); las reglas propias de cada proyecto (L3) prevalecen según la precedencia del plan.','vigente'),
  ('ADR-PROG-STD-004','Idioma de los identificadores (tablas, columnas, variables, funciones, rutas). No aplica al copy visible (Fase 1, en español) ni a los códigos de catálogo (literales)','Inglés: predomina en columnas y en lo más nuevo (lf_client 100 % inglés; created_at/updated_at 100 %), coincide con frameworks y evita tildes y ñ. El glosario de PG-00 fija una sola traducción por término (deuda → debt) y PG-11 lo verifica','Decidido por Paulo, owner de la Fase 2 (OK Decidido (a) inglés + glosario, Paulo 21/10). Fuente: plan Fase 2 sha256 0514e0071b73.','Estándar por defecto del catálogo del agente de Programación (L1/L2); las reglas propias de cada proyecto (L3) prevalecen según la precedencia del plan.','vigente'),
  ('ADR-PROG-STD-005','PK de tablas nuevas','id bigint generated always as identity; UUID solo si el id se expone fuera o se relaciona con auth.users. FK <entidad>_id (payments.debt_id)','Decidido por Paulo, owner de la Fase 2 (OK Decidido, Paulo 21/10). Fuente: plan Fase 2 sha256 0514e0071b73.','Estándar por defecto del catálogo del agente de Programación (L1/L2); las reglas propias de cada proyecto (L3) prevalecen según la precedencia del plan.','vigente'),
  ('ADR-PROG-STD-006','Nombres de constraints e índices','Siempre el nombre por defecto de Postgres (debts_pkey, payments_debt_id_fkey, payments_debt_id_idx); sin prefijos propios','Decidido por Paulo, owner de la Fase 2 (OK Decidido, Paulo 21/10). Fuente: plan Fase 2 sha256 0514e0071b73.','Estándar por defecto del catálogo del agente de Programación (L1/L2); las reglas propias de cada proyecto (L3) prevalecen según la precedencia del plan.','vigente'),
  ('ADR-PROG-STD-007','Nombres de funciones','Esquemas de proyecto: <verbo>_<objeto>_vN sin prefijo (saly.get_debt_summary_v1). Plataforma LF: lf_…_vN','Decidido por Paulo, owner de la Fase 2 (OK Decidido, Paulo 21/10). Fuente: plan Fase 2 sha256 0514e0071b73.','Estándar por defecto del catálogo del agente de Programación (L1/L2); las reglas propias de cada proyecto (L3) prevalecen según la precedencia del plan.','vigente'),
  ('ADR-PROG-STD-008','Header de idempotencia','Idempotency-Key en proyectos nuevos; LF mantiene X-Idempotency-Key','Decidido por Paulo, owner de la Fase 2 (OK Decidido, Paulo 21/10). Fuente: plan Fase 2 sha256 0514e0071b73.','Estándar por defecto del catálogo del agente de Programación (L1/L2); las reglas propias de cada proyecto (L3) prevalecen según la precedencia del plan.','vigente'),
  ('ADR-PROG-STD-009','request_id y correlation_id','Dos conceptos: X-Request-Id por petición HTTP y X-Correlation-Id de punta a punta (FE, BE, auditoría, navegación); ambos se devuelven y se guardan en logs y auditoría','Decidido por Paulo, owner de la Fase 2 (OK Decidido, Paulo 21/10). Fuente: plan Fase 2 sha256 0514e0071b73.','Estándar por defecto del catálogo del agente de Programación (L1/L2); las reglas propias de cada proyecto (L3) prevalecen según la precedencia del plan.','vigente'),
  ('ADR-PROG-STD-010','Montos','API: "amount": "1650.00", "currency": "PEN"; BD: numeric(18,2); nunca float','Decidido por Paulo, owner de la Fase 2 (OK Decidido, Paulo 21/10). Fuente: plan Fase 2 sha256 0514e0071b73.','Estándar por defecto del catálogo del agente de Programación (L1/L2); las reglas propias de cada proyecto (L3) prevalecen según la precedencia del plan.','vigente'),
  ('ADR-PROG-STD-011','Linters en CI','En cada repo: modo sombra y luego bloqueo solo sobre código nuevo o modificado. TS: ESLint + Prettier + tsc; Python: ruff + mypy; Postgres: lint de catálogo con SQL sobre la BD migrada; Spectral cuando haya OpenAPI. En claude-persona-lf-patch: admitir antes la ruta del workflow en PASE y pasar por el Train','Decidido por Paulo, owner de la Fase 2 (OK Decidido, Paulo 21/10). Fuente: plan Fase 2 sha256 0514e0071b73.','Estándar por defecto del catálogo del agente de Programación (L1/L2); las reglas propias de cada proyecto (L3) prevalecen según la precedencia del plan.','vigente'),
  ('ADR-PROG-STD-012','¿Se muestra un código al usuario? REG_ACC_002 (VIGENTE) prohíbe "códigos de error" en mensajes visibles; B2B-RULE-ERROR-003 (VIGENTE) exige mostrar trace_code','(b): el código técnico (LF_OTP_EXPIRADO) nunca se muestra; el de referencia ("Código para soporte: LF-20261021-AB12CD34") sí, porque es lo que permite rastrear el caso','Decidido por Paulo, owner de la Fase 2 (OK (b) como defecto; en LF es un conflicto interno de sus reglas, pendiente para Cristhian. Mostrar o no el código lo decide el spec de Fase 1; el agente garantiza que el trace_code exista y viaje en la respuesta). Fuente: plan Fase 2 sha256 0514e0071b73.','Estándar por defecto del catálogo del agente de Programación (L1/L2); las reglas propias de cada proyecto (L3) prevalecen según la precedencia del plan.','vigente'),
  ('ADR-PROG-STD-013','Stack con el que se califica la V1 del agente','(b). Calificación primero en el entorno local del plan (docker compose: PostgreSQL 17 + Floci que emula AWS) y después en QA de AWS. STD-BE se activa; STD-SB queda solo para proyectos con backend Supabase (como la plataforma LF)','Decidido por Paulo, owner de la Fase 2 (OK Decidido (b), Paulo 21/10 15:40 (reemplaza la elección previa de Supabase)). Fuente: plan Fase 2 sha256 0514e0071b73.','Estándar por defecto del catálogo del agente de Programación (L1/L2); las reglas propias de cada proyecto (L3) prevalecen según la precedencia del plan.','vigente'),
  ('ADR-PROG-STD-014','Infraestructura como código: qué escribe la Fase 2 y qué la Fase 4','(b). Si una pieza necesita un recurso (cola, bucket, secreto, evento), su IaC va en el mismo PR y se valida contra el emulador local. Red, cómputo, borde, identidad, entornos, secretos reales y promoción son de la Fase 4. El agente nunca aplica en la nube. Para LF ya está escrito así en infra-terraform/FLOCI-A-AWS.md (módulo app-resources igual en Floci y AWS)','Decidido por Paulo, owner de la Fase 2 (OK Decidido (b), Paulo 21/10 17:44). Fuente: plan Fase 2 sha256 0514e0071b73.','Estándar por defecto del catálogo del agente de Programación (L1/L2); las reglas propias de cada proyecto (L3) prevalecen según la precedencia del plan.','vigente'),
  ('ADR-PROG-STD-015','Perfil de arquitectura del proyecto (estilo de software, unidades desplegables, arquitectura de nube, Docker, comunicación)','(b). Es por proyecto, no del catálogo del agente. Cada proyecto declara su perfil con referencia exacta (repo + commit). Sin perfil vigente → REQUIRES_DECISION antes de programar. Salirse del perfil (servicio nuevo, unidad desplegable nueva, otro patrón de comunicación) → decisión humana + ADR, nunca en silencio. LF: paulozterra/lf-architecture@bbe718c (monolito modular Core + Payments + Workers; ECS Fargate ARM64, RDS, S3, EventBridge/SQS, Cognito, CloudFront) e paulozterra/paulozterra-infra-terraform (subido 21/10)','Decidido por Paulo, owner de la Fase 2 (OK Decidido (b), Paulo 21/10 17:44). Fuente: plan Fase 2 sha256 0514e0071b73.','Estándar por defecto del catálogo del agente de Programación (L1/L2); las reglas propias de cada proyecto (L3) prevalecen según la precedencia del plan.','vigente'),
  ('ADR-PROG-STD-016','Medición del consumo (tokens y costo del agente)','Siempre activa. Cada llamada al modelo registra tokens de entrada, de salida y de caché (lectura y escritura), modelo y costo calculado con una tabla de precios versionada. Se agrega por lote, por pedido y por etapa (planificar, construir, reintentos, dudas, reparación) y se separa el gasto útil del desperdiciado (intentos fallidos, rehacer por paquete vencido o por hallazgo). Hoy el Worker v0.8 ya registra entrada y salida por intento; falta caché y un registro persistente (Supabase vía Train)','Decidido por Paulo, owner de la Fase 2 (OK Pedido por Paulo, 22/10). Fuente: plan Fase 2 sha256 0514e0071b73.','Estándar por defecto del catálogo del agente de Programación (L1/L2); las reglas propias de cada proyecto (L3) prevalecen según la precedencia del plan.','vigente'),
  ('ADR-PROG-STD-017','Modo de optimización del consumo','Se elige por pedido y nunca relaja un control (reglamento, revisiones y pruebas iguales en cualquier modo). Palancas: (1) caché del contexto estable (reglamento, perfil técnico, paquete de Fase 1); (2) contexto mínimo (CONTEXT_BUDGET_GOVERNANCE); (3) no redescubrir; (4) freno temprano (PG-09); (5) modelo según dificultad del lote, apagado en V1 hasta que PG-18 demuestre que no baja la calidad. Presupuesto por pedido: aviso al 80 %, al 100 % REQUIRES_DECISION; nunca se recorta calidad para entrar en presupuesto. Montos POR DEFINIR con datos de PG-16','Decidido por Paulo, owner de la Fase 2 (OK Pedido por Paulo, 22/10). Fuente: plan Fase 2 sha256 0514e0071b73.','Estándar por defecto del catálogo del agente de Programación (L1/L2); las reglas propias de cada proyecto (L3) prevalecen según la precedencia del plan.','vigente');
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_work_items w ON w.id=c.work_item_id
     WHERE w.work_code ~ '^PROG-REM-0' AND c.status='PENDING' AND c.required AND c.created_by_execution_id=v_origin) <> 108
   OR (SELECT count(*) FROM programacion.engineering_plan_units WHERE id=v_unit AND work_item_id=v_work AND plan_event_id=v_event) <> 1
   OR (SELECT count(*) FROM programacion.engineering_plan_units WHERE plan_code=v_plan AND unit_metadata ? 'checkpoint_exit_criteria') <> 21
   OR (SELECT count(*) FROM transversal.decision_log WHERE adr LIKE 'ADR-PROG-STD-%') <> 17
 THEN RAISE EXCEPTION 'PG00_READBACK_FAILED'; END IF;
END;
$pg00$;
COMMIT;
