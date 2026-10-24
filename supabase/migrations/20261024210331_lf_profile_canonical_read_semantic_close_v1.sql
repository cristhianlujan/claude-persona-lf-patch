-- Deterministic independent judge for exact canonical Product reads.
-- It does NOT bypass semantic_judge: it implements that mandatory step without a
-- model only when every material statement is server-verifiable from the frozen
-- Router/Input/Context/RAW chain. All other profile work retains the 1-model rule.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_profile_execution_canonical_read_judge_v1(
  p_execution_id text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_input public.lf_operation_execution_steps%rowtype;
  v_context public.lf_operation_execution_steps%rowtype;
  v_execute public.lf_operation_execution_steps%rowtype;
  v_validate public.lf_operation_execution_steps%rowtype;
  v_pc jsonb;
  v_out jsonb;
  v_direct_rules jsonb;
  v_source_refs jsonb;
  v_claims jsonb;
  v_blockers jsonb;
  v_assumptions jsonb;
  v_direct_ref text;
  v_effective_ref text;
  v_subject text;
  v_direct_count integer;
  v_effective_count integer;
  v_candidate_digest text;
  v_scope_digest text;
  v_selected text;
  v_hard jsonb:='[]'::jsonb;
  v_body jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'verdict','BLOCKED_DETERMINISTIC_CANONICAL_READ',
      'blocking_codes',jsonb_build_array('CANONICAL_READ_EXECUTION_ID_REQUIRED'),
      'judge_mode','DETERMINISTIC_CANONICAL_READ_V1',
      'producer_independence_proven',true,
      'model_call_count',0
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.target_code<>'PERFIL-PRODUCT-DIRECTOR-LF'
     OR e.status<>'IN_PROGRESS'
     OR e.manifest->>'executor_mode'<>'GPT_NATIVE'
     OR e.manifest->>'executor_provider'<>'OPENAI_CHATGPT_NATIVE'
     OR coalesce((e.manifest->>'read_only')::boolean,false) IS NOT TRUE
     OR coalesce((e.manifest->>'no_write')::boolean,false) IS NOT TRUE
     OR coalesce((e.manifest->>'no_promotion')::boolean,false) IS NOT TRUE
     OR e.manifest#>>'{router_profile_handoff,channel}'<>'PRODUCTO'
     OR e.manifest#>>'{router_profile_handoff,business}'<>'LF'
     OR e.manifest#>>'{router_profile_handoff,semantic_request,router_action_binding,profile_task_intent}'
          <>'READ_PRODUCT_DEFINITION'
     OR e.manifest#>>'{router_profile_handoff,semantic_request,router_action_binding,input_governance_requirement}'
          <>'NOT_REQUIRED_CANONICAL_READ'
  THEN
    v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_EXECUTION_AUTHORITY_INVALID');
  END IF;

  SELECT * INTO v_input
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='input_validate'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_input.step_id IS NULL
     OR v_input.evidence_payload#>>'{input_governance,status}'<>'NOT_REQUIRED'
     OR v_input.evidence_payload#>>'{input_governance,decision}'<>'SKIP'
     OR v_input.evidence_payload#>>'{input_governance,profile_task_intent}'<>'READ_PRODUCT_DEFINITION'
     OR v_input.evidence_payload#>>'{input_governance,input_governance_requirement}'<>'NOT_REQUIRED_CANONICAL_READ'
     OR coalesce((v_input.evidence_payload#>>'{input_governance,continuation_allowed}')::boolean,false) IS NOT TRUE
     OR coalesce((v_input.evidence_payload#>>'{input_governance,router_reentry_required}')::boolean,true) IS TRUE
  THEN
    v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_INPUT_GOVERNANCE_INVALID');
  END IF;

  v_scope_digest:=v_input.evidence_payload->>'scope_authority_packet_sha256';
  IF coalesce(v_scope_digest,'') !~ '^sha256:[0-9a-f]{64}$' THEN
    v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_SCOPE_DIGEST_INVALID');
  END IF;

  SELECT * INTO v_context
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='context_admission'
    AND status='STEP_PASS_WITH_EVIDENCE';

  v_pc:=v_context.evidence_payload#>'{context_capsule,channel_context,product_context}';
  IF v_context.step_id IS NULL
     OR jsonb_typeof(v_pc)<>'object'
     OR v_pc->>'schema_version'<>'LF_PRODUCT_CANONICAL_RULE_READ_V1'
     OR nullif(v_pc->>'subject_ref','') IS NULL
     OR nullif(v_pc->>'direct_rules_ref','') IS NULL
     OR nullif(v_pc->>'effective_rules_ref','') IS NULL
     OR coalesce(v_pc->>'direct_rule_count','') !~ '^[0-9]+$'
     OR coalesce(v_pc->>'effective_rule_count','') !~ '^[0-9]+$'
     OR jsonb_typeof(v_pc->'direct_rules')<>'array'
  THEN
    v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_CONTEXT_INVALID');
  ELSE
    v_subject:=v_pc->>'subject_ref';
    v_direct_ref:=v_pc->>'direct_rules_ref';
    v_effective_ref:=v_pc->>'effective_rules_ref';
    v_direct_count:=(v_pc->>'direct_rule_count')::integer;
    v_effective_count:=(v_pc->>'effective_rule_count')::integer;
    v_direct_rules:=v_pc->'direct_rules';

    IF v_direct_count<=0
       OR v_effective_count<v_direct_count
       OR jsonb_array_length(v_direct_rules)<>v_direct_count
       OR EXISTS(
         SELECT 1
         FROM jsonb_array_elements(v_direct_rules) r(value)
         WHERE jsonb_typeof(r.value)<>'object'
           OR nullif(r.value->>'code','') IS NULL
           OR nullif(r.value->>'title','') IS NULL
           OR nullif(r.value->>'status','') IS NULL
       )
    THEN
      v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_RULE_PROJECTION_INVALID');
    END IF;
  END IF;

  SELECT * INTO v_execute
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='execute_profile'
    AND status='STEP_PASS_WITH_EVIDENCE';

  SELECT * INTO v_validate
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='output_validate'
    AND status='STEP_PASS_WITH_EVIDENCE';

  v_out:=v_execute.evidence_payload->'profile_output';
  v_candidate_digest:=v_execute.evidence_payload->>'candidate_digest';

  IF v_execute.step_id IS NULL
     OR jsonb_typeof(v_out)<>'object'
     OR coalesce(v_candidate_digest,'') !~ '^sha256:[0-9a-f]{64}$'
     OR v_candidate_digest IS DISTINCT FROM
        'sha256:'||encode(
          extensions.digest(convert_to(v_out::text,'UTF8'),'sha256'),'hex'
        )
     OR v_out->>'worker'<>'product_director_lf'
     OR v_out->>'output_type'<>'PRODUCT_DIRECTION_SPEC'
     OR v_out->>'self_verdict'<>'PASS'
     OR v_out#>>'{traceability,execution_id}' IS DISTINCT FROM p_execution_id
     OR v_out#>>'{deliverable_created,authority_status}'<>'SUPPORTED'
     OR v_out#>>'{deliverable_created,handoff_to_next,target}'<>'Orchestrator'
     OR coalesce((v_out#>>'{score,total}')::integer,0)<22
  THEN
    v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_PRODUCER_OUTPUT_INVALID');
  END IF;

  IF v_validate.step_id IS NULL
     OR v_validate.evidence_payload->>'output_contract_result'<>'PASS'
     OR coalesce((v_validate.evidence_payload#>>'{deterministic_validation,valid}')::boolean,false) IS NOT TRUE
     OR v_validate.evidence_payload#>>'{deterministic_validation,status}'<>'PASS'
     OR v_validate.evidence_payload->>'raw_output_sha256'
          IS DISTINCT FROM substr(v_candidate_digest,8)
  THEN
    v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_OUTPUT_VALIDATOR_NOT_PASS');
  END IF;

  v_source_refs:=v_out#>'{deliverable_created,product_decision,source_refs}';
  v_claims:=v_out#>'{deliverable_created,material_claims}';
  v_blockers:=v_out#>'{deliverable_created,blockers}';
  v_assumptions:=v_out#>'{deliverable_created,open_assumptions}';
  v_selected:=v_out#>>'{deliverable_created,product_decision,selected_decision}';

  IF jsonb_typeof(v_source_refs)<>'array'
     OR NOT EXISTS(
       SELECT 1 FROM jsonb_array_elements(v_source_refs) s(value)
       WHERE s.value->>'source_ref'=v_direct_ref
         AND s.value->>'authority'='AUTHORITATIVE'
         AND coalesce((s.value->>'current')::boolean,false)
     )
     OR NOT EXISTS(
       SELECT 1 FROM jsonb_array_elements(v_source_refs) s(value)
       WHERE s.value->>'source_ref'=v_effective_ref
         AND s.value->>'authority'='AUTHORITATIVE'
         AND coalesce((s.value->>'current')::boolean,false)
     )
  THEN
    v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_SOURCE_BINDING_INVALID');
  END IF;

  IF jsonb_typeof(v_claims)<>'array'
     OR NOT EXISTS(
       SELECT 1 FROM jsonb_array_elements(v_claims) c(value)
       WHERE c.value->>'authority_ref'=v_direct_ref
         AND c.value->>'status'='SUPPORTED'
         AND position(v_direct_count::text in coalesce(c.value->>'claim',''))>0
         AND position(v_subject in coalesce(c.value->>'claim',''))>0
     )
     OR NOT EXISTS(
       SELECT 1 FROM jsonb_array_elements(v_claims) c(value)
       WHERE c.value->>'authority_ref'=v_effective_ref
         AND c.value->>'status'='SUPPORTED'
         AND position(v_effective_count::text in coalesce(c.value->>'claim',''))>0
         AND position(v_subject in coalesce(c.value->>'claim',''))>0
     )
     OR nullif(v_selected,'') IS NULL
     OR position(v_direct_count::text in v_selected)=0
     OR position(v_effective_count::text in v_selected)=0
     OR position(v_subject in v_selected)=0
  THEN
    v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_MATERIAL_CLAIMS_NOT_DERIVED');
  END IF;

  IF jsonb_typeof(v_blockers)<>'array'
     OR jsonb_array_length(v_blockers)<>0
     OR jsonb_typeof(v_assumptions)<>'array'
     OR jsonb_array_length(v_assumptions)<>0
  THEN
    v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_UNRESOLVED_BLOCKER_OR_ASSUMPTION');
  END IF;

  IF jsonb_array_length(v_hard)>0 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'verdict','BLOCKED_DETERMINISTIC_CANONICAL_READ',
      'validator_status',case
        when v_validate.evidence_payload#>>'{deterministic_validation,status}'='PASS'
          then 'PASS' else 'BLOCKED' end,
      'producer_independence_proven',true,
      'model_call_count',0,
      'judge_mode','DETERMINISTIC_CANONICAL_READ_V1',
      'candidate_sha256',case
        when coalesce(v_candidate_digest,'') ~ '^sha256:[0-9a-f]{64}$'
          then substr(v_candidate_digest,8) else null end,
      'scope_packet_sha256',case
        when coalesce(v_scope_digest,'') ~ '^sha256:[0-9a-f]{64}$'
          then substr(v_scope_digest,8) else null end,
      'blocking_codes',v_hard,
      'unsupported_claims','[]'::jsonb,
      'result',jsonb_build_object(
        'verdict','BLOCKED_DETERMINISTIC_CANONICAL_READ',
        'candidate_sha256',case
          when coalesce(v_candidate_digest,'') ~ '^sha256:[0-9a-f]{64}$'
            then substr(v_candidate_digest,8) else null end,
        'scope_packet_sha256',case
          when coalesce(v_scope_digest,'') ~ '^sha256:[0-9a-f]{64}$'
            then substr(v_scope_digest,8) else null end,
        'unsupported_claims','[]'::jsonb,
        'blocking_codes',v_hard
      )
    );
  END IF;

  v_body:=jsonb_build_object(
    'status','PASS',
    'verdict','PASS_INDEPENDENT_SEMANTIC',
    'validator_status','PASS',
    'producer_independence_proven',true,
    'model_call_count',0,
    'judge_mode','DETERMINISTIC_CANONICAL_READ_V1',
    'candidate_sha256',substr(v_candidate_digest,8),
    'scope_packet_sha256',substr(v_scope_digest,8),
    'unsupported_claims','[]'::jsonb,
    'deterministic_readback',jsonb_build_object(
      'profile_task_intent','READ_PRODUCT_DEFINITION',
      'input_governance_requirement','NOT_REQUIRED_CANONICAL_READ',
      'product_context_schema','LF_PRODUCT_CANONICAL_RULE_READ_V1',
      'subject_ref',v_subject,
      'direct_rule_count',v_direct_count,
      'effective_rule_count',v_effective_count,
      'direct_rules_ref',v_direct_ref,
      'effective_rules_ref',v_effective_ref,
      'output_validator','PASS',
      'no_write',true
    ),
    'result',jsonb_build_object(
      'verdict','PASS_INDEPENDENT_SEMANTIC',
      'judge_mode','DETERMINISTIC_CANONICAL_READ_V1',
      'candidate_sha256',substr(v_candidate_digest,8),
      'scope_packet_sha256',substr(v_scope_digest,8),
      'unsupported_claims','[]'::jsonb,
      'blocking_codes','[]'::jsonb
    )
  );
  RETURN v_body;
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_execution_canonical_read_judge_v1(text)
  FROM PUBLIC,anon,authenticated,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_profile_execution_canonical_read_judge_v1(text)
  TO service_role;

COMMENT ON FUNCTION public.lf_profile_execution_canonical_read_judge_v1(text) IS
'Producer-independent deterministic semantic judge for exact PRODUCTO canonical-rule reads only. Requires Router-signed READ_PRODUCT_DEFINITION + NOT_REQUIRED_CANONICAL_READ, exact Context Pack refs/counts, clean Product Director validator, derived claims and zero unresolved assumptions. Does not generalize to analysis/change work.';


DO $patch_semantic_trust$
DECLARE
  v_def text;
  v_old_decl text;
  v_new_decl text;
  v_old_assign text;
  v_new_assign text;
  v_old_mode text;
  v_new_mode text;
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_profile_execution_trust_validation_v2(text,text,jsonb)'::regprocedure
     )) <> '5439d223f2dd925d5ac534b107ffc5a0' THEN
    RAISE EXCEPTION 'CANONICAL_READ_JUDGE_TRUST_V2_SOURCE_DRIFT';
  END IF;

  v_def:=pg_get_functiondef(
    'public.lf_profile_execution_trust_validation_v2(text,text,jsonb)'::regprocedure
  );

  v_old_decl:=E'  semantic_result jsonb;\n  hard jsonb := ''[]''::jsonb;\n';
  v_new_decl:=E'  semantic_result jsonb;\n'
    ||E'  canonical_read_judge jsonb;\n'
    ||E'  hard jsonb := ''[]''::jsonb;\n';

  IF strpos(v_def,v_old_decl)=0 THEN
    RAISE EXCEPTION 'CANONICAL_READ_JUDGE_TRUST_DECL_ANCHOR_MISSING';
  END IF;
  v_def:=replace(v_def,v_old_decl,v_new_decl);

  v_old_assign:=E'    semantic_result:=p_evidence_payload->''semantic_judge_result'';\n\n'
    ||E'    if jsonb_typeof(semantic_result)<>''object''';
  v_new_assign:=E'    semantic_result:=p_evidence_payload->''semantic_judge_result'';\n'
    ||E'    canonical_read_judge:=public.lf_profile_execution_canonical_read_judge_v1(p_execution_id);\n\n'
    ||E'    if jsonb_typeof(semantic_result)<>''object''';

  IF strpos(v_def,v_old_assign)=0 THEN
    RAISE EXCEPTION 'CANONICAL_READ_JUDGE_TRUST_ASSIGN_ANCHOR_MISSING';
  END IF;
  v_def:=replace(v_def,v_old_assign,v_new_assign);

  v_old_mode:=E'       or coalesce((semantic_result->>''producer_independence_proven'')::boolean,false) is not true\n'
    ||E'       or coalesce((semantic_result->>''model_call_count'')::integer,0)<>1\n';
  v_new_mode:=E'       or coalesce((semantic_result->>''producer_independence_proven'')::boolean,false) is not true\n'
    ||E'       or not (\n'
    ||E'         coalesce((semantic_result->>''model_call_count'')::integer,0)=1\n'
    ||E'         or (\n'
    ||E'           coalesce((semantic_result->>''model_call_count'')::integer,-1)=0\n'
    ||E'           and semantic_result->>''judge_mode''=''DETERMINISTIC_CANONICAL_READ_V1''\n'
    ||E'           and canonical_read_judge->>''status''=''PASS''\n'
    ||E'           and semantic_result is not distinct from canonical_read_judge\n'
    ||E'         )\n'
    ||E'       )\n';

  IF strpos(v_def,v_old_mode)=0 THEN
    RAISE EXCEPTION 'CANONICAL_READ_JUDGE_TRUST_MODEL_ANCHOR_MISSING';
  END IF;
  v_def:=replace(v_def,v_old_mode,v_new_mode);

  EXECUTE v_def;
END
$patch_semantic_trust$;


DO $close_login_rules_canary$
DECLARE
  v_exec constant text:='EXEC-PROFILE-GATE2-1BDAD35D77DC30810DE68282';
  v_judge jsonb;
  v_semantic_record jsonb;
  v_report_record jsonb;
  v_attach jsonb;
  v_terminal jsonb;
  v_clean integer;
BEGIN
  v_judge:=public.lf_profile_execution_canonical_read_judge_v1(v_exec);

  IF v_judge->>'status'<>'PASS'
     OR v_judge->>'verdict'<>'PASS_INDEPENDENT_SEMANTIC'
     OR v_judge->>'judge_mode'<>'DETERMINISTIC_CANONICAL_READ_V1'
     OR coalesce((v_judge->>'producer_independence_proven')::boolean,false) IS NOT TRUE
     OR coalesce((v_judge->>'model_call_count')::integer,-1)<>0
     OR jsonb_array_length(v_judge->'unsupported_claims')<>0
  THEN
    RAISE EXCEPTION 'LOGIN_RULES_CANONICAL_READ_JUDGE_NOT_PASS:%',v_judge;
  END IF;

  v_semantic_record:=public.lf_record_profile_execution_step_v1(
    v_exec,
    'semantic_judge',
    'supabase://public.lf_profile_execution_canonical_read_judge_v1/'||v_exec,
    jsonb_build_object(
      'semantic_judge_result',v_judge,
      'unsupported_claims','[]'::jsonb
    ),
    v_exec
  );

  IF v_semantic_record->>'outcome'<>'STEP_RECORDED'
     OR v_semantic_record->>'status'<>'STEP_PASS_WITH_EVIDENCE' THEN
    RAISE EXCEPTION 'LOGIN_RULES_CANONICAL_READ_SEMANTIC_RECORD_FAILED:%',v_semantic_record;
  END IF;

  v_report_record:=public.lf_record_profile_execution_step_v1(
    v_exec,
    'report_output',
    'supabase://public.lf_operation_execution_steps/'||v_exec||'/report_output',
    jsonb_build_object(
      'result','PASS_INDEPENDENT_SEMANTIC',
      'profile_code','PERFIL-PRODUCT-DIRECTOR-LF',
      'execution_id',v_exec,
      'no_write_performed',true,
      'candidate_sha256',v_judge->>'candidate_sha256',
      'scope_packet_sha256',v_judge->>'scope_packet_sha256',
      'judge_mode','DETERMINISTIC_CANONICAL_READ_V1',
      'model_call_count',0,
      'next_gate','RETURN_TO_ROUTER'
    ),
    v_exec
  );

  IF v_report_record->>'outcome'<>'STEP_RECORDED'
     OR v_report_record->>'status'<>'STEP_PASS_WITH_EVIDENCE' THEN
    RAISE EXCEPTION 'LOGIN_RULES_CANONICAL_READ_REPORT_RECORD_FAILED:%',v_report_record;
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=v_exec
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_clean<>11
     OR (SELECT status FROM public.lf_operation_execution WHERE execution_id=v_exec)<>'COMPLETED' THEN
    RAISE EXCEPTION 'LOGIN_RULES_CANONICAL_READ_NOT_11_OF_11:clean=% status=%',
      v_clean,
      (SELECT status FROM public.lf_operation_execution WHERE execution_id=v_exec);
  END IF;

  v_terminal:=public.lf_profile_execution_terminal_authority_receipt_v1(v_exec);
  IF v_terminal->>'status'<>'READY' THEN
    RAISE EXCEPTION 'LOGIN_RULES_CANONICAL_READ_TERMINAL_NOT_READY:%',v_terminal;
  END IF;

  v_attach:=public.lf_profile_execution_attach_terminal_authority_receipt_v1(v_exec,v_exec);
  IF v_attach->>'result' NOT IN (
    'TERMINAL_AUTHORITY_RECEIPT_ATTACHED',
    'TERMINAL_AUTHORITY_RECEIPT_ALREADY_ATTACHED'
  ) THEN
    RAISE EXCEPTION 'LOGIN_RULES_CANONICAL_READ_TERMINAL_ATTACH_FAILED:%',v_attach;
  END IF;
END
$close_login_rules_canary$;


DO $postcheck$
DECLARE
  v_exec constant text:='EXEC-PROFILE-GATE2-1BDAD35D77DC30810DE68282';
  v_judge jsonb;
  v_terminal jsonb;
  v_count integer;
  v_def text;
BEGIN
  v_judge:=public.lf_profile_execution_canonical_read_judge_v1(v_exec);
  v_terminal:=public.lf_profile_execution_terminal_authority_receipt_v1(v_exec);

  SELECT count(*) INTO v_count
  FROM public.lf_operation_execution_steps
  WHERE execution_id=v_exec
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_count<>11
     OR (SELECT status FROM public.lf_operation_execution WHERE execution_id=v_exec)<>'COMPLETED'
     OR v_judge->>'status'<>'PASS'
     OR v_judge->>'judge_mode'<>'DETERMINISTIC_CANONICAL_READ_V1'
     OR coalesce((v_judge->>'model_call_count')::integer,-1)<>0
     OR v_terminal->>'status'<>'READY'
     OR v_terminal#>>'{terminal_authority_receipt,report_output_receipt,judge_mode}'
          <>'DETERMINISTIC_CANONICAL_READ_V1'
     OR v_terminal#>>'{terminal_authority_receipt,report_output_receipt,model_call_count}'
          <>'0'
  THEN
    RAISE EXCEPTION 'LOGIN_RULES_CANONICAL_READ_TERMINAL_POSTCHECK_FAILED';
  END IF;

  v_def:=pg_get_functiondef(
    'public.lf_profile_execution_trust_validation_v2(text,text,jsonb)'::regprocedure
  );
  IF position('DETERMINISTIC_CANONICAL_READ_V1' in v_def)=0
     OR position('semantic_result is not distinct from canonical_read_judge' in v_def)=0
     OR position('model_call_count' in v_def)=0 THEN
    RAISE EXCEPTION 'CANONICAL_READ_JUDGE_TRUST_PATCH_NOT_INSTALLED';
  END IF;

  IF has_function_privilege(
       'supabase_read_only_user',
       'public.lf_profile_execution_canonical_read_judge_v1(text)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'CANONICAL_READ_JUDGE_DIRECT_READ_ONLY_EXECUTION_FORBIDDEN';
  END IF;
END
$postcheck$;

COMMIT;
