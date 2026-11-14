-- Exact SELECT pg_get_functiondef() current sandbox source frozen for PG17/18 rollback fixture.
-- public.lf_profile_execution_canonical_read_judge_v1(text)
CREATE OR REPLACE FUNCTION public.lf_profile_execution_canonical_read_judge_v1(p_execution_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
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
$function$
;

-- public.lf_profile_native_bridge_record_output_v1(text,jsonb,jsonb,text,text,text)
CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_record_output_v1(p_execution_id text, p_profile_output jsonb, p_validation jsonb, p_raw_evidence_ref text, p_validator_evidence_ref text, p_actor_execution_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_actor text;
  v_context public.lf_operation_execution_steps%rowtype;
  v_baseline public.lf_operation_execution_steps%rowtype;
  v_source public.lf_operation_execution_steps%rowtype;
  v_existing text;
  v_candidate_digest text;
  v_raw_sha text;
  v_step jsonb;
  v_clean integer;
  v_source_refs jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR jsonb_typeof(p_profile_output)<>'object'
     OR jsonb_typeof(p_validation)<>'object'
     OR coalesce((p_validation->>'valid')::boolean,false) IS NOT TRUE
     OR (
       jsonb_typeof(p_validation->'blocking_codes')='array'
       AND jsonb_array_length(p_validation->'blocking_codes')<>0
     )
     OR nullif(btrim(coalesce(p_raw_evidence_ref,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_validator_evidence_ref,'')),'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_INPUT_INVALID'
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.status<>'IN_PROGRESS'
     OR NOT COALESCE(
       (e.manifest->>'executor_mode'='GPT_NATIVE'
        AND e.manifest->>'executor_provider'='OPENAI_CHATGPT_NATIVE')
       OR (e.manifest->>'executor_mode'='CLAUDE_NATIVE'
        AND e.manifest->>'executor_provider'='ANTHROPIC_CLAUDE_NATIVE'),
       false)
     OR e.manifest ? 'queue_request_id'
     OR nullif(e.manifest->>'runtime_target','') IS NOT NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_EXECUTION_INVALID'
    );
  END IF;

  IF jsonb_array_length(public.lf_profile_ig_open_work_v1(p_execution_id))>0 THEN
    IF jsonb_typeof(p_profile_output#>'{traceability,ig_open_work_resolution}')<>'array'
       OR jsonb_array_length(p_profile_output#>'{traceability,ig_open_work_resolution}')
          <> jsonb_array_length(public.lf_profile_ig_open_work_v1(p_execution_id))
    THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_IG_OPEN_WORK_RESOLUTION_REQUIRED',
        'expected_open_work',public.lf_profile_ig_open_work_v1(p_execution_id),
        'required_output_field','traceability.ig_open_work_resolution'
      );
    END IF;

    IF (
      SELECT count(DISTINCT r->>'family_code')
      FROM jsonb_array_elements(p_profile_output#>'{traceability,ig_open_work_resolution}') r
    ) <> jsonb_array_length(public.lf_profile_ig_open_work_v1(p_execution_id))
    OR EXISTS(
      SELECT 1
      FROM jsonb_array_elements(public.lf_profile_ig_open_work_v1(p_execution_id)) w
      WHERE NOT EXISTS(
        SELECT 1
        FROM jsonb_array_elements(p_profile_output#>'{traceability,ig_open_work_resolution}') r
        WHERE r->>'family_code'=w->>'family_code'
      )
    )
    OR EXISTS(
      SELECT 1
      FROM jsonb_array_elements(p_profile_output#>'{traceability,ig_open_work_resolution}') r
      WHERE NOT EXISTS(
        SELECT 1
        FROM jsonb_array_elements(public.lf_profile_ig_open_work_v1(p_execution_id)) w
        WHERE w->>'family_code'=r->>'family_code'
      )
      OR r->>'status' NOT IN (
        'RESUELTA','NO_CORRESPONDE','DEPENDENCIA','DECISIÓN_REQUERIDA'
      )
      OR nullif(btrim(coalesce(r->>'reason','')),'') IS NULL
      OR (
        r->>'status'='RESUELTA'
        AND (
          jsonb_typeof(r->'evidence_refs')<>'array'
          OR jsonb_array_length(r->'evidence_refs')=0
        )
      )
      OR (
        r->>'status' IN ('DEPENDENCIA','DECISIÓN_REQUERIDA')
        AND nullif(btrim(coalesce(r->>'next_action','')),'') IS NULL
      )
    )
    THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_IG_OPEN_WORK_RESOLUTION_INVALID',
        'expected_open_work',public.lf_profile_ig_open_work_v1(p_execution_id)
      );
    END IF;
  END IF;

  SELECT * INTO v_context
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='context_admission'
    AND status='STEP_PASS_WITH_EVIDENCE';

  SELECT * INTO v_baseline
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='research_baseline_freeze'
    AND status='STEP_PASS_WITH_EVIDENCE';

  SELECT * INTO v_source
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='profile_source_read'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_context.step_id IS NULL
     OR v_baseline.step_id IS NULL
     OR v_source.step_id IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_PREDECESSOR_NOT_CLEAN'
    );
  END IF;

  v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);
  v_candidate_digest:='sha256:'||encode(
    extensions.digest(convert_to(p_profile_output::text,'UTF8'),'sha256'),
    'hex'
  );
  v_raw_sha=substr(v_candidate_digest,8);
  v_source_refs:=jsonb_build_array(
    v_source.evidence_payload->>'profile_source_ref',
    v_context.evidence_payload->>'context_receipt_ref'
  );

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='execute_profile';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'execute_profile',
      p_raw_evidence_ref,
      jsonb_build_object(
        'context_receipt_digest',v_context.evidence_payload->>'context_receipt_digest',
        'context_receipt_ref',v_context.evidence_payload->>'context_receipt_ref',
        'context_transport',jsonb_build_object(
          'profile_source_mode','JIT_BY_REF',
          'jit_resolver_ref','supabase://public.v_lf_fuente_operativa/EVIDENCE_RESOLVER_REGISTRY',
          'jit_only',true,
          'policy_payloads',false,
          'full_ekb_entries',false,
          'full_readmes',false,
          'full_prefetch_count',0,
          'hydrated_refs','[]'::jsonb
        ),
        'profile_output',p_profile_output,
        'candidate_digest',v_candidate_digest,
        'raw_output_sha256',v_raw_sha,
        'research_baseline_digest',
          v_baseline.evidence_payload#>>'{research_baseline_binding,baseline_digest}',
        'research_baseline_ref',v_baseline.evidence_payload->>'baseline_receipt_ref',
        'source_refs',v_source_refs
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_EXECUTE_PROFILE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='output_validate';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'output_validate',
      p_validator_evidence_ref,
      jsonb_build_object(
        'output_contract_result','PASS',
        'deterministic_validation',
          p_validation||jsonb_build_object(
            'status','PASS',
            'candidate_digest',v_candidate_digest
          ),
        'raw_output_sha256',v_raw_sha
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_VALIDATE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_clean<>9 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_POST_MODEL_STEP_COUNT',
      'clean_step_count',v_clean,
      'expected_clean_step_count',9
    );
  END IF;

  RETURN jsonb_build_object(
    'status','NATIVE_PRODUCER_VALIDATED',
    'execution_id',p_execution_id,
    'profile_code',e.target_code,
    'candidate_digest',v_candidate_digest,
    'raw_output_sha256',v_raw_sha,
    'clean_step_count',v_clean,
    'next_step','semantic_judge',
    'next_action','RUN_INDEPENDENT_SEMANTIC_JUDGE',
    'independent_semantic_judge_required',true,
    'producer_may_self_authorize',false,
    'terminal_authority_ready',false,
    'router_reentry_required',false
  );
END
$function$
;

-- public.lf_profile_execution_context_admission_v1(text)
CREATE OR REPLACE FUNCTION public.lf_profile_execution_context_admission_v1(p_execution_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'extensions'
AS $function$
declare
  e public.lf_operation_execution%rowtype;
  prior public.lf_operation_execution_steps%rowtype;
  prior_binding public.lf_operation_step_judge_bindings%rowtype;
  existing public.lf_operation_execution_steps%rowtype;
  context_binding public.lf_operation_step_judge_bindings%rowtype;
  compiled jsonb;
  receipt jsonb;
  event_id bigint;
  budget_event_id bigint;
  digest text;
  resolver_version text;
begin
  if nullif(btrim(coalesce(p_execution_id,'')),'') is null then
    raise exception 'BLOCK_PROFILE_CONTEXT_EXECUTION_ID_REQUIRED';
  end if;

  select * into e
  from public.lf_operation_execution
  where execution_id=p_execution_id;

  if not found
     or e.operation_code<>'EJECUCION_PERFIL_LF'
     or e.target_type<>'PERFIL'
     or e.status<>'IN_PROGRESS' then
    raise exception 'BLOCK_PROFILE_CONTEXT_EXECUTION_BINDING_INVALID:%',p_execution_id;
  end if;

  select * into context_binding
  from public.lf_operation_step_judge_bindings
  where operation_code='EJECUCION_PERFIL_LF'
    and step_id='context_admission'
    and status='ACTIVE_ENFORCEMENT';

  select * into existing
  from public.lf_operation_execution_steps
  where execution_id=p_execution_id and step_id='context_admission';

  if found and existing.status=context_binding.clean_result_value then
    return existing.evidence_payload||jsonb_build_object('replay',true);
  end if;

  select * into prior_binding
  from public.lf_operation_step_judge_bindings
  where operation_code='EJECUCION_PERFIL_LF'
    and step_id='input_validate'
    and status='ACTIVE_ENFORCEMENT';

  select * into prior
  from public.lf_operation_execution_steps
  where execution_id=p_execution_id and step_id='input_validate';

  if not found or prior.status<>prior_binding.clean_result_value then
    raise exception 'BLOCK_PROFILE_CONTEXT_INPUT_VALIDATE_NOT_CLEAN:%',p_execution_id;
  end if;

  select version_normalizada into resolver_version
  from public.v_lf_fuente_operativa
  where codigo_activo='EVIDENCE_RESOLVER_REGISTRY'
    and estado_operativo='ACTIVO';

  if resolver_version is null then
    raise exception 'BLOCK_PROFILE_CONTEXT_JIT_RESOLVER_NOT_CURRENT';
  end if;

  compiled:=public.fn_lf_router_preflight_v1(p_execution_id);

  if coalesce(compiled->>'status','')<>'READY'
     or compiled->>'blocking_code' is not null
     or coalesce(compiled#>>'{context_budget,status}','')='RED'
     or coalesce((compiled#>>'{delivery,jit_only}')::boolean,false) is not true
     or coalesce((compiled#>>'{delivery,policy_payloads}')::boolean,true) is not false
     or coalesce((compiled#>>'{delivery,full_ekb_entries}')::boolean,true) is not false
     or coalesce((compiled#>>'{delivery,full_readmes}')::boolean,true) is not false
     or jsonb_typeof(compiled->'lazy_refs')<>'object'
  then
    return jsonb_build_object(
      'status','BLOCKED',
      'blocking_code',coalesce(compiled->>'blocking_code','BLOCK_PROFILE_CONTEXT_ADMISSION_NOT_READY'),
      'compiled_context',compiled,
      'server_validated',false
    );
  end if;

  event_id:=(compiled->>'evento_id')::bigint;
  budget_event_id:=(compiled->>'context_budget_event_id')::bigint;

  select payload->'context_receipt' into receipt
  from public.lf_eventos
  where id=event_id
    and created_by_execution_id=p_execution_id
    and payload->>'producer'='fn_lf_router_preflight_v1';

  if receipt is null then
    raise exception 'BLOCK_PROFILE_CONTEXT_EVENT_READBACK_MISSING:%',event_id;
  end if;

  if not exists (
    select 1
    from private.lf_context_budget_events_v2
    where id=budget_event_id
      and execution_id=p_execution_id
      and evidence_event_id=event_id
      and context_status in ('GREEN','YELLOW')
  ) then
    raise exception 'BLOCK_PROFILE_CONTEXT_BUDGET_READBACK_MISSING:%',budget_event_id;
  end if;

  digest:='sha256:'||encode(
    extensions.digest(convert_to(receipt::text,'UTF8'),'sha256'),'hex'
  );

  return jsonb_build_object(
    'status','READY',
    'blocking_code',null,
    'server_validated',true,
    'compiler_ref','public.fn_lf_router_preflight_v1',
    'context_event_id',event_id,
    'context_budget_event_id',budget_event_id,
    'context_receipt_ref','supabase://public.lf_eventos/'||event_id::text||'#context_receipt',
    'context_receipt_digest',digest,
    'context_budget_status',receipt#>>'{context_budget,status}',
    'context_capsule_estimated_tokens',(receipt#>>'{context_budget,estimated_tokens}')::bigint,
    'context_capsule_bytes',octet_length(receipt::text),
    'soft_limit_tokens',(receipt#>>'{context_budget,soft_limit_tokens}')::bigint,
    'hard_limit_tokens',(receipt#>>'{context_budget,hard_limit_tokens}')::bigint,
    'delivery',receipt->'delivery',
    'lazy_refs',receipt->'lazy_refs',
    'profile_source_mode','JIT_BY_REF',
    'jit_resolver_ref','supabase://public.v_lf_fuente_operativa/EVIDENCE_RESOLVER_REGISTRY',
    'jit_resolver_version',resolver_version,
    'context_capsule',receipt,
    'replay',false
  );
end
$function$
;

-- public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)
CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_record_semantic_v1(p_execution_id text, p_semantic_judge_result jsonb, p_evidence_ref text, p_actor_execution_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_actor text;
  v_existing text;
  v_step jsonb;
  v_clean integer;
  v_verified_native jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR jsonb_typeof(p_semantic_judge_result)<>'object'
     OR nullif(btrim(coalesce(p_evidence_ref,'')),'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_INPUT_INVALID'
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.status<>'IN_PROGRESS'
     OR NOT COALESCE(
       (e.manifest->>'executor_mode'='GPT_NATIVE'
        AND e.manifest->>'executor_provider'='OPENAI_CHATGPT_NATIVE')
       OR
       (e.manifest->>'executor_mode'='CLAUDE_NATIVE'
        AND e.manifest->>'executor_provider'='ANTHROPIC_CLAUDE_NATIVE'),
       false
     )
     OR e.manifest ? 'queue_request_id'
     OR nullif(e.manifest->>'runtime_target','') IS NOT NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_EXECUTION_INVALID'
    );
  END IF;

  -- Effects-bearing LF Product Director Step70 requires a genuinely
  -- verified independent native provider receipt. Read-only profiles retain
  -- their pre-existing current-context path. No HMAC / asserted-JSON bypass.
  IF e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
    AND NOT (
      coalesce((e.manifest->>'read_only')::boolean,false) IS TRUE
      AND coalesce((e.manifest->>'no_write')::boolean,false) IS TRUE
      AND coalesce((e.manifest->>'no_promotion')::boolean,false) IS TRUE
    )
  THEN
    IF p_semantic_judge_result->>'review_mode'
       IN ('CURRENT_CONTEXT_REVIEW','HMAC_TEST','MOCK')
    THEN RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','LF_STEP70_NATIVE_SELF_REVIEW_FORBIDDEN'); END IF;
    IF to_regprocedure('public.lf_ig_verified_native_provider_receipt_v1(text)') IS NULL
    THEN RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','LF_STEP70_NATIVE_PROVIDER_VERIFIER_MISSING'); END IF;
    EXECUTE 'SELECT public.lf_ig_verified_native_provider_receipt_v1($1)'
      INTO v_verified_native USING p_execution_id;
    IF jsonb_typeof(v_verified_native)<>'object'
      OR v_verified_native->>'status' IS DISTINCT FROM 'CRYPTOGRAPHICALLY_VERIFIED'
      OR v_verified_native->>'execution_id' IS DISTINCT FROM p_execution_id
      OR v_verified_native->>'provider_receipt_ref'
           IS DISTINCT FROM p_semantic_judge_result->>'provider_receipt_ref'
      OR v_verified_native->>'candidate_sha256'
           IS DISTINCT FROM p_semantic_judge_result->>'candidate_sha256'
      OR v_verified_native->>'scope_packet_sha256'
           IS DISTINCT FROM p_semantic_judge_result->>'scope_packet_sha256'
      OR coalesce(p_semantic_judge_result->>'provider_receipt_ref','')=''
      OR p_semantic_judge_result->>'producer_independence_proven'
           IS DISTINCT FROM 'true'
      OR p_semantic_judge_result->>'model_call_count'
           IS DISTINCT FROM '1'
    THEN RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','LF_STEP70_NATIVE_RECEIPT_NOT_VERIFIED'); END IF;
  END IF;

  -- An asserted independent review is not proof of another model/reviewer.
  -- No cryptographically verified provider attestation => refuse the authority
  -- claim; callers can continue read-only through CURRENT_CONTEXT_REVIEW.
  IF p_semantic_judge_result->>'verdict'='PASS_INDEPENDENT_SEMANTIC' THEN
    IF to_regprocedure('public.lf_ig_verified_native_provider_receipt_v1(text)') IS NULL THEN
      RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','JUDGE_INDEPENDENCE_PROVIDER_VERIFIER_UNAVAILABLE');
    END IF;
    EXECUTE 'SELECT public.lf_ig_verified_native_provider_receipt_v1($1)'
      INTO v_verified_native USING p_execution_id;
    IF v_verified_native->>'status'<>'CRYPTOGRAPHICALLY_VERIFIED'
      OR v_verified_native->>'execution_id' IS DISTINCT FROM p_execution_id
      OR v_verified_native->>'candidate_sha256'
            IS DISTINCT FROM p_semantic_judge_result->>'candidate_sha256'
      OR v_verified_native->>'scope_packet_sha256'
            IS DISTINCT FROM p_semantic_judge_result->>'scope_packet_sha256'
      OR p_semantic_judge_result->>'provider_receipt_ref'
            IS DISTINCT FROM v_verified_native->>'provider_receipt_ref'
      OR v_verified_native->>'reviewer_model_independence_proven'<>'true'
    THEN
      RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','JUDGE_INDEPENDENCE_UNVERIFIED_AUTHORITY_CLAIM');
    END IF;
  END IF;

  IF p_semantic_judge_result->>'status' IS DISTINCT FROM 'PASS'
     OR p_semantic_judge_result->>'validator_status' IS DISTINCT FROM 'PASS'
     OR NOT (
       (
         p_semantic_judge_result->>'verdict'='PASS_INDEPENDENT_SEMANTIC'
         AND coalesce((p_semantic_judge_result->>'producer_independence_proven')::boolean,false) IS TRUE
         AND coalesce((p_semantic_judge_result->>'model_call_count')::integer,-1)=1
       ) OR (
         p_semantic_judge_result->>'verdict'='PASS_REVIEWED_CURRENT_CONTEXT'
         AND p_semantic_judge_result->>'review_mode'='CURRENT_CONTEXT_REVIEW'
         AND p_semantic_judge_result->>'reviewer_is_producer'='true'
         AND coalesce((p_semantic_judge_result->>'producer_independence_proven')::boolean,true) IS FALSE
         AND coalesce((p_semantic_judge_result->>'model_call_count')::integer,-1)=0
         AND coalesce((e.manifest->>'read_only')::boolean,false) IS TRUE
         AND coalesce((e.manifest->>'no_write')::boolean,false) IS TRUE
         AND coalesce((e.manifest->>'no_promotion')::boolean,false) IS TRUE
       )
     )
     OR jsonb_typeof(p_semantic_judge_result#>'{result,unsupported_claims}')<>'array'
     OR jsonb_array_length(p_semantic_judge_result#>'{result,unsupported_claims}')<>0
     OR jsonb_typeof(p_semantic_judge_result#>'{result,blocking_codes}')<>'array'
     OR jsonb_array_length(p_semantic_judge_result#>'{result,blocking_codes}')<>0 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_JUDGE_NOT_PASS'
    );
  END IF;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='semantic_judge';

  IF v_existing IS NULL OR v_existing IN ('BLOCKED_STEP_NOT_CLEAN', 'RETURN_TO_ROUTER') THEN
    -- Reuse the canonical recorder retry path, retaining attempt_history on the same RUN.
    v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);

    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'semantic_judge',
      p_evidence_ref,
      jsonb_build_object(
        'semantic_judge_result',p_semantic_judge_result,
        'unsupported_claims','[]'::jsonb,
        'semantic_review_receipt_ref',p_evidence_ref,
        'independent_semantic_receipt_ref',case
          when p_semantic_judge_result->>'review_mode'='CURRENT_CONTEXT_REVIEW' then null
          else v_verified_native->>'provider_receipt_ref' end,
        'judge_independence_status',case
          when p_semantic_judge_result->>'review_mode'='CURRENT_CONTEXT_REVIEW'
            then 'NOT_PROVEN' else 'PROVIDER_VERIFIED' end,
        'content_findings',case
          when p_semantic_judge_result->>'review_mode'='CURRENT_CONTEXT_REVIEW'
            then jsonb_build_array(jsonb_build_object(
               'finding_code','JUDGE_INDEPENDENCE_NOT_PROVEN',
               'continuation_allowed',true,'effect_authority',false,
               'reviewer_is_producer',true,'producer_independence_proven',false,
               'model_call_count',0))
          else '[]'::jsonb end
      ),
      v_actor
    );

    IF coalesce(v_step->>'status',v_step->>'step_status')
       IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_RECORD_REJECTED',
        'recorder_result',v_step
      );
    END IF;

  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_EXISTING_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_clean<>10 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_POST_STEP_COUNT',
      'clean_step_count',v_clean,
      'expected_clean_step_count',10
    );
  END IF;

  RETURN jsonb_build_object(
    'status','SEMANTIC_JUDGE_RECORDED',
    'execution_id',p_execution_id,
    'profile_code',e.target_code,
    'clean_step_count',v_clean,
    'last_completed_step','semantic_judge',
    'next_step','report_output',
    'next_action','RECORD_EXISTING_REPORT_OUTPUT'
  );
END
$function$
;

-- public.lf_profile_native_bridge_record_report_v1(text,text,text)
CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_record_report_v1(p_execution_id text, p_evidence_ref text, p_actor_execution_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_semantic public.lf_operation_execution_steps%rowtype;
  v_input jsonb;
  v_profile_output jsonb;
  v_report_findings jsonb;
  v_existing text;
  v_actor text;
  v_candidate text;
  v_scope text;
  v_semantic_receipt text;
  v_step jsonb;
  v_clean integer;
  v_terminal jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_evidence_ref,'')),'') IS NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_INPUT_INVALID');
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.status NOT IN ('IN_PROGRESS','COMPLETED')
     OR NOT COALESCE(
       (e.manifest->>'executor_mode'='GPT_NATIVE'
        AND e.manifest->>'executor_provider'='OPENAI_CHATGPT_NATIVE')
       OR
       (e.manifest->>'executor_mode'='CLAUDE_NATIVE'
        AND e.manifest->>'executor_provider'='ANTHROPIC_CLAUDE_NATIVE'),
       false
     )
     OR e.manifest ? 'queue_request_id'
     OR nullif(e.manifest->>'runtime_target','') IS NOT NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_EXECUTION_INVALID');
  END IF;

  SELECT * INTO v_semantic
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='semantic_judge'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_semantic.step_id IS NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_SEMANTIC_NOT_CLEAN');
  END IF;

  -- Read canonical evidence only. A security BLOCKED is never relabeled READY.
  SELECT evidence_payload INTO v_input
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='input_validate'
    AND status='STEP_PASS_WITH_EVIDENCE';
  IF v_input#>>'{input_governance,status}'='BLOCKED'
     AND v_input->>'analysis_scope' IS DISTINCT FROM 'READ_ONLY_WITH_IG_FINDINGS' THEN
    RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','BLOCK_REPORT_IG_FINDINGS_WRITE_SCOPE');
  END IF;
  IF v_input->>'analysis_scope'='READ_ONLY_WITH_IG_FINDINGS' THEN
    IF e.manifest->>'read_only'<>'true'
       OR e.manifest->>'no_write'<>'true'
       OR e.manifest->>'no_promotion'<>'true'
       OR e.manifest->>'automatic_impact'<>'false'
       OR e.manifest->>'governed_repair_write'<>'false'
       OR v_input#>>'{input_governance,status}'<>'BLOCKED'
       OR v_input->>'ig_security_clearance'<>'false'
       OR jsonb_typeof(v_input#>'{input_governance,governance_result}')<>'object'
    THEN
      RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','BLOCK_REPORT_IG_FINDINGS_SCOPE_OR_SOURCE_INVALID');
    END IF;
    SELECT evidence_payload->'profile_output' INTO v_profile_output
    FROM public.lf_operation_execution_steps
    WHERE execution_id=p_execution_id AND step_id='execute_profile'
      AND status='STEP_PASS_WITH_EVIDENCE';
    IF jsonb_typeof(v_profile_output)<>'object' THEN
      RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','BLOCK_REPORT_PROFILE_DECISION_SOURCE_MISSING');
    END IF;
    v_report_findings:=jsonb_build_object(
      'analysis_scope','READ_ONLY_WITH_IG_FINDINGS',
      'security_state','BLOCKED',
      'security_clearance',false,
      'input_step_ref','supabase://public.lf_operation_execution_steps/'||p_execution_id||'/input_validate',
      'input_governance',v_input->'input_governance',
      'profile_decision_observed',v_profile_output#>'{traceability,ig_open_work_resolution}',
      'report_status','FINDINGS_REPORTED_NOT_RESOLVED',
      'mutation_authorized',false,
      'promotion_authorized',false);
  END IF;

  v_candidate:=v_semantic.evidence_payload#>>'{semantic_judge_result,candidate_sha256}';
  v_scope:=v_semantic.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}';
  v_semantic_receipt:=coalesce(v_semantic.evidence_payload->>'semantic_review_receipt_ref',v_semantic.evidence_payload->>'independent_semantic_receipt_ref');

  IF coalesce(v_candidate,'') !~ '^[0-9a-f]{64}$'
     OR coalesce(v_scope,'') !~ '^[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_SEMANTIC_BINDING_INVALID');
  END IF;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='report_output';

  IF v_existing IS NULL THEN
    IF e.status<>'IN_PROGRESS' THEN
      RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_EXECUTION_ALREADY_CLOSED_WITHOUT_REPORT');
    END IF;
    v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'report_output',
      p_evidence_ref,
      jsonb_build_object(
        'result',v_semantic.evidence_payload#>>'{semantic_judge_result,verdict}',
        'execution_id',p_execution_id,
        'profile_code',e.target_code,
        'no_write_performed',true,
        'candidate_sha256',v_candidate,
        'scope_packet_sha256',v_scope,
        'semantic_review_receipt_ref',v_semantic_receipt,
        'independent_semantic_receipt_ref',case
          when v_semantic.evidence_payload#>>'{semantic_judge_result,review_mode}'='CURRENT_CONTEXT_REVIEW' then null
          else v_semantic.evidence_payload->>'independent_semantic_receipt_ref' end,
        'judge_independence_status',coalesce(
          v_semantic.evidence_payload->>'judge_independence_status',
          CASE WHEN v_semantic.evidence_payload#>>'{semantic_judge_result,review_mode}'='CURRENT_CONTEXT_REVIEW'
          THEN 'NOT_PROVEN' ELSE 'REQUIRES_PROVIDER_VERIFICATION' END),
        'content_findings',coalesce(v_semantic.evidence_payload->'content_findings',
          CASE WHEN v_semantic.evidence_payload#>>'{semantic_judge_result,review_mode}'='CURRENT_CONTEXT_REVIEW'
             THEN jsonb_build_array(jsonb_build_object('finding_code','JUDGE_INDEPENDENCE_NOT_PROVEN','continuation_allowed',true))
             ELSE '[]'::jsonb END),
        'next_gate','RETURN_TO_ROUTER'
      ) || CASE WHEN v_report_findings IS NOT NULL
           THEN jsonb_build_object('ig_findings',v_report_findings,
                                   'ig_findings_reported',true)
           ELSE '{}'::jsonb END,
      v_actor
    );
    IF coalesce(v_step->>'status',v_step->>'step_status') IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_NATIVE_REPORT_RECORD_REJECTED',
        'recorder_result',v_step
      );
    END IF;
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_REPORT_EXISTING_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND status='STEP_PASS_WITH_EVIDENCE';

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF v_clean<>11 OR e.status<>'COMPLETED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_REPORT_COMPLETION_NOT_CLEAN',
      'clean_step_count',v_clean,
      'execution_status',e.status
    );
  END IF;

  v_terminal:=public.lf_profile_execution_terminal_authority_receipt_v1(p_execution_id);
  IF v_terminal->>'status' IS DISTINCT FROM 'READY' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_REPORT_TERMINAL_RECEIPT_NOT_READY',
      'terminal_result',v_terminal
    );
  END IF;

  RETURN jsonb_build_object(
    'status','PROFILE_EXECUTION_COMPLETED',
    'execution_id',p_execution_id,
    'profile_code',e.target_code,
    'clean_step_count',v_clean,
    'last_completed_step','report_output',
    'execution_status',e.status,
    'terminal_authority_receipt_sha256',v_terminal->>'terminal_authority_receipt_sha256',
    'next_gate','RETURN_TO_ROUTER'
  );
END
$function$
;
