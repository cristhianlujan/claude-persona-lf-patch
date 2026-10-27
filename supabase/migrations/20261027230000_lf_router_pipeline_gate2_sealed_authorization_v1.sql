-- ACT-0001 candidate extension: Gate2 authorization from sealed pipeline evidence.
-- Candidate only. Does not alter Stage1/2, choose profiles, or trigger execution.
BEGIN;

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
       'EXEC-ROUTER-GATE2-MIGRATION-20261027','EXEC-ROUTER-GATE2-MIGRATION-20261027'
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

COMMIT;
