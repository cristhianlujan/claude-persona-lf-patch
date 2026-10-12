-- IG M9.12 EKB: root causes, prevention, reproducible validation.
DO $e$
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo IN
 ('IG-M912-POSTPASE-RECEIPT-SOURCE-DRIFT-001','IG-M912-M98-LIVE-READBACK-BLOCKED-001','IG-M912-JSONB-MISSING-ACTION-SPEC-001'))
 THEN RAISE EXCEPTION 'M912_EKB_ALREADY_REGISTERED'; END IF;
 INSERT INTO public.lf_error_knowledge
 (codigo,categoria,titulo,causa_raiz,prevencion,validacion,estado,evidencia,lote_origen,source_ref)
 VALUES
 ('IG-M912-POSTPASE-RECEIPT-SOURCE-DRIFT-001','GOVERNANCE',
  'M9.12 heredó recibos de POST_PASE desactivado',
  'El exit_criterion era IG local pero action_spec y SOURCE_PACK exigían FINAL_EVIDENCE/CLOSURE_GATE externos.',
  'Reusar el verificador y provenance_receipts existentes; validar bundle M9.0, M9.8 current, M9.10 drill y M9.11 soak sin activar POST_PASE.',
  'SQL Git con ROLLBACK: 0 evidencia POST_PASE, 0 missing textual, estado WAIT_DEPENDENCIES.',
  'VERIFICADO','github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261012021000_ig_m912_readiness_ig_owned_contract_v1.sql',
  'IG_CURATOR_VALIDATOR_REFACTOR_V2','programacion.engineering_plan_units M9.12'),
 ('IG-M912-M98-LIVE-READBACK-BLOCKED-001','ENGINEERING_VALIDATION',
  'M9.8 DONE pero verificador current BLOCKED',
  'fn_ig_m98_checkpoint_bound_readback_v2 devuelve GOVERNED_EVIDENCE_BINDING_MISSING pese a M9.8 DONE.',
  'CUTOVER_READY requiere verificación actual independiente de DONE; fallar cerrado y no emitir recibo mientras siga BLOCKED.',
  'M9.12 permanece WAIT_DEPENDENCIES y CUTOVER_READY no emitido hasta M9.8 PASS verificado.',
  'ACTIVO','supabase://programacion.fn_ig_m98_checkpoint_bound_readback_v2',
  'IG_CURATOR_VALIDATOR_REFACTOR_V2','programacion.fn_ig_m98_checkpoint_bound_readback_v2'),
 ('IG-M912-JSONB-MISSING-ACTION-SPEC-001','ENGINEERING_VALIDATION',
  'Action spec local ausente provocó propagación NULL',
  'PREREQ_RECEIPTS tiene contrato compilado genérico, no action_specs_v1 local; jsonb_set con SQL NULL anulaba unit_metadata.',
  'Inspeccionar nodo JSONB antes de escribir; reparar SOURCE_PACK y reutilizar compiled spec. Probar BEGIN/ROLLBACK sin residuos.',
  'Primer fallo transaccional NOT NULL; contratos exactos reparados, bootstrap WAIT_DEPENDENCIES.',
  'VERIFICADO','supabase://programacion.engineering_plan_units/M9.12',
  'IG_CURATOR_VALIDATOR_REFACTOR_V2','programacion.engineering_plan_units M9.12');
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo LIKE 'IG-M912-%' AND codigo IN
 ('IG-M912-POSTPASE-RECEIPT-SOURCE-DRIFT-001','IG-M912-M98-LIVE-READBACK-BLOCKED-001','IG-M912-JSONB-MISSING-ACTION-SPEC-001'))<>3
 THEN RAISE EXCEPTION 'M912_EKB_COUNT_FAIL'; END IF;
END $e$;