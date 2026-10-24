-- Remove profile-specific literals from the governed GPT_NATIVE profile runtime.
-- Historical canary migrations remain immutable evidence; runtime decisions become profile-dynamic.
BEGIN;

DO $guard_current_sources$
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure
     )) <> 'fceff0c8e79a9974f92a6de879e0c09e' THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_DEHARDCODE_BRIDGE_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_profile_execution_canonical_read_judge_v1(text)'::regprocedure
     )) <> '7f7dcf605180af2a866e02d9d823706c' THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_DEHARDCODE_JUDGE_SOURCE_DRIFT';
  END IF;
END
$guard_current_sources$;


-- The bridge already resolves the target profile dynamically from the execution.
-- Fix the remaining Product-Director-specific action label.
DO $patch_bridge_action$
DECLARE
  v_def text;
  v_old text;
  v_new text;
BEGIN
  v_def:=pg_get_functiondef(
    'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure
  );

  v_old:=E'''next_action'', ''EXECUTE_PRODUCT_DIRECTOR_IN_CURRENT_GPT_NATIVE_CONTEXT''';
  v_new:=E'''next_action'', ''EXECUTE_PROFILE_IN_CURRENT_GPT_NATIVE_CONTEXT''';

  IF strpos(v_def,v_old)=0 THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_DEHARDCODE_BRIDGE_ACTION_ANCHOR_MISSING';
  END IF;

  v_def:=replace(v_def,v_old,v_new);
  EXECUTE v_def;
END
$patch_bridge_action$;


-- Keep the existing function name/mode so historical semantic receipts remain
-- re-validatable, but make eligibility and semantic binding profile-agnostic.
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
  v_handoff jsonb;
  v_handoff_validation jsonb;
  v_profile_slug text;
  v_pc jsonb;
  v_out jsonb;
  v_direct_rules jsonb;
  v_blockers jsonb;
  v_assumptions jsonb;
  v_direct_ref text;
  v_effective_ref text;
  v_subject text;
  v_direct_count integer;
  v_effective_count integer;
  v_candidate_digest text;
  v_scope_digest text;
  v_out_text text;
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

  IF NOT FOUND THEN
    v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_EXECUTION_AUTHORITY_INVALID');
  ELSE
    v_handoff:=e.manifest->'router_profile_handoff';

    IF e.operation_code<>'EJECUCION_PERFIL_LF'
       OR e.target_type<>'PERFIL'
       OR e.status NOT IN ('IN_PROGRESS','COMPLETED')
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

    v_handoff_validation:=public.lf_router_profile_execution_handoff_validate_v1(
      v_handoff,
      v_handoff->>'literal_request',
      e.target_code
    );

    IF coalesce((v_handoff_validation->>'valid')::boolean,false) IS NOT TRUE
       OR v_handoff->>'profile_code' IS DISTINCT FROM e.target_code THEN
      v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_PROFILE_HANDOFF_INVALID');
    END IF;

    SELECT a.metadata->>'profile_slug'
      INTO v_profile_slug
    FROM public.lf_activos a
    WHERE a.codigo_activo=e.target_code
      AND a.tipo_activo='PERFIL'
      AND a.archived_at IS NULL
    LIMIT 1;

    IF nullif(v_profile_slug,'') IS NULL THEN
      v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_PROFILE_REGISTRY_UNRESOLVED');
    END IF;
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
         WHERE jsonb_typeof(r.value)<>'array'
           OR jsonb_array_length(r.value)<>3
           OR EXISTS(
             SELECT 1
             FROM jsonb_array_elements(r.value) f(value)
             WHERE jsonb_typeof(f.value)<>'string'
               OR nullif(btrim(f.value#>>'{}'),'') IS NULL
           )
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
     OR (
       nullif(v_out->>'worker','') IS NOT NULL
       AND nullif(v_profile_slug,'') IS NOT NULL
       AND v_out->>'worker' IS DISTINCT FROM v_profile_slug
     )
     OR (
       nullif(v_out->>'self_verdict','') IS NOT NULL
       AND v_out->>'self_verdict'<>'PASS'
     )
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

  v_out_text:=coalesce(v_out::text,'');

  -- Capability-level semantic binding: the producer schema may vary by profile,
  -- but the canonical subject, both authoritative refs and both server-derived
  -- counts must be represented in the validated candidate.
  IF nullif(v_subject,'') IS NULL
     OR nullif(v_direct_ref,'') IS NULL
     OR nullif(v_effective_ref,'') IS NULL
     OR position(v_subject in v_out_text)=0
     OR position(v_direct_ref in v_out_text)=0
     OR position(v_effective_ref in v_out_text)=0
     OR position(v_direct_count::text in v_out_text)=0
     OR position(v_effective_count::text in v_out_text)=0
  THEN
    v_hard:=v_hard||jsonb_build_array('CANONICAL_READ_MATERIAL_CLAIMS_NOT_DERIVED');
  END IF;

  v_blockers:=v_out#>'{deliverable_created,blockers}';
  v_assumptions:=v_out#>'{deliverable_created,open_assumptions}';

  IF (v_blockers IS NOT NULL AND (
        jsonb_typeof(v_blockers)<>'array'
        OR jsonb_array_length(v_blockers)<>0
      ))
     OR (v_assumptions IS NOT NULL AND (
        jsonb_typeof(v_assumptions)<>'array'
        OR jsonb_array_length(v_assumptions)<>0
      ))
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
+'Producer-independent deterministic semantic judge for exact PRODUCTO canonical-rule reads. Profile identity is derived from the governed execution/handoff and lf_activos registry; no profile name, output type, rubric score or downstream target is hardcoded.';


DO $postcheck$
DECLARE
  v_judge_def text;
  v_bridge_def text;
  v_exec text;
  v_recorded jsonb;
  v_readback jsonb;
BEGIN
  v_judge_def:=pg_get_functiondef(
    'public.lf_profile_execution_canonical_read_judge_v1(text)'::regprocedure
  );
  v_bridge_def:=pg_get_functiondef(
    'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure
  );

  IF position('EXECUTE_PRODUCT_DIRECTOR_IN_CURRENT_GPT_NATIVE_CONTEXT' in v_bridge_def)>0
     OR position('EXECUTE_PROFILE_IN_CURRENT_GPT_NATIVE_CONTEXT' in v_bridge_def)=0 THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_DEHARDCODE_BRIDGE_ACTION_NOT_GENERIC';
  END IF;

  IF position('PERFIL-PRODUCT-DIRECTOR-LF' in v_judge_def)>0
     OR position('product_director_lf' in v_judge_def)>0
     OR position('PRODUCT_DIRECTION_SPEC' in v_judge_def)>0
     OR position('Orchestrator' in v_judge_def)>0
     OR position('B2B-AUTH-001' in v_judge_def)>0
     OR position('EXEC-PROFILE-GATE2-' in v_judge_def)>0
     OR position('score,total' in v_judge_def)>0 THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_DEHARDCODE_PROFILE_LITERAL_REMAINS';
  END IF;

  IF position('lf_router_profile_execution_handoff_validate_v1' in v_judge_def)=0
     OR position('e.target_code' in v_judge_def)=0
     OR position('profile_slug' in v_judge_def)=0
     OR position('direct_rules_ref' in v_judge_def)=0
     OR position('effective_rules_ref' in v_judge_def)=0 THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_DEHARDCODE_DYNAMIC_BINDING_MISSING';
  END IF;

  IF has_function_privilege(
       'supabase_read_only_user',
       'public.lf_profile_execution_canonical_read_judge_v1(text)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'CANONICAL_READ_JUDGE_DIRECT_READ_ONLY_EXECUTION_FORBIDDEN';
  END IF;

  -- Re-derive one already-closed deterministic canonical-read receipt, if one
  -- exists, proving that historical evidence still validates after de-hardcoding.
  SELECT s.execution_id,
         s.evidence_payload->'semantic_judge_result'
    INTO v_exec,v_recorded
  FROM public.lf_operation_execution_steps s
  JOIN public.lf_operation_execution e USING (execution_id)
  WHERE s.step_id='semantic_judge'
    AND s.status='STEP_PASS_WITH_EVIDENCE'
    AND s.evidence_payload#>>'{semantic_judge_result,judge_mode}'
          ='DETERMINISTIC_CANONICAL_READ_V1'
    AND e.status='COMPLETED'
  ORDER BY s.created_at DESC NULLS LAST
  LIMIT 1;

  IF v_exec IS NOT NULL THEN
    v_readback:=public.lf_profile_execution_canonical_read_judge_v1(v_exec);
    IF v_readback IS DISTINCT FROM v_recorded THEN
      RAISE EXCEPTION 'PROFILE_NATIVE_DEHARDCODE_HISTORICAL_RECEIPT_DRIFT:execution=%',v_exec;
    END IF;
  END IF;
END
$postcheck$;

COMMIT;
