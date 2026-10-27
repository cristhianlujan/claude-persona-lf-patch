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
       'DYNAMIC_FROM_GATE2_RESULT','RETURN_TO_ORCHESTRATOR','ACTIVE_ENFORCEMENT',
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
       AND next_if_pass='DYNAMIC_FROM_GATE2_RESULT' AND status='ACTIVE_ENFORCEMENT')<>1
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
 -- Do not automatically dispatch a profile or hard-code an executor.
 UPDATE public.lf_operation_execution
 SET manifest=manifest||jsonb_build_object(
      'current_step','profile_gate2',
      'next_step','DYNAMIC_FROM_GATE2_RESULT',
      'gate2_sha256',h,
      'selected_profile_code',y->>'selected_profile_code'),
 updated_by_execution_id=p_execution_id,updated_at=now()
 WHERE execution_id=p_execution_id;
 RETURN jsonb_build_object('status','GATE2_AUTHORIZED','execution_id',p_execution_id,
    'current_step','profile_gate2','next_step','DYNAMIC_FROM_GATE2_RESULT',
    'gate2_derivation',g,'gate2_request',x->'gate2_request',
    'downstream_execution_allowed',false,'effect_authority',false,
    'caller_selects_next_step',false);
END $fn$;

COMMIT;
