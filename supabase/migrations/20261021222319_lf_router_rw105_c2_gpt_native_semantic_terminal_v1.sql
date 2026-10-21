-- RW1-05_C2 — forward-only candidate for canonical LF Migration Merge Train.
-- Scope: same GPT_NATIVE canary execution, exactly steps 10/11, native terminal receipt.
-- No producer rerun, no new execution/queue, no profile state change, no T3/production.
-- Admission: DO NOT APPLY until ACT-0001 grants the exact DB write route and Train gates pass.
-- Engineering checkpoint remains PENDING: closure operation/provider is not active.
BEGIN;
DO $rw105_c2_terminal$
DECLARE
  e CONSTANT text := 'EXEC-RW105-C2-GPT-NATIVE-CANARY-20261021-001';
  p CONSTANT text := 'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF';
  c CONSTANT text := '473b56fcc21b7da9b0b7876231ca69c8873c6935eab9e5db7224cf5bdb326447';
  s CONSTANT text := 'bc61d675317a2cb8bb8eeb12d58c5d2de466a2b1e5440cc1db152f25665f336d';
  raw_sha CONSTANT text := '86cc34048f8436479acff5fe0830b03cc0a8bbaf6f98acfeb31e7d1c094def07';
  judge_ref CONSTANT text := 'github://cristhianlujan/claude-persona-lf-patch/docs/programming-agent/router_wave/RW1_05_C2_GPT_NATIVE_INDEPENDENT_SEMANTIC_JUDGE_20261021_V2.json#blob:e33694f2d277a9d4162b696ed4f2ec90c2cb6629';
  ex public.lf_operation_execution%rowtype;
  input_payload jsonb;
  execute_payload jsonb;
  semantic_receipt jsonb;
  semantic_evidence jsonb;
  report_evidence jsonb;
  record_result jsonb;
  terminal jsonb;
  attachment jsonb;
  final_manifest jsonb;
  old_meta jsonb;
  new_meta jsonb;
  packet jsonb;
  material jsonb;
  j record;
  n integer;
BEGIN
  -- Strict source/current-ledger guard: do not reset or create the execution.
  SELECT * INTO STRICT ex
  FROM public.lf_operation_execution
  WHERE execution_id=e AND operation_code='EJECUCION_PERFIL_LF'
    AND target_type='PERFIL' AND target_code=p AND status='IN_PROGRESS'
  FOR UPDATE;

  IF ex.manifest->>'executor_mode' IS DISTINCT FROM 'GPT_NATIVE'
     OR ex.manifest->>'executor_provider' IS DISTINCT FROM 'OPENAI_CHATGPT_NATIVE'
     OR ex.manifest->>'adapter_id' IS DISTINCT FROM 'chatgpt-native-current-context-v1'
     OR ex.manifest ? 'queue_request_id'
     OR ex.manifest ? 'runtime_target'
     OR ex.manifest->>'host_execution' IS DISTINCT FROM 'FORBIDDEN'
     OR ex.manifest->>'remote_api_fallback' IS DISTINCT FROM 'FORBIDDEN'
     OR coalesce((ex.manifest->>'read_only')::boolean,false) IS NOT TRUE
     OR coalesce((ex.manifest->>'no_write')::boolean,false) IS NOT TRUE
     OR coalesce((ex.manifest->>'no_promotion')::boolean,false) IS NOT TRUE
  THEN RAISE EXCEPTION 'RW105_C2_EXECUTOR_MANIFEST_DRIFT'; END IF;

  SELECT count(*) INTO n FROM public.lf_operation_execution_steps
  WHERE execution_id=e AND status='STEP_PASS_WITH_EVIDENCE';
  IF n<>9 OR EXISTS (
    SELECT 1 FROM public.lf_operation_execution_steps
    WHERE execution_id=e AND step_id IN ('semantic_judge','report_output')
  ) OR EXISTS (
    SELECT 1 FROM public.lf_operation_execution_steps
    WHERE execution_id=e AND status<>'STEP_PASS_WITH_EVIDENCE'
  ) THEN RAISE EXCEPTION 'RW105_C2_9OF11_PRECONDITION_FAILED'; END IF;

  SELECT evidence_payload INTO STRICT input_payload
  FROM public.lf_operation_execution_steps
  WHERE execution_id=e AND step_id='input_validate'
    AND status='STEP_PASS_WITH_EVIDENCE';
  SELECT evidence_payload INTO STRICT execute_payload
  FROM public.lf_operation_execution_steps
  WHERE execution_id=e AND step_id='execute_profile'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF input_payload->>'scope_authority_packet_sha256' IS DISTINCT FROM 'sha256:'||s
     OR execute_payload->>'candidate_digest' IS DISTINCT FROM 'sha256:'||c
     OR execute_payload->>'raw_output_sha256' IS DISTINCT FROM raw_sha
     OR 'sha256:'||encode(extensions.digest(convert_to(
          (execute_payload->'profile_output')::text,'UTF8'),'sha256'),'hex')
        IS DISTINCT FROM 'sha256:'||c
     OR 'sha256:'||encode(extensions.digest(convert_to(
          ((input_payload->'scope_authority_packet')-'sha256')::text,'UTF8'),'sha256'),'hex')
        IS DISTINCT FROM 'sha256:'||s
     OR execute_payload#>>'{profile_output,status}' IS DISTINCT FROM 'RETURN_TO_SOURCE_FOR_READBACK'
     OR execute_payload#>>'{profile_output,routing,pipeline_action}' IS DISTINCT FROM 'RETURN_TO_ORCHESTRATOR'
     OR execute_payload#>>'{profile_output,routing,resolution_target}' IS DISTINCT FROM 'SOURCE_READBACK'
  THEN RAISE EXCEPTION 'RW105_C2_SERVER_BINDING_OR_OUTPUT_DRIFT'; END IF;

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1131 AND checkpoint_code='RW1-05_C2')
      IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'RW105_C2_CHECKPOINT_PREMATURELY_CLOSED'; END IF;

  -- This is the new independent GPT_NATIVE judge verdict, not #3041 or the producer.
  semantic_receipt:=jsonb_build_object(
    'status','PASS',
    'verdict','PASS_INDEPENDENT_SEMANTIC',
    'validator_status','PASS',
    'producer_independence_proven',true,
    'model_call_count',1,
    'candidate_sha256',c,
    'scope_packet_sha256',s,
    'result',jsonb_build_object(
      'verdict','PASS_INDEPENDENT_SEMANTIC',
      'candidate_sha256',c,
      'scope_packet_sha256',s,
      'unsupported_claims','[]'::jsonb,
      'blocking_codes','[]'::jsonb
    )
  );

  semantic_evidence:=jsonb_build_object(
    'semantic_judge_result',semantic_receipt,
    'unsupported_claims','[]'::jsonb,
    'independent_semantic_receipt_ref',judge_ref,
    'producer_receipt_not_used',true,
    'raw_output_sha256',raw_sha
  );
  record_result:=public.lf_record_profile_execution_step_v1(
    e,'semantic_judge',judge_ref,semantic_evidence,e
  );
  IF NOT EXISTS (
     SELECT 1 FROM public.lf_operation_execution_steps
      WHERE execution_id=e AND step_id='semantic_judge'
        AND status='STEP_PASS_WITH_EVIDENCE'
        AND evidence_payload#>>'{semantic_judge_result,verdict}'='PASS_INDEPENDENT_SEMANTIC'
        AND evidence_payload#>>'{semantic_judge_result,candidate_sha256}'=c
        AND evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}'=s
  ) THEN RAISE EXCEPTION 'RW105_C2_SEMANTIC_STEP_NOT_CLEAN:%',record_result; END IF;

  report_evidence:=jsonb_build_object(
    'result','PASS_INDEPENDENT_SEMANTIC',
    'profile_code',p,
    'execution_id',e,
    'no_write_performed',true,
    'candidate_sha256',c,
    'scope_packet_sha256',s,
    'independent_semantic_receipt_ref',judge_ref
  );
  record_result:=public.lf_record_profile_execution_step_v1(
    e,'report_output',
    'supabase://public.lf_operation_execution_steps/'||e||'/semantic_judge#report_output',
    report_evidence,e
  );
  IF NOT EXISTS (
     SELECT 1 FROM public.lf_operation_execution_steps
      WHERE execution_id=e AND step_id='report_output'
        AND status='STEP_PASS_WITH_EVIDENCE'
        AND evidence_payload->>'result'='PASS_INDEPENDENT_SEMANTIC'
        AND evidence_payload->>'execution_id'=e
  ) THEN RAISE EXCEPTION 'RW105_C2_REPORT_STEP_NOT_CLEAN:%',record_result; END IF;

  SELECT required_steps,required_steps_pass,fail_count,blocked_count,judge_result
    INTO STRICT j
    FROM public.v_lf_operation_execution_judge
   WHERE execution_id=e;
  IF j.required_steps<>11 OR j.required_steps_pass<>11
     OR j.fail_count<>0 OR j.blocked_count<>0 OR j.judge_result<>'PASS'
  THEN RAISE EXCEPTION 'RW105_C2_11OF11_NOT_CLEAN'; END IF;

  UPDATE public.lf_operation_execution
     SET status='COMPLETED',completed_at=clock_timestamp(),
         updated_at=clock_timestamp(),updated_by_execution_id=e
   WHERE execution_id=e AND status='IN_PROGRESS'
     AND operation_code='EJECUCION_PERFIL_LF' AND target_code=p;
  IF NOT FOUND THEN RAISE EXCEPTION 'RW105_C2_EXECUTION_COMPLETION_CAS_FAILED'; END IF;

  attachment:=public.lf_profile_execution_attach_terminal_authority_receipt_v1(e,e);
  IF attachment->>'result' NOT IN (
      'TERMINAL_AUTHORITY_RECEIPT_ATTACHED',
      'TERMINAL_AUTHORITY_RECEIPT_ALREADY_ATTACHED'
  ) OR coalesce(attachment->>'terminal_authority_receipt_sha256','') !~ '^sha256:[a-f0-9]{64}$'
  THEN RAISE EXCEPTION 'RW105_C2_TERMINAL_ATTACH_FAILED:%',attachment; END IF;

  terminal:=public.lf_profile_execution_terminal_authority_receipt_v1(e);
  IF terminal->>'status'<>'READY'
     OR terminal->>'terminal_authority_receipt_sha256'
        IS DISTINCT FROM attachment->>'terminal_authority_receipt_sha256'
     OR terminal#>>'{terminal_authority_receipt,canonical_execution_id}' IS DISTINCT FROM e
     OR terminal#>>'{terminal_authority_receipt,executor_mode}' IS DISTINCT FROM 'GPT_NATIVE'
  THEN RAISE EXCEPTION 'RW105_C2_TERMINAL_READBACK_INVALID:%',terminal; END IF;

  SELECT manifest INTO STRICT final_manifest
    FROM public.lf_operation_execution WHERE execution_id=e AND status='COMPLETED';
  IF final_manifest->>'terminal_authority_receipt_sha256'
       IS DISTINCT FROM terminal->>'terminal_authority_receipt_sha256'
     OR final_manifest#>>'{terminal_authority_receipt,sha256}'
       IS DISTINCT FROM terminal->>'terminal_authority_receipt_sha256'
  THEN RAISE EXCEPTION 'RW105_C2_TERMINAL_MANIFEST_NOT_ATTACHED'; END IF;

  -- Remove the outstanding material blocker only after 11/11 + READY receipt.
  -- Do NOT claim governed engineering checkpoint closure; its provider is inactive.
  SELECT unit_metadata INTO STRICT old_meta
    FROM programacion.engineering_plan_units
   WHERE plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1'
     AND unit_code='RW1-05' AND work_item_id=1131 AND disposition='ASSIGNED'
     AND md5(unit_metadata::text)='2fbbbfaa1f5e1d39ac3ef9ffd9188ac8'
   FOR UPDATE;

  IF old_meta#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2,missing_typed}'
     IS DISTINCT FROM '[{"code":"REAL_PROFILE_RUNTIME_CANARY_PENDING","kind":"MATERIAL_EXECUTION","blocking":true}]'::jsonb
  THEN RAISE EXCEPTION 'RW105_C2_BLOCKER_SET_DRIFT'; END IF;

  packet:=old_meta#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2}';
  material:=coalesce(packet->'material_execution_evidence','{}'::jsonb);
  material:=jsonb_set(
    material,'{evidence_lineage_runtime_canary_terminal_v1}',
    jsonb_build_object(
      'status','TERMINAL_AUTHORITY_READY',
      'execution_id',e,'profile_code',p,'executor_mode','GPT_NATIVE',
      'candidate_sha256',c,'scope_packet_sha256',s,
      'raw_output_sha256',raw_sha,
      'semantic_judge_verdict','PASS_INDEPENDENT_SEMANTIC',
      'semantic_judge_receipt_ref',judge_ref,
      'required_steps',11,'required_steps_pass',11,'fail_count',0,'blocked_count',0,
      'judge_result','PASS',
      'terminal_authority_receipt_sha256',terminal->>'terminal_authority_receipt_sha256',
      'terminal_readback_status','READY',
      'engineering_checkpoint_status','PENDING_GOVERNED_CLOSURE'
    ),true
  );
  packet:=jsonb_set(packet,'{missing_typed}','[]'::jsonb,true);
  packet:=jsonb_set(packet,'{material_execution_evidence}',material,true);
  new_meta:=jsonb_set(
    old_meta,'{source_pack_v2,checkpoint_inputs,RW1-05_C2}',packet,false
  );
  UPDATE programacion.engineering_plan_units
     SET unit_metadata=new_meta
   WHERE plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1'
     AND unit_code='RW1-05' AND work_item_id=1131 AND disposition='ASSIGNED'
     AND md5(unit_metadata::text)='2fbbbfaa1f5e1d39ac3ef9ffd9188ac8';
  IF NOT FOUND THEN RAISE EXCEPTION 'RW105_C2_BLOCKER_METADATA_CAS_FAILED'; END IF;

  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1131 AND checkpoint_code='RW1-05_C2')<>'PENDING'
     OR (SELECT unit_metadata#>'{source_pack_v2,checkpoint_inputs,RW1-05_C2,missing_typed}'
           FROM programacion.engineering_plan_units
          WHERE plan_code='LF_ROUTER_ARCHITECTURE_WAVE_V1'
            AND unit_code='RW1-05' AND work_item_id=1131) <> '[]'::jsonb
  THEN RAISE EXCEPTION 'RW105_C2_FINAL_GUARDED_READBACK_FAILED'; END IF;
END
$rw105_c2_terminal$;
COMMIT;
