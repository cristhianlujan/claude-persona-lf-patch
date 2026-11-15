-- SNAPSHOT ONLY. Read from sandbox SQL function definitions on 2026-11-14.
-- These are source preimages for isolated PG17/PG18 tests, not execution evidence.
CREATE SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE TABLE public.lf_operation_execution(execution_id text PRIMARY KEY,operation_code text,status text,request_sha256 text,target_code text,manifest jsonb);
CREATE TABLE public.lf_operation_execution_steps(execution_id text,step_id text,status text,evidence_payload jsonb);
CREATE TABLE public.lf_profile_selector_policy_v1(profile_code text,entry_policy text);
CREATE TABLE public.lf_profile_write_authority_v1(profile_code text,operation_code text,status text);
CREATE TABLE public.lf_router_action_registry(operation_code text,status text,write_allowed boolean,asset_type text);
CREATE TABLE public.lf_router_architecture_config_v1(config_key text PRIMARY KEY,value jsonb);
INSERT INTO public.lf_profile_selector_policy_v1 VALUES ('PERFIL-PRODUCT-DIRECTOR-LF','DIRECT'),('PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','DERIVATION_ONLY'),('PERFIL-QUALITY-PACK','DERIVATION_ONLY');
INSERT INTO public.lf_router_architecture_config_v1 VALUES ('FALLBACK_PROFILE','{"profile_code":"PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF"}');
CREATE FUNCTION public.lf_profile_selector_catalog_v1() RETURNS jsonb LANGUAGE sql STABLE AS $fixture$
SELECT '{"schema_version":"LF_PROFILE_SELECTOR_CATALOG_V1","all_canonical_descriptors_complete":true,"selectable_profile_count":3,"selection_mode":"DETERMINISTIC_DISCOVERY_ONLY","semantic_selection_performed":false,"profiles":[{"profile_code":"PERFIL-PRODUCT-DIRECTOR-LF","canonical_profile_key":"product_director_lf","entry_policy":"DIRECT","channels":["PRODUCTO"],"selection_eligible":true,"descriptor_status":"CURRENT","descriptor":{"description":"Product direction and acceptance criteria","selection_evidence":[{"kind":"PURPOSE","source_section":"Purpose","value":"Defines product direction"}]}},{"profile_code":"PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF","canonical_profile_key":"systemic_root_cause_repair_lf","entry_policy":"DERIVATION_ONLY","channels":["PRODUCTO"],"selection_eligible":true,"descriptor_status":"CURRENT","descriptor":{"description":"Implements bounded governed repairs","selection_evidence":[{"kind":"PURPOSE","source_section":"Purpose","value":"Repairs systemic defects"}]}},{"profile_code":"PERFIL-QUALITY-PACK","canonical_profile_key":"quality_pack","entry_policy":"DERIVATION_ONLY","channels":["PRODUCTO"],"selection_eligible":true,"descriptor_status":"CURRENT","descriptor":{"description":"Reviews implemented artifacts after worker","selection_evidence":[{"kind":"PURPOSE","source_section":"Purpose","value":"Quality reviews worker output"}]}}]}'::jsonb $fixture$;
CREATE FUNCTION public.lf_router_repair_profile_code_v1() RETURNS text LANGUAGE sql STABLE AS $fixture$
SELECT value->>'profile_code' FROM public.lf_router_architecture_config_v1 WHERE config_key='FALLBACK_PROFILE' $fixture$;
CREATE OR REPLACE FUNCTION public.lf_profile_result_router_return_classify_v1(p_profile_output jsonb, p_original_request text, p_execution_id text, p_profile_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  v_output_type text:=upper(coalesce(p_profile_output->>'output_type',''));
  v_pipeline_action text:=upper(coalesce(p_profile_output->>'pipeline_action',''));
  v_verdict text:=upper(coalesce(p_profile_output->>'verdict',''));
  v_status text:=upper(coalesce(p_profile_output->>'status',''));
  v_self_verdict text:=upper(coalesce(p_profile_output->>'self_verdict',''));
  v_routing jsonb:=coalesce(p_profile_output->'routing','null'::jsonb);
  v_repair_execution jsonb:=coalesce(p_profile_output->'repair_execution','null'::jsonb);
  v_redirect_kind text;
  v_payload jsonb;
  v_stage1_literal text;
  v_untyped_unresolved boolean:=false;
BEGIN
  IF jsonb_typeof(p_profile_output)<>'object'
     OR nullif(btrim(coalesce(p_original_request,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_profile_code,'')),'') IS NULL
  THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
      'status','BLOCKED',
      'code','PROFILE_RESULT_ROUTER_RETURN_INPUT_INVALID'
    );
  END IF;

  IF p_profile_output ? 'target_profile'
     OR (
       jsonb_typeof(v_routing)='object'
       AND v_routing ? 'target_profile'
     )
     OR (
       jsonb_typeof(p_profile_output->'safe_next_gate')='object'
       AND (p_profile_output->'safe_next_gate') ? 'target_profile'
     )
     OR (
       jsonb_typeof(p_profile_output->'handoff_to_next')='object'
       AND (p_profile_output->'handoff_to_next') ? 'target_profile'
     )
  THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
      'status','BLOCKED',
      'code','PROFILE_RESULT_DIRECT_TARGET_PROFILE_FORBIDDEN',
      'source_execution_id',p_execution_id,
      'source_profile_code',p_profile_code
    );
  END IF;

  IF jsonb_typeof(v_repair_execution)='object'
     AND upper(coalesce(v_repair_execution->>'mode',''))='EXECUTED_WITH_READBACK'
  THEN
    IF p_profile_code<>public.lf_router_repair_profile_code_v1()
       OR coalesce((v_repair_execution->>'returned_to_router')::boolean,false) IS NOT TRUE
       OR coalesce((v_repair_execution->>'promotion_performed')::boolean,true) IS NOT FALSE
       OR nullif(btrim(coalesce(v_repair_execution->>'authority_ref','')),'') IS NULL
       OR jsonb_typeof(v_repair_execution->'changes')<>'array'
       OR jsonb_array_length(v_repair_execution->'changes')=0
       OR jsonb_typeof(v_repair_execution->'preserved_constraints')<>'array'
       OR jsonb_array_length(v_repair_execution->'preserved_constraints')=0
       OR jsonb_typeof(v_repair_execution->'readback_refs')<>'array'
       OR jsonb_array_length(v_repair_execution->'readback_refs')=0
       OR nullif(btrim(coalesce(v_repair_execution->>'rollback_ref','')),'') IS NULL
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED',
        'code','PROFILE_RESULT_SRCR_EXECUTED_REPAIR_CONTRACT_INVALID',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

    v_redirect_kind:='SYSTEMIC_REPAIR_EXECUTED_WITH_READBACK';
    v_payload:=jsonb_build_object(
      'profile_status',p_profile_output->>'status',
      'profile_pack_id',p_profile_output->>'profile_pack_id',
      'repair_execution',v_repair_execution,
      'blocking_codes',coalesce(p_profile_output->'blocking_codes','[]'::jsonb),
      'next_gate',p_profile_output->'next_gate'
    );

  ELSIF v_output_type='PRODUCT_MISSING_INPUT_STATE' THEN
    IF jsonb_typeof(p_profile_output->'missing_fields')<>'array'
       OR jsonb_array_length(p_profile_output->'missing_fields')=0
       OR jsonb_typeof(p_profile_output->'why_required')<>'array'
       OR jsonb_array_length(p_profile_output->'why_required')=0
       OR jsonb_typeof(p_profile_output->'risk_if_assumed')<>'array'
       OR jsonb_array_length(p_profile_output->'risk_if_assumed')=0
       OR jsonb_typeof(p_profile_output->'safe_next_gate')<>'object'
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED',
        'code','PROFILE_RESULT_PRODUCT_MISSING_INPUT_CONTRACT_INVALID',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

    v_redirect_kind:='PRODUCT_MISSING_INPUT_STATE';
    v_payload:=jsonb_build_object(
      'missing_fields',p_profile_output->'missing_fields',
      'why_required',p_profile_output->'why_required',
      'risk_if_assumed',p_profile_output->'risk_if_assumed',
      'safe_next_gate',p_profile_output->'safe_next_gate'
    );

  ELSIF v_output_type='FRONTEND_MISSING_INPUT_STATE'
        OR v_pipeline_action='RETURN_TO_ORCHESTRATOR' THEN

    IF v_pipeline_action<>'RETURN_TO_ORCHESTRATOR'
       OR nullif(btrim(coalesce(p_profile_output->>'question_to_orchestrator','')),'') IS NULL
       OR jsonb_typeof(p_profile_output->'missing_fields')<>'array'
       OR jsonb_array_length(p_profile_output->'missing_fields')=0
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED',
        'code','PROFILE_RESULT_RETURN_TO_ORCHESTRATOR_CONTRACT_INVALID',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

    v_redirect_kind:=case
      when v_output_type<>'' then v_output_type
      else 'GENERIC_RETURN_TO_ORCHESTRATOR'
    end;

    v_payload:=jsonb_build_object(
      'missing_fields',p_profile_output->'missing_fields',
      'resolved_from_context',coalesce(p_profile_output->'resolved_from_context','[]'::jsonb),
      'conflicts_detected',coalesce(p_profile_output->'conflicts_detected','[]'::jsonb),
      'why_required',coalesce(p_profile_output->'why_required','[]'::jsonb),
      'risk_if_assumed',coalesce(p_profile_output->'risk_if_assumed','[]'::jsonb),
      'resolution_target',p_profile_output->>'resolution_target',
      'question_to_orchestrator',p_profile_output->>'question_to_orchestrator'
    );

  ELSIF jsonb_typeof(v_routing)='object'
        AND upper(coalesce(v_routing->>'pipeline_action',''))='RETURN_TO_ORCHESTRATOR' THEN

    IF upper(coalesce(v_routing->>'via',''))<>'ORCHESTRATOR'
       OR upper(coalesce(v_routing->>'resolution_target','')) NOT IN (
         'PRODUCER_REPAIR',
         'AUTHORITY_OR_CONTEXT_RESOLUTION'
       )
       OR v_verdict NOT IN (
         'RETURN_TO_WORKER_FOR_SELF_REPAIR',
         'RETURN_TO_ORCHESTRATOR'
       )
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED',
        'code','PROFILE_RESULT_QUALITY_ROUTING_CONTRACT_INVALID',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

    v_redirect_kind:='QUALITY_ROUTING_REDIRECT';
    v_payload:=jsonb_build_object(
      'verdict',v_verdict,
      'routing',v_routing,
      'blocking_codes',coalesce(p_profile_output->'blocking_codes','[]'::jsonb),
      'repair_actions',coalesce(p_profile_output->'repair_actions','[]'::jsonb),
      'remaining_risks',coalesce(p_profile_output->'remaining_risks','[]'::jsonb),
      'next_gate',p_profile_output->>'next_gate'
    );

  ELSIF jsonb_typeof(v_routing)='object'
        AND upper(coalesce(v_routing->>'pipeline_action','')) IN (
          'CONTINUE',
          'CONTINUE_WITH_RESTRICTIONS'
        ) THEN

    IF upper(coalesce(v_routing->>'via',''))<>'ORCHESTRATOR'
       OR nullif(btrim(coalesce(v_routing->>'resolution_target','')),'') IS NULL
       OR upper(coalesce(v_routing->>'resolution_target',''))='NONE'
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED',
        'code','PROFILE_RESULT_CONTINUE_ROUTING_CONTRACT_INVALID',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

    v_redirect_kind:=case
      when upper(v_routing->>'pipeline_action')='CONTINUE_WITH_RESTRICTIONS'
        then 'PROFILE_CONTINUE_WITH_RESTRICTIONS'
      else 'PROFILE_CONTINUE'
    end;

    v_payload:=jsonb_build_object(
      'profile_status',p_profile_output->>'status',
      'verdict',p_profile_output->>'verdict',
      'routing',v_routing,
      'blocking_codes',coalesce(p_profile_output->'blocking_codes','[]'::jsonb),
      'repair_actions',coalesce(p_profile_output->'repair_actions','[]'::jsonb),
      'remaining_risks',coalesce(p_profile_output->'remaining_risks','[]'::jsonb),
      'next_gate',p_profile_output->>'next_gate',
      'upstream_profile_output_sha256',
        'sha256:'||encode(
          extensions.digest(convert_to(p_profile_output::text,'UTF8'),'sha256'),
          'hex'
        ),
      'upstream_profile_output',p_profile_output
    );
  END IF;

  IF v_redirect_kind IS NOT NULL THEN
    -- Preserve the original request identity; keep unresolved_payload separate.
    v_stage1_literal:=p_original_request;

    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
      'status','RETURN_TO_ROUTER',
      'code','PROFILE_RESULT_TYPED_RETURN_TO_ORCHESTRATOR',
      'source_execution_id',p_execution_id,
      'source_profile_code',p_profile_code,
      'redirect_kind',v_redirect_kind,
      'router_return_request',jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_REQUEST_V1',
        'pipeline_action','RETURN_TO_ORCHESTRATOR',
        'route_policy','REPEAT_FULL_ROUTER_FLOW',
        'next_entrypoint','ACT-0001_STAGE1',
        'stage1_required',true,
        'reuse_prior_profile_selection',false,
        'prior_profile_is_advisory_only',true,
        'direct_profile_invocation_allowed',false,
        'original_request',p_original_request,
        'stage1_literal',v_stage1_literal,
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code,
        'unresolved_contract_type',v_redirect_kind,
        'unresolved_payload',v_payload,
        'advisory_profiles',coalesce(
          p_profile_output#>'{deliverable_created,profiles_to_activate}',
          '[]'::jsonb
        )
      ),
      'next_action','REENTER_ROUTER_STAGE1'
    );
  END IF;

  v_untyped_unresolved:=
       v_self_verdict IN ('NEEDS_INPUT','NEEDS_ADJUSTMENT','BLOCKED')
    OR v_status IN ('NEEDS_INPUT','BLOCKED','NEEDS_REPAIR')
    OR coalesce((p_profile_output->>'blocked')::boolean,false) IS TRUE
    OR (
      jsonb_typeof(p_profile_output->'missing_inputs')='array'
      AND jsonb_array_length(p_profile_output->'missing_inputs')>0
    )
    OR nullif(btrim(coalesce(p_profile_output->>'blocking_reason','')),'') IS NOT NULL;

  IF v_untyped_unresolved THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
      'status','BLOCKED',
      'code','PROFILE_RESULT_UNTYPED_ROUTING_SIGNAL',
      'source_execution_id',p_execution_id,
      'source_profile_code',p_profile_code,
      'next_action','FIX_PROFILE_ROUTING_CONTRACT'
    );
  END IF;

  RETURN jsonb_build_object(
    'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
    'status','COMPLETE',
    'code','PROFILE_RESULT_NO_ROUTER_RETURN_REQUIRED',
    'source_execution_id',p_execution_id,
    'source_profile_code',p_profile_code,
    'next_action','EMIT_PROFILE_RESULT'
  );
END
$function$
;
CREATE OR REPLACE FUNCTION public.lf_profile_selector_semantic_prepare_v2(p_literal_request text, p_channel text, p_derivation jsonb, p_stage1 jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
  v_catalog jsonb; v_all jsonb; v_profiles jsonb; v_request_sha text; v_catalog_sha text;
  v_channel text:=nullif(btrim(coalesce(p_channel,'')),'');
  v_src text:=nullif(btrim(coalesce(p_derivation->>'source_execution_id','')),'');
  v_ok boolean; v_deriv jsonb:=NULL;
  v_asset text:=upper(nullif(btrim(coalesce(p_stage1#>>'{alcance,target_type}','')),''));
  v_entry text[]:='{}';
begin
  if nullif(btrim(coalesce(p_literal_request,'')),'') is null then
    raise exception 'LF_PROFILE_SELECTOR_LITERAL_REQUEST_REQUIRED';
  end if;
  if v_channel is not null and v_channel not in ('PRODUCTO','PROGRAMACION','OPERACIONES') then
    raise exception 'LF_PROFILE_SELECTOR_CHANNEL_INVALID';
  end if;
  v_catalog:=public.lf_profile_selector_catalog_v1();
  if coalesce((v_catalog->>'all_canonical_descriptors_complete')::boolean,false) is not true
     or coalesce((v_catalog->>'selectable_profile_count')::integer,0)<=0
     or v_catalog->>'selection_mode'<>'DETERMINISTIC_DISCOVERY_ONLY'
     or coalesce((v_catalog->>'semantic_selection_performed')::boolean,true) is true
  then
    raise exception 'LF_PROFILE_SELECTOR_CATALOG_NOT_READY:%',left(v_catalog::text,1200);
  end if;
  v_request_sha:=encode(extensions.digest(convert_to(p_literal_request,'UTF8'),'sha256'),'hex');
  if v_src is not null then
    select true into v_ok
    from public.lf_operation_execution e
    join public.lf_profile_selector_policy_v1 sp on sp.profile_code=e.target_code
    where e.execution_id=v_src and e.operation_code='EJECUCION_PERFIL_LF' and e.status='COMPLETED'
      and e.request_sha256=v_request_sha and sp.entry_policy='DIRECT';
    -- Only canonical one-field envelope; DB proves COMPLETED, DIRECT and same SHA.
    IF v_ok IS TRUE AND jsonb_typeof(p_derivation)='object'
       AND (SELECT count(*) FROM jsonb_object_keys(p_derivation))=1
    THEN
      v_deriv:=jsonb_build_object('source_execution_id',v_src);
    END IF;
  end if;
  select coalesce(jsonb_agg(p order by p->>'profile_code'),'[]'::jsonb) into v_all
  from jsonb_array_elements(v_catalog->'profiles') p
  where coalesce((p->>'selection_eligible')::boolean,false) is true
    and p->>'descriptor_status'='CURRENT' and jsonb_typeof(p->'descriptor')='object'
    and nullif(btrim(coalesce(p#>>'{descriptor,description}','')),'') is not null;
  if jsonb_array_length(v_all)<>coalesce((v_catalog->>'selectable_profile_count')::integer,-1) then
    raise exception 'LF_PROFILE_SELECTOR_PREPARE_CARDINALITY_DRIFT';
  end if;
  -- Perfiles que entran por AUTORIDAD: el tipo de activo que pide la solicitud tiene operaciones de escritura
  -- activas en la tabla de rutas, y NINGUN perfil de entrada directa tiene esa operacion en la matriz de autoridad.
  -- Entonces se ofrecen los perfiles de solo derivacion que si la tienen.
  if v_asset is not null and v_deriv is null then
    select coalesce(array_agg(distinct a.profile_code),'{}') into v_entry
    from public.lf_profile_write_authority_v1 a
    join public.lf_router_action_registry r on r.operation_code=a.operation_code
    join public.lf_profile_selector_policy_v1 sp on sp.profile_code=a.profile_code
    where a.status='ACTIVE' and r.status='ACTIVE' and r.write_allowed is true
      and r.asset_type=v_asset and sp.entry_policy='DERIVATION_ONLY'
      and not exists (
        select 1 from public.lf_profile_write_authority_v1 a2
        join public.lf_profile_selector_policy_v1 sp2 on sp2.profile_code=a2.profile_code
        where a2.operation_code=a.operation_code and a2.status='ACTIVE' and sp2.entry_policy='DIRECT');
  end if;
  select coalesce(jsonb_agg(p order by p->>'profile_code'),'[]'::jsonb) into v_profiles
  from jsonb_array_elements(v_all) p
  where (v_channel is null or (p->'channels') ? v_channel)
    and (
      -- Temporary owner for INITIAL programming requests only, not a new
      -- entrypoint. Preserve the actual DERIVATION_ONLY policy; admission and
      -- every business/write action are still governed by their own contracts.
      (v_channel='PROGRAMACION' AND v_deriv IS NULL
        AND p->>'profile_code'='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
        AND p->>'entry_policy'='DERIVATION_ONLY'
        AND EXISTS (
          SELECT 1 FROM public.lf_profile_write_authority_v1 a
          WHERE a.profile_code=p->>'profile_code'
            AND a.operation_code='EJECUCION_PERFIL_LF'
            AND a.status='ACTIVE'
        )
      )
      OR
      -- Do not intercept valid derived returns or change other channels.
      ((v_channel IS DISTINCT FROM 'PROGRAMACION' OR v_deriv IS NOT NULL)
        AND (p->>'entry_policy'='DIRECT' OR v_deriv IS NOT NULL
             OR (p->>'profile_code')=ANY(v_entry))
      )
    );
  v_catalog_sha:=encode(extensions.digest(convert_to(v_profiles::text,'UTF8'),'sha256'),'hex');
  return jsonb_build_object(
    'schema_version','LF_PROFILE_SELECTOR_SEMANTIC_REQUEST_V1','selector','PROFILE_SELECTOR_LF',
    'literal_request',p_literal_request,'request_sha256',v_request_sha,'channel',v_channel,'derivation',v_deriv,
    'catalog_schema_version',v_catalog->>'schema_version','catalog_sha256',v_catalog_sha,
    'catalog_profile_count',jsonb_array_length(v_profiles),'candidate_profiles',v_profiles,
    'authority_entry_profiles',to_jsonb(v_entry),'authority_asset_type',v_asset,
    'allowed_decisions',jsonb_build_array('SELECTED','AMBIGUOUS','NO_MATCH'),
    'semantic_rules',jsonb_build_array('COMPARE_LITERAL_REQUEST_AGAINST_ALL_CANDIDATE_DESCRIPTORS','DO_NOT_PRESELECT_BY_KEYWORD_OR_PROFILE_NAME','USE_ONLY_DECLARED_DESCRIPTOR_EVIDENCE','SELECTED_REQUIRES_ONE_PROFILE','AMBIGUOUS_REQUIRES_TWO_OR_MORE_MATERIAL_CANDIDATES','NO_MATCH_WHEN_NO_DECLARED_PROFILE_CAPABILITY_FITS','NO_ROUTE_OR_EFFECT_AUTHORITY','CANDIDATES_ALREADY_FILTERED_BY_CHANNEL_AND_ENTRY_POLICY','MUTATION_REQUESTS_SELECT_ANALYSIS_PROFILE_FIRST'),
    'semantic_output_contract',jsonb_build_object('decision','SELECTED|AMBIGUOUS|NO_MATCH','selected_profile_code','string|null','ambiguous_profile_codes','array<string>','reason','non-empty string',
      'evidence_refs',jsonb_build_array(jsonb_build_object('profile_code','candidate profile code','kind','selection_evidence.kind','source_section','selection_evidence.source_section')),'material_ambiguities','array<object>'),
    'route_authority',false,'effect_authority',false,'downstream_execution_allowed',false);
end $function$
;

-- Native report function source preimage for terminal attach patch.
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
        'family_source_receipts',public.lf_input_family_catalog_receipts_for_run_v1(p_execution_id),
        'family_source_receipt_schema','LF_FAMILY_SOURCE_RECEIPTS_BY_REFERENCE_V1',
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
