-- Correccion de alcance de PE10A_CT01 (solo base de conocimiento de errores; no toca el plan ni lo ya cerrado).
-- Detalle: docs/profile_updater/PE10A_CT01_CORRECCION_ALCANCE_V1_20261027.md
DO $mig$
DECLARE v_exec text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
  AND target_code LIKE '%lf_pe10a_ct01_scope_correction_ekb_v1' AND status='IN_PROGRESS'
 ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'PE10A_CT01_CORRECTION_TRAIN_TRANSPORT_REQUIRED'; END IF;

 INSERT INTO public.lf_error_knowledge
   (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
    severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
 SELECT 'LF-PE10A-CT01-CLOSE-OVERSTATES-INDEPENDENT-RECEIPT-20261027-001','PROFILE_EVOLUTION',
  'Cierre de PE10A_CT01 puede leerse como mas avance y mas independencia del real',
  'El recibo de asercion de CT01 declara independent_receipt_bound=true y readback_passed=true. Las dos rondas del revisor externo dieron FAIL por evidencia insuficiente y sin atestacion del proveedor; el true significa aceptacion del dueño. El readback fue dentro de la transaccion. Las pruebas locales usaron stubs. CT01 es inventario/auditoria, no mejora funcional del actualizador.',
  'Las condiciones del contrato de cierre se nombraron como si exigieran verificacion externa, y se rellenaron con constantes al aceptar el dueño un recibo sin atestacion.',
  'Un booleano true en pass_when sin definicion operativa puede leerse como verificacion que no ocurrio.',
  'Definir en el contrato que prueba respalda cada condicion y registrar en observed el origen real (OWNER_ACCEPTED, IN_TRANSACTION). No presentar cierres de auditoria como avance funcional.',
  'Ver docs/profile_updater/PE10A_CT01_CORRECCION_ALCANCE_V1_20261027.md; observed.receipt_admission y observed.readback_scope ya declaraban el limite.',
  'MEDIUM',1,clock_timestamp(),clock_timestamp(),'PE10A_CT01','ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/blob/main/docs/profile_updater/PE10A_CT01_CORRECCION_ALCANCE_V1_20261027.md'
 WHERE NOT EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo='LF-PE10A-CT01-CLOSE-OVERSTATES-INDEPENDENT-RECEIPT-20261027-001');
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo='LF-PE10A-CT01-CLOSE-OVERSTATES-INDEPENDENT-RECEIPT-20261027-001')<>1
 THEN RAISE EXCEPTION 'PE10A_CT01_CORRECTION_POSTSTATE_INVALID'; END IF;
END
$mig$;
