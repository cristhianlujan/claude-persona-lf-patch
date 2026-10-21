-- RW1-05_C2 governed checkpoint closure.
-- Uses the already-active ACTUALIZACION_DB_LF / Migration Train route plus the
-- canonical engineering assertion recorder + checkpoint transition.
-- Explicitly does NOT activate CIERRE_CHECKPOINT_INGENIERIA_LF.
BEGIN;

DO $rw105_c2_close$
DECLARE
  v_plan constant text := 'LF_ROUTER_ARCHITECTURE_WAVE_V1';
  v_unit constant text := 'RW1-05';
  v_cp constant text := 'RW1-05_C2';
  v_work constant bigint := 1131;
  v_exec constant text := 'EXEC-RW105-C2-GPT-NATIVE-CANARY-20261021-001';
  v_actor constant text := 'MIGRATION_VIA_MERGE_TRAIN_RW1_05_C2_GOVERNED_CLOSE';
  v_terminal_sha constant text := 'sha256:caa55730e62d8c921b1e0f7032b55e382b11d22a3ed7bf77ed150434e89d762d';
  v_evidence_ref constant text :=
    'supabase://public.lf_operation_execution/EXEC-RW105-C2-GPT-NATIVE-CANARY-20261021-001#terminal_authority_receipt';

  v_contract jsonb;
  v_contract_sha text;
  v_terminal jsonb;
  v_terminal_body jsonb;
  v_shadow jsonb;
  v_train jsonb;
  v_observed jsonb;
  v_bad jsonb;
  v_receipt jsonb;
  v_result jsonb;
  v_bootstrap jsonb;
  v_err text;
  v_trial integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=v_work
      AND checkpoint_code='RW1-05_C1'
      AND status='DONE'
  )
  OR NOT EXISTS (
    SELECT 1
    FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=v_work
      AND checkpoint_code=v_cp
      AND status='PENDING'
      AND assertion_receipt_sha256 IS NULL
  )
  OR NOT EXISTS (
    SELECT 1
    FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=v_work
      AND checkpoint_code='RW1-05_C3'
      AND status='PENDING'
  )
  THEN
    RAISE EXCEPTION 'RW105_C2_CLOSE_CHECKPOINT_STATE_DRIFT';
  END IF;

  -- The reusable generic close operation must remain candidate-only.
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_registry
    WHERE operation_code='CIERRE_CHECKPOINT_INGENIERIA_LF'
      AND status='CANDIDATO_READ_ONLY'
      AND lifecycle_state_code='OP_CANDIDATE'
  )
  OR NOT EXISTS (
    SELECT 1 FROM public.lf_router_action_registry
    WHERE operation_code='CIERRE_CHECKPOINT_INGENIERIA_LF'
      AND asset_type='ENGINEERING_CHECKPOINT'
      AND action_code='CHECKPOINT_CLOSE'
      AND status='CANDIDATO_READ_ONLY'
      AND write_allowed=false
  )
  THEN
    RAISE EXCEPTION 'RW105_C2_CLOSE_CANDIDATE_OPERATION_CHANGED';
  END IF;

  v_bootstrap:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
  IF v_bootstrap->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
     OR v_bootstrap#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM v_cp
     OR coalesce((v_bootstrap#>>'{state,open_blockers}')::integer,-1)<>0
     OR coalesce((v_bootstrap#>>'{state,unmet_deps}')::integer,-1)<>0
  THEN
    RAISE EXCEPTION 'RW105_C2_CLOSE_BOOTSTRAP_NOT_READY:%',v_bootstrap::text;
  END IF;

  v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
    v_plan,v_unit,v_cp,
    programacion.fn_engineering_checkpoint_action_spec_v3(v_plan,v_unit,v_cp)
  );
  IF v_contract->>'status' IS DISTINCT FROM 'READY'
     OR v_contract->>'mode' IS DISTINCT FROM 'EXPLICIT_PASS_WHEN_SUBSET'
     OR jsonb_typeof(v_contract->'pass_when')<>'object'
  THEN
    RAISE EXCEPTION 'RW105_C2_CLOSE_ASSERTION_CONTRACT_NOT_READY:%',v_contract::text;
  END IF;
  v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract);

  SELECT public.lf_profile_execution_terminal_authority_receipt_v1(v_exec)
    INTO STRICT v_terminal;
  v_terminal_body:=v_terminal->'terminal_authority_receipt';

  IF v_terminal->>'status' IS DISTINCT FROM 'READY'
     OR v_terminal->>'terminal_authority_receipt_sha256' IS DISTINCT FROM v_terminal_sha
     OR v_terminal_body->>'sha256' IS DISTINCT FROM v_terminal_sha
     OR v_terminal_body->>'executor_mode' IS DISTINCT FROM 'GPT_NATIVE'
     OR v_terminal_body->>'execution_transport' IS DISTINCT FROM 'NATIVE_CURRENT_CONTEXT'
     OR v_terminal_body->>'queue_request_id' IS NOT NULL
     OR v_terminal_body->>'operation_code' IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
     OR v_terminal_body#>>'{canonical_judge_readback,required_steps}' IS DISTINCT FROM '11'
     OR v_terminal_body#>>'{canonical_judge_readback,required_steps_pass}' IS DISTINCT FROM '11'
     OR v_terminal_body#>>'{canonical_judge_readback,fail_count}' IS DISTINCT FROM '0'
     OR v_terminal_body#>>'{canonical_judge_readback,blocked_count}' IS DISTINCT FROM '0'
     OR v_terminal_body#>>'{canonical_judge_readback,judge_result}' IS DISTINCT FROM 'PASS'
     OR v_terminal_body#>>'{semantic_judge_receipt,semantic_judge_result,verdict}'
          IS DISTINCT FROM 'PASS_INDEPENDENT_SEMANTIC'
     OR v_terminal_body#>>'{context_receipt,server_validated}' IS DISTINCT FROM 'true'
     OR v_terminal_body#>>'{router_authority_receipt,status}' IS DISTINCT FROM 'READY_TO_EXECUTE'
     OR v_terminal_body#>>'{router_authority_receipt,operation_code}' IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
     OR v_terminal_body->>'authority_rule'
          IS DISTINCT FROM 'ROUTER_AND_OPERATION_EVIDENCE_ONLY_NO_SPECIALIST_EFFECT_AUTHORITY'
  THEN
    RAISE EXCEPTION 'RW105_C2_CLOSE_TERMINAL_AUTHORITY_NOT_CLEAN:%',v_terminal::text;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_execution e
    WHERE e.execution_id=v_exec
      AND e.status='COMPLETED'
      AND e.target_code='PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF'
      AND e.manifest->>'executor_mode'='GPT_NATIVE'
      AND e.manifest->>'executor_provider'='OPENAI_CHATGPT_NATIVE'
      AND coalesce((e.manifest->>'read_only')::boolean,false)=true
      AND coalesce((e.manifest->>'no_write')::boolean,false)=true
      AND coalesce((e.manifest->>'no_promotion')::boolean,false)=true
      AND coalesce((e.manifest->>'zero_cost')::boolean,false)=true
      AND e.manifest->>'terminal_authority_receipt_sha256'=v_terminal_sha
      AND e.manifest#>>'{terminal_authority_receipt,sha256}'=v_terminal_sha
  )
  OR NOT EXISTS (
    SELECT 1
    FROM public.v_lf_operation_execution_judge j
    WHERE j.execution_id=v_exec
      AND j.required_steps=11
      AND j.required_steps_pass=11
      AND j.fail_count=0
      AND j.blocked_count=0
      AND j.judge_result='PASS'
  )
  THEN
    RAISE EXCEPTION 'RW105_C2_CLOSE_EXECUTION_READBACK_NOT_CLEAN';
  END IF;

  SELECT payload INTO STRICT v_shadow
  FROM public.lf_eventos
  WHERE id=21414
    AND evento_tipo='STEP_EVIDENCE'
    AND entidad_codigo=v_cp;

  IF v_shadow->>'executor_mode' IS DISTINCT FROM 'GPT_NATIVE'
     OR v_shadow#>>'{resume_validator_readback,resume_validator_code}' IS DISTINCT FROM 'VALID'
     OR coalesce((v_shadow#>>'{resume_validator_readback,resume_allowed}')::boolean,false) IS NOT TRUE
     OR v_shadow#>>'{resume_route_summary,status}' IS DISTINCT FROM 'ROUTER_REDERIVED'
     OR v_shadow#>>'{resume_route_summary,router_status}' IS DISTINCT FROM 'READY_TO_EXECUTE'
     OR v_shadow#>>'{resume_route_summary,operation_code}' IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
     OR v_shadow#>>'{semantic_result,clarification_question}' IS NOT NULL
  THEN
    RAISE EXCEPTION 'RW105_C2_CLOSE_SEMANTIC_SHADOW_NOT_CLEAN:%',v_shadow::text;
  END IF;

  SELECT payload INTO STRICT v_train
  FROM public.lf_eventos
  WHERE evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED'
    AND payload#>>'{receipt,pr}'='3052'
    AND payload#>>'{receipt,terminal_status}'='COMPLETED'
  ORDER BY id DESC
  LIMIT 1;

  IF v_train#>>'{receipt,effect,phase}' IS DISTINCT FROM 'SUCCEEDED'
     OR v_train#>>'{receipt,parity,migration_source_parity}' IS DISTINCT FROM 'PASS'
     OR v_train#>>'{receipt,merge,in_main}' IS DISTINCT FROM 'true'
     OR v_train#>>'{receipt,ledger_readback,matches_target}' IS DISTINCT FROM 'true'
  THEN
    RAISE EXCEPTION 'RW105_C2_CLOSE_TRAIN_NOT_CLEAN:%',v_train::text;
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_profile_execution_reconcile_queue_terminal_v1(uuid,text)'::regprocedure
     )) IS DISTINCT FROM 'e0c00d5972701bde0ef52d5e4d8091f1'
  THEN
    RAISE EXCEPTION 'RW105_C2_CLOSE_QUEUE_RECONCILIATION_SOURCE_DRIFT';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM programacion.engineering_plan_units
    WHERE plan_code=v_plan
      AND unit_code=v_unit
      AND work_item_id=v_work
      AND disposition='ASSIGNED'
      AND jsonb_array_length(
        coalesce(unit_metadata#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2,missing_typed}','[]'::jsonb)
      )<>0
  )
  THEN
    RAISE EXCEPTION 'RW105_C2_CLOSE_MATERIAL_BLOCKERS_REMAIN';
  END IF;

  v_observed:=jsonb_build_object(
    'acl_widened',false,
    'merge_train_changed',false,
    'profile_judge_result','PASS',
    'profile_source_bound',true,
    'context_receipt_bound',true,
    'resume_validator_used',true,
    'literal_and_hash_bound',true,
    'profile_required_steps',11,
    'validator_receipt_bound',true,
    'input_governance_changed',false,
    'merge_train_control_pass',true,
    'raw_output_receipt_bound',true,
    'real_semantic_shadow_run',true,
    'remote_api_required_for_c2',false,
    'profile_required_steps_pass',11,
    'real_profile_runtime_canary',true,
    'specialist_effect_authority',false,
    'scope_authority_packet_bound',true,
    'semantic_judge_receipt_bound',true,
    'canonical_execution_completed',true,
    'router_authority_receipt_bound',true,
    'profile_terminal_receipt_attached',true,
    'profile_terminal_receipt_composed',true,
    'profile_canary_zero_cost_read_only',true,
    'caller_interaction_max_one_question',true,
    'act0001_rederived_after_valid_resume',true,
    'semantic_provider_provenance_receipt',true,
    'profile_canary_executor_mode_admitted',true,
    'semantic_consumer_shadow_materialized',true,
    'queue_terminal_reconciliation_verified',true,
    'same_request_id_and_execution_id_bound',true
  );

  IF (v_observed @> (v_contract->'pass_when')) IS DISTINCT FROM true
  THEN
    RAISE EXCEPTION 'RW105_C2_CLOSE_OBSERVED_NOT_MATCHING_CONTRACT';
  END IF;

  -- Negative: one material false must be rejected and leave no assertion receipt.
  BEGIN
    v_bad:=jsonb_build_object(
      'status','PASS',
      'evidence_ref',v_evidence_ref,
      'observed',jsonb_set(v_observed,'{profile_required_steps_pass}','10'::jsonb,true)
    );
    PERFORM programacion.fn_engineering_checkpoint_assertion_record_v1(
      v_plan,v_unit,v_cp,v_bad,v_actor
    );
    RAISE EXCEPTION 'RW105_C2_CLOSE_FORGED_10_OF_11_ACCEPTED';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'ENGINEERING_ASSERTION_RESULT_FAILED:%'
    THEN
      RAISE EXCEPTION 'RW105_C2_CLOSE_NEGATIVE_UNEXPECTED:%',v_err;
    END IF;
  END;

  IF EXISTS (
    SELECT 1 FROM programacion.engineering_work_checkpoints
    WHERE work_item_id=v_work
      AND checkpoint_code=v_cp
      AND assertion_receipt_sha256 IS NOT NULL
  )
  THEN
    RAISE EXCEPTION 'RW105_C2_CLOSE_NEGATIVE_LEFT_RESIDUE';
  END IF;

  -- Trial 1 rolls back assertion + transition. Trial 2 is the real closure.
  FOR v_trial IN 1..2 LOOP
    BEGIN
      v_bootstrap:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
      IF v_bootstrap#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM v_cp
         OR v_bootstrap->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
      THEN
        RAISE EXCEPTION 'RW105_C2_CLOSE_NOT_CURRENT_BEFORE_TRIAL:%',v_bootstrap::text;
      END IF;

      v_receipt:=programacion.fn_engineering_checkpoint_assertion_record_v1(
        v_plan,v_unit,v_cp,
        jsonb_build_object(
          'status','PASS',
          'evidence_ref',v_evidence_ref,
          'observed',v_observed
        ),
        v_actor
      );

      IF v_receipt->>'passed' IS DISTINCT FROM 'true'
         OR v_receipt->>'contract_sha256' IS DISTINCT FROM v_contract_sha
         OR coalesce(v_receipt->>'assertion_receipt_sha256','') !~ '^[0-9a-f]{64}$'
      THEN
        RAISE EXCEPTION 'RW105_C2_CLOSE_ASSERTION_RECEIPT_INVALID:%',v_receipt::text;
      END IF;

      v_result:=programacion.fn_engineering_checkpoint_transition_v1(
        v_plan,v_unit,v_cp,'DONE',v_evidence_ref,v_actor,
        'RW1-05_C2: real semantic shadow PASS; GPT_NATIVE canary 11/11 PASS; execution COMPLETED; terminal authority receipt READY; REMOTE_API not required; no T3/cutover.'
      );

      IF v_result#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
      THEN
        RAISE EXCEPTION 'RW105_C2_CLOSE_TRANSITION_NOT_APPLIED:%',v_result::text;
      END IF;

      IF NOT EXISTS (
        SELECT 1
        FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=v_work
          AND checkpoint_code=v_cp
          AND status='DONE'
          AND evidence_ref=v_evidence_ref
          AND assertion_contract_sha256=v_contract_sha
          AND assertion_receipt_sha256=v_receipt->>'assertion_receipt_sha256'
          AND assertion_receipt_sha256=programacion.fn_v09_sha256_jsonb(assertion_receipt)
      )
      OR NOT EXISTS (
        SELECT 1
        FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=v_work
          AND checkpoint_code='RW1-05_C3'
          AND status='PENDING'
      )
      THEN
        RAISE EXCEPTION 'RW105_C2_CLOSE_DONE_READBACK_FAILED';
      END IF;

      v_bootstrap:=programacion.fn_engineering_unit_bootstrap_v3(v_plan,v_unit);
      IF v_bootstrap#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'RW1-05_C3'
         OR coalesce((v_bootstrap#>>'{state,done_checkpoint_count}')::integer,-1)<>2
         OR coalesce((v_bootstrap#>>'{state,progress_pct}')::numeric,-1)<>66.67
      THEN
        RAISE EXCEPTION 'RW105_C2_CLOSE_NEXT_BOOTSTRAP_WRONG:%',v_bootstrap::text;
      END IF;

      IF v_trial=1 THEN
        RAISE EXCEPTION 'RW105_C2_CLOSE_POSITIVE_ROLLBACK_SENTINEL' USING ERRCODE='PZ088';
      END IF;
    EXCEPTION WHEN SQLSTATE 'PZ088' THEN
      IF v_trial<>1 THEN
        RAISE EXCEPTION 'RW105_C2_CLOSE_UNEXPECTED_ROLLBACK_SENTINEL';
      END IF;
    END;

    IF v_trial=1 AND (
      NOT EXISTS (
        SELECT 1
        FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=v_work
          AND checkpoint_code=v_cp
          AND status='PENDING'
          AND assertion_receipt_sha256 IS NULL
      )
      OR NOT EXISTS (
        SELECT 1
        FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=v_work
          AND checkpoint_code='RW1-05_C3'
          AND status='PENDING'
      )
    )
    THEN
      RAISE EXCEPTION 'RW105_C2_CLOSE_ROLLBACK_LEFT_RESIDUE';
    END IF;
  END LOOP;

  IF (SELECT status FROM programacion.engineering_work_items WHERE id=v_work)
       IS DISTINCT FROM 'IN_PROGRESS'
  THEN
    RAISE EXCEPTION 'RW105_C2_CLOSE_WORK_ITEM_PREMATURE_TERMINAL';
  END IF;

  IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND status='DONE')<>2
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work AND status='PENDING')<>1
  THEN
    RAISE EXCEPTION 'RW105_C2_CLOSE_FINAL_LEDGER_SHAPE_INVALID';
  END IF;
END
$rw105_c2_close$;

COMMIT;
