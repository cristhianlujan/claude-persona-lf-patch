-- IG M9.12 EKB: verify signed-receipt producer before consumer checkpoint attempts.
-- Learning only, append-only; no runtime/candidate/production changes.
DO $ekb$
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='IG-M912-READINESS-MISSING-AUTHORIZED-PRODUCER-001')
 THEN RAISE EXCEPTION 'M912_EKB_ALREADY_REGISTERED'; END IF;
 INSERT INTO public.lf_error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,estado,evidencia,lote_origen,source_ref)
 VALUES(
 'IG-M912-READINESS-MISSING-AUTHORIZED-PRODUCER-001',
 'GOVERNANCE',
 'M9.12 consumia CUTOVER_READY sin paso emisor autorizado',
 'Checkpoint CLOSURE_GATE_CONSUME requeria EVIDENCE_VERIFICATION firmado y test PASS, pero no existia productor de IG_CUTOVER_READINESS. Exigirlo sin emisor reproduciria bloqueo M9.9/M9.10.',
 'Desalineacion del contrato de verificacion: el verificador de recibo estaba definido, el productor autentico no. Adicionalmente coexistian bundles historicos: seleccionar el mas reciente no garantiza el SHA fijado por M9.0.',
 'REQUIRE_VERIFIED_RECEIPT_WITHOUT_PRODUCER_AND_PINNED_CURRENTNESS',
 'Preflight EKB->contrato->gobernanza->validador: si un checkpoint requiere recibo firmado, comprobar productor, autorizacion EVIDENCE_VERIFIER_V1, objeto y evento de emision, SHA fijado por unidad origen, pruebas positivas y negativas. Reparar contrato+gobernanza+productor juntos; probar con BEGIN/ROLLBACK y no usar mock PASS. Para cierre sandbox separar calificacion de activacion; no exigir POST_PASE desactivado ni falsificar emisor.',
 'M9.12: PR #2289 + #2291 merged; migracion exacta 20261012090000 Git=ledger=DB; prueba BEGIN/ROLLBACK sin residuos; firma protegida real receipt 1667 sobre bundle M9.0 receipt 187 SHA db84f4ab; SQL y Python source-bound PASS; missing/stale SHA REJECTED; 0 promotions; ledger DONE 5/5 100%. Gate live separado, NO activacion de produccion.',
 'VERIFICADO',
 'github://cristhianlujan/claude-persona-lf-patch/pull/2289;github://cristhianlujan/claude-persona-lf-patch/pull/2291;supabase://programacion.provenance_receipts/1667',
 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.12',
 'supabase://programacion.engineering_plan_units/M9.12');
 IF NOT EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='IG-M912-READINESS-MISSING-AUTHORIZED-PRODUCER-001'
  AND estado='VERIFICADO') THEN RAISE EXCEPTION 'M912_EKB_READBACK_FAILED'; END IF;
END $ekb$;
