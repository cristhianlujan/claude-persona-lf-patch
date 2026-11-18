-- Source-bound prerequisite for IG Chat9 L2: NO rules, policies or other data mutated.
-- The Migration Train event is a proof anchor only; actual PG17 functional
-- rollback and negatives are separately required before inserting an evidence row.
-- Step70/Owner V2 remain pending; never infer them from this migration alone.
-- Other chats may add unrelated CANDIDATO rows. Source-bound codes+SHA, not
-- global inventory counts, are the exact correctness and collision guard.
BEGIN;
DO $ig_chat9_l2_proof$
DECLARE
 r record; patched jsonb; src text; patch_sha text; cand_sha text; row_data jsonb;
 n int;
BEGIN
 IF to_regclass('public.lf_ig_functional_train_evidence_v1') IS NULL
 OR (SELECT count(*) FROM public.lf_global_config)<46
 OR (SELECT count(*) FROM public.lf_global_config WHERE scope='CLIENT')<>6
 OR (SELECT count(*) FROM lf_ops.reglas WHERE codigo IN ('REG_SES_003','REG_ATQ_016') AND estado='VIGENTE')<>2
 THEN RAISE EXCEPTION 'CHAT9_L2_PROOF_SOURCE_BASELINE_DRIFT'; END IF;
 FOR r IN SELECT * FROM (VALUES
   ('REG_ATQ_016','EXEC-PROFILE-GATE2-20142FEB637CF8230EFB86E5','c16436927a07128022e33b932ea8ee6f8e3dc550264b059b8130e56e4ce143c7','b7b4f96167366592d1da5b7ea167f32525d9a7bb91b02d04eadbe1908e422293','37c1394198971e65902d444205dc0cf48a8c839958df53f14fb2db7914b58bae'),
   ('REG_SES_003','EXEC-PROFILE-GATE2-CE703F89151A142D1B6630D8','cd4ddc5dbf5e4dfbf93023bf08df60b870330a29bb79c4fb731b4904c0da7321','93865ab6d1e4c541136cac3f5d2a58b52687cfe2a9aa47290b96ec704a951117','4e03594096ae2eb2f5d986a19e941408f9b0f028ef0207a38788b977dbe8ed66')
 ) AS expected(rule_code,parent_run,source_sha,proposal_sha,candidate_sha)
 LOOP
   SELECT public.lf_asset_snapshot_sha_v1('REGLA',r.rule_code)
     INTO src;
   IF src IS DISTINCT FROM r.source_sha
      OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution e
        WHERE e.execution_id=r.parent_run AND e.operation_code='EJECUCION_PERFIL_LF'
          AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF' AND e.status='IN_PROGRESS'
          AND e.manifest->>'read_only'='true' AND e.manifest->>'no_write'='true')
      OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s
        WHERE s.execution_id=r.parent_run AND s.step_id='input_validate'
          AND s.status='STEP_PASS_WITH_EVIDENCE')
      OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s
        WHERE s.execution_id=r.parent_run AND s.step_id='output_validate'
          AND s.status='STEP_PASS_WITH_EVIDENCE'
          AND s.evidence_payload->>'output_contract_result'='PASS')
   THEN RAISE EXCEPTION 'CHAT9_L2_PROOF_PARENT_OR_SOURCE_DRIFT:%',r.rule_code; END IF;
   SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}'
     INTO patched FROM public.lf_operation_execution_steps s
     WHERE s.execution_id=r.parent_run AND s.step_id='execute_profile'
       AND s.status='STEP_PASS_WITH_EVIDENCE';
   patch_sha:=encode(extensions.digest(convert_to(patched::text,'UTF8'),'sha256'),'hex');
   IF patch_sha IS DISTINCT FROM r.proposal_sha
      OR patched->>'rule_code'<>r.rule_code
      OR patched->>'change_kind'<>'FUNCTIONAL'
      OR (SELECT count(*) FROM jsonb_object_keys(patched->'changes'))<>3
      OR NOT (patched->'changes' ?& array['descripcion','razon','valor_config'])
      OR jsonb_typeof(patched#>'{changes,valor_config}')<>'object'
      OR EXISTS(SELECT 1 FROM jsonb_each(patched#>'{changes,valor_config}') j
                WHERE jsonb_typeof(j.value)='number')
   THEN RAISE EXCEPTION 'CHAT9_L2_PROOF_PATCH_SCOPE_OR_SHA_DRIFT:%',r.rule_code; END IF;
   SELECT (to_jsonb(rr)-'created_at'-'updated_at') ||
     jsonb_build_object(
      'descripcion',patched#>>'{changes,descripcion}',
      'razon',patched#>>'{changes,razon}',
      'valor_config',patched#>'{changes,valor_config}',
      'pendiente_decision',false,'pendiente_detalle',NULL)
   INTO row_data FROM lf_ops.reglas rr WHERE rr.codigo=r.rule_code AND rr.estado='VIGENTE';
   cand_sha:=encode(extensions.digest(convert_to(row_data::text,'UTF8'),'sha256'),'hex');
   IF cand_sha IS DISTINCT FROM r.candidate_sha
   THEN RAISE EXCEPTION 'CHAT9_L2_PROOF_CANDIDATE_SHA_DRIFT:%',r.rule_code; END IF;
   IF r.rule_code='REG_SES_003' THEN
     IF patched#>>'{changes,valor_config,concurrency_subject}'<>'RESOLVED_USER_ACCOUNT'
     OR patched#>>'{changes,valor_config,global_ip_session_lock}'<>'DENY'
     OR patched#>>'{changes,valor_config,max_concurrent_sessions_config_ref,scope}'<>'CLIENT'
     OR patched#>>'{changes,valor_config,max_concurrent_sessions_config_ref,config_key}'<>'ONBOARDING_ACCOUNT_MAX_CONCURRENT_SESSIONS'
     THEN RAISE EXCEPTION 'CHAT9_L2_SESSION_SCOPE_INCORRECT'; END IF;
   ELSIF r.rule_code='REG_ATQ_016' THEN
     IF patched#>>'{changes,valor_config,shared_ip_hard_block}'<>'DENY'
     OR patched#>>'{changes,valor_config,account_restriction_scope}'<>'RESOLVED_USER_ACCOUNT_ONLY'
     OR patched#>>'{changes,valor_config,additional_abuse_evidence}'<>'REQUIRED'
     OR patched#>>'{changes,valor_config,account_hold_minutes_config_ref,scope}'<>'CLIENT'
     THEN RAISE EXCEPTION 'CHAT9_L2_ATQ_SCOPE_INCORRECT'; END IF;
   END IF;
 END LOOP;
 IF (SELECT count(*) FROM public.lf_ig_functional_train_evidence_v1
     WHERE rule_code IN ('REG_SES_003','REG_ATQ_016'))<>0
 THEN RAISE EXCEPTION 'CHAT9_L2_EVIDENCE_ALREADY_PRESENT'; END IF;
 RAISE NOTICE 'CHAT9_L2_PREFLIGHT_PROOF_ONLY_PASS source_and_patch_sha_2_of_2; no rule DML; backend_E2E_NOT_TESTED';
END $ig_chat9_l2_proof$;
COMMIT;
