-- IG M8.11 EKB lessons, source first. No runtime/policies/IG checkpoint modification.
-- Existing EKB records are augmented, not recreated. New codes are deduplicated on canonical table.
DO $pre$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM programacion.engineering_plan_units pu WHERE pu.id=67
    AND pu.unit_code='M8.11'
    AND pu.unit_metadata#>>'{performance_regression_defer_v1,obligation_status}'='OPEN_DEFERRED_NOT_PASSED')
 THEN RAISE EXCEPTION 'M811_EKB_PREFLIGHT_NO_DEFERRED_DECISION'; END IF;
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=255 AND status='DONE')<>4
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=255 AND status='NOT_APPLICABLE')<>1
 THEN RAISE EXCEPTION 'M811_EKB_PREFLIGHT_CHECKPOINT_STATE_DRIFT'; END IF;
 IF (SELECT count(*) FROM transversal.error_knowledge WHERE codigo IN
     ('IG-CROSS-WORKSTREAM-POST-PASE-BLEED-001','ENGINEERING-BLOCKER-DUAL-SCOPE-REPAIR-001'))<>2
 THEN RAISE EXCEPTION 'M811_EKB_PREFLIGHT_EXISTING_LESSONS_MISSING'; END IF;
END $pre$;

INSERT INTO transversal.error_knowledge(
 codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,
 consumer_role,root_cause_family,detectability,source_context,source_ref
) VALUES
('IG-M811-P95-RELATIVE-BASELINE-DEFERRED-001','INPUT_GOVERNANCE','El gate absoluto de p95 no sustituye la regresion relativa sin baseline comparable','M8.11 exigia rechazo automatico de regresion relativa frente a M8.10, mientras M8.10 difirio el benchmark formal hasta despues del primer despliegue. SentinelX ejecuto caso positivo p95=26010ms, caso absoluto 150001ms correctamente rechazado, y caso regresivo 32512ms (+25% diagnostico) aceptado. El test M8.11 termino con exit code 1. El cierre previo a despliegue separa la obligacion relativa abierta del SLO absoluto vigente.','Desalineacion simultanea del criterio de salida M8.11 y la gobernanza temporal del benchmark M8.10; se asumio un baseline relativo y una tolerancia que no estaban autorizados.','ABSOLUTE_SLO_CONFUSED_WITH_RELATIVE_P95_GATE','Antes de exigir regresion relativa, comprobar baseline comparable por cohorte y SHA de release, tolerancia numerica aprobada y prueba positiva+negativa real. Si el owner ha diferido la medicion, corregir contrato y gobernanza en un mismo lote, marcar el checkpoint NOT_APPLICABLE solo con autoridad, mantener la obligacion OPEN_DEFERRED_NOT_PASSED y nunca reemplazar la prueba por un PASS ficticio.','Comprobacion real SentinelX ENG_M8_11_REGRESSION_GATE_NEGATIVE exit=1; +25% es mutacion diagnostica NO umbral. PR2129 merge 5db2c75d7b9ede82ba7bc54cfd3a5c224c4d8197; M8.11 100% con 4 DONE + 1 NOT_APPLICABLE y 0 bloqueos; deuda relativa sigue OPEN_DEFERRED_NOT_PASSED y limite absoluto 150000ms intacto.','HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','2128,2129','ACTIVO','github://cristhianlujan/claude-persona-lf-patch/pull/2128;github://cristhianlujan/claude-persona-lf-patch/pull/2129;supabase://programacion.engineering_plan_units/M8.11#performance_regression_defer_v1','EXECUTION',ARRAY['ENGINEERING_EXECUTOR','ENGINEERING_SCHEDULER','INPUT_GOVERNANCE']::text[],'R4_NO_CUESTIONA','LOUD_EARLY','IG_CURATOR_VALIDATOR_REFACTOR_V2/M8.11 REGRESSION_GATE_NEGATIVE','github://cristhianlujan/claude-persona-lf-patch/pull/2128;github://cristhianlujan/claude-persona-lf-patch/pull/2129'),
('IG-M811-NEGATIVE-TEST-FAIL-NOT-PASS-001','ENGINEERING_GOVERNANCE','Un test adversarial que evidencia ausencia del gate no autoriza cierre como PASS','El test adversarial de M8.11 devolvio exit code 1 y demostro falta de deteccion relativa. Los resultados de un diagnostico negativo y de una prueba de admision del checkpoint tienen semantica distinta. No se debe registrar asercion PASSED por haber detectado un defecto, ni promover un test con exit code distinto de cero.','Confusion entre exito investigativo de encontrar un defecto y exito operativo de un gate; un resultado FAIL se podia malinterpretar como prueba superada.','ADVERSARIAL_DIAGNOSTIC_FAIL_PROMOTED_TO_CLOSURE_RISK','Separar salida del runner y estado del checkpoint. El resultado de un runner con exit!=0 debe conservarse como diagnostico real y excluirse de recibos de PASS. La decision owner puede declarar NOT_APPLICABLE por diferimiento con evidencia trazable, no cambiar el resultado observado del test. La obligacion no probada sigue abierta.','PR2128 runner real en SentinelX: test_exit_code=1, test_passed=false, adversarial_case_executed=true; PR2129 aprobacion de diferimiento registrada; checkpoint M8.11 REGRESSION_GATE_NEGATIVE=NOT_APPLICABLE, no DONE ni PASS, y sigue deuda OPEN_DEFERRED_NOT_PASSED.','HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','2128,2129','ACTIVO','github://cristhianlujan/claude-persona-lf-patch/pull/2128;supabase://programacion.engineering_work_checkpoints/M8.11/REGRESSION_GATE_NEGATIVE','EXECUTION',ARRAY['ENGINEERING_EXECUTOR','ENGINEERING_SCHEDULER','INPUT_GOVERNANCE']::text[],'R2_NO_VE','LOUD_EARLY','IG_CURATOR_VALIDATOR_REFACTOR_V2/M8.11 assertion semantics','github://cristhianlujan/claude-persona-lf-patch/pull/2128'),
('ENGINEERING-MIGRATION-TIMESTAMP-INVALID-001','ENGINEERING_GOVERNANCE','Migracion con HHMMSS invalido debe corregirse antes de publicar o aplicar','La primera migracion candidata para M8.11 uso 20261009294500 (hora 29:45 invalida). Se renombro antes del merge a 20261010020000; su SQL exacto se ensayo con BEGIN/ROLLBACK y se aplico desde main con registro en ledger. El PR2129 y PR2130 quedaron fusionados; cada fuente coincide con la entrada de su ledger.','El nombre de archivo se genero como cadena numerica creciente sin validar que la parte de hora-minuto-segundo fuera temporalmente valida.','MIGRATION_VERSION_DIGITS_VALID_FORMAT_INVALID_CLOCK','Generar versiones de migracion con fecha UTC real y validar parseo estricto YYYYMMDDHHMMSS (HH 00..23, MM/SS 00..59), unicidad y orden antes de crear PR. Descartar la version invalida, prohibir migraciones duplicadas, probar SQL exacto con ROLLBACK y registrar solo despues de merge y readback Git=ledger=DB.','Archivo 20261009294500 retirado de la rama; archivo canonico 20261010020000 fusionado PR2129; Git blob efe171ae3e8766d01e62b3d2af42886457626815. Ledger exact_sql_match=true, hash SQL adde77663e2c0e35197f6200d6c0d2aa16a8741bde2cca8cae1fdcb38858558a; segunda migracion 20261010021000 PR2130 igualmente exact_sql_match=true.','MEDIUM',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','2129','ACTIVO','github://cristhianlujan/claude-persona-lf-patch/pull/2129;supabase://supabase_migrations.schema_migrations/20261010020000','EXECUTION',ARRAY['ENGINEERING_EXECUTOR','ENGINEERING_SCHEDULER','INPUT_GOVERNANCE']::text[],'R5_EROSION_PROCESO','LOUD_EARLY','IG M8.11 R16 migration naming','github://cristhianlujan/claude-persona-lf-patch/pull/2129'),
('ENGINEERING-SUPABASE-CONNECTOR-THROTTLE-BURST-001','ENGINEERING_ORCHESTRATION','Fanout rapido de consultas SQL excede cuota del conector y exige backoff controlado','Durante el registro de los hallazgos de M8.11 el conector Supabase devolvio RATE_LIMITED/ThrottlerException con Retry after 59, 58 y 56 segundos para consultas de inspeccion agrupadas. No fue evidencia de defecto de la base ni de perdida de datos; tras reducir llamadas se recupero la lectura.','Demasiadas solicitudes de inspeccion al conector en una ventana corta; la cuota del proveedor se agoto temporalmente. No existe evidencia de error del motor PostgreSQL.','MCP_SQL_REQUEST_BURST_429','Reutilizar el EKB preflight y el bootstrap, limitar fanout y agrupar solo consultas necesarias; ante 429 respetar Retry-after y reducir a lecturas minimas secuenciales. Nunca inventar readbacks ni suponer commit cuando hay bloqueo de transporte.','Respuestas reales RATE_LIMITED Retry after 59/58/56 seconds, seguidas de lectura recuperada de pg_get_viewdef(public.lf_error_knowledge) y estructura transversal.error_knowledge; EKB visto desde la vista canonical.','MEDIUM',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','','ACTIVO','supabase://public.lf_error_knowledge#view=transversal.error_knowledge;connector-observation://RATE_LIMITED-2026-10-11','EXECUTION',ARRAY['ENGINEERING_EXECUTOR','ENGINEERING_SCHEDULER','INPUT_GOVERNANCE']::text[],'R5_EROSION_PROCESO','LOUD_EARLY','IG_CURATOR_VALIDATOR_REFACTOR_V2/M8.11 EKB registration 2026-10-11','supabase://public.lf_error_knowledge;supabase://transversal.error_knowledge')
ON CONFLICT (codigo) DO UPDATE
SET titulo=excluded.titulo, descripcion=excluded.descripcion, causa_raiz=excluded.causa_raiz,
    patron=excluded.patron, prevencion=excluded.prevencion, validacion=excluded.validacion,
    evidencia=excluded.evidencia, pr=excluded.pr, source_ref=excluded.source_ref,
    root_cause_family=excluded.root_cause_family, detectability=excluded.detectability,
    ultima_vez=now(),updated_at=now();

UPDATE transversal.error_knowledge
SET evidencia = concat_ws(';',nullif(evidencia,''),
   'github://cristhianlujan/claude-persona-lf-patch/pull/2130#merge=bd3d03f66427e75532f2027808d688faa8c0eec0'),
    validacion = concat_ws(' ',nullif(validacion,''),
    '[M8.11 2026-10-11] PR2130 corrige GATE_READBACK: fuente IG propia, eventos POST_PASE eliminados; SQL exacto Git=ledger=DB; M8.11 DONE 100% y 0 bloqueos.'),
    prevencion = concat_ws(' ',nullif(prevencion,''),
    '[M8.11] Revalidar tambien queries/events del SOURCE_PACK, no solo nombre de checkpoint y exit_criterion, para impedir el arrastre de fuentes de workstreams desactivados.'),
    frecuencia=coalesce(frecuencia,0)+1,ultima_vez=now(),updated_at=now()
WHERE codigo='IG-CROSS-WORKSTREAM-POST-PASE-BLEED-001'
 AND coalesce(evidencia,'') NOT LIKE '%/pull/2130#merge=%';

UPDATE transversal.error_knowledge
SET evidencia=concat_ws(';',nullif(evidencia,''),
   'github://cristhianlujan/claude-persona-lf-patch/pull/2129',
   'github://cristhianlujan/claude-persona-lf-patch/pull/2130'),
    validacion=concat_ws(' ',nullif(validacion,''),
    '[M8.11 2026-10-11] Contrato y gobierno actualizados PR2129 con rollback real, admision SAFE_CHANGE_ADMISSION, merge y paridad; fuente de GATE_READBACK reparada PR2130; obligacion relativa OPEN_DEFERRED_NOT_PASSED, 4 DONE y 1 NOT_APPLICABLE.'),
    frecuencia=coalesce(frecuencia,0)+1,ultima_vez=now(),updated_at=now()
WHERE codigo='ENGINEERING-BLOCKER-DUAL-SCOPE-REPAIR-001'
 AND coalesce(evidencia,'') NOT LIKE '%/pull/2129%';

DO $post$
DECLARE v_new int; v_old int;
BEGIN
 SELECT count(*) INTO v_new FROM public.lf_error_knowledge
 WHERE codigo IN ('IG-M811-P95-RELATIVE-BASELINE-DEFERRED-001','IG-M811-NEGATIVE-TEST-FAIL-NOT-PASS-001','ENGINEERING-MIGRATION-TIMESTAMP-INVALID-001','ENGINEERING-SUPABASE-CONNECTOR-THROTTLE-BURST-001')
   AND estado='ACTIVO' AND nullif(prevencion,'') IS NOT NULL AND nullif(validacion,'') IS NOT NULL;
 SELECT count(*) INTO v_old FROM public.lf_error_knowledge
 WHERE (codigo='IG-CROSS-WORKSTREAM-POST-PASE-BLEED-001' AND evidencia LIKE '%/pull/2130#merge=%')
    OR (codigo='ENGINEERING-BLOCKER-DUAL-SCOPE-REPAIR-001' AND evidencia LIKE '%/pull/2129%');
 IF v_new<>4 OR v_old<>2
 THEN RAISE EXCEPTION 'M811_EKB_READBACK_FAIL new=% old=%',v_new,v_old; END IF;
END $post$;
