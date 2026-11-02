-- Isolated-only PG17.6 snapshot (2026-10-30), not a production migration.
-- Exact original pg_get_functiondef source for the six guarded functions.
-- Mock tables are fixtures for resolving the legacy function's %rowtype.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE TABLE public.lf_operation_execution (execution_id text,operation_code text,target_code text,status text,manifest jsonb,updated_by_execution_id text,updated_at timestamptz);
CREATE TABLE public.lf_operation_execution_steps (execution_id text,step_id text,status text,evidence_payload jsonb,step_order integer);
CREATE TABLE public.lf_router_action_registry (asset_type text,action_code text,operation_code text,status text,write_allowed boolean,requires_existing_target boolean);
CREATE TABLE public.lf_activos (codigo_activo text,tipo_activo text,archived_at timestamptz,metadata jsonb,ruta_esperada text);
SET check_function_bodies = off;
-- LIVE_HASH lf_profile_native_bridge_begin_v1 36a3bb6ea8a020c9b1f9cb94ee93b357
CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_begin_v1(p_stage1 jsonb, p_semantic_result jsonb, p_executor_mode text DEFAULT 'GPT_NATIVE'::text, p_actor_execution_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_route jsonb;
  v_selection_request jsonb;
  v_selection_validation jsonb;
  v_after_selection jsonb;
  v_gate2_derived jsonb;
  v_request jsonb;
  v_gate2_result jsonb;
  v_validation jsonb;
  v_materialized jsonb;
  v_actor text;
  v_channel text;
  v_expected_route_step text;
  v_expected_gate2_step text;
BEGIN
  IF jsonb_typeof(p_stage1)<>'object'
     OR jsonb_typeof(p_semantic_result)<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_INPUT_INVALID'
    );
  END IF;

  IF upper(coalesce(p_executor_mode,'')) NOT IN ('GPT_NATIVE','CLAUDE_NATIVE') THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_EXECUTOR_MODE',
      'required_executor_mode','GPT_NATIVE|CLAUDE_NATIVE'
    );
  END IF;

  IF p_semantic_result->>'schema_version'
       <>'LF_PROFILE_SELECTOR_SEMANTIC_RESULT_V1' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_SELECTION_RESULT_REQUIRED',
      'required_schema_version','LF_PROFILE_SELECTOR_SEMANTIC_RESULT_V1'
    );
  END IF;

  v_channel:=upper(coalesce(p_stage1->>'canal_candidato',''));
  IF v_channel NOT IN ('PRODUCTO','PROGRAMACION','OPERACIONES')
     OR p_stage1->>'negocio_codigo'<>'LF' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_CHANNEL_OR_BUSINESS_INVALID',
      'channel',v_channel,
      'business',p_stage1->>'negocio_codigo'
    );
  END IF;

  v_expected_route_step:=v_channel||'_PROFILE_SELECTION_REQUIRED';
  v_expected_gate2_step:=v_channel||'_GATE2_PERFIL';

  v_route:=public.lf_router_route_v1(p_stage1,'{}'::jsonb,false);

  IF v_route->>'paso' IS DISTINCT FROM v_expected_route_step
     OR upper(coalesce(v_route->>'canal_candidato','')) IS DISTINCT FROM v_channel
     OR v_route->>'negocio_codigo'<>'LF'
     OR jsonb_typeof(v_route->'profile_selection_request')<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_ROUTE_NOT_READY',
      'expected_route_step',v_expected_route_step,
      'route',v_route
    );
  END IF;

  v_selection_request:=v_route->'profile_selection_request';
  v_selection_validation:=public.lf_profile_selector_semantic_validate_v1(
    v_selection_request,p_semantic_result
  );

  IF v_selection_validation->>'status'<>'VALID'
     OR p_semantic_result->>'decision'<>'SELECTED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_SELECTION_INVALID',
      'profile_selection_validation',v_selection_validation
    );
  END IF;

  v_after_selection:=public.lf_router_profile_after_selection_v1(
    p_stage1,p_semantic_result
  );

  IF v_after_selection->>'status'<>'READY_FOR_GATE2'
     OR v_after_selection->>'paso' IS DISTINCT FROM v_expected_gate2_step
     OR v_after_selection->>'channel' IS DISTINCT FROM v_channel
     OR jsonb_typeof(v_after_selection->'gate2_request')<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_GATE2_NOT_READY',
      'expected_gate2_step',v_expected_gate2_step,
      'after_profile_selection',v_after_selection
    );
  END IF;

  v_request:=v_after_selection->'gate2_request';

  v_gate2_derived:=public.lf_router_profile_gate2_result_from_selection_v1(
    v_request,p_semantic_result
  );

  IF v_gate2_derived->>'status'<>'READY'
     OR jsonb_typeof(v_gate2_derived->'gate2_result')<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_GATE2_DERIVATION_FAILED',
      'gate2_derivation',v_gate2_derived
    );
  END IF;

  v_gate2_result:=v_gate2_derived->'gate2_result';
  v_validation:=v_gate2_derived->'validation';

  v_actor:=coalesce(
    nullif(btrim(p_actor_execution_id),''),
    'PROFILE-NATIVE-BRIDGE-'||upper(substr(v_request->>'request_sha256',1,20))
  );

  v_materialized:=public.lf_router_profile_execution_after_gate2_v1(
    v_request,
    v_gate2_result,
    v_channel,
    p_stage1->>'negocio_codigo',
    p_stage1->'alcance',
    upper(p_executor_mode),
    v_actor,
    NULL
  );

  IF v_materialized->>'status'<>'NATIVE_EXECUTION_READY' THEN
    RETURN v_materialized||jsonb_build_object(
      'bridge_status','BLOCKED',
      'bridge_stage','GATE2_MATERIALIZATION',
      'profile_selection_result',p_semantic_result,
      'gate2_result',v_gate2_result
    );
  END IF;

  RETURN v_materialized||jsonb_build_object(
    'bridge_status','READY',
    'bridge_stage','NATIVE_EXECUTION_MATERIALIZED',
    'stage1',p_stage1,
    'profile_selection_result',p_semantic_result,
    'profile_selection_validation',v_selection_validation,
    'gate2_result',v_gate2_result,
    'gate2_validation',v_validation,
    'gate2_derivation_mode','DETERMINISTIC_FROM_VALIDATED_PROFILE_SELECTION',
    'second_model_call_required',false,
    'router_route_summary',jsonb_build_object(
      'paso',v_route->>'paso',
      'canal_candidato',v_channel,
      'negocio_codigo',p_stage1->>'negocio_codigo',
      'perfil_candidato',v_after_selection->>'perfil_candidato'
    )
  );
END
$function$;

-- LIVE_HASH lf_router_pipeline_begin_v1 1c4977c7f17e514cd5d32e9b7b693a00
CREATE OR REPLACE FUNCTION public.lf_router_pipeline_begin_v1(p_request_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  v_request text:=btrim(coalesce(p_request_text,''));
  v_request_sha text;
  v_execution_id text;
  v_begin jsonb;
  v_step jsonb;
BEGIN
  IF v_request='' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_REQUEST_REQUIRED'
    );
  END IF;

  -- Pure read-only derivation: no execution row, step row or manifest update.
  -- Explicit governed effects continue through the existing writer, opted in
  -- only by its already-authorized service-role entrypoint.
  IF session_user = 'supabase_read_only_user' THEN
    v_begin:=jsonb_build_object(
         'schema_version','LF_ROUTER_READ_ONLY_CONTEXT_V1',
         'original_request_text',v_request,
         'request_sha256',encode(extensions.digest(convert_to(v_request,'UTF8'),'sha256'),'hex'),
         'next_step','stage1_seal',
         'effect_authority',false
    );
    RETURN jsonb_build_object(
      'status','STAGE1_REQUIRED',
      'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
      'transport_mode','READ_ONLY_CONTEXT',
      'request_context',v_begin,
      'transport_token','ROCTX:'||encode(convert_to(v_begin::text,'UTF8'),'base64'),
      'current_step','request_intake',
      'next_step','stage1_seal',
      'stage1_contract','LF_ROUTER_STAGE1_V2',
      'effect_authority',false,
      'downstream_execution_allowed',false
    );
  END IF;
  v_request_sha:=encode(
    extensions.digest(convert_to(v_request,'UTF8'),'sha256'),
    'hex'
  );
  v_execution_id:='EXEC-ROUTER-'||
    upper(replace(gen_random_uuid()::text,'-',''));

  v_begin:=public.fn_lf_operation_reserve_execution_v1(
    v_execution_id,
    'EJECUCION_ROUTER_LF',
    'DOC',
    'ACT-0001',
    'router-pipeline:'||v_execution_id,
    v_request_sha,
    v_execution_id,
    'cristhianlujan/claude-persona-lf-patch',
    'ACT-0001',
    jsonb_build_object(
      'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
      'router','ACT-0001',
      'original_request_text',v_request,
      'request_sha256',v_request_sha,
      'pipeline_mode','GOVERNED_DYNAMIC_STATE_MACHINE',
      'current_step','request_intake',
      'next_step','stage1_seal',
      'effect_authority',false
    )
  );

  IF v_begin->>'result' NOT IN ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION')
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_PIPELINE_RESERVE_FAILED',
      'begin',v_begin
    );
  END IF;

  v_step:=public.lf_record_router_execution_step_v1(
    v_execution_id,
    'request_intake',
    'router-request://'||v_request_sha,
    jsonb_build_object(
      'original_request_text',v_request,
      'request_sha256',v_request_sha,
      'stage1_required',true
    ),
    v_execution_id
  );

  IF v_step->>'outcome'<>'STEP_RECORDED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_REQUEST_INTAKE_NOT_CLEAN',
      'execution_id',v_execution_id,
      'step_result',v_step
    );
  END IF;

  UPDATE public.lf_operation_execution
  SET manifest=manifest||jsonb_build_object(
        'current_step','request_intake',
        'next_step','stage1_seal'
      ),
      updated_by_execution_id=v_execution_id,
      updated_at=now()
  WHERE execution_id=v_execution_id;

  RETURN jsonb_build_object(
    'status','STAGE1_REQUIRED',
    'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
    'execution_id',v_execution_id,
    'request_sha256',v_request_sha,
    'stage1_contract','LF_ROUTER_STAGE1_V2',
    'current_step','request_intake',
    'next_step','stage1_seal',
    'caller_selects_next_step',false,
    'downstream_execution_allowed',false
  );
END
$function$;

-- LIVE_HASH lf_router_pipeline_context_profile_admit_v2 d1bc9787de30980bdff8d4f48c58d438
CREATE OR REPLACE FUNCTION public.lf_router_pipeline_context_profile_admit_v2(p_context jsonb, p_executor_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
 v_stage jsonb;
 v_route jsonb;
 v_transition jsonb;
 v_request jsonb;
 v_selection jsonb;
 v_validation jsonb;
 v_after jsonb;
 v_gate jsonb;
 v_literal text;
 v_mode text;
 v_action_count integer;
BEGIN
 IF jsonb_typeof(p_context)<>'object'
    OR p_context->>'schema_version'<>'LF_ROUTER_EXECUTION_PIPELINE_V1'
    OR p_context->>'status'<>'GATE2_DERIVED_PENDING_GOVERNED_ADMISSION'
    OR p_context->>'transport_mode'<>'CONTEXT_TRANSPORT'
    OR p_context->'effect_authority' IS DISTINCT FROM 'false'::jsonb
    OR p_context->'downstream_execution_allowed' IS DISTINCT FROM 'false'::jsonb
 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_ADMISSION_ENVELOPE_INVALID');
 END IF;
 v_stage:=p_context->'stage1_payload';
 v_literal:=v_stage->>'texto_original';
 IF nullif(btrim(coalesce(v_literal,'')),'') IS NULL
    OR coalesce((public.lf_router_stage1_validate_v2(v_stage)->>'valid')::boolean,false) IS NOT TRUE
 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_ADMISSION_STAGE1_INVALID');
 END IF;
 v_route:=public.lf_router_route_v1(v_stage,'{}'::jsonb,false);
 v_transition:=public.lf_router_route_transition_resolve_v1(v_route);
 IF v_route IS DISTINCT FROM p_context->'route_result'
    OR v_transition IS DISTINCT FROM p_context->'transition'
    OR v_transition->>'status'<>'RESOLVED'
    OR v_transition->>'transition_code'<>'PROFILE_SELECTION_REQUIRED'
    OR v_transition->>'next_step'<>'profile_semantic_selection'
 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_ADMISSION_ROUTE_INVALID');
 END IF;
 v_request:=v_route->'profile_selection_request';
 v_selection:=p_context->'semantic_result';
 v_validation:=public.lf_profile_selector_semantic_validate_v1(v_request,v_selection);
 IF v_validation->>'status'<>'VALID'
    OR v_selection->>'decision'<>'SELECTED'
    OR v_validation IS DISTINCT FROM p_context->'semantic_validation'
 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_ADMISSION_SELECTION_INVALID');
 END IF;
 v_after:=public.lf_router_profile_after_selection_v1(v_stage,v_selection);
 IF v_after->>'status'<>'READY_FOR_GATE2'
    OR v_after IS DISTINCT FROM p_context->'after_selection_result'
 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_ADMISSION_AFTER_SELECTION_INVALID');
 END IF;
 v_gate:=public.lf_router_profile_gate2_result_from_selection_v1(
   v_after->'gate2_request',v_selection);
 IF v_gate->>'status'<>'READY'
    OR v_gate IS DISTINCT FROM p_context->'gate2_derivation'
 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_ADMISSION_GATE2_INVALID');
 END IF;
 SELECT count(*) INTO v_action_count
 FROM public.lf_router_action_registry
 WHERE asset_type='PERFIL'
   AND action_code='PROFILE_EXECUTION'
   AND operation_code='EJECUCION_PERFIL_LF'
   AND status='ACTIVE'
   AND write_allowed=false
   AND requires_existing_target=true;
 IF v_action_count<>1 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_ADMISSION_OPERATION_UNAVAILABLE');
 END IF;
 v_mode:=upper(nullif(btrim(coalesce(p_executor_mode,'')),''));
 IF v_mode IS NULL OR v_mode NOT IN ('GPT_NATIVE','CLAUDE_NATIVE','REMOTE_API') THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_ADMISSION_EXECUTOR_INVALID');
 END IF;
 -- Reuses existing governed profile begin and its idempotency/provenance checks.
 -- It must not reenter Stage1/Stage2 or authorize unrelated asset mutations.
 RETURN public.lf_router_profile_execution_after_gate2_v1(
   v_after->'gate2_request',v_gate->'gate2_result',
   v_stage->>'canal_candidato',v_stage->>'negocio_codigo',
   v_stage->'alcance',v_mode,NULL,NULL
 );
END;
$function$;

-- LIVE_HASH lf_router_pipeline_profile_handoff_continue_v1 51c05f2efc1d31c304f0126c20a14e8d
CREATE OR REPLACE FUNCTION public.lf_router_pipeline_profile_handoff_continue_v1(p_execution_id text, p_executor_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
 e public.lf_operation_execution%rowtype;
 s7 public.lf_operation_execution_steps%rowtype;
 s6 public.lf_operation_execution_steps%rowtype;
 s1 public.lf_operation_execution_steps%rowtype;
 v_gate jsonb;
 v_after jsonb;
 v_stage1 jsonb;
 v_mode text;
 v_result jsonb;
BEGIN
 SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
 IF NOT FOUND OR e.operation_code<>'EJECUCION_ROUTER_LF'
    OR e.target_code<>'ACT-0001' OR e.status<>'IN_PROGRESS'
    OR e.manifest->>'next_step'<>'profile_execution_handoff'
 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ROUTER_HANDOFF_TRANSITION_NOT_AUTHORIZED');
 END IF;
 SELECT * INTO s7 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='profile_gate2';
 SELECT * INTO s6 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='profile_after_selection';
 SELECT * INTO s1 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='stage1_seal';
 IF s7.execution_id IS NULL OR s7.status<>'STEP_PASS_WITH_EVIDENCE'
    OR s6.execution_id IS NULL OR s6.status<>'STEP_PASS_WITH_EVIDENCE'
    OR s1.execution_id IS NULL OR s1.status<>'STEP_PASS_WITH_EVIDENCE'
 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ROUTER_HANDOFF_SEALED_STEPS_REQUIRED');
 END IF;
 IF coalesce((public.lf_router_pipeline_gate2_trust_v1(
    p_execution_id,s7.evidence_payload)->>'valid')::boolean,false) IS NOT TRUE
 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ROUTER_HANDOFF_GATE2_TRUST_INVALID');
 END IF;
 v_gate:=s7.evidence_payload->'gate2_derivation';
 v_after:=s6.evidence_payload->'after_selection_result';
 v_stage1:=s1.evidence_payload->'stage1_payload';
 v_mode:=upper(nullif(btrim(coalesce(p_executor_mode,'')),''));
 IF v_mode IS NULL OR v_mode NOT IN ('GPT_NATIVE','CLAUDE_NATIVE','REMOTE_API') THEN
   RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_HANDOFF_EXECUTOR_MODE_REQUIRED',
      'allowed_executor_modes',jsonb_build_array('GPT_NATIVE','CLAUDE_NATIVE','REMOTE_API'));
 END IF;
 IF v_after->>'perfil_candidato' IS DISTINCT FROM
    s7.evidence_payload->>'selected_profile_code'
 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ROUTER_HANDOFF_PROFILE_MISMATCH');
 END IF;
 -- Reuse the approved Gate2→handoff→EJECUCION_PERFIL_LF materializer.
 -- This procedure validates the signed handoff itself; no Router re-entry.
 v_result:=public.lf_router_profile_execution_after_gate2_v1(
    v_after->'gate2_request',v_gate->'gate2_result',
    v_stage1->>'canal_candidato',v_stage1->>'negocio_codigo',
    v_stage1->'alcance',v_mode,p_execution_id,NULL
 );
 IF v_result->>'status' NOT IN ('NATIVE_EXECUTION_READY','PENDING','NATIVE_EXECUTOR_REQUIRED') THEN
   RETURN v_result||jsonb_build_object('router_pipeline_handoff_success',false);
 END IF;
 UPDATE public.lf_operation_execution SET
   manifest=manifest||jsonb_build_object(
     'current_step','profile_execution_handoff',
     'next_step','EXISTING_PROFILE_EXECUTOR',
     'executor_mode',v_mode,
     'profile_handoff_status',v_result->>'status'
   ),
   updated_by_execution_id=p_execution_id,updated_at=now()
 WHERE execution_id=p_execution_id;
 RETURN v_result||jsonb_build_object(
   'router_pipeline_handoff_success',true,
   'router_pipeline_execution_id',p_execution_id,
   'downstream_path','EXISTING_EJECUCION_PERFIL_LF');
END $function$;

-- LIVE_HASH lf_router_profile_after_selection_v1 754cf13fc6c7669763baa07a4031bc71
CREATE OR REPLACE FUNCTION public.lf_router_profile_after_selection_v1(p_stage1 jsonb, p_selection_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  v_stage1_validation jsonb;
  v_selection_request jsonb;
  v_selection_validation jsonb;
  v_base jsonb;
  v_decision text;
  v_profile text;
  v_profile_mode text;
  v_rs jsonb;
  v_profile_task_intent text;
  v_profile_ig_requirement text;
  v_profile_action_binding jsonb;
  v_channel text;
  v_schema text;
  v_channel_precondition jsonb;
BEGIN
  v_stage1_validation:=public.lf_router_stage1_validate_v2(p_stage1);
  v_channel:=upper(coalesce(p_stage1->>'canal_candidato',''));
  v_schema:='LF_ROUTER_CHANNEL_PROFILE_AFTER_SELECTION_V1';

  v_base:=jsonb_build_object(
    'schema_version',v_schema,
    'router','ACT-0001',
    'channel',v_channel,
    'downstream_execution_allowed',false
  );

  IF coalesce((v_stage1_validation->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN v_base||jsonb_build_object(
      'status','BLOCKED',
      'paso',v_channel||'_PROFILE_SELECTION_STAGE1_INVALID',
      'blocking_code','BLOCK_'||v_channel||'_PROFILE_SELECTION_STAGE1_INVALID',
      'stage1_validation',v_stage1_validation
    );
  END IF;

  IF p_stage1->>'schema_version'<>'LF_ROUTER_STAGE1_V2'
     OR v_channel NOT IN ('PRODUCTO','PROGRAMACION','OPERACIONES')
     OR p_stage1->>'negocio_codigo'<>'LF'
     OR jsonb_array_length(coalesce(p_stage1->'negocios_afectados','[]'::jsonb))<>0
  THEN
    RETURN v_base||jsonb_build_object(
      'status','BLOCKED',
      'paso',v_channel||'_PROFILE_SELECTION_ROUTE_MISMATCH',
      'blocking_code','BLOCK_'||coalesce(nullif(v_channel,''),'UNKNOWN')||'_PROFILE_SELECTION_ROUTE_MISMATCH'
    );
  END IF;

  v_selection_request:=public.lf_profile_selector_semantic_prepare_v1(
    p_stage1->>'texto_original'
  );

  v_selection_validation:=public.lf_profile_selector_semantic_validate_v1(
    v_selection_request,
    p_selection_result
  );

  IF v_selection_validation->>'status'<>'VALID' THEN
    RETURN v_base||jsonb_build_object(
      'status','BLOCKED',
      'paso',v_channel||'_PROFILE_SELECTION_INVALID',
      'blocking_code','BLOCK_'||v_channel||'_PROFILE_SELECTION_INVALID',
      'profile_selection_validation',v_selection_validation
    );
  END IF;

  v_decision:=p_selection_result->>'decision';

  IF v_decision='AMBIGUOUS' THEN
    RETURN v_base||jsonb_build_object(
      'status','WAITING_DECISION',
      'paso',v_channel||'_PROFILE_SELECTION_AMBIGUOUS',
      'decision','AMBIGUOUS',
      'candidatos',p_selection_result->'ambiguous_profile_codes',
      'material_ambiguities',p_selection_result->'material_ambiguities',
      'reason',p_selection_result->>'reason',
      'profile_selection_receipt_sha256',p_selection_result->>'semantic_receipt_sha256',
      'siguiente_paso_es','Resolver la ambiguedad material antes de Gate2.',
      'downstream_execution_allowed',false
    );
  END IF;

  IF v_decision='NO_MATCH' THEN
    RETURN v_base||jsonb_build_object(
      'status','BLOCKED',
      'paso',v_channel||'_PROFILE_SELECTION_NO_MATCH',
      'decision','NO_MATCH',
      'reason',p_selection_result->>'reason',
      'profile_selection_receipt_sha256',p_selection_result->>'semantic_receipt_sha256',
      'siguiente_paso_es','No ejecutar perfil; registrar la brecha de capacidad o revisar el canal.',
      'downstream_execution_allowed',false
    );
  END IF;

  IF v_decision<>'SELECTED'
     OR nullif(btrim(coalesce(p_selection_result->>'selected_profile_code','')),'') IS NULL
  THEN
    RETURN v_base||jsonb_build_object(
      'status','BLOCKED',
      'paso',v_channel||'_PROFILE_SELECTION_DECISION_INVALID',
      'blocking_code','BLOCK_'||v_channel||'_PROFILE_SELECTION_DECISION_INVALID'
    );
  END IF;

  v_profile:=p_selection_result->>'selected_profile_code';

  SELECT a.estado_operativo
    INTO v_profile_mode
  FROM public.lf_activos a
  JOIN public.lf_profile_selection_registry_v1 r
    ON r.profile_code=a.codigo_activo
   AND r.descriptor_status='CURRENT'
  WHERE a.codigo_activo=v_profile
    AND a.tipo_activo='PERFIL'
    AND a.archived_at IS NULL
    AND nullif(a.metadata->>'canonical_profile_key','') IS NOT NULL
  LIMIT 1;

  IF nullif(v_profile_mode,'') IS NULL THEN
    RETURN v_base||jsonb_build_object(
      'status','BLOCKED',
      'paso',v_channel||'_PROFILE_SELECTION_PROFILE_NOT_CURRENT',
      'blocking_code','BLOCK_'||v_channel||'_PROFILE_SELECTION_PROFILE_NOT_CURRENT',
      'perfil_candidato',v_profile
    );
  END IF;

  v_channel_precondition:=case v_channel
    when 'PRODUCTO' then jsonb_build_object(
      'code','PRODUCTO_PROFILE_ADMINISTRATION',
      'required_before_profile_execution',false,
      'required_before_channel_effect',true,
      'effect_boundary','SEPARATE_GOVERNED_OPERATION'
    )
    when 'PROGRAMACION' then jsonb_build_object(
      'code','PROGRAMACION_PRECHECK_DEFINICION',
      'precondition_required','EXACT_CANONICAL_DEFINITION_REF_AND_CURRENTNESS',
      'if_definition_missing_or_differs','PRODUCTO_PRIMERO',
      'if_definition_current','PROGRAMACION_ADMISION_REQUERIDA',
      'programming_entry_contract','PROGRAMMING_ENTRY_CONTRACT_V1',
      'upstream_required','ANALYSIS_IMPLEMENTATION_PACKAGE_V1',
      'required_before_profile_execution',false,
      'required_before_channel_effect',true,
      'profile_execution_role','READ_ONLY_CHANNEL_ADMINISTRATION'
    )
    else jsonb_build_object(
      'code','OPERACIONES_CAPACIDAD_REQUERIDA',
      'capability_status_required','ACTIVE',
      'actor_scope_authorization_required',true,
      'required_before_profile_execution',false,
      'required_before_channel_effect',true,
      'profile_execution_role','READ_ONLY_CHANNEL_ADMINISTRATION'
    )
  end;

  v_rs:=public.lf_router_resolve_v1(
    p_stage1->>'texto_original',
    v_profile,
    'PROFILE_EXECUTION',
    'PERFIL',
    'ROUTER'
  );

  v_profile_task_intent:=upper(coalesce(p_stage1->>'accion',''));
  v_profile_ig_requirement:=case
    when v_channel='PRODUCTO'
      and v_profile_task_intent='READ_PRODUCT_DEFINITION'
      then 'NOT_REQUIRED_CANONICAL_READ'
    else 'REQUIRED_BY_TASK'
  end;

  IF jsonb_typeof(v_rs#>'{semantic_handoff_v2,router_action_binding}')='object' THEN
    v_profile_action_binding:=
      (v_rs#>'{semantic_handoff_v2,router_action_binding}')
      ||jsonb_build_object(
        'profile_task_intent',v_profile_task_intent,
        'input_governance_requirement',v_profile_ig_requirement,
        'channel',v_channel,
        'channel_precondition',v_channel_precondition,
        'channel_effect_authority',false
      );

    v_profile_action_binding:=v_profile_action_binding||jsonb_build_object(
      'binding_sha256',
      'sha256:'||encode(
        extensions.digest(
          convert_to((v_profile_action_binding-'binding_sha256')::text,'UTF8'),
          'sha256'
        ),
        'hex'
      )
    );

    v_rs:=jsonb_set(
      v_rs,
      '{semantic_handoff_v2,router_action_binding}',
      v_profile_action_binding,
      true
    );
  END IF;

  IF v_rs->>'blocking_code'<>'BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED'
     OR v_rs#>>'{semantic_handoff_v2,schema_version}'<>'LF_ROUTER_SEMANTIC_REQUEST_V1'
     OR v_rs#>>'{semantic_handoff_v2,candidate_subjects,0,asset_code}' IS DISTINCT FROM v_profile
  THEN
    RETURN v_base||jsonb_build_object(
      'status','BLOCKED',
      'paso',v_channel||'_GATE2_NO_LISTO',
      'blocking_code','BLOCK_'||v_channel||'_PROFILE_GATE2_NOT_READY',
      'perfil_candidato',v_profile,
      'router_resolve',v_rs,
      'channel_precondition',v_channel_precondition,
      'profile_selection_receipt_sha256',p_selection_result->>'semantic_receipt_sha256',
      'siguiente_paso_es','Bloquear; la seleccion no pudo materializar un Gate2 ligado al perfil elegido.'
    );
  END IF;

  RETURN v_base||jsonb_build_object(
    'status','READY_FOR_GATE2',
    'paso',v_channel||'_GATE2_PERFIL',
    'perfil_candidato',v_profile,
    'perfil_modo',v_profile_mode,
    'profile_selection_result',p_selection_result,
    'profile_selection_validation',v_selection_validation,
    'profile_selection_receipt_sha256',p_selection_result->>'semantic_receipt_sha256',
    'canonical_investigation_owner','SELECTED_PROFILE_READ_ONLY',
    'profile_context_hydrator','public.lf_profile_execution_channel_context_v1',
    'channel_precondition',v_channel_precondition,
    'channel_precondition_enforcement','BEFORE_CHANNEL_EFFECT_NOT_BEFORE_READ_ONLY_PROFILE_ADMINISTRATION',
    'gate2_request',v_rs->'semantic_handoff_v2',
    'gate2_result_contract','LF_ROUTER_SEMANTIC_RESULT_V1',
    'gate2_result_deriver','public.lf_router_profile_gate2_result_from_selection_v1',
    'after_gate2_handoff_builder','public.lf_router_profile_execution_handoff_v1',
    'gate2_pass_entrypoint','public.lf_router_profile_execution_after_gate2_v1',
    'siguiente_operacion',jsonb_build_object(
      'operation_code','EJECUCION_PERFIL_LF',
      'entrypoint','GATE2_AUTO_MATERIALIZER',
      'materializer','public.lf_router_profile_execution_after_gate2_v1',
      'context_hydrator','public.lf_profile_execution_channel_context_v1',
      'router_reentry_before_execution',false,
      'return_to_router_after_profile_result',true,
      'effect_authority',false
    ),
    'motivo_es','La seleccion semantica eligio un perfil CURRENT para administrar el canal en solo lectura; las precondiciones del canal siguen siendo obligatorias antes de cualquier efecto.',
    'siguiente_paso_es','Resolver Gate2 para EJECUCION_PERFIL_LF; cualquier efecto posterior debe satisfacer la precondicion del canal y su operacion gobernada.',
    'downstream_execution_allowed',false
  );
END
$function$;

-- LIVE_HASH lf_router_profile_execution_after_gate2_v1 94c468133a3961cc261ea312a0d23400
CREATE OR REPLACE FUNCTION public.lf_router_profile_execution_after_gate2_v1(p_request jsonb, p_result jsonb, p_channel text, p_business text, p_scope jsonb, p_executor_mode text, p_actor_execution_id text DEFAULT NULL::text, p_github_backup_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_built jsonb;
  v_handoff jsonb;
  v_mode text:=upper(nullif(btrim(coalesce(p_executor_mode,'')),''));
  v_profile text;
  v_slug text;
  v_path text;
  v_execution_id text;
  v_actor text;
  v_begin jsonb;
  v_remote jsonb;
BEGIN
  v_built:=public.lf_router_profile_execution_handoff_v1(
    p_request,p_result,p_channel,p_business,p_scope
  );
  IF v_built->>'status' IS DISTINCT FROM 'READY'
     OR jsonb_typeof(v_built->'handoff')<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_GATE2_HANDOFF_NOT_READY',
      'handoff_result',v_built,
      'router_reentry_required',false
    );
  END IF;

  v_handoff:=v_built->'handoff';
  v_profile:=v_handoff->>'profile_code';

  IF v_mode NOT IN ('GPT_NATIVE','CLAUDE_NATIVE','REMOTE_API') THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_EXECUTOR_MODE_REQUIRED',
      'profile_code',v_profile,
      'allowed_executor_modes',jsonb_build_array('GPT_NATIVE','CLAUDE_NATIVE','REMOTE_API'),
      'router_reentry_required',false
    );
  END IF;

  IF v_mode='REMOTE_API' THEN
    v_remote:=programacion.fn_lf_profile_runtime_enqueue_authorized_v1(
      v_handoff,
      coalesce(nullif(btrim(p_actor_execution_id),''),'ACT-0001-GATE2'),
      p_github_backup_reason
    );
    RETURN v_remote||jsonb_build_object(
      'gate2_materialized',v_remote->>'status' IN ('PENDING','NATIVE_EXECUTOR_REQUIRED'),
      'router_profile_handoff',v_handoff,
      'router_reentry_required',false,
      'return_to_router_after_profile_result',true
    );
  END IF;

  SELECT a.metadata->>'profile_slug',
         coalesce(
           nullif(a.metadata->>'entrypoint_path',''),
           case
             when a.ruta_esperada like '%.md' then a.ruta_esperada
             when nullif(a.ruta_esperada,'') is not null
               then rtrim(a.ruta_esperada,'/')||'/SKILL.md'
             else null
           end
         )
    INTO v_slug,v_path
  FROM public.lf_activos a
  WHERE a.codigo_activo=v_profile
    AND a.tipo_activo='PERFIL'
    AND a.archived_at IS NULL
  LIMIT 1;

  IF nullif(v_slug,'') IS NULL OR nullif(v_path,'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_GATE2_SOURCE_BINDING_UNRESOLVED',
      'profile_code',v_profile,
      'router_reentry_required',false
    );
  END IF;

  v_execution_id:='EXEC-PROFILE-GATE2-'||upper(substr(v_handoff->>'request_sha256',1,24));
  v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),v_execution_id);

  v_begin:=public.lf_profile_execution_begin_from_handoff_v1(
    v_handoff,
    v_mode,
    v_execution_id,
    'router-profile-gate2:'||(v_handoff->>'request_sha256')||':'||v_profile,
    v_actor,
    'cristhianlujan/claude-persona-lf-patch',
    v_path,
    jsonb_build_object(
      'gate2_auto_materialized',true,
      'channel',p_channel,
      'business',p_business
    )
  );

  IF v_begin->>'status' IS DISTINCT FROM 'READY' THEN
    RETURN v_begin||jsonb_build_object(
      'router_profile_handoff',v_handoff,
      'router_reentry_required',false
    );
  END IF;

  RETURN v_begin||jsonb_build_object(
    'status','NATIVE_EXECUTION_READY',
    'gate2_materialized',true,
    'executor_mode',v_mode,
    'profile_code',v_profile,
    'profile_slug',v_slug,
    'profile_source_path',v_path,
    'router_profile_handoff',v_handoff,
    'next_action','EXECUTE_PROFILE_IN_AUTHORIZED_NATIVE_CONTEXT',
    'router_reentry_required',false,
    'return_to_router_after_profile_result',true
  );
END
$function$;
RESET check_function_bodies;
