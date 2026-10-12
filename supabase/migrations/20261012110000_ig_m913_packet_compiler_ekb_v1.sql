-- EKB: verified M9.13 compiler repair, with independent live-readback still pending.
-- Scope: append one public.lf_error_knowledge record only.
DO $ekb$
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='IG-M913-BOUNDED-TEST-MISSING-CANONICAL-EXIT-001') THEN
   RAISE EXCEPTION 'M913_EKB_DUPLICATE_CODE';
 END IF;
 INSERT INTO public.lf_error_knowledge
  (id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
   severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,
   created_at,updated_at,source_context,source_ref)
 VALUES
  (gen_random_uuid(),'IG-M913-BOUNDED-TEST-MISSING-CANONICAL-EXIT-001',
   'IG_CHECKPOINT_COMPILATION','M9.13 test contract omitted required canonical_exit_criterion',
   'The M9_INDEPENDENT_READBACK author-and-run checkpoint had a test_code/test_path but compiled to BLOCK_BOUNDED_CHECKPOINT_TEST_CONTRACT_INCOMPLETE even with 13/13 peers DONE and all their evidence present.',
   'fn_engineering_execution_packet_apply_bounded_checkpoint_test_v requires test_execution_contract.canonical_exit_criterion; the M9.13 action spec lacked this field. This is a contract compiler completeness error, distinct from the genuine missing signed independent live readback.',
   'BOUNDED_CHECKPOINT_TEST declared without mandatory semantic test criterion; blocked execution packet misdiagnosed as absence of external runner.',
   'During EKB->contract->governance->validator preflight, require test_code, test_path, canonical_exit_criterion, checkpoint_title_context and exact declared mutation target; simulate compilation before authoring. Repair action_spec and governance atomically. Never mark independent proof PASS merely because packet is READY, and never trust a self-declared different actor.',
   'PR #2293 merged main 0d618a14bd3896c22ab7ee5bed15f86df95657aa; exact-source migration 20261012104500 Git blob a6b5b8536d847de903ef55fd8684cc144f6fb426 in ledger statement[1]; BEFORE BLOCK_BOUNDED_CHECKPOINT_TEST_CONTRACT_INCOMPLETE, AFTER READY/CONTINUE_CURRENT_CHECKPOINT, execution_allowed=true; no checkpoint state modification. SentinelX artifact self-test passed positive=1 negative=3. Genuine independent signed readback over live ledger remains PENDING, no DONE claim.',
   'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.13','#2293','VERIFICADO',
   'sandbox://M9.13#checkpoint5;GitHub PR#2293;supabase://supabase_migrations.schema_migrations/20261012104500;sentinelx://host_3d5ff6fb467d4e9e/self-test;live-signed-readback=PENDING',
   now(),now(),'M9_INDEPENDENT_READBACK','github://cristhianlujan/claude-persona-lf-patch/pull/2293');
END $ekb$;
