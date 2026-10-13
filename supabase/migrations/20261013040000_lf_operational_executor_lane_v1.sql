-- LF_OPERATION_EXECUTOR governance candidate v1.
-- Migration Train ONLY. No project/checkpoint-specific values.
-- All effects, authorization, and governed closure must share one transaction.
BEGIN;

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM public.lf_operation_registry WHERE operation_code='EJECUCION_OPERATIVA_LF')
     OR EXISTS (SELECT 1 FROM public.lf_router_action_registry
                WHERE asset_type='OPERATIONAL_DB' AND action_code='OPERATION_EXECUTE') THEN
    RAISE EXCEPTION 'OP_EXECUTOR_CANDIDATE_CONFLICT_REQUIRES_RECONCILIATION';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lf_router_action_registry
                 WHERE asset_type='DB' AND action_code='UPDATE'
                   AND operation_code='ACTUALIZACION_DB_LF' AND status='ACTIVE') THEN
    RAISE EXCEPTION 'MIGRATION_TRAIN_ROUTE_NOT_PRESERVED';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lf_activos
                 WHERE codigo_activo='ROUTER_DOWNSTREAM_AUTHORITY' AND archived_at IS NULL
                   AND estado_operativo='ACTIVO'
                   AND jsonb_typeof(metadata #> '{transversal_inventory,consumers_known}')='array') THEN
    RAISE EXCEPTION 'ROUTER_AUTHORITY_CONSUMER_CATALOGUE_NOT_READY';
  END IF;
END $guard$;

INSERT INTO public.lf_operation_registry (
  operation_code,version,status,source_model,source_repo,source_paths,notes,
  operation_family,operation_domain,operation_type,applies_to_asset_type,
  lifecycle_state_code,created_by_execution_id
) VALUES (
  'EJECUCION_OPERATIVA_LF','v1.0.0','SANDBOX_ACTIVE','GIT_FIRST_SQL',
  'cristhianlujan/claude-persona-lf-patch',
  '["public.lf_operational_executor_begin_v1",
    "public.lf_operational_executor_finish_v1",
    "public.lf_close_operational_execution_v1",
    "sandbox/lf_contract_gate_test/operational_executor/operation_lane_contract_candidate_v1.json"]'::jsonb,
  'Bounded operational handler dispatcher; no migrations, no caller-provided SQL or broad DML.',
  'OPERATIONAL_EXECUTION','OPERATIONAL_DATA','EXECUTION_PROTOCOL',
  'OPERATIONAL_DB','OP_CANDIDATE','EXEC-TRAIN-OPERATIONAL-BOOTSTRAP-V1'
);

INSERT INTO public.lf_operation_contracts (
  operation_code,contract_code,contract_path,required_before_write,allowed,blocked,
  required_after_write,status,created_by_execution_id
) VALUES (
  'EJECUCION_OPERATIVA_LF','CONTRACT-EJECUCION-OPERATIVA-LF-v1',
  'supabase://public/lf_operation_contracts/EJECUCION_OPERATIVA_LF/v1',
  '["router_authority_receipt","current_execution","exact_handler_manifest",
    "effect_guard_reservation","lease_fence","contract_currentness"]'::jsonb,
  '{"lane":"GOVERNED_OPERATIONAL_DML","executor":"LF_OPERATION_EXECUTOR_V1",
    "router":"ACT-0001","target_type":"OPERATIONAL_DB",
    "action":"OPERATION_EXECUTE","handler_registry":"TRUSTED_ONLY",
    "transaction":"ATOMIC_ONE_CONNECTION"}'::jsonb,
  '["DB_UPDATE_ROUTE","MIGRATION","DDL","ARBITRARY_SQL",
    "UNREGISTERED_HANDLER","CROSS_OPERATION_REPLAY","UNSCOPED_DML"]'::jsonb,
  '["handler_readback","operation_effect_guard_readback","router_authority_readback",
    "governed_execution_closeout"]'::jsonb,
  'ACTIVE_ENFORCEMENT','EXEC-TRAIN-OPERATIONAL-BOOTSTRAP-V1'
);

WITH steps(ord,id,evidence) AS (VALUES
 (10,'preflight','["router_authority_validation","operation_admission","handler_binding"]'::jsonb),
 (20,'effect','["effect_guard_reservation","effect_receipt"]'::jsonb),
 (30,'verify','["effect_guard_readback","handler_readback","router_authority_readback"]'::jsonb)
)
INSERT INTO public.lf_operation_steps (
  operation_code,step_order,step_id,required,evidence_required,source_path,active,
  execution_order,created_by_execution_id
)
SELECT 'EJECUCION_OPERATIVA_LF',ord,id,true,
       array_to_string(ARRAY(SELECT jsonb_array_elements_text(evidence)),','),
       'supabase://public/lf_operation_step_contracts/EJECUCION_OPERATIVA_LF/'||id,
       true,ord,'EXEC-TRAIN-OPERATIONAL-BOOTSTRAP-V1'
FROM steps;

WITH steps(ord,id,evidence,next_step) AS (VALUES
 (10,'preflight','["router_authority_validation","operation_admission","handler_binding"]'::jsonb,'effect'),
 (20,'effect','["effect_guard_reservation","effect_receipt"]'::jsonb,'verify'),
 (30,'verify','["effect_guard_readback","handler_readback","router_authority_readback"]'::jsonb,NULL::text)
)
INSERT INTO public.lf_operation_step_contracts (
  operation_code,step_id,step_order,execution_order,contract_code,purpose,
  input_required,resolver_ref,output_payload,pass_condition,block_condition,
  blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,
  status,created_by_execution_id
)
SELECT 'EJECUCION_OPERATIVA_LF',id,ord,ord,'CONTRACT-EJECUCION-OPERATIVA-LF-v1',
       'SQL-validated operational executor '||id,'[]'::jsonb,
       'public.lf_close_operational_execution_v1',evidence,
       '{"server_validated":true}'::jsonb,'{"server_invalid":true}'::jsonb,
       'BLOCK_OPERATIONAL_'||upper(id),'JUDGE-OPERATIONAL-EXECUTION-V1',
       evidence,next_step,'RETURN_TO_ROUTER',
       'ACTIVE_ENFORCEMENT','EXEC-TRAIN-OPERATIONAL-BOOTSTRAP-V1'
FROM steps;

INSERT INTO public.lf_operation_judges (
  operation_code,judge_code,judge_path,pass_if,fail_if,result_values,status,
  created_by_execution_id
) VALUES (
  'EJECUCION_OPERATIVA_LF','JUDGE-OPERATIONAL-EXECUTION-V1',
  'supabase://public/lf_operation_judges/EJECUCION_OPERATIVA_LF/V1',
  '{"server_validated":true}'::jsonb,'{"server_invalid":true}'::jsonb,
  '["PASS_CLEAN","BLOCKED_BY_ENFORCEMENT","RETURN_TO_WORKER"]'::jsonb,
  'ACTIVE_ENFORCEMENT','EXEC-TRAIN-OPERATIONAL-BOOTSTRAP-V1'
);

WITH s(ord,id,keys) AS (VALUES
 (10,'preflight','["router_authority_validation","operation_admission","handler_binding"]'::jsonb),
 (20,'effect','["effect_guard_reservation","effect_receipt"]'::jsonb),
 (30,'verify','["effect_guard_readback","handler_readback","router_authority_readback"]'::jsonb)
)
INSERT INTO public.lf_operation_step_judge_bindings (
  operation_code,step_order,step_id,judge_code,clean_result_value,
  blocked_result_value,return_result_value,required_evidence_keys,status,
  created_by_execution_id
)
SELECT 'EJECUCION_OPERATIVA_LF',ord,id,'JUDGE-OPERATIONAL-EXECUTION-V1',
       'PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER',
       keys,'ACTIVE_ENFORCEMENT','EXEC-TRAIN-OPERATIONAL-BOOTSTRAP-V1'
FROM s;

INSERT INTO public.lf_operation_policy_bindings (
  operation_code,policy_code,policy_role,required,distribution_modes,
  binding_status,created_by_execution_id
) VALUES
 ('EJECUCION_OPERATIVA_LF','POL-LF-OPERATION-LIFECYCLE','GOVERNANCE_LIFECYCLE',true,ARRAY['ROUTER','DIRECT'],'ACTIVE','EXEC-TRAIN-OPERATIONAL-BOOTSTRAP-V1'),
 ('EJECUCION_OPERATIVA_LF','POL-LF-POLICY-CONSUMPTION','POLICY_CONSUMPTION',true,ARRAY['ROUTER','DIRECT'],'ACTIVE','EXEC-TRAIN-OPERATIONAL-BOOTSTRAP-V1'),
 ('EJECUCION_OPERATIVA_LF','POL-LF-SOURCE-RESOLUTION','SOURCE_RESOLUTION',true,ARRAY['ROUTER','DIRECT'],'ACTIVE','EXEC-TRAIN-OPERATIONAL-BOOTSTRAP-V1'),
 ('EJECUCION_OPERATIVA_LF','POL-LF-STATE-MODEL','STATE_MODEL',true,ARRAY['ROUTER','DIRECT'],'ACTIVE','EXEC-TRAIN-OPERATIONAL-BOOTSTRAP-V1');

INSERT INTO public.lf_router_action_registry (
  asset_type,action_code,operation_code,operation_resolution,
  requires_existing_target,requires_missing_target,write_allowed,status,
  notes,created_by_execution_id
) VALUES (
  'OPERATIONAL_DB','OPERATION_EXECUTE','EJECUCION_OPERATIVA_LF','STATIC',
  false,false,true,'ACTIVE',
  'Dedicated operational-handler route; DB/UPDATE migration path remains exclusive.',
  'EXEC-TRAIN-OPERATIONAL-BOOTSTRAP-V1'
);

UPDATE public.lf_activos a
SET metadata=jsonb_set(
      a.metadata,'{transversal_inventory,consumers_known}',
      (a.metadata #> '{transversal_inventory,consumers_known}') ||
      '["EJECUCION_OPERATIVA_LF"]'::jsonb,
      false
    ),
    updated_by_execution_id='EXEC-TRAIN-OPERATIONAL-BOOTSTRAP-V1'
WHERE a.codigo_activo='ROUTER_DOWNSTREAM_AUTHORITY'
  AND a.archived_at IS NULL
  AND a.estado_operativo='ACTIVO'
  AND NOT ((a.metadata #> '{transversal_inventory,consumers_known}') ? 'EJECUCION_OPERATIVA_LF');

DO $authority$
BEGIN
  IF NOT public.lf_router_downstream_authority_consumer_v1('EJECUCION_OPERATIVA_LF') THEN
    RAISE EXCEPTION 'OPERATIONAL_ROUTER_AUTHORITY_CONSUMER_NOT_BOUND';
  END IF;
END $authority$;

-- SQL definer close: unlike the migration close, never reuses
-- ACTUALIZACION_DB_LF's judge or mutates that operation's registry.
CREATE OR REPLACE FUNCTION public.lf_close_operational_execution_v1(
  p_execution_id text,p_lease_owner text,p_lease_fence bigint,
  p_closure_evidence jsonb,p_actor_execution_id text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions
AS $close$
DECLARE
  v_exec public.lf_operation_execution%rowtype;
  v_effect public.lf_operation_effect_guard%rowtype;
  v_auth jsonb;
  v_admission jsonb;
  v_count integer;
  v_now timestamptz := clock_timestamp();
  v_step record;
  v_step_result jsonb;
  v_payload jsonb;
BEGIN
  IF jsonb_typeof(p_closure_evidence) IS DISTINCT FROM 'object'
     OR btrim(coalesce(p_actor_execution_id,''))='' THEN
    RAISE EXCEPTION 'OPERATIONAL_CLOSE_RECEIPT_OR_ACTOR_INVALID';
  END IF;
  SELECT * INTO v_exec FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id FOR UPDATE;
  IF NOT FOUND OR v_exec.operation_code<>'EJECUCION_OPERATIVA_LF'
     OR v_exec.target_type<>'OPERATIONAL_DB'
     OR v_exec.status<>'IN_PROGRESS' THEN
    RAISE EXCEPTION 'OPERATIONAL_CLOSE_EXECUTION_NOT_ADMITTED';
  END IF;
  IF v_exec.lease_owner IS DISTINCT FROM p_lease_owner
     OR v_exec.lease_fence IS DISTINCT FROM p_lease_fence
     OR v_exec.lease_expires_at IS NULL OR v_exec.lease_expires_at<=v_now THEN
    RAISE EXCEPTION 'OPERATIONAL_CLOSE_STALE_LEASE';
  END IF;
  v_auth:=public.lf_router_downstream_authority_validate_v1(p_execution_id);
  IF v_auth->>'code' IS DISTINCT FROM 'ROUTER_DOWNSTREAM_AUTHORITY_VALID'
     OR v_auth->>'valid' IS DISTINCT FROM 'true'
     OR v_auth->>'applicable' IS DISTINCT FROM 'true'
     OR v_auth->>'target_code' IS DISTINCT FROM v_exec.target_code THEN
    RAISE EXCEPTION 'OPERATIONAL_CLOSE_ROUTER_NOT_CURRENT';
  END IF;
  v_admission:=v_exec.manifest->'operational_transaction_admission';
  IF v_admission->>'status' IS DISTINCT FROM 'APPROVED'
     OR v_admission->>'verification' IS DISTINCT FROM 'PASS'
     OR v_admission->>'lane' IS DISTINCT FROM 'GOVERNED_OPERATIONAL_DML'
     OR v_admission->>'connector' IS DISTINCT FROM 'LF_OPERATION_EXECUTOR_V1'
     OR v_admission->>'handler_code' IS DISTINCT FROM p_closure_evidence->>'handler_code'
     OR v_admission->>'handler_revision' IS DISTINCT FROM p_closure_evidence->>'handler_revision'
     OR v_admission->>'payload_sha256' IS DISTINCT FROM p_closure_evidence->>'payload_sha256'
     OR v_admission->>'effect_scope' IS DISTINCT FROM p_closure_evidence->>'effect_scope'
     OR v_admission->>'dispatch_key' IS DISTINCT FROM p_closure_evidence->>'dispatch_key'
     OR v_exec.request_sha256 IS DISTINCT FROM p_closure_evidence->>'payload_sha256'
     OR v_exec.target_code IS DISTINCT FROM v_admission->>'handler_code' THEN
    RAISE EXCEPTION 'OPERATIONAL_CLOSE_HANDLER_BINDING_NOT_EXACT';
  END IF;
  IF p_closure_evidence->>'execution_id' IS DISTINCT FROM p_execution_id
     OR p_closure_evidence->>'schema_version' IS DISTINCT FROM 'lf-operation-executor-receipt/v1'
     OR p_closure_evidence #>> '{readback,verified}' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'OPERATIONAL_CLOSE_READBACK_NOT_VERIFIED';
  END IF;
  SELECT * INTO v_effect FROM public.lf_operation_effect_guard
  WHERE execution_id=p_execution_id
    AND effect_scope=p_closure_evidence->>'effect_scope' FOR UPDATE;
  IF NOT FOUND OR v_effect.state<>'SUCCEEDED'
     OR v_effect.receipt IS DISTINCT FROM p_closure_evidence
     OR v_effect.dispatch_key IS DISTINCT FROM p_closure_evidence->>'dispatch_key'
     OR v_effect.effect_request_sha256 IS DISTINCT FROM p_closure_evidence->>'payload_sha256' THEN
    RAISE EXCEPTION 'OPERATIONAL_CLOSE_EFFECT_RECEIPT_MISMATCH';
  END IF;
  SELECT count(*) INTO v_count FROM public.lf_operation_effect_guard
  WHERE execution_id=p_execution_id;
  IF v_count<>1 THEN RAISE EXCEPTION 'OPERATIONAL_CLOSE_EFFECT_CARDINALITY_INVALID'; END IF;
  SELECT count(*) INTO v_count FROM public.lf_operation_steps s
  JOIN public.lf_operation_step_contracts c
    ON c.operation_code=s.operation_code AND c.step_id=s.step_id AND c.step_order=s.step_order
  JOIN public.lf_operation_step_judge_bindings b
    ON b.operation_code=s.operation_code AND b.step_order=s.step_order AND b.step_id=s.step_id
  JOIN public.lf_operation_judges j
    ON j.operation_code=b.operation_code AND j.judge_code=b.judge_code
  WHERE s.operation_code='EJECUCION_OPERATIVA_LF'
    AND s.required AND s.active AND c.status='ACTIVE_ENFORCEMENT'
    AND b.status='ACTIVE_ENFORCEMENT' AND j.status='ACTIVE_ENFORCEMENT'
    AND b.clean_result_value='PASS_CLEAN';
  IF v_count<>3 OR
     (SELECT count(*) FROM public.lf_operation_steps
      WHERE operation_code='EJECUCION_OPERATIVA_LF' AND required AND active)<>3 THEN
    RAISE EXCEPTION 'OPERATIONAL_CLOSE_JUDGE_OR_STEPS_NOT_EXACT';
  END IF;
  IF EXISTS(SELECT 1 FROM public.lf_operation_execution_steps
            WHERE execution_id=p_execution_id) THEN
    RAISE EXCEPTION 'OPERATIONAL_CLOSE_PREEXISTING_STEP_EVIDENCE';
  END IF;

  -- Reuse the operation-neutral recorder and registered mini-judge.
  -- Assertions are server-derived after verifying durable Router, effect and readback.
  FOR v_step IN
    SELECT step_id FROM public.lf_operation_steps
    WHERE operation_code='EJECUCION_OPERATIVA_LF'
      AND required AND active ORDER BY execution_order,step_order
  LOOP
    v_payload:=CASE v_step.step_id
      WHEN 'preflight' THEN jsonb_build_object(
        'router_authority_validation',v_auth,'operation_admission',v_admission,
        'handler_binding',v_exec.target_code)
      WHEN 'effect' THEN jsonb_build_object(
        'effect_guard_reservation',jsonb_build_object(
          'effect_scope',v_effect.effect_scope,'dispatch_key',v_effect.dispatch_key,
          'effect_request_sha256',v_effect.effect_request_sha256),
        'effect_receipt',v_effect.receipt)
      WHEN 'verify' THEN jsonb_build_object(
        'effect_guard_readback',jsonb_build_object(
          'state',v_effect.state,'receipt',v_effect.receipt),
        'handler_readback',p_closure_evidence->'readback',
        'router_authority_readback',v_auth)
      ELSE NULL
    END;
    IF v_payload IS NULL THEN
      RAISE EXCEPTION 'OPERATIONAL_CLOSE_UNRECOGNIZED_REQUIRED_STEP:%',v_step.step_id;
    END IF;
    v_step_result:=public.lf_record_operation_step_core_v1(
      p_execution_id,v_step.step_id,
      'LF_OPERATION_EXECUTOR_V1:'||p_execution_id,v_payload,
      p_actor_execution_id,
      'EJECUCION_OPERATIVA_LF','OPERATIONAL_DB',
      'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
      jsonb_build_object('valid',true,'code','OPERATIONAL_SQL_AUTHORITY_TRUST_VALID',
        'server_assertions',jsonb_build_array('server_validated'),
        'server_hard_fails','[]'::jsonb),
      false,'lf_close_operational_execution_v1'
    );
    IF v_step_result->>'outcome' IS DISTINCT FROM 'STEP_RECORDED'
       OR v_step_result->>'status' IS DISTINCT FROM 'PASS_CLEAN' THEN
      RAISE EXCEPTION 'OPERATIONAL_CLOSE_CANONICAL_JUDGE_BLOCKED:%:%',
        v_step.step_id,v_step_result->>'code';
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM public.lf_operation_execution_steps
      WHERE execution_id=p_execution_id AND status='PASS_CLEAN')<>3 THEN
    RAISE EXCEPTION 'OPERATIONAL_CLOSE_REQUIRED_STEPS_NOT_CLEAN';
  END IF;

  UPDATE public.lf_operation_execution
     SET status='COMPLETED',completed_at=v_now,lease_owner=NULL,
         lease_expires_at=NULL,
         manifest=manifest || jsonb_build_object(
           'operation_closed',true,
           'closed_by','lf_close_operational_execution_v1',
           'closure_evidence',p_closure_evidence),
         updated_by_execution_id=p_actor_execution_id,updated_at=v_now
   WHERE execution_id=p_execution_id AND status='IN_PROGRESS';
  IF NOT FOUND THEN RAISE EXCEPTION 'OPERATIONAL_CLOSE_WRITE_CONFLICT'; END IF;
  RETURN jsonb_build_object('result','EXECUTION_COMPLETED',
                            'execution_id',p_execution_id,'completed_at',v_now);
END $close$;

CREATE OR REPLACE FUNCTION public.lf_operational_executor_begin_v1(
  p_execution_id text,p_operation_code text,p_target_code text,p_handler_code text,
  p_handler_revision text,p_payload_sha text,p_effect_scope text,p_dispatch_key text,
  p_actor text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions
AS $begin$
DECLARE
  v_exec public.lf_operation_execution%rowtype;
  v_admission jsonb;
  v_auth jsonb;
  v_route jsonb;
  v_owner text;
  v_lease jsonb;
  v_reserve jsonb;
BEGIN
  PERFORM public.lf_operational_executor_assert_principal_v1('lf_operation_executor_runtime');
  IF p_operation_code IS DISTINCT FROM 'EJECUCION_OPERATIVA_LF'
     OR p_target_code IS DISTINCT FROM p_handler_code
     OR coalesce(p_payload_sha,'') !~ '^[0-9a-f]{64}$'
     OR btrim(coalesce(p_actor,''))='' THEN
    RAISE EXCEPTION 'OPERATIONAL_BEGIN_INPUT_OR_SCOPE_INVALID';
  END IF;
  v_route:=public.lf_router_resolve_v1(
    'Governed operational handler',NULL,'OPERATION_EXECUTE','OPERATIONAL_DB','ROUTER'
  );
  IF v_route->>'status' IS DISTINCT FROM 'READY_TO_EXECUTE'
     OR v_route->>'router' IS DISTINCT FROM 'ACT-0001'
     OR v_route->>'operation_code' IS DISTINCT FROM 'EJECUCION_OPERATIVA_LF'
     OR v_route->>'downstream_execution_allowed' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'OPERATIONAL_BEGIN_ROUTER_ROUTE_BLOCKED';
  END IF;
  SELECT * INTO v_exec FROM public.lf_operation_execution
   WHERE execution_id=p_execution_id FOR UPDATE;
  IF NOT FOUND OR v_exec.operation_code IS DISTINCT FROM p_operation_code
     OR v_exec.target_type IS DISTINCT FROM 'OPERATIONAL_DB'
     OR v_exec.target_code IS DISTINCT FROM p_target_code
     OR v_exec.status IS DISTINCT FROM 'IN_PROGRESS'
     OR v_exec.request_sha256 IS DISTINCT FROM p_payload_sha THEN
    RAISE EXCEPTION 'OPERATIONAL_BEGIN_EXECUTION_NOT_ADMITTED';
  END IF;
  -- Admission provenance is issued by the independent authority service.
  IF v_exec.created_by_execution_id IS DISTINCT FROM
       'OP-ADMISSION:'||(v_exec.manifest #>> '{operational_authority_receipt,issuer_login}')
     OR v_exec.manifest #>> '{operational_authority_receipt,issuer_role}'
       IS DISTINCT FROM 'lf_operational_admission_authority'
     OR coalesce(v_exec.manifest #>> '{operational_authority_receipt,approval_sha256}','')
       !~ '^[0-9a-f]{64}$'
     OR btrim(coalesce(v_exec.manifest #>> '{operational_authority_receipt,approval_ref}',''))='' THEN
    RAISE EXCEPTION 'OPERATIONAL_BEGIN_INDEPENDENT_ADMISSION_PROVENANCE_MISSING';
  END IF;
  v_admission:=v_exec.manifest->'operational_transaction_admission';
  IF v_admission->>'status' IS DISTINCT FROM 'APPROVED'
     OR v_admission->>'verification' IS DISTINCT FROM 'PASS'
     OR v_admission->>'lane' IS DISTINCT FROM 'GOVERNED_OPERATIONAL_DML'
     OR v_admission->>'connector' IS DISTINCT FROM 'LF_OPERATION_EXECUTOR_V1'
     OR v_admission->>'handler_code' IS DISTINCT FROM p_handler_code
     OR v_admission->>'handler_revision' IS DISTINCT FROM p_handler_revision
     OR v_admission->>'payload_sha256' IS DISTINCT FROM p_payload_sha
     OR v_admission->>'effect_scope' IS DISTINCT FROM p_effect_scope
     OR v_admission->>'dispatch_key' IS DISTINCT FROM p_dispatch_key THEN
    RAISE EXCEPTION 'OPERATIONAL_BEGIN_MANIFEST_NOT_EXACT';
  END IF;
  PERFORM public.lf_operational_executor_assert_decision_current_v1(p_execution_id);
  v_auth:=public.lf_router_downstream_authority_validate_v1(p_execution_id);
  IF v_auth->>'code' IS DISTINCT FROM 'ROUTER_DOWNSTREAM_AUTHORITY_VALID'
     OR v_auth->>'applicable' IS DISTINCT FROM 'true'
     OR v_auth->>'valid' IS DISTINCT FROM 'true'
     OR v_auth->>'target_type' IS DISTINCT FROM 'OPERATIONAL_DB'
     OR v_auth->>'target_code' IS DISTINCT FROM p_target_code THEN
    RAISE EXCEPTION 'OPERATIONAL_BEGIN_ROUTER_AUTHORITY_INVALID';
  END IF;
  v_owner:='operational-executor-' ||
    substr(encode(extensions.digest(convert_to(p_execution_id,'UTF8'),'sha256'),'hex'),1,32);
  v_lease:=public.fn_lf_operation_acquire_lease_v1(
    p_execution_id,v_owner,120,p_actor
  );
  IF v_lease->>'result' IS DISTINCT FROM 'LEASE_ACQUIRED' THEN
    RAISE EXCEPTION 'OPERATIONAL_BEGIN_LEASE_NOT_ACQUIRED';
  END IF;
  v_reserve:=public.fn_lf_operation_reserve_effect_v1(
    p_execution_id,v_owner,(v_lease->>'lease_fence')::bigint,
    p_effect_scope,p_payload_sha,p_dispatch_key,p_actor
  );
  IF v_reserve->>'result' IS DISTINCT FROM 'EFFECT_RESERVED_NEW'
     OR v_reserve->>'dispatch_permitted' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'OPERATIONAL_BEGIN_EFFECT_REPLAY_OR_AMBIGUOUS';
  END IF;
  RETURN jsonb_build_object(
    'result','READY_FOR_HANDLER','execution_id',p_execution_id,
    'lease_owner',v_owner,'lease_fence',(v_lease->>'lease_fence')::bigint,
    'payload_sha256',p_payload_sha,'effect_scope',p_effect_scope,
    'router_authority_validation',v_auth
  );
END $begin$;

CREATE OR REPLACE FUNCTION public.lf_operational_executor_finish_v1(
  p_execution_id text,p_lease_owner text,p_lease_fence bigint,p_effect_scope text,
  p_receipt jsonb,p_actor text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions
AS $finish$
DECLARE
  v_auth jsonb;
  v_mark jsonb;
  v_close jsonb;
BEGIN
  PERFORM public.lf_operational_executor_assert_principal_v1('lf_operation_executor_runtime');
  PERFORM public.lf_operational_executor_assert_decision_current_v1(p_execution_id);
  v_auth:=public.lf_router_downstream_authority_validate_v1(p_execution_id);
  IF v_auth->>'code' IS DISTINCT FROM 'ROUTER_DOWNSTREAM_AUTHORITY_VALID'
     OR v_auth->>'applicable' IS DISTINCT FROM 'true'
     OR v_auth->>'valid' IS DISTINCT FROM 'true'
     OR v_auth->>'operation_code' IS DISTINCT FROM 'EJECUCION_OPERATIVA_LF' THEN
    RAISE EXCEPTION 'OPERATIONAL_FINISH_ROUTER_AUTHORITY_STALE';
  END IF;
  v_mark:=public.fn_lf_operation_mark_effect_succeeded_v1(
    p_execution_id,p_lease_owner,p_lease_fence,p_effect_scope,p_receipt,p_actor
  );
  IF v_mark->>'result' IS DISTINCT FROM 'EFFECT_SUCCESS_PERSISTED' THEN
    RAISE EXCEPTION 'OPERATIONAL_FINISH_EFFECT_NOT_NEWLY_SUCCEEDED';
  END IF;
  v_close:=public.lf_close_operational_execution_v1(
    p_execution_id,p_lease_owner,p_lease_fence,p_receipt,p_actor
  );
  IF v_close->>'result' IS DISTINCT FROM 'EXECUTION_COMPLETED' THEN
    RAISE EXCEPTION 'OPERATIONAL_FINISH_GOVERNED_CLOSE_NOT_DURABLE';
  END IF;
  RETURN v_close;
END $finish$;

-- Shared principal verifier for the independent admission and effect runtime.
-- Called before any reservation, handler execution or finish-side mutation.
CREATE OR REPLACE FUNCTION public.lf_operational_executor_assert_principal_v1(
  p_expected_role text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public
AS $principal$
DECLARE v_login pg_roles%rowtype;
BEGIN
  IF p_expected_role NOT IN (
    'lf_operational_admission_authority','lf_operation_executor_runtime'
  ) THEN RAISE EXCEPTION 'OPERATIONAL_PRINCIPAL_ROLE_UNKNOWN'; END IF;
  IF session_user IN ('postgres','authenticator','service_role','programacion_builder')
     OR session_user=current_user THEN
    RAISE EXCEPTION 'OPERATIONAL_PRINCIPAL_EXTERNAL_LOGIN_REQUIRED';
  END IF;
  SELECT * INTO v_login FROM pg_roles WHERE rolname=session_user;
  IF NOT FOUND OR NOT v_login.rolcanlogin OR v_login.rolsuper
     OR v_login.rolcreatedb OR v_login.rolcreaterole OR v_login.rolinherit
     OR v_login.rolreplication OR v_login.rolbypassrls THEN
    RAISE EXCEPTION 'OPERATIONAL_PRINCIPAL_LEAST_PRIVILEGE_REQUIRED';
  END IF;
  IF NOT EXISTS(
      SELECT 1 FROM pg_auth_members m
      JOIN pg_roles g ON g.oid=m.roleid
      JOIN pg_roles u ON u.oid=m.member
      WHERE g.rolname=p_expected_role AND u.rolname=session_user
        AND m.set_option=true AND m.inherit_option=false AND m.admin_option=false
     ) OR EXISTS (
      SELECT 1 FROM pg_auth_members m
      JOIN pg_roles g ON g.oid=m.roleid
      JOIN pg_roles u ON u.oid=m.member
      WHERE u.rolname=session_user
        AND g.rolname IN (
          'lf_operational_admission_authority','lf_operation_executor_runtime'
        )
        AND g.rolname<>p_expected_role
     ) THEN
    RAISE EXCEPTION 'OPERATIONAL_PRINCIPAL_ROLE_CROSSOVER_OR_MEMBERSHIP_INVALID';
  END IF;
  -- A dedicated login must not be able to SET ROLE any third principal.
  IF EXISTS(
    SELECT 1 FROM pg_auth_members m
    JOIN pg_roles g ON g.oid=m.roleid
    JOIN pg_roles u ON u.oid=m.member
    WHERE u.rolname=session_user AND g.rolname<>p_expected_role
  ) THEN
    RAISE EXCEPTION 'OPERATIONAL_PRINCIPAL_EXTRA_ROLE_MEMBERSHIP_FORBIDDEN';
  END IF;
END $principal$;

-- Independent admission principal: the effect executor cannot approve itself.
-- Role membership and an external decision receipt are independently checked.
CREATE OR REPLACE FUNCTION public.lf_operational_executor_admit_v1(
  p_execution_id text,p_handler_code text,p_handler_revision text,
  p_payload_sha text,p_effect_scope text,p_dispatch_key text,
  p_idempotency_key text,p_approval_receipt jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions
AS $admit$
DECLARE
  v_route jsonb;
  v_manifest jsonb;
  v_reserved jsonb;
  v_authority jsonb;
  v_decision jsonb;
  v_latest jsonb;
  v_policy jsonb;
  v_subject jsonb;
  v_meta jsonb;
  v_req_id uuid;
  v_expires timestamptz;
  v_required_authority text;
  v_required_role text;
  v_allowed_actions jsonb;
BEGIN
  PERFORM public.lf_operational_executor_assert_principal_v1('lf_operational_admission_authority');
  IF coalesce(p_execution_id,'') !~ '^EXEC-[A-Z0-9_-]{3,200}$'
     OR coalesce(p_handler_code,'') !~ '^[A-Z][A-Z0-9_]{1,100}$'
     OR btrim(coalesce(p_handler_revision,''))=''
     OR coalesce(p_payload_sha,'') !~ '^[0-9a-f]{64}$'
     OR btrim(coalesce(p_effect_scope,''))=''
     OR btrim(coalesce(p_dispatch_key,''))=''
     OR btrim(coalesce(p_idempotency_key,''))='' THEN
    RAISE EXCEPTION 'OPERATIONAL_ADMISSION_IDENTITY_INVALID';
  END IF;
  IF jsonb_typeof(p_approval_receipt) IS DISTINCT FROM 'object'
     OR p_approval_receipt->>'schema_version'
        IS DISTINCT FROM 'LF_OPERATIONAL_REQUEST_AUTHORIZATION_V1'
     OR p_approval_receipt->>'decision' IS DISTINCT FROM 'APPROVED'
     OR btrim(coalesce(p_approval_receipt->>'approval_ref',''))=''
     OR p_approval_receipt->>'operation_code' IS DISTINCT FROM 'EJECUCION_OPERATIVA_LF'
     OR p_approval_receipt->>'handler_code' IS DISTINCT FROM p_handler_code
     OR p_approval_receipt->>'handler_revision' IS DISTINCT FROM p_handler_revision
     OR p_approval_receipt->>'payload_sha256' IS DISTINCT FROM p_payload_sha
     OR p_approval_receipt->>'effect_scope' IS DISTINCT FROM p_effect_scope
     OR p_approval_receipt->>'dispatch_key' IS DISTINCT FROM p_dispatch_key
     OR p_approval_receipt->>'idempotency_key' IS DISTINCT FROM p_idempotency_key THEN
    RAISE EXCEPTION 'OPERATIONAL_ADMISSION_EXTERNAL_DECISION_NOT_EXACT';
  END IF;
  -- The caller's JSON is only a locator; LF's durable, verified decision
  -- is the authority. Do not create a second approval ledger.
  IF coalesce(p_approval_receipt->>'request_id','')
         !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     OR coalesce(p_approval_receipt->>'receipt_sha256','')
         !~ '^[0-9a-f]{64}$'
     OR coalesce(p_approval_receipt->>'currentness_sha256','')
         !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'OPERATIONAL_ADMISSION_DURABLE_DECISION_REF_REQUIRED';
  END IF;
  v_req_id:=(p_approval_receipt->>'request_id')::uuid;
  v_decision:=private.fn_lf_human_decision_consume_v1(v_req_id);
  v_latest:=private.fn_lf_human_decision_current_for_subject_v1(
    'LF_OPERATION_EXECUTOR','OPERATIONAL_EXECUTION',p_execution_id
  );
  IF v_latest #>> '{routing,request_id}' IS DISTINCT FROM v_req_id::text
     OR v_latest #>> '{routing,request_status}' IS DISTINCT FROM 'DECIDED' THEN
    RAISE EXCEPTION 'OPERATIONAL_DECISION_SUPERSEDED_OR_OPEN';
  END IF;
  IF v_decision IS NULL
     OR v_decision->>'schema_version' IS DISTINCT FROM 'lf-human-decision-consume/v1'
     OR v_decision->>'request_status' IS DISTINCT FROM 'DECIDED'
     OR v_decision->>'producer_code' IS DISTINCT FROM 'LF_OPERATION_EXECUTOR'
     OR v_decision->>'subject_type' IS DISTINCT FROM 'OPERATIONAL_EXECUTION'
     OR v_decision->>'subject_key' IS DISTINCT FROM p_execution_id
     OR v_decision->>'currentness_sha256'
          IS DISTINCT FROM p_approval_receipt->>'currentness_sha256'
     OR v_decision #>> '{decision_receipt,decision_code}' IS DISTINCT FROM 'APPROVE'
     OR v_decision #>> '{decision_receipt,receipt_sha256}'
          IS DISTINCT FROM p_approval_receipt->>'receipt_sha256'
     OR v_decision #>> '{decision_receipt,receipt_id}'
          IS DISTINCT FROM p_approval_receipt->>'receipt_id'
     OR p_approval_receipt->>'approval_ref'
          IS DISTINCT FROM 'supabase://private/lf_human_decision_receipts_v1/'
                            ||coalesce(v_decision #>> '{decision_receipt,receipt_id}','') THEN
    RAISE EXCEPTION 'OPERATIONAL_ADMISSION_VERIFIED_DECISION_NOT_CURRENT';
  END IF;
  SELECT r.subject_ref,r.metadata,r.expires_at,
         r.required_authority_ref,r.required_reviewer_role,r.allowed_actions
    INTO v_subject,v_meta,v_expires,v_required_authority,
         v_required_role,v_allowed_actions
    FROM private.lf_human_decision_requests_v1 r
   WHERE r.request_id=v_req_id AND r.status='DECIDED';
  IF NOT FOUND OR (v_expires IS NOT NULL AND v_expires<=clock_timestamp())
     OR v_subject->>'operation_code' IS DISTINCT FROM 'EJECUCION_OPERATIVA_LF'
     OR v_subject->>'execution_id' IS DISTINCT FROM p_execution_id
     OR v_subject->>'handler_code' IS DISTINCT FROM p_handler_code
     OR v_subject->>'handler_revision' IS DISTINCT FROM p_handler_revision
     OR v_subject->>'payload_sha256' IS DISTINCT FROM p_payload_sha
     OR v_subject->>'effect_scope' IS DISTINCT FROM p_effect_scope
     OR v_subject->>'dispatch_key' IS DISTINCT FROM p_dispatch_key
     OR v_subject->>'idempotency_key' IS DISTINCT FROM p_idempotency_key
     OR NOT (v_allowed_actions ? 'APPROVE') THEN
    RAISE EXCEPTION 'OPERATIONAL_ADMISSION_DECISION_SCOPE_OR_EXPIRY_INVALID';
  END IF;
  v_policy:=private.fn_lf_human_decision_resolve_policy_v1(
     'LF_OPERATION_EXECUTOR','OPERATIONAL_EXECUTION',
     coalesce(v_meta->'classification_context','{}'::jsonb)
  );
  IF v_policy->>'state' IS DISTINCT FROM 'ACTIVE'
     OR v_policy->>'required_authority_ref' IS DISTINCT FROM v_required_authority
     OR v_policy->>'required_reviewer_role' IS DISTINCT FROM v_required_role
     OR NOT (coalesce(v_policy->'allowed_actions','[]'::jsonb) ? 'APPROVE') THEN
    RAISE EXCEPTION 'OPERATIONAL_ADMISSION_AUTHORITY_POLICY_NOT_ACTIVE';
  END IF;
  IF private.fn_lf_human_decision_assert_authority_receipt_v1(
       v_req_id,'APPROVE',
       v_decision #>> '{decision_receipt,reviewer_role}',
       v_decision #>> '{decision_receipt,authority_ref}',
       v_decision #>> '{decision_receipt,authority_receipt_ref}',
       v_decision #>> '{decision_receipt,authority_receipt_sha256}',
       v_decision #>> '{decision_receipt,observed_currentness_sha256}'
     ) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'OPERATIONAL_ADMISSION_AUTHORITY_RECEIPT_INVALID';
  END IF;
  -- Role identity proves an independent issuer, NOT cryptographic provenance
  -- of the provided receipt. Actual issuer/currentness EKB remains a hard gate.
  v_route:=public.lf_router_resolve_v1(
    'Governed operational handler',NULL,'OPERATION_EXECUTE','OPERATIONAL_DB','ROUTER'
  );
  IF v_route->>'status' IS DISTINCT FROM 'READY_TO_EXECUTE'
     OR v_route->>'router' IS DISTINCT FROM 'ACT-0001'
     OR v_route->>'asset_type' IS DISTINCT FROM 'OPERATIONAL_DB'
     OR v_route->>'action_code' IS DISTINCT FROM 'OPERATION_EXECUTE'
     OR v_route->>'operation_code' IS DISTINCT FROM 'EJECUCION_OPERATIVA_LF'
     OR v_route->>'downstream_execution_allowed' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'OPERATIONAL_ADMISSION_ROUTER_BLOCKED';
  END IF;
  v_authority:=jsonb_build_object(
    'issuer_role','lf_operational_admission_authority',
    'issuer_login',session_user,
    'approval_ref',p_approval_receipt->>'approval_ref',
    'decision_request_id',v_req_id::text,
    'decision_receipt_sha256',v_decision #>> '{decision_receipt,receipt_sha256}',
    'currentness_sha256',v_decision->>'currentness_sha256',
    'approval_sha256',encode(
      extensions.digest(convert_to(p_approval_receipt::text,'UTF8'),'sha256'),'hex'),
    'router_result',v_route
  );
  v_manifest:=jsonb_build_object(
    'operational_transaction_admission',jsonb_build_object(
      'status','APPROVED','verification','PASS',
      'lane','GOVERNED_OPERATIONAL_DML',
      'connector','LF_OPERATION_EXECUTOR_V1',
      'handler_code',p_handler_code,'handler_revision',p_handler_revision,
      'payload_sha256',p_payload_sha,'effect_scope',p_effect_scope,
      'dispatch_key',p_dispatch_key
    ),
    'operational_authority_receipt',v_authority
  );
  v_reserved:=public.fn_lf_operation_reserve_execution_v1(
    p_execution_id,'EJECUCION_OPERATIVA_LF',
    'OPERATIONAL_DB',p_handler_code,
    p_idempotency_key,p_payload_sha,
    'OP-ADMISSION:'||session_user,
    NULL,NULL,v_manifest
  );
  IF v_reserved->>'result' IS DISTINCT FROM 'RESERVED_NEW_EXECUTION'
     OR v_reserved->>'dispatch_permitted' IS DISTINCT FROM 'true'
     OR v_reserved->>'execution_id' IS DISTINCT FROM p_execution_id THEN
    RAISE EXCEPTION 'OPERATIONAL_ADMISSION_REPLAY_OR_EXECUTION_MISMATCH';
  END IF;
  RETURN jsonb_build_object(
    'result','OPERATIONAL_EXECUTION_ADMITTED',
    'execution_id',p_execution_id,
    'operation_code','EJECUCION_OPERATIVA_LF',
    'handler_code',p_handler_code,
    'payload_sha256',p_payload_sha,
    'approval_ref',p_approval_receipt->>'approval_ref'
  );
END $admit$;

-- Re-check decision currentness at execution time and before effect close.
-- Uses LF's existing canonical decision ledger, not a parallel approval store.
CREATE OR REPLACE FUNCTION public.lf_operational_executor_assert_decision_current_v1(
  p_execution_id text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,private,extensions
AS $decision_current$
DECLARE
  v_exec public.lf_operation_execution%rowtype;
  v_proof jsonb;
  v_decision jsonb;
  v_latest jsonb;
  v_subject jsonb;
  v_meta jsonb;
  v_expires timestamptz;
  v_authority text;
  v_reviewer text;
  v_policy jsonb;
  v_req uuid;
BEGIN
  SELECT * INTO v_exec FROM public.lf_operation_execution
   WHERE execution_id=p_execution_id FOR UPDATE;
  IF NOT FOUND OR v_exec.operation_code IS DISTINCT FROM 'EJECUCION_OPERATIVA_LF'
     OR v_exec.target_type IS DISTINCT FROM 'OPERATIONAL_DB'
     OR v_exec.status IS DISTINCT FROM 'IN_PROGRESS' THEN
    RAISE EXCEPTION 'OPERATIONAL_DECISION_EXECUTION_NOT_ACTIVE';
  END IF;
  v_proof:=v_exec.manifest->'operational_authority_receipt';
  IF coalesce(v_proof->>'decision_request_id','')
      !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     OR coalesce(v_proof->>'decision_receipt_sha256','') !~ '^[0-9a-f]{64}$'
     OR coalesce(v_proof->>'currentness_sha256','') !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'OPERATIONAL_DECISION_PROOF_NOT_DURABLE';
  END IF;
  v_req:=(v_proof->>'decision_request_id')::uuid;
  v_decision:=private.fn_lf_human_decision_consume_v1(v_req);
  v_latest:=private.fn_lf_human_decision_current_for_subject_v1(
    'LF_OPERATION_EXECUTOR','OPERATIONAL_EXECUTION',p_execution_id
  );
  IF v_latest #>> '{routing,request_id}' IS DISTINCT FROM v_req::text
     OR v_latest #>> '{routing,request_status}' IS DISTINCT FROM 'DECIDED' THEN
    RAISE EXCEPTION 'OPERATIONAL_DECISION_SUPERSEDED_OR_OPEN';
  END IF;
  IF v_decision IS NULL
     OR v_decision->>'request_status' IS DISTINCT FROM 'DECIDED'
     OR v_decision->>'producer_code' IS DISTINCT FROM 'LF_OPERATION_EXECUTOR'
     OR v_decision->>'subject_type' IS DISTINCT FROM 'OPERATIONAL_EXECUTION'
     OR v_decision->>'subject_key' IS DISTINCT FROM p_execution_id
     OR v_decision->>'currentness_sha256' IS DISTINCT FROM v_proof->>'currentness_sha256'
     OR v_decision #>> '{decision_receipt,decision_code}' IS DISTINCT FROM 'APPROVE'
     OR v_decision #>> '{decision_receipt,receipt_sha256}'
           IS DISTINCT FROM v_proof->>'decision_receipt_sha256'
     OR v_proof->>'approval_ref'
           IS DISTINCT FROM 'supabase://private/lf_human_decision_receipts_v1/'
             ||coalesce(v_decision #>> '{decision_receipt,receipt_id}','') THEN
    RAISE EXCEPTION 'OPERATIONAL_DECISION_NO_LONGER_CURRENT';
  END IF;
  SELECT r.subject_ref,r.metadata,r.expires_at,
         r.required_authority_ref,r.required_reviewer_role
    INTO v_subject,v_meta,v_expires,v_authority,v_reviewer
    FROM private.lf_human_decision_requests_v1 r
   WHERE r.request_id=v_req AND r.status='DECIDED';
  IF NOT FOUND OR (v_expires IS NOT NULL AND v_expires<=clock_timestamp())
     OR v_subject->>'operation_code' IS DISTINCT FROM v_exec.operation_code
     OR v_subject->>'execution_id' IS DISTINCT FROM p_execution_id
     OR v_subject->>'handler_code' IS DISTINCT FROM v_exec.target_code
     OR v_subject->>'payload_sha256' IS DISTINCT FROM v_exec.request_sha256
     OR v_subject->>'handler_revision' IS DISTINCT FROM
        v_exec.manifest #>> '{operational_transaction_admission,handler_revision}'
     OR v_subject->>'effect_scope' IS DISTINCT FROM
        v_exec.manifest #>> '{operational_transaction_admission,effect_scope}'
     OR v_subject->>'dispatch_key' IS DISTINCT FROM
        v_exec.manifest #>> '{operational_transaction_admission,dispatch_key}'
     OR v_subject->>'idempotency_key' IS DISTINCT FROM v_exec.idempotency_key THEN
    RAISE EXCEPTION 'OPERATIONAL_DECISION_BINDING_OR_EXPIRY_STALE';
  END IF;
  v_policy:=private.fn_lf_human_decision_resolve_policy_v1(
    'LF_OPERATION_EXECUTOR','OPERATIONAL_EXECUTION',
    coalesce(v_meta->'classification_context','{}'::jsonb)
  );
  IF v_policy->>'state' IS DISTINCT FROM 'ACTIVE'
     OR v_policy->>'required_authority_ref' IS DISTINCT FROM v_authority
     OR v_policy->>'required_reviewer_role' IS DISTINCT FROM v_reviewer
     OR NOT (coalesce(v_policy->'allowed_actions','[]'::jsonb) ? 'APPROVE') THEN
    RAISE EXCEPTION 'OPERATIONAL_DECISION_ROUTE_POLICY_NO_LONGER_ACTIVE';
  END IF;
  PERFORM private.fn_lf_human_decision_assert_authority_receipt_v1(
    v_req,'APPROVE',
    v_decision #>> '{decision_receipt,reviewer_role}',
    v_decision #>> '{decision_receipt,authority_ref}',
    v_decision #>> '{decision_receipt,authority_receipt_ref}',
    v_decision #>> '{decision_receipt,authority_receipt_sha256}',
    v_decision #>> '{decision_receipt,observed_currentness_sha256}'
  );
END $decision_current$;

-- An operational lane never creates a login or directly grants table writes.
DO $role$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='lf_operation_executor_runtime') THEN
   CREATE ROLE lf_operation_executor_runtime NOLOGIN NOINHERIT;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='lf_operational_admission_authority') THEN
   CREATE ROLE lf_operational_admission_authority NOLOGIN NOINHERIT;
 END IF;
END $role$;
DO $roles_verify$
BEGIN
 IF (
    SELECT count(*) FROM pg_roles r
    WHERE r.rolname IN ('lf_operational_admission_authority','lf_operation_executor_runtime')
      AND r.rolcanlogin=false AND r.rolinherit=false AND r.rolsuper=false
      AND r.rolcreatedb=false AND r.rolcreaterole=false
      AND r.rolreplication=false AND r.rolbypassrls=false
 ) <> 2 THEN
   RAISE EXCEPTION 'OPERATIONAL_AUTHORITY_ROLE_PRIVILEGES_UNSAFE';
 END IF;
 IF EXISTS(
   SELECT 1 FROM pg_auth_members m
   JOIN pg_roles g ON g.oid=m.roleid
   JOIN pg_roles u ON u.oid=m.member
   WHERE g.rolname IN ('lf_operational_admission_authority','lf_operation_executor_runtime')
     AND u.rolname IN ('lf_operational_admission_authority','lf_operation_executor_runtime')
 ) THEN
   RAISE EXCEPTION 'OPERATIONAL_AUTHORITY_ROLE_CROSS_MEMBERSHIP_FORBIDDEN';
 END IF;
END $roles_verify$;

GRANT USAGE ON SCHEMA public TO lf_operation_executor_runtime;
GRANT USAGE ON SCHEMA public TO lf_operational_admission_authority;
REVOKE ALL ON FUNCTION public.lf_operational_executor_assert_decision_current_v1(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lf_operational_executor_assert_principal_v1(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lf_operational_executor_admit_v1(text,text,text,text,text,text,text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lf_close_operational_execution_v1(text,text,bigint,jsonb,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lf_operational_executor_begin_v1(text,text,text,text,text,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lf_operational_executor_finish_v1(text,text,bigint,text,jsonb,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lf_operational_executor_assert_principal_v1(text)
  TO lf_operational_admission_authority,lf_operation_executor_runtime;
GRANT EXECUTE ON FUNCTION public.lf_operational_executor_admit_v1(text,text,text,text,text,text,text,jsonb)
  TO lf_operational_admission_authority;
GRANT EXECUTE ON FUNCTION public.lf_operational_executor_begin_v1(text,text,text,text,text,text,text,text,text)
  TO lf_operation_executor_runtime;
GRANT EXECUTE ON FUNCTION public.lf_operational_executor_finish_v1(text,text,bigint,text,jsonb,text)
  TO lf_operation_executor_runtime;

DO $verify$
DECLARE v_migration text; v_route jsonb;
BEGIN
 SELECT operation_code INTO v_migration FROM public.lf_router_action_registry
 WHERE asset_type='DB' AND action_code='UPDATE';
 IF v_migration IS DISTINCT FROM 'ACTUALIZACION_DB_LF' THEN
   RAISE EXCEPTION 'OPERATIONAL_MIGRATION_ROUTE_CHANGED';
 END IF;
 v_route:=public.lf_router_resolve_v1(
   'Governed operational handler',NULL,'OPERATION_EXECUTE','OPERATIONAL_DB','ROUTER'
 );
 IF v_route->>'status' IS DISTINCT FROM 'READY_TO_EXECUTE'
    OR v_route->>'operation_code' IS DISTINCT FROM 'EJECUCION_OPERATIVA_LF'
    OR v_route->>'downstream_execution_allowed' IS DISTINCT FROM 'true' THEN
   RAISE EXCEPTION 'OPERATIONAL_ROUTER_ADMISSION_READBACK_BLOCKED';
 END IF;
END $verify$;
COMMIT;
