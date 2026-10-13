-- IG M10.12 learning, independent EKB-only changeset.
-- One new knowledge entry; no unit/checkpoint/contract/runtime mutation.
-- Supabase MCP remains read-only. Git -> Merge Train -> ledger -> DB readback.
DO $m1012_ekb$
DECLARE
 v_code constant text := 'IG-M1012-VERIFIED-SUITE-NOT-CHECKPOINT-ASSERTION-001';
 v_prior text;
 v_terminal text;
 v_receipt_sha text;
 v_ledger boolean;
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code) THEN
   RAISE EXCEPTION 'M1012_EKB_ENTRY_ALREADY_EXISTS';
 END IF;
 SELECT w.status INTO v_terminal FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
   AND u.unit_code='M10.12';
 IF v_terminal IS DISTINCT FROM 'DONE' THEN
   RAISE EXCEPTION 'M1012_EKB_UNIT_NOT_TERMINAL';
 END IF;
 SELECT c.assertion_receipt_sha256 INTO v_receipt_sha
 FROM programacion.engineering_work_checkpoints c
 WHERE c.work_item_id=198 AND c.checkpoint_code='NEG_CASCADE'
   AND c.status='DONE'
   AND c.assertion_receipt->>'passed'='true'
   AND c.assertion_receipt->>'mode'='EXPLICIT_PASS_WHEN_SUBSET';
 IF v_receipt_sha IS NULL THEN
   RAISE EXCEPTION 'M1012_EKB_ASSERTION_READBACK_MISSING';
 END IF;
 SELECT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
   WHERE name='lf_ig_m1012_conditional_zero_target_closure_v1')
 INTO v_ledger;
 IF NOT v_ledger THEN
   RAISE EXCEPTION 'M1012_EKB_TERMINAL_MIGRATION_NOT_IN_LEDGER';
 END IF;
 INSERT INTO public.lf_error_knowledge
 (id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,
  created_at,updated_at,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref)
 VALUES (
   gen_random_uuid(),v_code,'ENGINEERING_VALIDATION',
   'Suite VERIFIED no sustituye assertion receipt del checkpoint material',
   'En M10.12 CP5 NEG_CASCADE la suite externa IG_M1012_NEG_CASCADE_BOUNDED_V1 tenia bundle VERIFIED y prueba 9/9, pero el primer intento de cierre PR2440 en LF Migration Merge Train fallo atomicamente antes del ledger por ENGINEERING_MATERIAL_ASSERTION_RECEIPT_REQUIRED. Supabase read-only reporto 30% sin avance falso. El guard correcto impidio un falso DONE.',
   'El flujo saltaba el registrador canonico fn_engineering_checkpoint_assertion_record_v1 entre el resultado de RUN_TEST y fn_engineering_checkpoint_transition_v1; el bundle de suite valida el grafo de pruebas, no el contrato material del checkpoint.',
   'TEST_SUITE_VERIFIED -> CP_MATERIAL_DONE sin assertion_receipt ni contract_sha256',
   'Antes de cerrar cualquier checkpoint material: consultar action_spec y assertion_contract READY, derivar el observed exacto de evidencia ejecutada y atada a proveedor, probar rechazo con observed adversarial, registrar recibo con fn_engineering_checkpoint_assertion_record_v1, validar SHA/receipt/currentness, despues usar fn_engineering_checkpoint_transition_v1. Nunca deshabilitar guard ni fabricar PASS. Tras fallo PRE-APPLY por Train corregir el blob Git y repetir solo con evidencia nueva, no por Supabase MCP.',
   'PR #2440: primer run 38442937432 BLOCKED antes de ledger; run de reparacion 38443744441 COMPLETED, migracion 20261013181001 source-ledger coincidente, CP5 DONE con assertion_receipt_sha256 real, M10.12 DONE 100% 6/6 terminal. El oraculo acotado 9/9 NO prueba un DROP real ni habilita runtime.',
   'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','2440',
   'VALIDATED_TESTED',
   'github://cristhianlujan/claude-persona-lf-patch/pull/2440;supabase://programacion.engineering_work_checkpoints/198/NEG_CASCADE;supabase://supabase_migrations.schema_migrations/20261013181001',
   now(),now(),'EXECUTION',ARRAY['ENGINEERING_EXECUTOR','VALIDATOR']::text[],
   'R2_NO_VE','PROCESS_DEPENDENT',
   'M10.12 PAULO-096 engineering conditional zero-target closure; no physical retirement',
   'github://cristhianlujan/claude-persona-lf-patch/pull/2440'
 );
 IF (SELECT COUNT(*) FROM public.lf_error_knowledge WHERE codigo=v_code) IS DISTINCT FROM 1 THEN
   RAISE EXCEPTION 'M1012_EKB_ONE_ROW_READBACK_FAILED';
 END IF;
END
$m1012_ekb$;
