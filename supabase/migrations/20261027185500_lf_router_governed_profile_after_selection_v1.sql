-- Extend governed ACT-0001 pilot with execution-bound profile after-selection continuation.
BEGIN;

DO $precheck$
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_router_execution_trust_validation_v1(text,text,jsonb)'::regprocedure
     )) <> 'af791145ffdf8f576037f04ce635a0d9' THEN
    RAISE EXCEPTION 'ROUTER_AFTER_SELECTION_TRUST_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_router_profile_after_selection_v1(jsonb,jsonb)'::regprocedure
     )) <> 'd1038f29f9887b4945a0ce54c0d724b0' THEN
    RAISE EXCEPTION 'ROUTER_AFTER_SELECTION_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_router_pipeline_profile_semantic_submit_v1(text,text)'::regprocedure
     )) <> '0337d19b26d5f30a077653f5ac2a1521' THEN
    RAISE EXCEPTION 'ROUTER_AFTER_SELECTION_SEMANTIC_SUBMIT_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure
     )) <> 'fe08a25c8e3c023d7181194d2dfdee0d' THEN
    RAISE EXCEPTION 'ROUTER_AFTER_SELECTION_CORE_SOURCE_DRIFT';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_registry
    WHERE operation_code='EJECUCION_ROUTER_LF'
      AND version='v0.3-pilot'
      AND status='CANDIDATO_READ_ONLY'
      AND lifecycle_state_code='OP_CANDIDATE'
  ) THEN
    RAISE EXCEPTION 'ROUTER_AFTER_SELECTION_V03_BASELINE_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lf_operation_step_contracts
    WHERE operation_code='EJECUCION_ROUTER_LF'
      AND step_id='profile_after_selection'
  ) THEN
    RAISE EXCEPTION 'ROUTER_AFTER_SELECTION_STEP_ALREADY_EXISTS';
  END IF;
END
$precheck$;

INSERT INTO public.lf_operation_execution(
  execution_id,operation_code,target_type,target_code,status,manifest,
  created_by_execution_id,updated_by_execution_id
) VALUES (
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V04-20261027-001',
  'VULNERABILITY_COVERAGE_REPAIR_LF',
  'OPERATION_PROTOCOL_REPAIR',
  'EJECUCION_ROUTER_LF',
  'IN_PROGRESS',
  jsonb_build_object(
    'mode','ROUTER_PROFILE_AFTER_SELECTION_GOVERNANCE_BOOTSTRAP',
    'governance_bootstrap',true,
    'bootstrap_operation_code','EJECUCION_ROUTER_LF',
    'bootstrap_status_ceiling','SANDBOX_ACTIVE',
    'candidate_only',true,
    'production_allowed',false,
    'runtime_activation',false,
    'router_cutover_executed',false,
    'change_scope','ADD_PROFILE_AFTER_SELECTION_STEP'
  ),
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V04-20261027-001',
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V04-20261027-001'
);

UPDATE public.lf_operation_registry
SET version='v0.4-pilot',
    notes='Pilot governed runtime for ACT-0001. request_intake -> stage1_seal -> stage2_route -> resolve_next_transition -> profile_semantic_selection -> profile_after_selection when SELECTED. No Router effect authority and no production cutover.',
    updated_by_execution_id='EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V04-20261027-001',
    updated_at=clock_timestamp()
WHERE operation_code='EJECUCION_ROUTER_LF'
  AND status='CANDIDATO_READ_ONLY'
  AND lifecycle_state_code='OP_CANDIDATE';

UPDATE public.lf_operation_contracts
SET contract_code='CONTRACT-EJECUCION-ROUTER-LF-v0.4',
    contract_path='public.lf_operation_contracts/EJECUCION_ROUTER_LF/CONTRACT-EJECUCION-ROUTER-LF-v0.4',
    allowed=allowed||jsonb_build_object(
      'profile_after_selection',true,
      'profile_after_selection_source','SEALED_STAGE1_PLUS_SEALED_SEMANTIC_SELECTION',
      'profile_after_selection_caller_supplied',false,
      'profile_after_selection_server_recomputed',true
    ),
    blocked=blocked||jsonb_build_array(
      'profile_after_selection_without_selected_semantic_result',
      'caller_supplied_after_selection_result',
      'after_selection_result_mismatch',
      'after_selection_profile_mismatch',
      'forged_after_selection_validation'
    ),
    updated_by_execution_id='EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V04-20261027-001',
    updated_at=clock_timestamp()
WHERE operation_code='EJECUCION_ROUTER_LF'
  AND status='ACTIVE_ENFORCEMENT';

UPDATE public.lf_operation_step_contracts
SET contract_code='CONTRACT-EJECUCION-ROUTER-LF-v0.4',
    updated_by_execution_id='EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V04-20261027-001',
    updated_at=clock_timestamp()
WHERE operation_code='EJECUCION_ROUTER_LF'
  AND status='ACTIVE_ENFORCEMENT';

INSERT INTO public.lf_operation_step_contracts(
  operation_code,step_id,step_order,execution_order,contract_code,purpose,
  input_required,resolver_ref,output_payload,pass_condition,block_condition,
  blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,
  status,notes,execution_sql,fail_condition,created_by_execution_id,updated_by_execution_id
) VALUES (
  'EJECUCION_ROUTER_LF',
  'profile_after_selection',
  60,
  60,
  'CONTRACT-EJECUCION-ROUTER-LF-v0.4',
  'Materialize the channel-neutral post-selection Router result only from Stage1 and semantic profile-selection evidence sealed in this execution.',
  jsonb_build_array('sealed_stage1','sealed_selected_profile_result'),
  'public.lf_router_profile_after_selection_v1',
  jsonb_build_array(
    'selected_profile_code',
    'profile_selection_receipt_sha256',
    'after_selection_result',
    'after_selection_sha256',
    'after_selection_status',
    'after_selection_step'
  ),
  jsonb_build_array('server_validated'),
  jsonb_build_array(
    'semantic_selection_not_clean',
    'semantic_decision_not_selected',
    'stage1_not_clean',
    'profile_mismatch',
    'after_selection_result_mismatch',
    'after_selection_not_ready_for_gate2'
  ),
  'BLOCK_ROUTER_PROFILE_AFTER_SELECTION_NOT_CLEAN',
  'JUDGE-EJECUCION-ROUTER-LF-v0.1',
  jsonb_build_array(
    'selected_profile_code',
    'profile_selection_receipt_sha256',
    'after_selection_result',
    'after_selection_sha256',
    'after_selection_status',
    'after_selection_step'
  ),
  'profile_gate2',
  'RETURN_TO_ORCHESTRATOR',
  'ACTIVE_ENFORCEMENT',
  'No caller supplies Stage1 or after-selection output. Both are reconstructed from durable evidence for the same router execution.',
  NULL,
  NULL,
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V04-20261027-001',
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V04-20261027-001'
);

INSERT INTO public.lf_operation_steps(
  operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,
  active,execution_order,created_by_execution_id,updated_by_execution_id
) VALUES (
  'EJECUCION_ROUTER_LF',
  60,
  'profile_after_selection',
  true,
  'selected_profile_code; profile_selection_receipt_sha256; after_selection_result; after_selection_sha256; after_selection_status; after_selection_step',
  'public.lf_operation_step_contracts/EJECUCION_ROUTER_LF/profile_after_selection',
  NULL,
  true,
  60,
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V04-20261027-001',
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V04-20261027-001'
);

INSERT INTO public.lf_operation_step_judge_bindings(
  operation_code,step_order,step_id,judge_code,
  clean_result_value,blocked_result_value,return_result_value,
  required_evidence_keys,status,created_by_execution_id,updated_by_execution_id
) VALUES (
  'EJECUCION_ROUTER_LF',
  60,
  'profile_after_selection',
  'JUDGE-EJECUCION-ROUTER-LF-v0.1',
  'STEP_PASS_WITH_EVIDENCE',
  'BLOCKED_ROUTER_PIPELINE_NOT_CLEAN',
  'RETURN_TO_ORCHESTRATOR',
  jsonb_build_array(
    'selected_profile_code',
    'profile_selection_receipt_sha256',
    'after_selection_result',
    'after_selection_sha256',
    'after_selection_status',
    'after_selection_step'
  ),
  'ACTIVE_ENFORCEMENT',
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V04-20261027-001',
  'EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V04-20261027-001'
);

CREATE OR REPLACE FUNCTION public.lf_router_profile_after_selection_trust_v1(
  p_execution_id text,
  p_evidence_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  s1 public.lf_operation_execution_steps%rowtype;
  ss public.lf_operation_execution_steps%rowtype;
  v_stage1 jsonb;
  v_semantic jsonb;
  v_expected jsonb;
  v_expected_sha text;
  hard jsonb:='[]'::jsonb;
BEGIN
  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_ROUTER_LF'
     OR e.target_code<>'ACT-0001'
     OR e.status<>'IN_PROGRESS'
  THEN
    RETURN jsonb_build_object(
      'valid',false,
      'code','ROUTER_AFTER_SELECTION_EXECUTION_BINDING_INVALID',
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  END IF;

  SELECT * INTO s1
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='stage1_seal';

  SELECT * INTO ss
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='profile_semantic_selection';

  IF s1.execution_id IS NULL
     OR s1.status<>'STEP_PASS_WITH_EVIDENCE'
     OR jsonb_typeof(s1.evidence_payload->'stage1_payload')<>'object'
     OR ss.execution_id IS NULL
     OR ss.status<>'STEP_PASS_WITH_EVIDENCE'
     OR ss.evidence_payload->>'decision'<>'SELECTED'
     OR jsonb_typeof(ss.evidence_payload->'semantic_result')<>'object'
  THEN
    hard:=hard||jsonb_build_array('server_validation_failed');
  ELSE
    v_stage1:=s1.evidence_payload->'stage1_payload';
    v_semantic:=ss.evidence_payload->'semantic_result';
    v_expected:=public.lf_router_profile_after_selection_v1(
      v_stage1,v_semantic
    );
    v_expected_sha:=encode(
      extensions.digest(convert_to(v_expected::text,'UTF8'),'sha256'),
      'hex'
    );

    IF v_expected->>'status'<>'READY_FOR_GATE2'
       OR p_evidence_payload->>'selected_profile_code'
            IS DISTINCT FROM v_semantic->>'selected_profile_code'
       OR p_evidence_payload->>'profile_selection_receipt_sha256'
            IS DISTINCT FROM v_semantic->>'semantic_receipt_sha256'
       OR p_evidence_payload->'after_selection_result'
            IS DISTINCT FROM v_expected
       OR p_evidence_payload->>'after_selection_sha256'
            IS DISTINCT FROM v_expected_sha
       OR p_evidence_payload->>'after_selection_status'
            IS DISTINCT FROM v_expected->>'status'
       OR p_evidence_payload->>'after_selection_step'
            IS DISTINCT FROM v_expected->>'paso'
       OR v_expected->>'perfil_candidato'
            IS DISTINCT FROM v_semantic->>'selected_profile_code'
    THEN
      hard:=hard||jsonb_build_array('server_validation_failed');
    END IF;
  END IF;

  IF jsonb_array_length(hard)>0 THEN
    RETURN jsonb_build_object(
      'valid',false,
      'code','ROUTER_AFTER_SELECTION_SERVER_VALIDATION_FAILED',
      'server_assertions','[]'::jsonb,
      'server_hard_fails',hard
    );
  END IF;

  RETURN jsonb_build_object(
    'valid',true,
    'code','ROUTER_AFTER_SELECTION_SERVER_VALIDATED',
    'server_assertions',jsonb_build_array('server_validated'),
    'server_hard_fails','[]'::jsonb
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_router_profile_after_selection_trust_v1(text,jsonb)
  FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_router_profile_after_selection_trust_v1(text,jsonb)
  TO postgres;

DO $patch_router_trust$
DECLARE
  d text;
  old_decl text := $old$
  hard jsonb:='[]'::jsonb;
  v_profile_semantic_trust jsonb;
BEGIN
$old$;
  new_decl text := $new$
  hard jsonb:='[]'::jsonb;
  v_profile_semantic_trust jsonb;
  v_profile_after_selection_trust jsonb;
BEGIN
$new$;
  old_tail text := $oldtail$
  ELSIF p_step_id='profile_semantic_selection' THEN
    v_profile_semantic_trust:=
      public.lf_router_profile_semantic_selection_trust_v1(
        p_execution_id,p_evidence_payload
      );

    IF coalesce((v_profile_semantic_trust->>'valid')::boolean,false) IS NOT TRUE THEN
      hard:=hard||jsonb_build_array('server_validation_failed');
    END IF;

  ELSE
    hard:=hard||jsonb_build_array('server_validation_failed');
  END IF;
$oldtail$;
  new_tail text := $newtail$
  ELSIF p_step_id='profile_semantic_selection' THEN
    v_profile_semantic_trust:=
      public.lf_router_profile_semantic_selection_trust_v1(
        p_execution_id,p_evidence_payload
      );

    IF coalesce((v_profile_semantic_trust->>'valid')::boolean,false) IS NOT TRUE THEN
      hard:=hard||jsonb_build_array('server_validation_failed');
    END IF;

  ELSIF p_step_id='profile_after_selection' THEN
    v_profile_after_selection_trust:=
      public.lf_router_profile_after_selection_trust_v1(
        p_execution_id,p_evidence_payload
      );

    IF coalesce((v_profile_after_selection_trust->>'valid')::boolean,false) IS NOT TRUE THEN
      hard:=hard||jsonb_build_array('server_validation_failed');
    END IF;

  ELSE
    hard:=hard||jsonb_build_array('server_validation_failed');
  END IF;
$newtail$;
BEGIN
  d:=pg_get_functiondef(
    'public.lf_router_execution_trust_validation_v1(text,text,jsonb)'::regprocedure
  );

  IF (length(d)-length(replace(d,old_decl,'')))/length(old_decl)<>1 THEN
    RAISE EXCEPTION 'ROUTER_AFTER_SELECTION_TRUST_DECL_ANCHOR_DRIFT';
  END IF;

  IF (length(d)-length(replace(d,old_tail,'')))/length(old_tail)<>1 THEN
    RAISE EXCEPTION 'ROUTER_AFTER_SELECTION_TRUST_TAIL_ANCHOR_DRIFT';
  END IF;

  d:=replace(d,old_decl,new_decl);
  d:=replace(d,old_tail,new_tail);
  EXECUTE d;
END
$patch_router_trust$;

CREATE OR REPLACE FUNCTION public.lf_router_pipeline_profile_after_selection_continue_v1(
  p_execution_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  s1 public.lf_operation_execution_steps%rowtype;
  ss public.lf_operation_execution_steps%rowtype;
  v_stage1 jsonb;
  v_semantic jsonb;
  v_after jsonb;
  v_after_sha text;
  v_step jsonb;
BEGIN
  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_ROUTER_LF'
     OR e.target_code<>'ACT-0001'
     OR e.status<>'IN_PROGRESS'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_PIPELINE_EXECUTION_INVALID'
    );
  END IF;

  SELECT * INTO s1
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='stage1_seal';

  SELECT * INTO ss
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='profile_semantic_selection';

  IF s1.execution_id IS NULL
     OR s1.status<>'STEP_PASS_WITH_EVIDENCE'
     OR ss.execution_id IS NULL
     OR ss.status<>'STEP_PASS_WITH_EVIDENCE'
     OR ss.evidence_payload->>'decision'<>'SELECTED'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_PROFILE_SELECTION_NOT_READY_FOR_AFTER_SELECTION',
      'execution_id',p_execution_id
    );
  END IF;

  v_stage1:=s1.evidence_payload->'stage1_payload';
  v_semantic:=ss.evidence_payload->'semantic_result';

  v_after:=public.lf_router_profile_after_selection_v1(
    v_stage1,v_semantic
  );

  IF v_after->>'status'<>'READY_FOR_GATE2' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code',coalesce(
        v_after->>'blocking_code',
        'BLOCK_ROUTER_PROFILE_AFTER_SELECTION_NOT_READY'
      ),
      'execution_id',p_execution_id,
      'after_selection_result',v_after
    );
  END IF;

  v_after_sha:=encode(
    extensions.digest(convert_to(v_after::text,'UTF8'),'sha256'),
    'hex'
  );

  v_step:=public.lf_record_router_execution_step_v1(
    p_execution_id,
    'profile_after_selection',
    'router-profile-after-selection://'||v_after_sha,
    jsonb_build_object(
      'selected_profile_code',v_semantic->>'selected_profile_code',
      'profile_selection_receipt_sha256',v_semantic->>'semantic_receipt_sha256',
      'after_selection_result',v_after,
      'after_selection_sha256',v_after_sha,
      'after_selection_status',v_after->>'status',
      'after_selection_step',v_after->>'paso'
    ),
    p_execution_id
  );

  IF v_step->>'outcome'<>'STEP_RECORDED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code',coalesce(
        v_step->>'code',
        'BLOCK_ROUTER_PROFILE_AFTER_SELECTION_NOT_CLEAN'
      ),
      'execution_id',p_execution_id,
      'step_result',v_step
    );
  END IF;

  UPDATE public.lf_operation_execution
  SET manifest=manifest||jsonb_build_object(
        'current_step','profile_after_selection',
        'next_step','profile_gate2',
        'selected_profile_code',v_semantic->>'selected_profile_code',
        'profile_after_selection_sha256',v_after_sha,
        'profile_after_selection_step',v_after->>'paso'
      ),
      updated_by_execution_id=p_execution_id,
      updated_at=now()
  WHERE execution_id=p_execution_id;

  RETURN jsonb_build_object(
    'status','PROFILE_AFTER_SELECTION_READY',
    'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
    'execution_id',p_execution_id,
    'current_step','profile_after_selection',
    'next_step','profile_gate2',
    'selected_profile_code',v_semantic->>'selected_profile_code',
    'after_selection_result',v_after,
    'caller_selects_next_step',false,
    'effect_authority',false,
    'downstream_execution_allowed',false
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_router_pipeline_profile_after_selection_continue_v1(text)
  FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_router_pipeline_profile_after_selection_continue_v1(text)
  TO postgres;

DO $patch_semantic_submit$
DECLARE
  d text;
  old_decl text := $old$
  v_status text;
BEGIN
$old$;
  new_decl text := $new$
  v_status text;
  v_after_selection jsonb;
BEGIN
$new$;
  old_return text := $oldreturn$
  RETURN jsonb_build_object(
    'status',v_status,
    'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
    'execution_id',p_execution_id,
    'current_step','profile_semantic_selection',
    'next_step',v_next_step,
    'semantic_result',v_result,
    'semantic_validation',v_validation,
    'caller_selects_next_step',false,
    'effect_authority',false,
    'downstream_execution_allowed',false
  );
$oldreturn$;
  new_return text := $newreturn$
  IF v_decision='SELECTED' THEN
    v_after_selection:=
      public.lf_router_pipeline_profile_after_selection_continue_v1(
        p_execution_id
      );

    RETURN v_after_selection||jsonb_build_object(
      'semantic_status','PROFILE_SELECTION_READY',
      'semantic_result',v_result,
      'semantic_validation',v_validation
    );
  END IF;

  RETURN jsonb_build_object(
    'status',v_status,
    'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
    'execution_id',p_execution_id,
    'current_step','profile_semantic_selection',
    'next_step',v_next_step,
    'semantic_result',v_result,
    'semantic_validation',v_validation,
    'caller_selects_next_step',false,
    'effect_authority',false,
    'downstream_execution_allowed',false
  );
$newreturn$;
BEGIN
  d:=pg_get_functiondef(
    'public.lf_router_pipeline_profile_semantic_submit_v1(text,text)'::regprocedure
  );

  IF (length(d)-length(replace(d,old_decl,'')))/length(old_decl)<>1 THEN
    RAISE EXCEPTION 'ROUTER_AFTER_SELECTION_SUBMIT_DECL_ANCHOR_DRIFT';
  END IF;

  IF (length(d)-length(replace(d,old_return,'')))/length(old_return)<>1 THEN
    RAISE EXCEPTION 'ROUTER_AFTER_SELECTION_SUBMIT_RETURN_ANCHOR_DRIFT';
  END IF;

  d:=replace(d,old_decl,new_decl);
  d:=replace(d,old_return,new_return);
  EXECUTE d;
END
$patch_semantic_submit$;

COMMENT ON FUNCTION public.lf_router_pipeline_profile_after_selection_continue_v1(text) IS
'Internal-only governed ACT-0001 continuation after a SELECTED semantic profile result. Reconstructs Stage1 and semantic selection from durable execution evidence and materializes the canonical channel-neutral post-selection result.';

DO $postcheck$
DECLARE
  v_begin jsonb;
  v_exec text;
  v_stage1 jsonb;
  v_flow jsonb;
  v_prepare jsonb;
  v_submit jsonb;
  v_status jsonb;
  v_raw text;
  v_early jsonb;
  v_fake jsonb;
  v_begin2 jsonb;
  v_exec2 text;
BEGIN
  IF (
    SELECT count(*)
    FROM public.lf_operation_step_contracts
    WHERE operation_code='EJECUCION_ROUTER_LF'
      AND status='ACTIVE_ENFORCEMENT'
  )<>6 THEN
    RAISE EXCEPTION 'ROUTER_AFTER_SELECTION_STEP_COUNT_FAILED';
  END IF;

  IF has_function_privilege(
       'service_role',
       'public.lf_router_pipeline_profile_after_selection_continue_v1(text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'supabase_read_only_user',
       'public.lf_router_pipeline_profile_after_selection_continue_v1(text)',
       'EXECUTE'
     )
  THEN
    RAISE EXCEPTION 'ROUTER_AFTER_SELECTION_INTERNAL_ACL_FAILED';
  END IF;

  BEGIN
    v_begin:=public.lf_router_pipeline_begin_v1(
      'Analiza técnicamente el Login B2B sin realizar cambios.'
    );
    v_exec:=v_begin->>'execution_id';

    v_early:=public.lf_router_pipeline_profile_after_selection_continue_v1(
      v_exec
    );
    IF v_early->>'blocking_code'
         <>'BLOCK_ROUTER_PROFILE_SELECTION_NOT_READY_FOR_AFTER_SELECTION'
    THEN
      RAISE EXCEPTION 'ROUTER_AFTER_SELECTION_EARLY_CALL_NOT_BLOCKED:%',v_early;
    END IF;

    v_stage1:=jsonb_build_object(
      'schema_version','LF_ROUTER_STAGE1_V2',
      'texto_original','Analiza técnicamente el Login B2B sin realizar cambios.',
      'es_operacion',true,
      'respuesta_directa',false,
      'accion','analizar técnicamente',
      'sujeto','Login B2B',
      'correcciones','[]'::jsonb,
      'formas_busqueda',jsonb_build_array('Login B2B'),
      'ambiguo',false,
      'alternativas','[]'::jsonb,
      'pregunta_usuario',null,
      'capability_hint',null,
      'downstream_execution_allowed',false,
      'canal_candidato','PROGRAMACION',
      'negocio_codigo','LF',
      'negocios_afectados','[]'::jsonb,
      'ruta_transversal',null,
      'razon_seleccion','Análisis técnico',
      'alcance',jsonb_build_object(
        'target_type','PANTALLA',
        'target_hint','B2B-AUTH-001',
        'resolution_status','UNRESOLVED'
      )
    );

    v_flow:=public.lf_router_pipeline_stage1_submit_v1(v_exec,v_stage1);

    IF v_flow->>'status'<>'NEXT_TRANSITION_READY'
       OR v_flow->>'next_step'<>'profile_semantic_selection'
    THEN
      RAISE EXCEPTION 'ROUTER_AFTER_SELECTION_STAGE2_FLOW_FAIL:%',v_flow;
    END IF;

    v_prepare:=public.lf_router_pipeline_profile_semantic_prepare_v1(v_exec);

    v_raw:=jsonb_build_object(
      'decision','SELECTED',
      'selected_profile_code','ACT-0051',
      'ambiguous_profile_codes','[]'::jsonb,
      'reason','Frontend implementation analysis matches the declared ACT-0051 purpose and activation scope.',
      'evidence_refs',jsonb_build_array(
        jsonb_build_object(
          'profile_code','ACT-0051',
          'kind','PURPOSE',
          'source_section','Purpose'
        )
      ),
      'material_ambiguities','[]'::jsonb
    )::text;

    v_submit:=public.lf_router_pipeline_profile_semantic_submit_v1(
      v_exec,v_raw
    );

    IF v_submit->>'status'<>'PROFILE_AFTER_SELECTION_READY'
       OR v_submit->>'current_step'<>'profile_after_selection'
       OR v_submit->>'next_step'<>'profile_gate2'
       OR v_submit->>'selected_profile_code'<>'ACT-0051'
       OR v_submit#>>'{after_selection_result,status}'<>'READY_FOR_GATE2'
       OR v_submit#>>'{after_selection_result,paso}'<>'PROGRAMACION_GATE2_PERFIL'
       OR v_submit#>>'{after_selection_result,perfil_candidato}'<>'ACT-0051'
       OR v_submit#>>'{semantic_result,decision}'<>'SELECTED'
    THEN
      RAISE EXCEPTION 'ROUTER_AFTER_SELECTION_VALID_FLOW_FAIL:%',v_submit;
    END IF;

    v_status:=public.lf_router_pipeline_status_v1(v_exec);
    IF jsonb_array_length(v_status->'steps')<>6
       OR v_status#>>'{steps,5,step_id}'<>'profile_after_selection'
       OR v_status#>>'{steps,5,status}'<>'STEP_PASS_WITH_EVIDENCE'
       OR v_status#>>'{manifest,next_step}'<>'profile_gate2'
    THEN
      RAISE EXCEPTION 'ROUTER_AFTER_SELECTION_STATUS_FAIL:%',v_status;
    END IF;

    v_begin2:=public.lf_router_pipeline_begin_v1(
      'Consulta el Login B2B sin realizar cambios.'
    );
    v_exec2:=v_begin2->>'execution_id';

    v_fake:=public.lf_record_operation_step_core_v1(
      v_exec2,
      'profile_after_selection',
      'forged://profile-after-selection',
      jsonb_build_object(
        'selected_profile_code','ACT-0051',
        'profile_selection_receipt_sha256',repeat('0',64),
        'after_selection_result',jsonb_build_object(
          'status','READY_FOR_GATE2',
          'paso','PROGRAMACION_GATE2_PERFIL',
          'perfil_candidato','ACT-0051'
        ),
        'after_selection_sha256',repeat('0',64),
        'after_selection_status','READY_FOR_GATE2',
        'after_selection_step','PROGRAMACION_GATE2_PERFIL'
      ),
      v_exec2,
      'EJECUCION_ROUTER_LF',
      'DOC',
      'ACTIVE_ENFORCEMENT',
      'ACTIVE_ENFORCEMENT',
      'ACTIVE_ENFORCEMENT',
      jsonb_build_object(
        'valid',true,
        'server_assertions',jsonb_build_array('server_validated'),
        'server_hard_fails','[]'::jsonb
      ),
      false,
      'FORGED_AFTER_SELECTION_CALLER'
    );

    IF v_fake->>'outcome'<>'BLOCKED' THEN
      RAISE EXCEPTION 'ROUTER_AFTER_SELECTION_FORGED_NOT_BLOCKED:%',v_fake;
    END IF;

    RAISE EXCEPTION USING
      ERRCODE='PZ304',
      MESSAGE='ROUTER_AFTER_SELECTION_ROLLBACK_SENTINEL';
  EXCEPTION
    WHEN SQLSTATE 'PZ304' THEN
      NULL;
  END;

  IF EXISTS (
    SELECT 1
    FROM public.lf_operation_execution
    WHERE operation_code='EJECUCION_ROUTER_LF'
  ) THEN
    RAISE EXCEPTION 'ROUTER_AFTER_SELECTION_POSTCHECK_RESIDUE';
  END IF;
END
$postcheck$;

UPDATE public.lf_operation_execution
SET status='COMPLETED',
    completed_at=clock_timestamp(),
    updated_at=clock_timestamp(),
    updated_by_execution_id='EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V04-20261027-001',
    manifest=manifest||jsonb_build_object(
      'result','ROUTER_PROFILE_AFTER_SELECTION_PILOT_REGISTERED',
      'operation_code','EJECUCION_ROUTER_LF',
      'operation_version','v0.4-pilot',
      'operation_status','CANDIDATO_READ_ONLY',
      'operation_lifecycle_state','OP_CANDIDATE',
      'production_allowed',false,
      'router_cutover_executed',false
    )
WHERE execution_id='EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V04-20261027-001'
  AND operation_code='VULNERABILITY_COVERAGE_REPAIR_LF'
  AND status='IN_PROGRESS'
  AND manifest->>'bootstrap_operation_code'='EJECUCION_ROUTER_LF'
  AND manifest->>'bootstrap_status_ceiling'='SANDBOX_ACTIVE';

DO $bootstrap_close_postcheck$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_execution
    WHERE execution_id='EXEC-BOOTSTRAP-EJECUCION-ROUTER-LF-V04-20261027-001'
      AND operation_code='VULNERABILITY_COVERAGE_REPAIR_LF'
      AND target_code='EJECUCION_ROUTER_LF'
      AND status='COMPLETED'
      AND completed_at IS NOT NULL
      AND manifest->>'result'='ROUTER_PROFILE_AFTER_SELECTION_PILOT_REGISTERED'
  ) THEN
    RAISE EXCEPTION 'ROUTER_AFTER_SELECTION_BOOTSTRAP_CLOSE_FAILED';
  END IF;
END
$bootstrap_close_postcheck$;

COMMIT;
