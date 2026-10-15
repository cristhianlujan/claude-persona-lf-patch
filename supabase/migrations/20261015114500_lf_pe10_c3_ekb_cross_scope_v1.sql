-- LF PE10_C3: add one cross-scope root-cause finding to canonical EKB only.
-- Route: ACT-0001 -> ACTUALIZACION_DB_LF -> LF Migration Merge Train.
-- No profile/runtime/ledger/operation-state mutation. Existing EKB records are not rewritten.
-- Positive INSERT and readback run inside a SAVEPOINT and are rolled back first.
BEGIN;
DO $ekb_pre$
BEGIN
  IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo='LF-PE10-C3-CROSS-PLAN-LEDGER-MISATTRIBUTION-20261015-001')
  THEN RAISE EXCEPTION 'PE10_C3_EKB_ALREADY_REGISTERED_RECONCILE'; END IF;
END $ekb_pre$;
SAVEPOINT pe10_c3_ekb_probe;
INSERT INTO public.lf_error_knowledge (codigo, categoria, titulo, descripcion, causa_raiz, patron, prevencion, validacion, severidad, frecuencia, lote_origen, estado, source_ref, lifecycle_phase, root_cause_family, detectability, source_context)
VALUES ('LF-PE10-C3-CROSS-PLAN-LEDGER-MISATTRIBUTION-20261015-001',
  'PROFILE_EVOLUTION',
  'Confusion entre productor Reparador y productor PE10 llevo a proponer wiring innecesario',
  'En recuperacion 2026-10-15 se observaron 0/27 manifiestos de EJECUCION_PERFIL_LF del Reparador con los tres campos del ledger, pero se extrapolo ese hallazgo a PE10_C3. El expediente PE10_C3 ya tenia el productor, dispatch, binding y recibo SOURCE_SNAPSHOT VERIFIED exactos; no correspondia modificar el worker de Hetzner.',
  'Diagnostico sin vincular primero el objetivo, operation_code, producer_execution_id, subject_ref y receipt_id al mismo expediente. Se trataron dos productores/operaciones de LF distintos como una sola dependencia.',
  'Hallazgo cierto en runtime A extrapolado como bloqueo de checkpoint B; correccion propuesta en componente no consumidor del checkpoint.',
  'Antes de reparar el ledger resolver la identidad exacta del plan/unidad/checkpoint y comparar operation_code, execution_id, subject_ref, source_head y receipt id. Consultar EKB y recibos del mismo consumidor. Si el SOURCE_SNAPSHOT exacto ya esta VERIFIED, no reabrir el productor ni duplicar mecanismos. Separar ausencia de permiso EXECUTE del conector read_only de fallo del contrato de negocio. Resolver semantica de PE10_C3 y drain de PE10_C4 por separado.',
  'Readback 2026-10-15: PE10_C3 SOURCE_SNAPSHOT receipt 37db027e-ad58-4cbb-b4dc-01b7568f6ac2 VERIFIED; digest 73c88455cf0501de2eb4e1226e622de9e3283c0d6b024e77cd725df60966af8a coincide. Revision independiente EXEC-PE10C3-INDEP-e983544d2ee0aeb9 mantiene 2/6 pasos, 0 INDEPENDENT_REVIEW_RECEIPT PASS; updater historico 22 IN_PROGRESS. Independientemente, 27 ejecuciones de EJECUCION_PERFIL_LF del Reparador no tienen triple identidad. El conector supabase_read_only_user carece de EXECUTE en fn_lf_evidence_ledger_anchor_v1; intento devolvio permission denied y 0 filas residuales de prueba. No se ejecuto un anchor positivo.',
  'MEDIUM',
  1,
  'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C3',
  'ACTIVO',
  'supabase://private.lf_evidence_ledger_v1/37db027e-ad58-4cbb-b4dc-01b7568f6ac2',
  'construction',
  'R2_NO_VE',
  'LOUD_LATE',
  'LF_PROFILE_REPAIR_RECOVERY_20261015');
DO $ekb_positive$
BEGIN
  IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo='LF-PE10-C3-CROSS-PLAN-LEDGER-MISATTRIBUTION-20261015-001' AND titulo='Confusion entre productor Reparador y productor PE10 llevo a proponer wiring innecesario'
      AND root_cause_family='R2_NO_VE' AND detectability='LOUD_LATE')<>1
  THEN RAISE EXCEPTION 'PE10_C3_EKB_ROLLBACK_POSITIVE_FAILED'; END IF;
END $ekb_positive$;
ROLLBACK TO SAVEPOINT pe10_c3_ekb_probe;
DO $ekb_negative$
BEGIN
  IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='LF-PE10-C3-CROSS-PLAN-LEDGER-MISATTRIBUTION-20261015-001')
  THEN RAISE EXCEPTION 'PE10_C3_EKB_ROLLBACK_LEAK'; END IF;
END $ekb_negative$;
RELEASE SAVEPOINT pe10_c3_ekb_probe;
-- Durable write, only after both reversible checks pass.
INSERT INTO public.lf_error_knowledge (codigo, categoria, titulo, descripcion, causa_raiz, patron, prevencion, validacion, severidad, frecuencia, lote_origen, estado, source_ref, lifecycle_phase, root_cause_family, detectability, source_context)
VALUES ('LF-PE10-C3-CROSS-PLAN-LEDGER-MISATTRIBUTION-20261015-001',
  'PROFILE_EVOLUTION',
  'Confusion entre productor Reparador y productor PE10 llevo a proponer wiring innecesario',
  'En recuperacion 2026-10-15 se observaron 0/27 manifiestos de EJECUCION_PERFIL_LF del Reparador con los tres campos del ledger, pero se extrapolo ese hallazgo a PE10_C3. El expediente PE10_C3 ya tenia el productor, dispatch, binding y recibo SOURCE_SNAPSHOT VERIFIED exactos; no correspondia modificar el worker de Hetzner.',
  'Diagnostico sin vincular primero el objetivo, operation_code, producer_execution_id, subject_ref y receipt_id al mismo expediente. Se trataron dos productores/operaciones de LF distintos como una sola dependencia.',
  'Hallazgo cierto en runtime A extrapolado como bloqueo de checkpoint B; correccion propuesta en componente no consumidor del checkpoint.',
  'Antes de reparar el ledger resolver la identidad exacta del plan/unidad/checkpoint y comparar operation_code, execution_id, subject_ref, source_head y receipt id. Consultar EKB y recibos del mismo consumidor. Si el SOURCE_SNAPSHOT exacto ya esta VERIFIED, no reabrir el productor ni duplicar mecanismos. Separar ausencia de permiso EXECUTE del conector read_only de fallo del contrato de negocio. Resolver semantica de PE10_C3 y drain de PE10_C4 por separado.',
  'Readback 2026-10-15: PE10_C3 SOURCE_SNAPSHOT receipt 37db027e-ad58-4cbb-b4dc-01b7568f6ac2 VERIFIED; digest 73c88455cf0501de2eb4e1226e622de9e3283c0d6b024e77cd725df60966af8a coincide. Revision independiente EXEC-PE10C3-INDEP-e983544d2ee0aeb9 mantiene 2/6 pasos, 0 INDEPENDENT_REVIEW_RECEIPT PASS; updater historico 22 IN_PROGRESS. Independientemente, 27 ejecuciones de EJECUCION_PERFIL_LF del Reparador no tienen triple identidad. El conector supabase_read_only_user carece de EXECUTE en fn_lf_evidence_ledger_anchor_v1; intento devolvio permission denied y 0 filas residuales de prueba. No se ejecuto un anchor positivo.',
  'MEDIUM',
  1,
  'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_C3',
  'ACTIVO',
  'supabase://private.lf_evidence_ledger_v1/37db027e-ad58-4cbb-b4dc-01b7568f6ac2',
  'construction',
  'R2_NO_VE',
  'LOUD_LATE',
  'LF_PROFILE_REPAIR_RECOVERY_20261015');
DO $ekb_final$
BEGIN
  IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo='LF-PE10-C3-CROSS-PLAN-LEDGER-MISATTRIBUTION-20261015-001' AND titulo='Confusion entre productor Reparador y productor PE10 llevo a proponer wiring innecesario'
      AND estado='ACTIVO' AND root_cause_family='R2_NO_VE' AND detectability='LOUD_LATE')<>1
  THEN RAISE EXCEPTION 'PE10_C3_EKB_DURABLE_READBACK_FAILED'; END IF;
END $ekb_final$;
COMMIT;
