-- CANDIDATE ONLY: one authorized entry Router V2 Stage 06 -> EJECUCION_PERFIL_LF Stage 07.
-- In the same atomic patch, retire four duplicate START/WRITE entrypoints.
-- Do NOT retire internal begin_from_handoff, begin_v1, model continuation, or step recording.
-- Source-first design. DO NOT apply this file via a read-only session, Supabase MCP apply_migration,
-- or directly in production. Promote through exact-head Migration Merge Train with approval/rollback.
-- PRESTATE DB MD5: d1bc9787de30980bdff8d4f48c58d438 (30 Oct 2026).
-- The existing service_role-only execute ACL is preserved; no GRANT/REVOKE.
BEGIN;
DO $source_guard$
BEGIN
  IF to_regprocedure('public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)') IS NULL
     OR md5(pg_get_functiondef('public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)'::regprocedure))
        <> 'd1bc9787de30980bdff8d4f48c58d438'
  THEN
    RAISE EXCEPTION 'BLOCK_ROUTER_STAGE6_ADMISSION_SOURCE_DRIFT';
  END IF;
  IF to_regprocedure('public.lf_router_pipeline_begin_v1(p_request_text text)') IS NULL
     OR md5(pg_get_functiondef('public.lf_router_pipeline_begin_v1(p_request_text text)'::regprocedure)) <> '1c4977c7f17e514cd5d32e9b7b693a00' THEN
    RAISE EXCEPTION 'BLOCK_ROUTER_ONE_PATH_SOURCE_DRIFT:lf_router_pipeline_begin_v1';
  END IF;

  IF to_regprocedure('public.lf_profile_native_bridge_begin_v1(p_stage1 jsonb, p_semantic_result jsonb, p_executor_mode text, p_actor_execution_id text)') IS NULL
     OR md5(pg_get_functiondef('public.lf_profile_native_bridge_begin_v1(p_stage1 jsonb, p_semantic_result jsonb, p_executor_mode text, p_actor_execution_id text)'::regprocedure)) <> '36a3bb6ea8a020c9b1f9cb94ee93b357' THEN
    RAISE EXCEPTION 'BLOCK_ROUTER_ONE_PATH_SOURCE_DRIFT:lf_profile_native_bridge_begin_v1';
  END IF;

  IF to_regprocedure('public.lf_router_pipeline_profile_handoff_continue_v1(p_execution_id text, p_executor_mode text)') IS NULL
     OR md5(pg_get_functiondef('public.lf_router_pipeline_profile_handoff_continue_v1(p_execution_id text, p_executor_mode text)'::regprocedure)) <> '51c05f2efc1d31c304f0126c20a14e8d' THEN
    RAISE EXCEPTION 'BLOCK_ROUTER_ONE_PATH_SOURCE_DRIFT:lf_router_pipeline_profile_handoff_continue_v1';
  END IF;

  IF to_regprocedure('public.lf_router_profile_execution_after_gate2_v1(p_request jsonb, p_result jsonb, p_channel text, p_business text, p_scope jsonb, p_executor_mode text, p_actor_execution_id text, p_github_backup_reason text)') IS NULL
     OR md5(pg_get_functiondef('public.lf_router_profile_execution_after_gate2_v1(p_request jsonb, p_result jsonb, p_channel text, p_business text, p_scope jsonb, p_executor_mode text, p_actor_execution_id text, p_github_backup_reason text)'::regprocedure)) <> '94c468133a3961cc261ea312a0d23400' THEN
    RAISE EXCEPTION 'BLOCK_ROUTER_ONE_PATH_SOURCE_DRIFT:lf_router_profile_execution_after_gate2_v1';
  END IF;
END
$source_guard$;

CREATE OR REPLACE FUNCTION public.lf_router_pipeline_context_profile_admit_v2(p_context jsonb, p_executor_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql STABLE
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
 v_handoff jsonb;
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
 IF v_mode IS NULL OR v_mode NOT IN ('GPT_NATIVE','CLAUDE_NATIVE') THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_ADMISSION_EXECUTOR_INVALID');
 END IF;
 -- Stage 06: admission is derivation only. Never call a begin/materializer here.
 -- STABLE is an additional PostgreSQL read-only SPI guard on this exact function.
 v_handoff:=public.lf_router_profile_execution_handoff_v1(
   v_after->'gate2_request',v_gate->'gate2_result',
   v_stage->>'canal_candidato',v_stage->>'negocio_codigo',
   v_stage->'alcance'
 );
 IF v_handoff->>'status' IS DISTINCT FROM 'READY'
    OR jsonb_typeof(v_handoff->'handoff')<>'object'
    OR v_handoff#>>'{handoff,operation_code}' IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
    OR v_handoff#>>'{handoff,profile_code}' IS DISTINCT FROM v_selection->>'selected_profile_code'
 THEN
   RETURN jsonb_build_object(
     'status','BLOCKED',
     'blocking_code','BLOCK_CONTEXT_ADMISSION_HANDOFF_INVALID',
     'handoff_validation',v_handoff,
     'write_performed',false,
     'execution_id',NULL
   );
 END IF;
 RETURN jsonb_build_object(
   'status','PROFILE_HANDOFF_READY',
   'schema_version','LF_ROUTER_PROFILE_ADMISSION_RESULT_V1',
   'profile_code',v_handoff#>>'{handoff,profile_code}',
   'executor_mode',v_mode,
   'router_profile_handoff',v_handoff->'handoff',
   'handoff_fingerprint_sha256',v_handoff#>>'{handoff,fingerprint_sha256}',
   'handoff_authorized',true,
   'effect_authority',false,
   'write_performed',false,
   'execution_id',NULL,
   'next_action','EJECUCION_PERFIL_LF_BEGIN_REQUIRED',
   'router_reentry_required',false
 );
END;
$function$
;

COMMENT ON FUNCTION public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)
 IS 'ACT-0001 Stage 06: validate existing context and emit authenticated handoff only, STABLE/read-only. Never instantiate EJECUCION_PERFIL_LF; Stage 07 is the explicit sole writer.';

-- Disable obsolete competing launchers only after Stage 06 has become pure handoff.
-- Preserve source history and existing execution/step rows for audit.
-- RETIRED ENTRYPOINT: lf_router_pipeline_begin_v1. Preserve signature/ACL for clear rejection;
-- historical execution rows remain untouched. This function never invokes its old writer.
CREATE OR REPLACE FUNCTION public.lf_router_pipeline_begin_v1(p_request_text text)
 RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $retired$
BEGIN
  RETURN jsonb_build_object(
    'status','BLOCKED',
    'blocking_code','LEGACY_ROUTER_V1_ENTRY_RETIRED',
    'canonical_route','ACT-0001_CONTEXT_V2_TO_EJECUCION_PERFIL_LF',
    'write_performed',false,
    'execution_id',NULL
  );
END;
$retired$;
COMMENT ON FUNCTION public.lf_router_pipeline_begin_v1(p_request_text text)
 IS 'Deprecated competing entrypoint: no effects. Route through Router V2 stage 06 and EJECUCION_PERFIL_LF stage 07 canonical begin_from_handoff.';

-- RETIRED ENTRYPOINT: lf_profile_native_bridge_begin_v1. Preserve signature/ACL for clear rejection;
-- historical execution rows remain untouched. This function never invokes its old writer.
CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_begin_v1(p_stage1 jsonb, p_semantic_result jsonb, p_executor_mode text DEFAULT 'GPT_NATIVE'::text, p_actor_execution_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $retired$
BEGIN
  RETURN jsonb_build_object(
    'status','BLOCKED',
    'blocking_code','DUPLICATE_NATIVE_BRIDGE_ENTRY_RETIRED',
    'canonical_route','ACT-0001_CONTEXT_V2_TO_EJECUCION_PERFIL_LF',
    'write_performed',false,
    'execution_id',NULL
  );
END;
$retired$;
COMMENT ON FUNCTION public.lf_profile_native_bridge_begin_v1(p_stage1 jsonb, p_semantic_result jsonb, p_executor_mode text, p_actor_execution_id text)
 IS 'Deprecated competing entrypoint: no effects. Route through Router V2 stage 06 and EJECUCION_PERFIL_LF stage 07 canonical begin_from_handoff.';

-- RETIRED ENTRYPOINT: lf_router_pipeline_profile_handoff_continue_v1. Preserve signature/ACL for clear rejection;
-- historical execution rows remain untouched. This function never invokes its old writer.
CREATE OR REPLACE FUNCTION public.lf_router_pipeline_profile_handoff_continue_v1(p_execution_id text, p_executor_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $retired$
BEGIN
  RETURN jsonb_build_object(
    'status','BLOCKED',
    'blocking_code','LEGACY_ROUTER_V1_HANDOFF_WRITER_RETIRED',
    'canonical_route','ACT-0001_CONTEXT_V2_TO_EJECUCION_PERFIL_LF',
    'write_performed',false,
    'execution_id',NULL
  );
END;
$retired$;
COMMENT ON FUNCTION public.lf_router_pipeline_profile_handoff_continue_v1(p_execution_id text, p_executor_mode text)
 IS 'Deprecated competing entrypoint: no effects. Route through Router V2 stage 06 and EJECUCION_PERFIL_LF stage 07 canonical begin_from_handoff.';

-- RETIRED ENTRYPOINT: lf_router_profile_execution_after_gate2_v1. Preserve signature/ACL for clear rejection;
-- historical execution rows remain untouched. This function never invokes its old writer.
CREATE OR REPLACE FUNCTION public.lf_router_profile_execution_after_gate2_v1(p_request jsonb, p_result jsonb, p_channel text, p_business text, p_scope jsonb, p_executor_mode text, p_actor_execution_id text DEFAULT NULL::text, p_github_backup_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $retired$
BEGIN
  RETURN jsonb_build_object(
    'status','BLOCKED',
    'blocking_code','DUPLICATE_GATE2_BEGIN_WRITER_RETIRED',
    'canonical_route','ACT-0001_CONTEXT_V2_TO_EJECUCION_PERFIL_LF',
    'write_performed',false,
    'execution_id',NULL
  );
END;
$retired$;
COMMENT ON FUNCTION public.lf_router_profile_execution_after_gate2_v1(p_request jsonb, p_result jsonb, p_channel text, p_business text, p_scope jsonb, p_executor_mode text, p_actor_execution_id text, p_github_backup_reason text)
 IS 'Deprecated competing entrypoint: no effects. Route through Router V2 stage 06 and EJECUCION_PERFIL_LF stage 07 canonical begin_from_handoff.';
COMMIT;
