-- LF Router: single ordered Train migration for existing pipeline transport + Gate2.
-- Candidate, no production write outside LF Migration Merge Train.
BEGIN;

-- ACT-0001 candidate extension: Gate2 authorization from sealed pipeline evidence.
-- Candidate only. Does not alter Stage1/2, choose profiles, or trigger execution.

CREATE OR REPLACE FUNCTION public.lf_router_pipeline_gate2_trust_v1(
  p_execution_id text, p_evidence_payload jsonb
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions' AS $fn$
DECLARE
  s6 public.lf_operation_execution_steps%rowtype;
  s5 public.lf_operation_execution_steps%rowtype;
  x jsonb;
  y jsonb;
  g jsonb;
  h text;
BEGIN
  SELECT * INTO s6 FROM public.lf_operation_execution_steps
   WHERE execution_id=p_execution_id AND step_id='profile_after_selection';
  SELECT * INTO s5 FROM public.lf_operation_execution_steps
   WHERE execution_id=p_execution_id AND step_id='profile_semantic_selection';
  IF s6.execution_id IS NULL OR s6.status<>'STEP_PASS_WITH_EVIDENCE'
     OR s5.execution_id IS NULL OR s5.status<>'STEP_PASS_WITH_EVIDENCE'
     OR s5.evidence_payload->>'decision'<>'SELECTED'
  THEN
    RETURN jsonb_build_object('valid',false,'code','GATE2_PREREQUISITES_NOT_SEALED',
      'server_hard_fails',jsonb_build_array('server_validation_failed'),
      'server_assertions','[]'::jsonb);
  END IF;
  x:=s6.evidence_payload->'after_selection_result';
  y:=s5.evidence_payload->'semantic_result';
  IF x->>'status'<>'READY_FOR_GATE2'
     OR jsonb_typeof(x->'gate2_request')<>'object'
     OR x->>'perfil_candidato' IS DISTINCT FROM y->>'selected_profile_code'
  THEN
    RETURN jsonb_build_object('valid',false,'code','GATE2_SEALED_REQUEST_INVALID',
      'server_hard_fails',jsonb_build_array('server_validation_failed'),
      'server_assertions','[]'::jsonb);
  END IF;
  g:=public.lf_router_profile_gate2_result_from_selection_v1(x->'gate2_request',y);
  h:=encode(extensions.digest(convert_to(g::text,'UTF8'),'sha256'),'hex');
  IF g->>'status'<>'READY'
     OR p_evidence_payload->'gate2_derivation' IS DISTINCT FROM g
     OR p_evidence_payload->>'gate2_sha256' IS DISTINCT FROM h
     OR p_evidence_payload->>'selected_profile_code' IS DISTINCT FROM y->>'selected_profile_code'
     OR p_evidence_payload->>'after_selection_sha256' IS DISTINCT FROM s6.evidence_payload->>'after_selection_sha256'
  THEN
    RETURN jsonb_build_object('valid',false,'code','GATE2_DERIVATION_EVIDENCE_MISMATCH',
      'server_hard_fails',jsonb_build_array('server_validation_failed'),
      'server_assertions','[]'::jsonb);
  END IF;
  RETURN jsonb_build_object('valid',true,'code','GATE2_SERVER_VALIDATED',
    'server_hard_fails','[]'::jsonb,'server_assertions',jsonb_build_array('server_validated'));
END $fn$;

-- Extend the preexisting trust dispatcher rather than install an alternative recorder.
DO $patch$
DECLARE d text;
  anchor text := E'\n  ELSE\n    hard:=hard||jsonb_build_array(''server_validation_failed'');\n  END IF;\n\n  IF jsonb_array_length(hard)>0 THEN';
  replacement text := E'\n  ELSIF p_step_id=''profile_gate2'' THEN\n    IF coalesce((public.lf_router_pipeline_gate2_trust_v1(p_execution_id,p_evidence_payload)->>''valid'')::boolean,false) IS NOT TRUE THEN\n      hard:=hard||jsonb_build_array(''server_validation_failed'');\n    END IF;\n  ELSE\n    hard:=hard||jsonb_build_array(''server_validation_failed'');\n  END IF;\n\n  IF jsonb_array_length(hard)>0 THEN';
BEGIN
  d:=pg_get_functiondef('public.lf_router_execution_trust_validation_v1(text,text,jsonb)'::regprocedure);
  IF (length(d)-length(replace(d,anchor,'')))/length(anchor)<>1 THEN
    RAISE EXCEPTION 'GATE2_TRUST_DISPATCHER_ANCHOR_DRIFT';
  END IF;
  EXECUTE replace(d,anchor,replacement);
END $patch$;

-- A real, operation-scoped provenance execution is reserved by the authorized
-- Migration Train transaction. This is migration audit, not per-query logging.
-- Idempotent on retries and checked by the existing provenance guard.
DO $router_provenance$
DECLARE
  v_id text := 'EXEC-ROUTER-CONTRACT-GATE2-20261028';
  v_key text := 'lf-router-pipeline-context-gate2-integration-v1';
  v_sha text := encode(extensions.digest(convert_to(v_key,'UTF8'),'sha256'),'hex');
  v_result jsonb;
BEGIN
  v_result:=public.fn_lf_operation_reserve_execution_v1(
    v_id,'EJECUCION_ROUTER_LF','DOC','ACT-0001',
    v_key,v_sha,v_id,
    'cristhianlujan/claude-persona-lf-patch',
    'supabase/migrations/20261028020345_lf_router_pipeline_context_gate2_integration_v1.sql',
    jsonb_build_object('purpose','GATE2_CONTRACT_MIGRATION_PROVENANCE',
      'effect_authority',false,'deployment_route','LF_MIGRATION_MERGE_TRAIN')
  );
  IF v_result->>'result' NOT IN ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION')
     OR v_result->>'execution_id' IS DISTINCT FROM v_id THEN
    RAISE EXCEPTION 'BLOCK_ROUTER_CONTRACT_PROVENANCE_RESERVATION';
  END IF;
END $router_provenance$;

INSERT INTO public.lf_operation_step_contracts
(operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,
 resolver_ref,output_payload,pass_condition,block_condition,blocking_code,
 mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,status,notes,
 created_by_execution_id,updated_by_execution_id)
SELECT 'EJECUCION_ROUTER_LF','profile_gate2',70,70,
       'CONTRACT-EJECUCION-ROUTER-LF-v0.4',
       'Autorización de ejecución del perfil: derivación determinística de Gate 2 exclusivamente desde selección y preparación selladas.',
       '["sealed_profile_after_selection","sealed_profile_semantic_selection"]'::jsonb,
       'public.lf_router_profile_gate2_result_from_selection_v1',
       '["selected_profile_code","after_selection_sha256","gate2_derivation","gate2_sha256"]'::jsonb,
       '["server_validated"]'::jsonb,
       '["profile_after_selection_not_clean","semantic_selection_not_clean","gate2_not_ready","gate2_evidence_mismatch"]'::jsonb,
       'BLOCK_ROUTER_PROFILE_GATE2_NOT_CLEAN', 'JUDGE-EJECUCION-ROUTER-LF-v0.1',
       '["selected_profile_code","after_selection_sha256","gate2_derivation","gate2_sha256"]'::jsonb,
       'profile_execution_handoff','RETURN_TO_ORCHESTRATOR','ACTIVE_ENFORCEMENT',
       'Este paso solo se ejecuta si la ruta sellada lo requiere; no hace otra selección semántica. Gate 2 no autoriza efectos de canal ni bypass. El handoff debe ser validado por su propio contrato gobernado.',
       (SELECT execution_id FROM public.lf_operation_execution WHERE operation_code='EJECUCION_ROUTER_LF' AND idempotency_key='lf-router-pipeline-context-gate2-integration-v1' AND execution_id='EXEC-ROUTER-CONTRACT-GATE2-20261028'),(SELECT execution_id FROM public.lf_operation_execution WHERE operation_code='EJECUCION_ROUTER_LF' AND idempotency_key='lf-router-pipeline-context-gate2-integration-v1' AND execution_id='EXEC-ROUTER-CONTRACT-GATE2-20261028')
WHERE NOT EXISTS (
  SELECT 1 FROM public.lf_operation_step_contracts
  WHERE operation_code='EJECUCION_ROUTER_LF' AND step_id='profile_gate2'
);

DO $check$
BEGIN
 IF (SELECT count(*) FROM public.lf_operation_step_contracts
     WHERE operation_code='EJECUCION_ROUTER_LF' AND step_id='profile_gate2'
       AND step_order=70 AND resolver_ref='public.lf_router_profile_gate2_result_from_selection_v1'
       AND next_if_pass='profile_execution_handoff' AND status='ACTIVE_ENFORCEMENT')<>1
 THEN RAISE EXCEPTION 'GATE2_CONTRACT_POSTCHECK_FAIL'; END IF;
END $check$;

CREATE OR REPLACE FUNCTION public.lf_router_pipeline_gate2_continue_v1(
 p_execution_id text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions' AS $fn$
DECLARE
  e public.lf_operation_execution%rowtype;
  s6 public.lf_operation_execution_steps%rowtype;
  s5 public.lf_operation_execution_steps%rowtype;
  x jsonb; y jsonb; g jsonb; h text; r jsonb;
BEGIN
 SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
 IF NOT FOUND OR e.operation_code<>'EJECUCION_ROUTER_LF'
    OR e.target_code<>'ACT-0001' OR e.status<>'IN_PROGRESS'
    OR e.manifest->>'next_step'<>'profile_gate2'
 THEN
  RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_GATE2_TRANSITION_NOT_AUTHORIZED');
 END IF;
 SELECT * INTO s6 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='profile_after_selection';
 SELECT * INTO s5 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='profile_semantic_selection';
 IF s6.execution_id IS NULL OR s6.status<>'STEP_PASS_WITH_EVIDENCE'
 OR s5.execution_id IS NULL OR s5.status<>'STEP_PASS_WITH_EVIDENCE'
 OR s5.evidence_payload->>'decision'<>'SELECTED'
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_GATE2_PRIOR_STEPS_NOT_CLEAN'); END IF;
 x:=s6.evidence_payload->'after_selection_result';
 y:=s5.evidence_payload->'semantic_result';
 IF x->>'status'<>'READY_FOR_GATE2' OR x->>'perfil_candidato' IS DISTINCT FROM y->>'selected_profile_code'
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_GATE2_SELECTION_MISMATCH'); END IF;
 g:=public.lf_router_profile_gate2_result_from_selection_v1(x->'gate2_request',y);
 IF g->>'status'<>'READY' THEN RETURN g||jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_GATE2_DERIVATION_FAILED'); END IF;
 h:=encode(extensions.digest(convert_to(g::text,'UTF8'),'sha256'),'hex');
 r:=public.lf_record_router_execution_step_v1(
    p_execution_id,'profile_gate2','router-gate2://'||h,
    jsonb_build_object('selected_profile_code',y->>'selected_profile_code',
       'after_selection_sha256',s6.evidence_payload->>'after_selection_sha256',
       'gate2_derivation',g,'gate2_sha256',h),p_execution_id
 );
 IF r->>'outcome'<>'STEP_RECORDED' THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_GATE2_RECORD_FAILED','record_result',r);
 END IF;
 -- Continue into the pre-existing Gate2 handoff entrypoint, without choosing an executor.
 UPDATE public.lf_operation_execution
 SET manifest=manifest||jsonb_build_object(
      'current_step','profile_gate2',
      'next_step','profile_execution_handoff',
      'gate2_sha256',h,
      'selected_profile_code',y->>'selected_profile_code'),
 updated_by_execution_id=p_execution_id,updated_at=now()
 WHERE execution_id=p_execution_id;
 RETURN jsonb_build_object('status','GATE2_AUTHORIZED','execution_id',p_execution_id,
    'current_step','profile_gate2','next_step','profile_execution_handoff',
    'gate2_derivation',g,'gate2_request',x->'gate2_request',
    'downstream_execution_allowed',false,'effect_authority',false,
    'caller_selects_next_step',false);
END $fn$;


-- The selected executor mode is supplied explicitly by the authorized caller,
-- never inferred from a profile name or silently defaulted.
-- This resumes the PRE-EXISTING handoff+profile execution entrypoint.
CREATE OR REPLACE FUNCTION public.lf_router_pipeline_profile_handoff_continue_v1(
 p_execution_id text, p_executor_mode text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions' AS $fn$
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
END $fn$;


-- Required operational registration for the existing governed recorder.
-- Gate2 is conditional; do not force unrelated routes through profile selection.
INSERT INTO public.lf_operation_steps
(operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,
 active,execution_order,created_by_execution_id,updated_by_execution_id)
SELECT 'EJECUCION_ROUTER_LF',70,'profile_gate2',false,
 'selected_profile_code; after_selection_sha256; gate2_derivation; gate2_sha256',
 'public.lf_operation_step_contracts/EJECUCION_ROUTER_LF/profile_gate2',
 NULL,true,70,(SELECT execution_id FROM public.lf_operation_execution WHERE operation_code='EJECUCION_ROUTER_LF' AND idempotency_key='lf-router-pipeline-context-gate2-integration-v1' AND execution_id='EXEC-ROUTER-CONTRACT-GATE2-20261028'),(SELECT execution_id FROM public.lf_operation_execution WHERE operation_code='EJECUCION_ROUTER_LF' AND idempotency_key='lf-router-pipeline-context-gate2-integration-v1' AND execution_id='EXEC-ROUTER-CONTRACT-GATE2-20261028')
WHERE NOT EXISTS (SELECT 1 FROM public.lf_operation_steps
 WHERE operation_code='EJECUCION_ROUTER_LF' AND step_id='profile_gate2');

INSERT INTO public.lf_operation_step_judge_bindings
(operation_code,step_order,step_id,judge_code,clean_result_value,
 blocked_result_value,return_result_value,required_evidence_keys,status,
 created_by_execution_id,updated_by_execution_id)
SELECT 'EJECUCION_ROUTER_LF',70,'profile_gate2','JUDGE-EJECUCION-ROUTER-LF-v0.1',
 'STEP_PASS_WITH_EVIDENCE','BLOCKED_ROUTER_PIPELINE_NOT_CLEAN','RETURN_TO_ORCHESTRATOR',
 '["selected_profile_code","after_selection_sha256","gate2_derivation","gate2_sha256"]'::jsonb,
 'ACTIVE_ENFORCEMENT',
 (SELECT execution_id FROM public.lf_operation_execution WHERE operation_code='EJECUCION_ROUTER_LF' AND idempotency_key='lf-router-pipeline-context-gate2-integration-v1' AND execution_id='EXEC-ROUTER-CONTRACT-GATE2-20261028'),(SELECT execution_id FROM public.lf_operation_execution WHERE operation_code='EJECUCION_ROUTER_LF' AND idempotency_key='lf-router-pipeline-context-gate2-integration-v1' AND execution_id='EXEC-ROUTER-CONTRACT-GATE2-20261028')
WHERE NOT EXISTS (SELECT 1 FROM public.lf_operation_step_judge_bindings
 WHERE operation_code='EJECUCION_ROUTER_LF' AND step_id='profile_gate2');

DO $preflight$
BEGIN
 IF (SELECT count(*) FROM public.lf_operation_steps WHERE operation_code='EJECUCION_ROUTER_LF'
     AND step_id='profile_gate2' AND step_order=70 AND required=false AND active=true)<>1
 OR (SELECT count(*) FROM public.lf_operation_step_judge_bindings WHERE operation_code='EJECUCION_ROUTER_LF'
     AND step_id='profile_gate2' AND step_order=70 AND judge_code='JUDGE-EJECUCION-ROUTER-LF-v0.1'
     AND status='ACTIVE_ENFORCEMENT')<>1
 THEN RAISE EXCEPTION 'GATE2_REGISTRY_JUDGE_BINDING_POSTCHECK_FAILED'; END IF;
END $preflight$;

-- ---- NEXT COMPATIBILITY UNIT (SAME TRAIN MIGRATION) ----

-- Router ACT-0001 candidate: read-only transport through EXISTING pipeline functions.
-- No new public Router function. Existing governed persisted branch remains unchanged.
-- Must be acceptance tested before deployment / cutover.

DO $patch$
DECLARE
 d text;
 anchor text;
 replacement text;
BEGIN
 d:=pg_get_functiondef('public.lf_router_pipeline_begin_v1(text)'::regprocedure);
 anchor:=E'  v_request_sha:=encode(\n';
 IF (length(d)-length(replace(d,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'ROUTER_BEGIN_TRANSPORT_ANCHOR_DRIFT';
 END IF;
 replacement:=$sql$  -- Pure read-only derivation: no execution row, step row or manifest update.
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
$sql$;
 EXECUTE replace(d,anchor,replacement);
END $patch$;

DO $patch$
DECLARE d text; anchor text; replacement text;
BEGIN
 d:=pg_get_functiondef('public.lf_router_pipeline_stage1_submit_v1(text,jsonb)'::regprocedure);
 anchor:=E'  SELECT * INTO e\n';
 IF (length(d)-length(replace(d,anchor,'')))/length(anchor)<>1 THEN
  RAISE EXCEPTION 'ROUTER_STAGE1_TRANSPORT_ANCHOR_DRIFT';
 END IF;
 replacement:=$sql$  -- The read-only user supplies an encoded JSON envelope in the existing
  -- execution-id parameter. It does not qualify as an execution id or receipt.
  IF session_user='supabase_read_only_user' THEN
    DECLARE
      v_ctx jsonb;
      v_route jsonb;
      v_transition jsonb;
      v_literal text;
    BEGIN
      IF left(coalesce(p_execution_id,''),6)<>'ROCTX:' THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_READ_ONLY_CONTEXT_REQUIRED');
      END IF;
      BEGIN
        v_ctx:=convert_from(decode(substr(p_execution_id,7),'base64'),'UTF8')::jsonb;
      EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_READ_ONLY_CONTEXT_INVALID');
      END;
      v_literal:=v_ctx->>'original_request_text';
      IF v_ctx->>'schema_version'<>'LF_ROUTER_READ_ONLY_CONTEXT_V1'
         OR nullif(btrim(coalesce(v_literal,'')),'') IS NULL
         OR v_ctx->>'request_sha256' IS DISTINCT FROM
           encode(extensions.digest(convert_to(v_literal,'UTF8'),'sha256'),'hex')
         OR p_stage1->>'texto_original' IS DISTINCT FROM v_literal
         OR p_stage1->>'schema_version'<>'LF_ROUTER_STAGE1_V2'
      THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_READ_ONLY_CONTEXT_REQUEST_MISMATCH');
      END IF;
      v_validation:=public.lf_router_stage1_validate_v2(p_stage1);
      IF v_validation->>'valid'<>'true' THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_ROUTER_STAGE1_INVALID',
          'stage1_validation',v_validation);
      END IF;
      v_route:=public.lf_router_route_v1(p_stage1,'{}'::jsonb,false);
      v_transition:=public.lf_router_route_transition_resolve_v1(v_route);
      IF v_transition->>'status'<>'RESOLVED' THEN
        RETURN jsonb_build_object('status','BLOCKED',
           'blocking_code','BLOCK_ROUTER_TRANSITION_INVALID',
           'stage1_validation',v_validation,
           'route_result',v_route,'transition',v_transition);
      END IF;
      RETURN jsonb_build_object(
        'status','NEXT_TRANSITION_READY',
        'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
        'transport_mode','READ_ONLY_CONTEXT',
        'current_step','resolve_next_transition',
        'next_step',v_transition->>'next_step',
        'stage1_validation',v_validation,
        'stage1_payload',p_stage1,
        'route_result',v_route,
        'transition',v_transition,
        'profile_selection_request',v_route->'profile_selection_request',
        'transport_token','ROCTX:'||encode(convert_to(jsonb_build_object(
           'schema_version','LF_ROUTER_READ_ONLY_CONTEXT_V1',
           'original_request_text',v_literal,
           'request_sha256',v_ctx->>'request_sha256',
           'stage1_payload',p_stage1,
           'stage2_route',v_route,
           'transition',v_transition,
           'next_step',v_transition->>'next_step',
           'effect_authority',false
        )::text,'UTF8'),'base64'),
        'trace_persistence','NONE',
        'effect_authority',false,
        'downstream_execution_allowed',false
      );
    END;
  END IF;
  SELECT * INTO e
$sql$;
 EXECUTE replace(d,anchor,replacement);
END $patch$;

-- No blanket grant to internal functions. Read-only can use only the
-- guarded existing beginning and Stage1 continuation.
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_begin_v1(text) TO supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_stage1_submit_v1(text,jsonb) TO supabase_read_only_user;

-- ---- NEXT COMPATIBILITY UNIT (SAME TRAIN MIGRATION) ----

-- ACT-0001: continue transported read-only context using EXISTING pipeline functions.
-- No new Router entrypoints; no DB writes by read-only branches.
-- No privilege to execute handoff or effects.

DO $patch$
DECLARE d text; anchor text; replacement text;
BEGIN
 d:=pg_get_functiondef('public.lf_router_pipeline_profile_semantic_prepare_v1(text)'::regprocedure);
 anchor:=E'  SELECT * INTO e\n';
 IF (length(d)-length(replace(d,anchor,'')))/length(anchor)<>1 THEN
   RAISE EXCEPTION 'ROUTER_SEMANTIC_PREPARE_ANCHOR_DRIFT';
 END IF;
 replacement:=$sql$  IF session_user='supabase_read_only_user' THEN
    DECLARE
      v_ctx jsonb; v_stage1 jsonb; v_route jsonb;
      v_trans jsonb; v_req jsonb; v_literal text;
    BEGIN
      IF left(coalesce(p_execution_id,''),6)<>'ROCTX:' THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_READ_ONLY_CONTEXT_REQUIRED');
      END IF;
      BEGIN
        v_ctx:=convert_from(decode(substr(p_execution_id,7),'base64'),'UTF8')::jsonb;
      EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_READ_ONLY_CONTEXT_INVALID');
      END;
      v_literal:=v_ctx->>'original_request_text';
      v_stage1:=v_ctx->'stage1_payload';
      v_route:=v_ctx->'stage2_route';
      v_trans:=v_ctx->'transition';
      IF v_ctx->>'schema_version'<>'LF_ROUTER_READ_ONLY_CONTEXT_V1'
        OR nullif(btrim(coalesce(v_literal,'')),'') IS NULL
        OR v_ctx->>'request_sha256' IS DISTINCT FROM
           encode(extensions.digest(convert_to(v_literal,'UTF8'),'sha256'),'hex')
        OR v_stage1->>'texto_original' IS DISTINCT FROM v_literal
        OR coalesce((public.lf_router_stage1_validate_v2(v_stage1)->>'valid')::boolean,false) IS NOT TRUE
        OR v_route IS DISTINCT FROM public.lf_router_route_v1(v_stage1,'{}'::jsonb,false)
        OR v_trans IS DISTINCT FROM public.lf_router_route_transition_resolve_v1(v_route)
        OR v_trans->>'next_step'<>'profile_semantic_selection'
        OR v_trans->>'transition_code'<>'PROFILE_SELECTION_REQUIRED'
      THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_READ_ONLY_CONTEXT_NOT_VERIFIED');
      END IF;
      v_req:=v_route->'profile_selection_request';
      IF jsonb_typeof(v_req)<>'object'
         OR v_req->>'schema_version'<>'LF_PROFILE_SELECTOR_SEMANTIC_REQUEST_V1'
         OR v_req->>'literal_request' IS DISTINCT FROM v_literal
      THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_READ_ONLY_PROFILE_REQUEST_INVALID');
      END IF;
      RETURN jsonb_build_object(
         'status','PROFILE_SEMANTIC_SELECTION_REQUIRED',
         'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
         'transport_mode','READ_ONLY_CONTEXT',
         'transport_token',p_execution_id,
         'current_step','resolve_next_transition',
         'next_step','profile_semantic_selection',
         'profile_selection_request',v_req,
         'profile_selection_request_sha256',
             encode(extensions.digest(convert_to(v_req::text,'UTF8'),'sha256'),'hex'),
         'stage1_payload',v_stage1,
         'transition',v_trans,
         'trace_persistence','NONE',
         'effect_authority',false,
         'downstream_execution_allowed',false
      );
    END;
  END IF;
  SELECT * INTO e
$sql$;
 EXECUTE replace(d,anchor,replacement);
END $patch$;

DO $patch$
DECLARE d text; anchor text; replacement text;
BEGIN
 d:=pg_get_functiondef('public.lf_router_pipeline_profile_semantic_submit_v1(text,text)'::regprocedure);
 anchor:=E'  v_prepare:=public.lf_router_pipeline_profile_semantic_prepare_v1(\n';
 IF (length(d)-length(replace(d,anchor,'')))/length(anchor)<>1 THEN
   RAISE EXCEPTION 'ROUTER_SEMANTIC_SUBMIT_ANCHOR_DRIFT';
 END IF;
 replacement:=$sql$  IF session_user='supabase_read_only_user' THEN
    DECLARE
      v_prep jsonb; v_ctx jsonb; v_raw_result jsonb; v_sel jsonb;
      v_after jsonb; v_gate jsonb; v_literal text;
      v_sha text;
    BEGIN
      v_prep:=public.lf_router_pipeline_profile_semantic_prepare_v1(p_execution_id);
      IF v_prep->>'status'<>'PROFILE_SEMANTIC_SELECTION_REQUIRED' THEN
        RETURN v_prep;
      END IF;
      IF nullif(btrim(coalesce(p_raw,'')),'') IS NULL THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ROUTER_PROFILE_SELECTION_RAW_REQUIRED');
      END IF;
      v_raw_result:=public.lf_profile_selector_semantic_consume_raw_v1(
        v_prep->'profile_selection_request',p_raw);
      IF v_raw_result->>'status'<>'VALID'
         OR jsonb_typeof(v_raw_result->'result')<>'object'
         OR jsonb_typeof(v_raw_result->'validation')<>'object'
      THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ROUTER_PROFILE_SEMANTIC_SELECTION_INVALID',
         'semantic_consume_result',v_raw_result);
      END IF;
      v_sel:=v_raw_result->'result';
      IF v_sel->>'decision'<>'SELECTED' THEN
        RETURN jsonb_build_object(
          'status',CASE WHEN v_sel->>'decision'='AMBIGUOUS' THEN 'PROFILE_SELECTION_AMBIGUOUS' ELSE 'PROFILE_SELECTION_NO_MATCH' END,
          'current_step','profile_semantic_selection',
          'semantic_result',v_sel,
          'semantic_validation',v_raw_result->'validation',
          'trace_persistence','NONE','effect_authority',false,
          'downstream_execution_allowed',false);
      END IF;
      BEGIN
        v_ctx:=convert_from(decode(substr(p_execution_id,7),'base64'),'UTF8')::jsonb;
      EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_READ_ONLY_CONTEXT_INVALID');
      END;
      v_after:=public.lf_router_profile_after_selection_v1(v_ctx->'stage1_payload',v_sel);
      IF v_after->>'status'<>'READY_FOR_GATE2' THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code',coalesce(v_after->>'blocking_code','BLOCK_ROUTER_PROFILE_AFTER_SELECTION_NOT_READY'),
          'after_selection_result',v_after,'effect_authority',false);
      END IF;
      v_gate:=public.lf_router_profile_gate2_result_from_selection_v1(
          v_after->'gate2_request',v_sel);
      IF v_gate->>'status'<>'READY' THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','BLOCK_GATE2_DERIVATION_FAILED',
          'gate2_derivation',v_gate,'effect_authority',false);
      END IF;
      RETURN jsonb_build_object(
         'status','READ_ONLY_GATE2_DERIVED_NOT_AUTHORIZED',
         'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
         'transport_mode','READ_ONLY_CONTEXT',
         'current_step','profile_gate2',
         'next_step','GOVERNED_PROFILE_EXECUTION_REQUIRED',
         'stage1_payload',v_ctx->'stage1_payload',
         'route_result',v_ctx->'stage2_route',
         'transition',v_ctx->'transition',
         'semantic_result',v_sel,
         'semantic_validation',v_raw_result->'validation',
         'after_selection_result',v_after,
         'gate2_derivation',v_gate,
         'trace_persistence','NONE',
         'effect_authority',false,
         'downstream_execution_allowed',false,
         'handoff_authorized',false
      );
    END;
  END IF;
  v_prepare:=public.lf_router_pipeline_profile_semantic_prepare_v1(
$sql$;
 EXECUTE replace(d,anchor,replacement);
END $patch$;

-- Existing functions only; do not grant direct access to internal dispatchers.
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_profile_semantic_prepare_v1(text)
  TO supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_profile_semantic_submit_v1(text,text)
  TO supabase_read_only_user;

