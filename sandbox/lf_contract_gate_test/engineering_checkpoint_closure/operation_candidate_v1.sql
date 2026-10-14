-- CANDIDATE SOURCE ONLY. NOT A MIGRATION. DO NOT RUN WITHOUT ADMISSION.
-- Reuses ACT-0001 authority, S30 effect guard, Engineering assertion/transition.
-- No change to DB_WRITE_TRANSPORT or LF Migration Merge Train.

CREATE TABLE IF NOT EXISTS programacion.engineering_checkpoint_closure_providers_v1 (
 plan_code text NOT NULL,
 unit_code text NOT NULL,
 checkpoint_code text NOT NULL,
 provider_fn regprocedure NOT NULL,
 binding_state text NOT NULL CHECK (binding_state IN ('CANDIDATE','ACTIVE','RETIRED')),
 contract_ref text NOT NULL,
 PRIMARY KEY(plan_code,unit_code,checkpoint_code)
);
REVOKE ALL ON programacion.engineering_checkpoint_closure_providers_v1
 FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_checkpoint_close_governed_v1(
 p_execution_id text,
 p_plan_code text,
 p_unit_code text,
 p_checkpoint_code text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,programacion,public,extensions
AS $close$
DECLARE
 c_operation constant text := 'CIERRE_CHECKPOINT_INGENIERIA_LF';
 v_exec public.lf_operation_execution%rowtype;
 v_authority jsonb;
 v_binding programacion.engineering_checkpoint_closure_providers_v1%rowtype;
 v_provider_schema text;
 v_provider_name text;
 v_provider_volatility "char";
 v_provider_args integer;
 v_provider_security boolean;
 v_check_id bigint;
 v_check_status text;
 v_boot jsonb;
 v_ready jsonb;
 v_spec jsonb;
 v_contract jsonb;
 v_contract_sha text;
 v_proof jsonb;
 v_assertion jsonb;
 v_transition jsonb;
 v_request_sha text;
 v_effect public.lf_operation_effect_guard%rowtype;
 v_scope text;
 v_receipt jsonb;
 v_evidence_ref text;
 v_receipt_sha text;
BEGIN
 -- Callability is restricted to service_role JWT; never trust an actor string.
 IF current_setting('request.jwt.claim.role',true) IS DISTINCT FROM 'service_role'
 THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_AUTHORITY_REQUIRED'; END IF;
 IF coalesce(p_execution_id,'')='' OR coalesce(p_plan_code,'')=''
    OR coalesce(p_unit_code,'')='' OR coalesce(p_checkpoint_code,'')=''
 THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_IDENTITY_REQUIRED'; END IF;

 SELECT * INTO v_exec FROM public.lf_operation_execution
 WHERE execution_id=p_execution_id FOR UPDATE;
 IF NOT FOUND OR v_exec.operation_code IS DISTINCT FROM c_operation
    OR v_exec.status IS DISTINCT FROM 'IN_PROGRESS'
    OR v_exec.target_type IS DISTINCT FROM 'ENGINEERING_CHECKPOINT'
    OR v_exec.target_code IS DISTINCT FROM
       concat_ws('/',p_plan_code,p_unit_code,p_checkpoint_code)
    OR v_exec.idempotency_key IS NULL
    OR coalesce(v_exec.request_sha256,'') !~ '^[a-f0-9]{64}
 THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_EXECUTION_NOT_BOUND'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM public.lf_operation_registry r
   WHERE r.operation_code=c_operation
     AND r.lifecycle_state_code='OP_OPERATIONAL'
     AND r.status IN ('SANDBOX_ACTIVE','PRODUCCION_CONTROLADA')
 ) THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_OPERATION_NOT_ACTIVATED'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM public.lf_router_action_registry r
   WHERE r.asset_type='ENGINEERING_CHECKPOINT'
     AND r.action_code='CHECKPOINT_CLOSE' AND r.operation_code=c_operation
     AND r.status='ACTIVE' AND r.write_allowed=true
 ) THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_ROUTER_BINDING_NOT_ACTIVE'; END IF;

 -- Existing Router validation must be applicable AND valid, never optional.
 IF NOT public.lf_router_downstream_authority_consumer_v1(c_operation)
 THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_ROUTER_CONSUMER_NOT_REGISTERED'; END IF;
 v_authority:=public.lf_router_downstream_authority_validate_v1(p_execution_id);
 IF v_authority->>'applicable' IS DISTINCT FROM 'true'
    OR v_authority->>'valid' IS DISTINCT FROM 'true'
    OR v_authority->>'operation_code' IS DISTINCT FROM c_operation
    OR v_authority->>'target_type' IS DISTINCT FROM 'ENGINEERING_CHECKPOINT'
    OR v_authority->>'action_code' IS DISTINCT FROM 'CHECKPOINT_CLOSE'
 THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_ROUTER_AUTHORITY_REJECTED:%',v_authority->>'code'; END IF;

 SELECT c.id,c.status INTO v_check_id,v_check_status
 FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
 WHERE u.plan_code=p_plan_code AND u.unit_code=p_unit_code
   AND u.disposition='ASSIGNED' AND c.checkpoint_code=p_checkpoint_code
 FOR UPDATE OF c;
 IF NOT FOUND THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_CHECKPOINT_NOT_FOUND'; END IF;

 SELECT * INTO v_binding
 FROM programacion.engineering_checkpoint_closure_providers_v1 b
 WHERE b.plan_code=p_plan_code AND b.unit_code=p_unit_code
   AND b.checkpoint_code=p_checkpoint_code AND b.binding_state='ACTIVE';
 IF NOT FOUND THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_PROOF_PROVIDER_NOT_ACTIVE'; END IF;
 SELECT n.nspname,p.proname,p.provolatile,p.pronargs,p.prosecdef
 INTO v_provider_schema,v_provider_name,v_provider_volatility,v_provider_args,
      v_provider_security
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE p.oid=v_binding.provider_fn::oid;
 IF v_provider_schema IS DISTINCT FROM 'programacion'
    OR v_provider_volatility NOT IN ('s','i') OR v_provider_args<>3
    OR v_provider_security
    OR to_regprocedure(format('%I.%I(text,text,text)',
        v_provider_schema,v_provider_name)) IS DISTINCT FROM v_binding.provider_fn
 THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_PROVIDER_SIGNATURE_DENIED'; END IF;

 IF v_check_status='DONE' THEN
   IF NOT EXISTS (
    SELECT 1 FROM programacion.engineering_work_checkpoints c
    WHERE c.id=v_check_id AND c.assertion_receipt->>'passed'='true'
      AND c.assertion_contract_sha256=c.assertion_receipt->>'contract_sha256'
      AND c.assertion_receipt_sha256=programacion.fn_v09_sha256_jsonb(c.assertion_receipt)
   ) THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_DONE_WITHOUT_VALID_RECEIPT'; END IF;
   RETURN jsonb_build_object('status','NOOP_ALREADY_TERMINAL',
       'checkpoint_code',p_checkpoint_code);
 END IF;
 IF v_check_status NOT IN ('PENDING','IN_PROGRESS')
 THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_BAD_CHECKPOINT_STATE:%',v_check_status; END IF;

 v_boot:=programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code);
 v_ready:=programacion.fn_engineering_checkpoint_execution_readiness_v1(
    p_plan_code,p_unit_code,p_checkpoint_code);
 IF v_boot->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
    OR v_boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM p_checkpoint_code
    OR v_ready->>'status' IS DISTINCT FROM 'READY'
    OR v_ready->>'execution_ready' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_CHECKPOINT_NOT_READY'; END IF;
 v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    p_plan_code,p_unit_code,p_checkpoint_code);
 v_contract:=programacion.fn_engineering_action_spec_assertion_contract_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,v_spec);
 IF v_contract->>'status' IS DISTINCT FROM 'READY'
 THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_ASSERTION_CONTRACT_NOT_READY'; END IF;
 v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract);

 -- The pre-reserved S30 effect must match exactly this scope and contract.
 v_scope:=concat_ws('/',p_plan_code,p_unit_code,p_checkpoint_code);
 v_request_sha:=programacion.fn_v09_sha256_jsonb(jsonb_build_object(
   'operation_code',c_operation,'execution_id',p_execution_id,
   'plan_code',p_plan_code,'unit_code',p_unit_code,
   'checkpoint_code',p_checkpoint_code,'contract_sha256',v_contract_sha));
 SELECT * INTO v_effect FROM public.lf_operation_effect_guard g
 WHERE g.execution_id=p_execution_id AND g.effect_scope=v_scope FOR UPDATE;
 IF NOT FOUND OR v_effect.state IS DISTINCT FROM 'RESERVED'
    OR v_effect.effect_request_sha256 IS DISTINCT FROM v_request_sha
 THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_EFFECT_NOT_RESERVED'; END IF;

 -- Trusted server-side provider. There is no client-supplied PASS or SQL.
 EXECUTE format('SELECT %I.%I($1,$2,$3)',v_provider_schema,v_provider_name)
 INTO v_proof USING p_plan_code,p_unit_code,p_checkpoint_code;
 IF jsonb_typeof(v_proof) IS DISTINCT FROM 'object'
    OR v_proof->>'status' IS DISTINCT FROM 'PASS'
    OR jsonb_typeof(v_proof->'observed') IS DISTINCT FROM 'object'
    OR (jsonb_typeof(v_contract->'pass_when')='object'
       AND coalesce(v_proof->'observed' @> (v_contract->'pass_when'),false) IS NOT TRUE)
 THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_PROVIDER_PROOF_FAILED'; END IF;
 v_evidence_ref:=v_proof->>'evidence_ref';
 IF nullif(btrim(coalesce(v_evidence_ref,'')),'') IS NULL
 THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_EVIDENCE_REF_MISSING'; END IF;
 v_assertion:=programacion.fn_engineering_checkpoint_assertion_record_v1(
   p_plan_code,p_unit_code,p_checkpoint_code,v_proof,p_execution_id);
 v_receipt_sha:=v_assertion->>'assertion_receipt_sha256';
 IF v_assertion->>'passed' IS DISTINCT FROM 'true'
    OR v_assertion->>'contract_sha256' IS DISTINCT FROM v_contract_sha
    OR coalesce(v_receipt_sha,'') !~ '^[a-f0-9]{64}
 THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_ASSERTION_RECEIPT_INVALID'; END IF;

 v_transition:=programacion.fn_engineering_checkpoint_transition_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,'DONE',v_evidence_ref,
    p_execution_id,'Goberned provider-backed checkpoint closure');
 IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
 THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_TRANSITION_NOT_APPLIED'; END IF;

 IF NOT EXISTS (
  SELECT 1 FROM programacion.engineering_work_checkpoints c
  WHERE c.id=v_check_id AND c.status='DONE'
    AND c.assertion_contract_sha256=v_contract_sha
    AND c.assertion_receipt_sha256=v_receipt_sha
    AND c.assertion_receipt_sha256=programacion.fn_v09_sha256_jsonb(c.assertion_receipt)
 ) THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_READBACK_MISMATCH'; END IF;

 v_receipt:=jsonb_build_object('schema_version','ENGINEERING_CHECKPOINT_CLOSE_V1',
   'status','DONE','plan_code',p_plan_code,'unit_code',p_unit_code,
   'checkpoint_code',p_checkpoint_code,'execution_id',p_execution_id,
   'contract_sha256',v_contract_sha,'assertion_receipt_sha256',v_receipt_sha,
   'provider_ref',v_binding.provider_fn::text,'evidence_ref',v_evidence_ref);
 UPDATE public.lf_operation_effect_guard
 SET state='SUCCEEDED',resolved_at=clock_timestamp(),receipt=v_receipt,
     updated_by_execution_id=p_execution_id
 WHERE execution_id=p_execution_id AND effect_scope=v_scope AND state='RESERVED';
 IF NOT FOUND THEN RAISE EXCEPTION 'ENGINEERING_CLOSE_EFFECT_NOT_COMMITTED'; END IF;
 RETURN v_receipt;
END $close$;

-- NO EXECUTE grant here. Admission/activation must explicitly approve grant.
REVOKE ALL ON FUNCTION programacion.fn_engineering_checkpoint_close_governed_v1(
 text,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
