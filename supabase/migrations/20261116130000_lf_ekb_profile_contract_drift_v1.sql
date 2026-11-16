-- IG 07:55 Lima 2026-11-16: EKB only. No code/runtime/previous RUN changes.
-- PR metadata: #4046 (this one-file migration PR).
BEGIN;
DO $ekb$
DECLARE
 v_pr text:='#4046';
 v_source_ref text:='supabase/migrations/20261116130000_lf_ekb_profile_contract_drift_v1.sql';
 v_codes text[]:=ARRAY[
    'LF-PROFILE-EDGE-PROMOTION-ALLOWED-FALSE-CONTRACT-20261116-001',
    'LF-PROFILE-BLOCKED-RETURN-PANTALLA-ID-NOT-TRANSPORTED-20261116-001',
    'LF-PROFILE-PY-STALE-VALIDATOR-CONTINUATION-CODE-20261116-001'
 ]::text[];
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=ANY(v_codes)) THEN
   RAISE EXCEPTION 'LF_E21_PROFILE_CONTRACT_EKB_CODE_ALREADY_EXISTS';
 END IF;
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
  validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,
  lifecycle_phase,consumer_role,root_cause_family,detectability,source_context,source_ref,created_at,updated_at)
 VALUES
  (gen_random_uuid(),'LF-PROFILE-EDGE-PROMOTION-ALLOWED-FALSE-CONTRACT-20261116-001','PROFILE_EXECUTION',
   'Edge exige promotion_allowed=false aunque SQL admite true en handoff validado',
   'profile_continuation.ts L162 (main b60c7cdf) exige repair.promotion_allowed === false; SQL admite true; prueba en memoria (37 escenarios sinteticos) da 403 PROFILE_CONTINUATION_GOVERNED_READ_ONLY_AUTHORITY_REQUIRED antes de IG; L21/L144/L843 fijan target_code PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
   'autorizacion duplicada Edge (valor fijo) vs SQL (derivada) sin test cruzado',
   'EDGE_SQL_CONTRACT_DRIFT',
   'Edge acepta true solo si SQL lo valido; sin valores fijos; test cruzado',
   'PG17/18 BEGIN/ROLLBACK, CI real, SELECT del EKB tras Train',
   'HIGH',1,clock_timestamp(),clock_timestamp(),
   'LF_E21_PROFILE_CONTRACT_20261116',v_pr,'ACTIVO',
   'prueba en memoria, sin corrida real',
   'PROFILE_EXECUTION',ARRAY['PRODUCT_DIRECTOR','ROUTER']::text[],
   'R5_EROSION_PROCESO','LOUD_EARLY',
   'IG 07:55 Lima 2026-11-16; hallazgo informado por el dueño, sin corrida real',
   v_source_ref,clock_timestamp(),clock_timestamp()),
  (gen_random_uuid(),'LF-PROFILE-BLOCKED-RETURN-PANTALLA-ID-NOT-TRANSPORTED-20261116-001','PROFILE_EXECUTION',
   'El mensaje generico omite pantalla_id que exige la comprobacion del retorno bloqueado',
   'lf_profile_native_resume.py ~L1430 exige governed.pantalla_id == body.pantalla_id para IG_CONTEXT_PACK_BLOCKED; el mensaje no lo transporta y la guarda no se activa',
   'Campo obligatorio pantalla_id no transportado entre el mensaje de retorno bloqueado y el validador consumidor',
   'REQUIRED_FIELD_NOT_TRANSPORTED',
   'transportar y verificar pantalla_id autorizado',
   'PG17/18 BEGIN/ROLLBACK, CI real, SELECT del EKB tras Train',
   'MEDIUM',1,clock_timestamp(),clock_timestamp(),
   'LF_E21_PROFILE_CONTRACT_20261116',v_pr,'ACTIVO',
   'prueba en memoria, sin corrida real',
   'PROFILE_EXECUTION',ARRAY['PRODUCT_DIRECTOR','ROUTER']::text[],
   'R5_EROSION_PROCESO','SILENT',
   'IG 07:55 Lima 2026-11-16; hallazgo informado por el dueño, sin corrida real',
   v_source_ref,clock_timestamp(),clock_timestamp()),
  (gen_random_uuid(),'LF-PROFILE-PY-STALE-VALIDATOR-CONTINUATION-CODE-20261116-001','PROFILE_EXECUTION',
   'Python espera el codigo de continuacion antiguo del Validator',
   'is_direct_validator_continuation ~L594 exige IG_CONTEXT_PACK_VALIDATOR_RESUME_REQUIRED; una continuacion valida se registra como reintento',
   'Código esperado por Python desfasado respecto de la respuesta del Validator; desalineación del contrato Edge/Python',
   'EDGE_PY_RESPONSE_CONTRACT_DRIFT',
   'alinear contratos',
   'PG17/18 BEGIN/ROLLBACK, CI real, SELECT del EKB tras Train',
   'MEDIUM',1,clock_timestamp(),clock_timestamp(),
   'LF_E21_PROFILE_CONTRACT_20261116',v_pr,'ACTIVO',
   'prueba en memoria, sin corrida real',
   'PROFILE_EXECUTION',ARRAY['PRODUCT_DIRECTOR','ROUTER']::text[],
   'R5_EROSION_PROCESO','SILENT',
   'IG 07:55 Lima 2026-11-16; hallazgo informado por el dueño, sin corrida real',
   v_source_ref,clock_timestamp(),clock_timestamp());
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=ANY(v_codes))<>3 THEN
   RAISE EXCEPTION 'LF_E21_PROFILE_CONTRACT_EKB_INSERT_COUNT_NOT_3';
 END IF;
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=ANY(v_codes)
   AND categoria='PROFILE_EXECUTION' AND lifecycle_phase='PROFILE_EXECUTION'
   AND root_cause_family='R5_EROSION_PROCESO' AND lote_origen='LF_E21_PROFILE_CONTRACT_20261116'
   AND estado='ACTIVO' AND frecuencia=1 AND pr=v_pr AND source_ref=v_source_ref
   AND consumer_role=ARRAY['PRODUCT_DIRECTOR','ROUTER']::text[]
   AND evidencia='prueba en memoria, sin corrida real')<>3 THEN
   RAISE EXCEPTION 'LF_E21_PROFILE_CONTRACT_EKB_CONTRACT_FIELDS_DRIFT';
 END IF;
END $ekb$;
COMMIT;
