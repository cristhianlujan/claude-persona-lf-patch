-- RW1-05_C2 support: compose and attach a terminal Profile Runtime authority receipt.
-- This adds evidence composition only. It does not add a new operation step, authorize an effect,
-- activate the semantic specialist, widen ACL, or alter Merge Train / Input Governance.
BEGIN;

DO $pre$
DECLARE c int;
BEGIN
  IF md5(pg_get_functiondef('public.lf_profile_execution_reconcile_queue_terminal_v1(uuid,text)'::regprocedure))
       <> 'e0c00d5972701bde0ef52d5e4d8091f1'
     OR md5(pg_get_functiondef('public.lf_profile_execution_scope_authority_packet_v1(text,text,text)'::regprocedure))
       <> 'b17af5a6d0a0fa6341bb1fbc5ce4e0bf'
     OR md5(pg_get_functiondef('public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)'::regprocedure))
       <> '7cf717887006e278356a716f3fd80182'
  THEN RAISE EXCEPTION 'RW105_C2_PROFILE_RECEIPT_SOURCE_DRIFT'; END IF;

  SELECT count(*) INTO c FROM public.lf_operation_steps
   WHERE operation_code='EJECUCION_PERFIL_LF' AND active;
  IF c<>11 THEN RAISE EXCEPTION 'RW105_C2_PROFILE_RECEIPT_STEP_DRIFT:%',c; END IF;

  SELECT count(*) INTO c FROM public.lf_operation_step_judge_bindings
   WHERE operation_code='EJECUCION_PERFIL_LF' AND status='ACTIVE_ENFORCEMENT';
  IF c<>11 THEN RAISE EXCEPTION 'RW105_C2_PROFILE_RECEIPT_BINDING_DRIFT:%',c; END IF;

  IF (SELECT status FROM public.lf_operation_registry WHERE operation_code='EJECUCION_PERFIL_LF')
       IS DISTINCT FROM 'PRODUCCION_CONTROLADA_READ_ONLY'
  THEN RAISE EXCEPTION 'RW105_C2_PROFILE_RECEIPT_OPERATION_STATE_DRIFT'; END IF;
END
$pre$;

CREATE OR REPLACE FUNCTION public.lf_profile_execution_terminal_authority_receipt_v1(
  p_execution_id text
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE
  e public.lf_operation_execution%rowtype;
  j record;
  v_steps jsonb;
  v_step_count int;
  v_router jsonb;
  v_scope jsonb;
  v_source jsonb;
  v_context jsonb;
  v_execute jsonb;
  v_output jsonb;
  v_semantic jsonb;
  v_report jsonb;
  v_literal text;
  v_body jsonb;
  v_sha text;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','code','PROFILE_TERMINAL_RECEIPT_INPUT_INVALID');
  END IF;

  SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
  IF NOT FOUND OR e.operation_code<>'EJECUCION_PERFIL_LF' OR e.target_type<>'PERFIL' THEN
    RETURN jsonb_build_object('status','BLOCKED','code','PROFILE_TERMINAL_RECEIPT_EXECUTION_INVALID');
  END IF;
  IF e.status<>'COMPLETED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED','code','PROFILE_TERMINAL_RECEIPT_EXECUTION_NOT_COMPLETED',
      'canonical_status',e.status
    );
  END IF;

  SELECT required_steps,required_steps_pass,fail_count,blocked_count,judge_result
    INTO j
  FROM public.v_lf_operation_execution_judge
  WHERE execution_id=p_execution_id;

  IF j IS NULL OR j.judge_result IS DISTINCT FROM 'PASS'
     OR j.required_steps IS DISTINCT FROM 11
     OR j.required_steps_pass IS DISTINCT FROM j.required_steps
     OR coalesce(j.fail_count,0)<>0 OR coalesce(j.blocked_count,0)<>0
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED','code','PROFILE_TERMINAL_RECEIPT_JUDGE_NOT_CLEAN',
      'judge_result',coalesce(j.judge_result,'MISSING'),
      'required_steps',j.required_steps,
      'required_steps_pass',j.required_steps_pass,
      'fail_count',j.fail_count,
      'blocked_count',j.blocked_count
    );
  END IF;

  SELECT count(*),
         jsonb_object_agg(
           s.step_id,
           jsonb_build_object(
             'status',s.status,
             'evidence_ref',s.evidence_ref,
             'evidence_payload',s.evidence_payload
           )
           ORDER BY os.step_order
         )
    INTO v_step_count,v_steps
  FROM public.lf_operation_execution_steps s
  JOIN public.lf_operation_steps os
    ON os.operation_code='EJECUCION_PERFIL_LF'
   AND os.step_id=s.step_id
   AND os.active
  WHERE s.execution_id=p_execution_id
    AND s.status='STEP_PASS_WITH_EVIDENCE';

  IF v_step_count<>11 OR jsonb_typeof(v_steps)<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED','code','PROFILE_TERMINAL_RECEIPT_STEP_SET_INCOMPLETE',
      'clean_steps',v_step_count
    );
  END IF;

  v_router:=v_steps#>'{router,evidence_payload,router_result}';
  v_scope:=v_steps#>'{input_validate,evidence_payload,scope_authority_packet}';
  v_source:=v_steps#>'{profile_source_read,evidence_payload}';
  v_context:=v_steps#>'{context_admission,evidence_payload}';
  v_execute:=v_steps#>'{execute_profile,evidence_payload}';
  v_output:=v_steps#>'{output_validate,evidence_payload}';
  v_semantic:=v_steps#>'{semantic_judge,evidence_payload}';
  v_report:=v_steps#>'{report_output,evidence_payload}';
  v_literal:=v_scope#>>'{authorized_requirements,0,statement}';

  IF jsonb_typeof(v_router)<>'object'
     OR v_router->>'status'<>'READY_TO_EXECUTE'
     OR v_router->>'operation_code'<>'EJECUCION_PERFIL_LF'
     OR jsonb_typeof(v_scope)<>'object'
     OR v_scope->>'packet_version'<>'LF_SCOPE_AUTHORITY_PACKET_V1'
     OR coalesce(v_scope->>'sha256','') !~ '^sha256:[0-9a-f]{64}$'
     OR jsonb_typeof(v_source)<>'object'
     OR coalesce(v_source->>'profile_source_digest','') !~ '^sha256:[0-9a-f]{64}$'
     OR jsonb_typeof(v_context)<>'object'
     OR coalesce(v_context->>'context_receipt_digest','') !~ '^sha256:[0-9a-f]{64}$'
     OR jsonb_typeof(v_execute)<>'object'
     OR jsonb_typeof(v_execute->'profile_output')<>'object'
     OR jsonb_typeof(v_output)<>'object'
     OR jsonb_typeof(v_semantic)<>'object'
     OR v_semantic#>>'{semantic_judge_result,status}' IS DISTINCT FROM 'PASS'
     OR jsonb_typeof(v_report)<>'object'
     OR v_report->>'result' IS DISTINCT FROM 'PASS_INDEPENDENT_SEMANTIC'
     OR nullif(v_literal,'') IS NULL
  THEN
    RETURN jsonb_build_object('status','BLOCKED','code','PROFILE_TERMINAL_RECEIPT_AUTHORITY_CHAIN_INCOMPLETE');
  END IF;

  IF e.manifest->>'queue_request_id' IS NULL
     OR e.manifest->>'input_sha256' IS NULL
     OR v_scope->>'execution_id' IS DISTINCT FROM p_execution_id
     OR v_report->>'execution_id' IS DISTINCT FROM p_execution_id
     OR v_report->>'profile_code' IS DISTINCT FROM e.target_code
  THEN
    RETURN jsonb_build_object('status','BLOCKED','code','PROFILE_TERMINAL_RECEIPT_IDENTITY_MISMATCH');
  END IF;

  v_body:=jsonb_build_object(
    'schema_version','LF_PROFILE_RUNTIME_TERMINAL_AUTHORITY_RECEIPT_V1',
    'queue_request_id',e.manifest->>'queue_request_id',
    'canonical_execution_id',e.execution_id,
    'operation_code',e.operation_code,
    'profile_code',e.target_code,
    'input_literal',v_literal,
    'input_literal_sha256',e.manifest->>'input_sha256',
    'router_authority_receipt',v_router,
    'scope_authority_packet',v_scope,
    'scope_authority_packet_sha256',v_steps#>>'{input_validate,evidence_payload,scope_authority_packet_sha256}',
    'profile_source_receipt',v_source,
    'context_receipt',jsonb_build_object(
      'ref',v_context->>'context_receipt_ref',
      'digest',v_context->>'context_receipt_digest',
      'server_validated',v_context->'server_validated'
    ),
    'raw_output_receipt',jsonb_build_object(
      'profile_output_sha256','sha256:'||encode(
        extensions.digest(convert_to((v_execute->'profile_output')::text,'UTF8'),'sha256'),'hex'
      ),
      'execute_evidence_ref',v_steps#>>'{execute_profile,evidence_ref}'
    ),
    'validator_receipt',jsonb_build_object(
      'output_contract_result',v_output->>'output_contract_result',
      'deterministic_validation',v_output->'deterministic_validation',
      'evidence_ref',v_steps#>>'{output_validate,evidence_ref}'
    ),
    'semantic_judge_receipt',v_semantic,
    'report_output_receipt',v_report,
    'canonical_judge_readback',jsonb_build_object(
      'required_steps',j.required_steps,
      'required_steps_pass',j.required_steps_pass,
      'fail_count',j.fail_count,
      'blocked_count',j.blocked_count,
      'judge_result',j.judge_result
    ),
    'source_refs',jsonb_build_array(
      v_steps#>>'{router,evidence_ref}',
      v_steps#>>'{input_validate,evidence_ref}',
      v_steps#>>'{profile_source_read,evidence_ref}',
      v_steps#>>'{context_admission,evidence_ref}',
      v_steps#>>'{execute_profile,evidence_ref}',
      v_steps#>>'{output_validate,evidence_ref}',
      v_steps#>>'{semantic_judge,evidence_ref}',
      v_steps#>>'{report_output,evidence_ref}'
    ),
    'authority_rule','ROUTER_AND_OPERATION_EVIDENCE_ONLY_NO_SPECIALIST_EFFECT_AUTHORITY'
  );
  v_sha:='sha256:'||encode(extensions.digest(convert_to(v_body::text,'UTF8'),'sha256'),'hex');

  RETURN jsonb_build_object(
    'status','READY',
    'terminal_authority_receipt',v_body||jsonb_build_object('sha256',v_sha),
    'terminal_authority_receipt_sha256',v_sha
  );
END
$fn$;

CREATE OR REPLACE FUNCTION public.lf_profile_execution_attach_terminal_authority_receipt_v1(
  p_execution_id text,
  p_actor_execution_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  e public.lf_operation_execution%rowtype;
  r jsonb;
  v_sha text;
  v_existing text;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR p_actor_execution_id IS DISTINCT FROM p_execution_id THEN
    RETURN jsonb_build_object('result','INPUT_OR_ACTOR_INVALID','blocking_code','PROFILE_TERMINAL_RECEIPT_ATTACH_FAILED');
  END IF;

  SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id FOR UPDATE;
  IF NOT FOUND OR e.operation_code<>'EJECUCION_PERFIL_LF' OR e.status<>'COMPLETED' THEN
    RETURN jsonb_build_object('result','EXECUTION_NOT_ATTACHABLE','blocking_code','PROFILE_TERMINAL_RECEIPT_ATTACH_FAILED');
  END IF;

  r:=public.lf_profile_execution_terminal_authority_receipt_v1(p_execution_id);
  IF r->>'status'<>'READY' THEN RETURN r||jsonb_build_object('result','RECEIPT_NOT_READY'); END IF;
  v_sha:=r->>'terminal_authority_receipt_sha256';
  v_existing:=e.manifest->>'terminal_authority_receipt_sha256';

  IF v_existing IS NOT NULL THEN
    IF v_existing=v_sha THEN
      RETURN jsonb_build_object(
        'result','TERMINAL_AUTHORITY_RECEIPT_ALREADY_ATTACHED',
        'terminal_authority_receipt',r->'terminal_authority_receipt',
        'terminal_authority_receipt_sha256',v_sha
      );
    END IF;
    RETURN jsonb_build_object(
      'result','TERMINAL_AUTHORITY_RECEIPT_CONFLICT',
      'blocking_code','PROFILE_TERMINAL_RECEIPT_ATTACH_FAILED',
      'existing_sha256',v_existing,'candidate_sha256',v_sha
    );
  END IF;

  UPDATE public.lf_operation_execution
     SET manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object(
           'terminal_authority_receipt',r->'terminal_authority_receipt',
           'terminal_authority_receipt_sha256',v_sha
         ),
         updated_by_execution_id=p_actor_execution_id,
         updated_at=now()
   WHERE execution_id=p_execution_id
     AND status='COMPLETED'
     AND manifest->>'terminal_authority_receipt_sha256' IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'result','TERMINAL_AUTHORITY_RECEIPT_COMPARE_AND_SET_FAILED',
      'blocking_code','PROFILE_TERMINAL_RECEIPT_ATTACH_FAILED'
    );
  END IF;

  RETURN jsonb_build_object(
    'result','TERMINAL_AUTHORITY_RECEIPT_ATTACHED',
    'terminal_authority_receipt',r->'terminal_authority_receipt',
    'terminal_authority_receipt_sha256',v_sha
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_execution_terminal_authority_receipt_v1(text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_execution_terminal_authority_receipt_v1(text)
  TO postgres,service_role,supabase_read_only_user;

REVOKE ALL ON FUNCTION public.lf_profile_execution_attach_terminal_authority_receipt_v1(text,text)
  FROM PUBLIC,anon,authenticated,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_profile_execution_attach_terminal_authority_receipt_v1(text,text)
  TO postgres,service_role;

COMMENT ON FUNCTION public.lf_profile_execution_terminal_authority_receipt_v1(text) IS
'RW1-05_C2 server-owned terminal evidence composer for EJECUCION_PERFIL_LF. Requires 11/11 clean canonical steps and PASS judge; composes Router, literal/hash, scope, source, context, RAW digest, validators, semantic judge and terminal readback. No effect authority.';
COMMENT ON FUNCTION public.lf_profile_execution_attach_terminal_authority_receipt_v1(text,text) IS
'RW1-05_C2 idempotent manifest attachment of the server-composed terminal authority receipt. Actor must be the exact canonical profile execution.';

DO $post$
DECLARE d text;
BEGIN
  d:=pg_get_functiondef('public.lf_profile_execution_terminal_authority_receipt_v1(text)'::regprocedure);
  IF position('router_authority_receipt' in d)=0
     OR position('scope_authority_packet' in d)=0
     OR position('semantic_judge_receipt' in d)=0
     OR position('required_steps_pass' in d)=0
  THEN RAISE EXCEPTION 'RW105_C2_PROFILE_RECEIPT_COMPOSER_POSTCHECK_FAILED'; END IF;

  IF has_function_privilege('anon','public.lf_profile_execution_terminal_authority_receipt_v1(text)','EXECUTE')
     OR has_function_privilege('authenticated','public.lf_profile_execution_terminal_authority_receipt_v1(text)','EXECUTE')
     OR has_function_privilege('anon','public.lf_profile_execution_attach_terminal_authority_receipt_v1(text,text)','EXECUTE')
     OR has_function_privilege('authenticated','public.lf_profile_execution_attach_terminal_authority_receipt_v1(text,text)','EXECUTE')
     OR has_function_privilege('supabase_read_only_user','public.lf_profile_execution_attach_terminal_authority_receipt_v1(text,text)','EXECUTE')
  THEN RAISE EXCEPTION 'RW105_C2_PROFILE_RECEIPT_ACL_WIDENED'; END IF;
END
$post$;

COMMIT;
