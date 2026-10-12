-- IG M9.10 EKB prevention: no durable release candidate prerequisite for sandbox.
-- Append-only methodology learning; no change to checkpoint, capability registry or runtime.
DO $m910_ekb$
BEGIN
 IF NOT EXISTS (
  SELECT 1 FROM programacion.engineering_plan_units u
  JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  AND u.unit_code='M9.10' AND w.status='DONE'
 ) OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c
       JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
       WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND u.unit_code='M9.10'
       AND c.status='DONE')<>5
 THEN RAISE EXCEPTION 'M910_EKB_PRECONDITION_NOT_CLOSED'; END IF;
 IF EXISTS (SELECT 1 FROM public.lf_capability_version_registry
            WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.1')
 THEN RAISE EXCEPTION 'M910_EKB_UNEXPECTED_DURABLE_CANDIDATE'; END IF;
 INSERT INTO transversal.error_knowledge(
   codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,evidencia,
   source_ref,lote_origen,estado,lifecycle_phase,consumer_role)
 SELECT
 'IG-M910-SANDBOX-PERMANENT-CANDIDATE-FALSE-PREREQUISITE-001',
 'ENGINEERING_CONTRACT_PREFLIGHT',
 'Version candidata permanente no es prerrequisito de una prueba reversible de sandbox',
 'M9.10 se bloqueo al buscar una version persistente 1.0.1 de INPUT_GOVERNANCE. Para el criterio de salida de ingenieria (drill sandbox-only), registrar una version RELEASED permanente habria ampliado la autoridad sin necesidad. El bloqueador no correspondia a la naturaleza de la prueba. Se reutilizo promotor versionado con version transaccional, cohorte activa obtenida de datos gobernados y ROLLBACK por cohorte, sin registrar una release operativa ni fabricar recibos live.',
 'Preflight confundio posibilidad de probar el mecanismo de versionado con necesidad de publicar una nueva version autentica del servicio en el registry. La inexistencia de candidata duradera fue clasificada como bloqueo operacional aunque contrato y gobernanza exigian solo calificacion reversible.',
 'Antes de exigir una version permanente: clasificar SANDBOX_DRILL frente a RUNTIME_CUTOVER. Para SANDBOX_DRILL, usar fixture candidata transaccional derivada de manifiesto vigente y contexto gobernado, pasar promotor canonico positivo y negativo, restaurar puntero EXACTO con ROLLBACK y comprobar cero residuos. No atribuir equivalencia funcional ni habilitacion productiva a esa prueba. Si se pide admision operativa, candidato real, recibos firmados y revision independiente continuan obligatorios. Reusar controles previos y no repetir pruebas de M9.9 sin drift.',
 'Control positivo M9.10: 7/7 cohortes activas desde datos, version transitoria insertada en SQL con ROLLBACK, 7 promociones reales observadas, 7 negativas BLOCK_CURRENTNESS_MISMATCH, 7 reversiones por promotor y 7 rollback exactos. Control adversarial CP4: version transitoria detectada como delta +1 y despues 0; historia intacta (253 runs, 11891 assessments join run_id, 62 bindings, registro IG 1/1). CP5 readback PASS; bootstrap M9.10 DONE 100% 5/5, blockers=0; live gate sigue BLOCKED. Prohibido declarar prueba funcional runtime.',
 'Git CP2 PR2284 / main f026aafaa3a05bbe019b123c452c72b7991c602e; CP3 PR2285 / main 3475939639dcfaf25850e395e2ab9c3c38b1f3b2; CP4 PR2286 / main 02c1429682d24f3dd2975a1ff4d6bd6f1179547e; EKB relacionado IG-EKB-READ-WITHOUT-SEMANTIC-PREFLIGHT-001',
 'programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.10',
 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.10',
 'VERIFICADO','METHODOLOGY_REPAIR',ARRAY['Architect','Builder','Judge','Auditor']::text[]
 WHERE NOT EXISTS(SELECT 1 FROM transversal.error_knowledge
                  WHERE codigo='IG-M910-SANDBOX-PERMANENT-CANDIDATE-FALSE-PREREQUISITE-001');
END $m910_ekb$;
