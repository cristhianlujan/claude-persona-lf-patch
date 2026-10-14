-- M10.5/CP2 EKB: do not treat successful offline bundle replay as
-- evidence of provider-level deploy/rollback or a certified R17 release.
-- Knowledge-only, no Operations routing mutation or runtime effect.
DO $m105_ekb_rehearsal$
DECLARE
  v_code constant text := 'IG-M105-R17-OFFLINE-VS-PROVIDER-REHEARSAL-016';
BEGIN
  IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code)
  THEN RAISE EXCEPTION 'EKB_R17_REHEARSAL_DUPLICATE'; END IF;

  IF NOT EXISTS(
    SELECT 1 FROM public.lf_eventos
    WHERE id=20890
      AND evento_tipo='RUNTIME_PREFLIGHT'
      AND payload->>'rehearsal_scope'='EPHEMERAL_FILE_BUNDLE_ONLY'
      AND payload->>'workflow_run_id'='38524367551'
      AND payload->>'provider_rollback_drill_executed'='false'
      AND payload->>'provider_idempotency_drill_executed'='false'
      AND payload->>'acceptance_declared'='false'
      AND payload->'file_bundle'->>'repeated_forward_changes'='0'
      AND payload->'file_bundle'->>'repeated_rollback_changes'='0'
  ) THEN RAISE EXCEPTION 'EKB_R17_REHEARSAL_PROOF_MISSING'; END IF;

  INSERT INTO public.lf_error_knowledge (
    codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
    severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,
    created_at,updated_at,lifecycle_phase,consumer_role,root_cause_family,
    detectability,source_context,source_ref
  ) VALUES (
    v_code,'INPUT_GOVERNANCE',
    'Offline bundle reversal must not be mistaken for provider-level rollback or idempotency',
    'M10.5 CP2 requires a reversible deployment route. PR #2603 used the exact main and rollback Git bundles in a temporary directory: first forward modified two files, repeat modified none, rollback restored two, second rollback modified none; one additional bridge file disappeared on reversal. Five Management GET measurements and before/after Edge v23 remained stable. The system intentionally did not exercise an actual provider deploy, provider rollback, provider-level idempotency or effect guard. PR #2606 persisted the truthful partial event 20890.',
    'File-system reconciliation proves the reproducibility of a package but cannot establish behavior of the external Edge deployment provider, its API side effects, runtime rollback timing or effect-ledger idempotency.',
    'A simulation may be falsely credited as full R17 gate approval unless local file replay, provider effect, readback and signed authorization are classified independently.',
    'For R17, preserve separate fields for offline_bundle_rehearsal, provider_deployment_executed, provider_rollback_drill_executed and provider_idempotency_drill_executed. Require exact Git file SHA256, old/current manifest and provider GET before/after without token logging. A successful local rehearsal is partial evidence only; the governed Operations step judge must not mark R17 PASS without provider-level proof and relevant signed runtime authorization. Record the result as RUNTIME_PREFLIGHT operational-event/v2, never test-evidence/v2 Skill artifact.',
    'GitHub run #38524367551 SUCCESS: source main 37a72b57966858d7dad7bd43fc84e7744d6c3f65, rollback cbaecd8d154b593f7d16126e9f3097797f31a7aa, first/second forward changes 2/0, first/second restore changes 2/0, no temp residue; before/after live Edge v23, no provider calls except GET. PR #2606 Train #38524738721 SUCCESS, Supabase event 20890 with provider rollback/idempotency false, no acceptance; Router OP_CANDIDATE write_allowed=false.',
    'ALTA',1,clock_timestamp(),clock_timestamp(),
    'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.5/CP2',
    'PR #2603; PR #2606','resuelto',
    'GitHub Actions #38524367551 artifact m105-r17-offline-rollback-38524367551; RUNTIME_PREFLIGHT event 20890; Train #38524738721',
    clock_timestamp(),clock_timestamp(),
    'RUNTIME_CHANGE_PREFLIGHT',ARRAY['OPERATION_EXECUTOR','ENGINEERING_VALIDATOR']::text[],
    'R5_EROSION_PROCESO','PROCESS_DEPENDENT',
    'Boundary between local reversible bundle and governed Supabase provider effect for M10.5 CP2',
    'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2603'
  );

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_error_knowledge
    WHERE codigo=v_code AND estado='resuelto'
      AND source_ref='https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2603'
  ) THEN RAISE EXCEPTION 'EKB_R17_REHEARSAL_READBACK_FAILED'; END IF;
END $m105_ekb_rehearsal$;
