-- IG M10.7 G2B: record approved architecture as CONTRACT DESIGN ONLY.
-- This migration does not modify runtime functions, source tables, rights, triggers or CP3.
DO $record$
DECLARE
 v_code constant text := 'IG-M107-FROZEN-CONTEXT-FINAL-COMMIT-FENCE-019';
 v_receipt jsonb;
 v_trigger_count integer;
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code) THEN
   RAISE EXCEPTION 'IG_M107_G2B_CONTRACT_ALREADY_REGISTERED';
 END IF;
 IF md5(pg_get_functiondef('programacion.fn_input_governance_run_context_packet_v1(bigint)'::regprocedure)) <>
    'c0d4e5e8515e79343358fa1d490d0ca6'
 OR md5(pg_get_functiondef('programacion.fn_input_run_source_currentness_v1(bigint)'::regprocedure)) <>
    'ba43b8cc06220a2ae079d5d7d6c7710c'
 THEN RAISE EXCEPTION 'IG_M107_G2B_CURRENT_RUNTIME_CHANGED'; END IF;
 SELECT count(*) INTO v_trigger_count FROM pg_trigger t
 JOIN pg_class c ON c.oid=t.tgrelid
 JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE NOT t.tgisinternal AND t.tgenabled IN ('O','A') AND n.nspname='programacion'
 AND c.relname IN ('input_family_assessments','input_gap_proposals','input_readiness_runs');
 IF v_trigger_count<>21 THEN RAISE EXCEPTION 'IG_M107_G2B_TRIGGER_INVENTORY_CHANGED'; END IF;
 v_receipt := jsonb_build_object(
  'schema','IG_M107_G2B_FROZEN_CONTEXT_CONTRACT_DESIGN_V1',
  'document','docs/ig/IG_EXECUTION_SOURCE_CONTEXT_V1_G0.md',
  'github_document_blob_sha','8d2e69ca7296396b47fa5283b68e8111ff3fb5e7',
  'decision','FREEZE_ONCE_REUSE_WITHIN_RUN_FINAL_PROTECTED_CHECK',
  'source_compilation_once_per_run',true,
  'validator_semantic_independence_required',true,
  'final_same_transaction_authority_and_result',true,
  'all_source_writers_epoch_coverage_required',true,
  'source_epoch_implemented',false,
  'two_real_sessions_proven',false,
  'runtime_consumers_changed',false,
  'runtime_activation_allowed',false,
  'g2b_pass',false,
  'cp3_closed',false,
  'triggers_enabled_verified',v_trigger_count,
  'fence_algorithm','SOURCE_EPOCH_WRITERS_AND_CONFLICTING_LOCK_UNTIL_COMMIT',
  'require_negative_toctou_and_stale_rejection',true
 );
 INSERT INTO public.lf_error_knowledge (
   id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
   validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,
   evidencia,created_at,updated_at,lifecycle_phase,root_cause_family,detectability,
   source_context,source_ref)
 VALUES (
   gen_random_uuid(),v_code,'GOVERNANCE',
   'M10.7 G2B diseño aprobado: congelar una vez, verificar vigencia bajo fence final',
   'Contrato de reutilización por run sin compartir veredictos ni omitir controles; cierre protegido contra cambios concurrentes. La evidencia es de diseño, NO prueba G2B ni activación runtime.',
   'Reconstrucciones repetidas del manifiesto para verificar source currentness; cache sin fence permitiría falso PASS por carrera al cerrar.',
   'FROZEN_RUN_CONTEXT_WITH_ATOMIC_FINAL_CURRENTNESS',
   'Antes de activar G3: demostrar dos sesiones reales, epoch incrementado por todos los writers relevantes, bloqueo conflictivo durante readback y COMMIT, negativos por source/contract/identity/TOCTOU y rendimiento comparable; si falta cobertura, FAIL_CLOSED.',
   'Design readback en Git/main y ledger; G2B PASS requiere evidencia material posterior de prueba con dos sesiones. G1 y 21 triggers inalterados.',
   'HIGH',1,clock_timestamp(),clock_timestamp(),
   'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7','ACTIVO',
   v_receipt::text,clock_timestamp(),clock_timestamp(),'PREFLIGHT',
   'R4_NO_CUESTIONA','LOUD_EARLY','G2B contract refinement only, not runtime deployment',
   'docs/ig/IG_EXECUTION_SOURCE_CONTEXT_V1_G0.md'
 );
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1 THEN
   RAISE EXCEPTION 'IG_M107_G2B_CONTRACT_EKB_READBACK_FAILED';
 END IF;
END $record$;
