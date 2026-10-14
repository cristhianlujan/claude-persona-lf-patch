-- INITIAL CANDIDATE INSTALLATION, NOT AN OPERATION ACTIVATION.
-- Purpose: install a generic administrative checkpoint closure executor and
-- one pilot evidence provider, with no enabled Router/action/GRANT/write.
-- Source: PR #2657 merged main. Test in transaction BEFORE final COMMIT.
-- Uses LF Migration Merge Train; no modification to Train or DB_WRITE_TRANSPORT.
BEGIN;
DO $preflight$
DECLARE v record;
BEGIN
 IF to_regprocedure('programacion.fn_engineering_checkpoint_close_governed_v1(text,text,text,text)') IS NOT NULL
 OR to_regprocedure('programacion.fn_ig_m105_cp2_closure_proof_v1(text,text,text)') IS NOT NULL
 OR to_regclass('programacion.engineering_checkpoint_closure_providers_v1') IS NOT NULL
 THEN RAISE EXCEPTION 'CHECKPOINT_CLOSURE_ALREADY_INSTALLED_ABORT'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_operation_registry
      WHERE operation_code='CIERRE_CHECKPOINT_INGENIERIA_LF')
 THEN RAISE EXCEPTION 'CHECKPOINT_CLOSURE_OPERATION_ALREADY_REGISTERED_ABORT'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_router_action_registry
      WHERE asset_type='ENGINEERING_CHECKPOINT' AND action_code='CHECKPOINT_CLOSE')
 THEN RAISE EXCEPTION 'CHECKPOINT_CLOSURE_ROUTER_ALREADY_REGISTERED_ABORT'; END IF;
 SELECT * INTO STRICT v FROM programacion.v_ig_m105_cp2_sample_readback_v1;
 IF v.sample_run_id IS NULL OR v.sample_screen_id<>1
    OR v.sample_verdict<>'PASS_CP2_MUESTRA'
    OR v.valid_family_count<>5 OR v.sample_family_count<>5
    OR v.source_current IS DISTINCT FROM true
    OR v.stale_negative_verified IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'CHECKPOINT_CLOSURE_PILOT_PROOF_NOT_CURRENT'; END IF;
 IF NOT EXISTS (SELECT 1 FROM programacion.engineering_work_checkpoints c
     WHERE c.work_item_id=477 AND c.checkpoint_code='NEW_RUNS_VNEXT'
       AND c.status='PENDING' AND c.assertion_receipt_sha256 IS NULL)
 THEN RAISE EXCEPTION 'CHECKPOINT_CLOSURE_PILOT_STATE_NOT_PENDING'; END IF;
END $preflight$;

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


-- CANDIDATE only. Domain-specific evidence provider, not a generic engine change.
-- No DML outside the future, authorized installation. No new screen runs.

CREATE OR REPLACE FUNCTION programacion.fn_ig_m105_cp2_closure_proof_v1(
 p_plan_code text,p_unit_code text,p_checkpoint_code text
) RETURNS jsonb
LANGUAGE plpgsql STABLE
SET search_path=pg_catalog,programacion,public
AS $provider$
DECLARE
 v programacion.v_ig_m105_cp2_sample_readback_v1%rowtype;
 v_valid int;
 v_stale bigint;
 v_families text[];
BEGIN
 IF p_plan_code IS DISTINCT FROM 'IG_CURATOR_VALIDATOR_REFACTOR_V2'
    OR p_unit_code IS DISTINCT FROM 'M10.5'
    OR p_checkpoint_code IS DISTINCT FROM 'NEW_RUNS_VNEXT'
 THEN RAISE EXCEPTION 'M105_SAMPLE_PROVIDER_WRONG_TARGET'; END IF;
 SELECT * INTO STRICT v FROM programacion.v_ig_m105_cp2_sample_readback_v1;
 IF v.sample_screen_id IS DISTINCT FROM 1
   OR v.sample_run_id IS NULL
   OR v.run_status IS DISTINCT FROM 'COMPLETED'
   OR v.source_current IS DISTINCT FROM true
   OR v.sampled_screen_count IS DISTINCT FROM 1
   OR v.sample_family_count IS DISTINCT FROM 5
   OR v.valid_family_count IS DISTINCT FROM 5
   OR v.sample_verdict IS DISTINCT FROM 'PASS_CP2_MUESTRA'
   OR v.stale_negative_verified IS DISTINCT FROM true
   OR v.authorizes_production IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'M105_SAMPLE_PROVIDER_NO_REAL_PASS'; END IF;

 SELECT array_agg(f.family ORDER BY f.family) INTO v_families
 FROM jsonb_to_recordset(v.sample_families) AS f(
  family text,valid_evidence boolean);
 IF v_families IS DISTINCT FROM ARRAY[
  'ACCESSIBILITY','API_DATA_CONTRACT','FRESHNESS_INVALIDATION','SECURITY','STATES'
 ]::text[] THEN RAISE EXCEPTION 'M105_SAMPLE_PROVIDER_STRATA_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_to_recordset(v.sample_families)
   AS f(family text,valid_evidence boolean)
   WHERE f.valid_evidence IS DISTINCT FROM true)
 THEN RAISE EXCEPTION 'M105_SAMPLE_PROVIDER_INVALID_EVIDENCE_FLAG'; END IF;

 SELECT count(*) INTO v_valid FROM programacion.input_family_assessments a
 WHERE a.run_id=v.sample_run_id
 AND a.family_code IN ('ACCESSIBILITY','API_DATA_CONTRACT',
       'FRESHNESS_INVALIDATION','SECURITY','STATES')
 AND a.validator_outcome IN ('PASS','FAIL','BLOCKED')
 AND a.validator_identity IS NOT NULL
 AND a.validator_sha256 ~ '^[0-9a-f]{64}$'
 AND a.validator_assessed_at IS NOT NULL
 AND jsonb_typeof(a.validator_findings)='array';
 IF v_valid<>5 THEN RAISE EXCEPTION 'M105_SAMPLE_PROVIDER_INDEPENDENT_EVIDENCE_MISSING'; END IF;
 SELECT r.id INTO v_stale FROM programacion.input_readiness_runs r
 WHERE r.pantalla_id=1 AND r.status='COMPLETED' AND r.id<v.sample_run_id
 AND NOT programacion.fn_input_run_is_source_current(r.id)
 ORDER BY r.id DESC LIMIT 1;
 IF v_stale IS NULL OR NOT programacion.fn_input_run_is_source_current(v.sample_run_id)
 THEN RAISE EXCEPTION 'M105_SAMPLE_PROVIDER_CURRENT_OR_STALE_NEGATIVE_FAILED'; END IF;

 RETURN jsonb_build_object(
  'status','PASS',
  'evidence_ref','supabase://programacion.v_ig_m105_cp2_sample_readback_v1'
    ||'#screen=1&run='||v.sample_run_id||'&stale_negative='||v_stale,
  'observed',jsonb_build_object(
   'sampled_screen_count',1,'sample_family_count',5,'valid_family_count',v_valid,
   'sample_verdict',v.sample_verdict,'source_current',v.source_current,
   'stale_negative_verified',v.stale_negative_verified,
   'authorizes_production',false,
   'sample_run_id',v.sample_run_id,
   'semantic_observation_count',v.semantic_observation_count)
 );
END $provider$;

-- Candidate-only registry entry; NOT ACTIVE. Only owner can activate after
-- Router/operation/guard, grant and exact-identity checks are admitted.
INSERT INTO programacion.engineering_checkpoint_closure_providers_v1
(plan_code,unit_code,checkpoint_code,provider_fn,binding_state,contract_ref)
VALUES(
 'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.5','NEW_RUNS_VNEXT',
 'programacion.fn_ig_m105_cp2_closure_proof_v1(text,text,text)'::regprocedure,
 'CANDIDATE','M105_CP2_REPRESENTATIVE_SAMPLE_V1')
ON CONFLICT(plan_code,unit_code,checkpoint_code) DO NOTHING;

REVOKE ALL ON FUNCTION programacion.fn_ig_m105_cp2_closure_proof_v1(
 text,text,text) FROM PUBLIC,anon,authenticated;


-- Test the real provider (server-owned, no user-authored PASS accepted).
DO $trial_positive$
DECLARE p jsonb; v jsonb;
BEGIN
 SELECT programacion.fn_ig_m105_cp2_closure_proof_v1(
  'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.5','NEW_RUNS_VNEXT') INTO p;
 IF p->>'status' IS DISTINCT FROM 'PASS'
 OR p->'observed' IS NULL
 OR p#>>'{observed,sample_verdict}' IS DISTINCT FROM 'PASS_CP2_MUESTRA'
 OR p#>>'{observed,source_current}' IS DISTINCT FROM 'true'
 OR p#>>'{observed,valid_family_count}' IS DISTINCT FROM '5'
 OR p#>>'{observed,authorizes_production}' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'CP_CLOSURE_PILOT_PROVIDER_TEST_FAILED:%',p; END IF;
 -- Deliberate invalid target MUST fail, with no state changes.
 BEGIN
  PERFORM programacion.fn_ig_m105_cp2_closure_proof_v1(
   'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.5','SUITE_M7_GREEN');
  RAISE EXCEPTION 'CP_CLOSURE_WRONG_TARGET_TEST_WAS_ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM IS DISTINCT FROM 'M105_SAMPLE_PROVIDER_WRONG_TARGET'
  THEN RAISE EXCEPTION 'CP_CLOSURE_WRONG_TARGET_UNEXPECTED:%',SQLERRM; END IF;
 END;
 RAISE NOTICE 'CP_CLOSURE_PROVIDER_TRIAL: POSITIVE_AND_WRONG_TARGET_NEGATIVE_PASSED';
END $trial_positive$;

-- A real SAVEPOINT/ROLLBACK-to-savepoint validates that even a simulated
-- temporary ACTIVE provider binding leaves NO authorized state afterward.
SAVEPOINT cp_closure_cumulative_negative;
UPDATE programacion.engineering_checkpoint_closure_providers_v1
 SET binding_state='ACTIVE'
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
   AND unit_code='M10.5' AND checkpoint_code='NEW_RUNS_VNEXT';
ROLLBACK TO SAVEPOINT cp_closure_cumulative_negative;
RELEASE SAVEPOINT cp_closure_cumulative_negative;

DO $trial_negative$
DECLARE v_state text; v_message text; v_role text;
BEGIN
 SELECT binding_state INTO v_state
 FROM programacion.engineering_checkpoint_closure_providers_v1
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
   AND unit_code='M10.5' AND checkpoint_code='NEW_RUNS_VNEXT';
 IF v_state IS DISTINCT FROM 'CANDIDATE'
 THEN RAISE EXCEPTION 'CP_CLOSURE_ROLLBACK_BINDING_NOT_RESTORED:%',v_state; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_router_action_registry
   WHERE asset_type='ENGINEERING_CHECKPOINT' AND action_code='CHECKPOINT_CLOSE'
   AND status='ACTIVE' AND write_allowed)
 THEN RAISE EXCEPTION 'CP_CLOSURE_ACTIVE_ROUTER_ROUTE_CREATED'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_operation_registry
   WHERE operation_code='CIERRE_CHECKPOINT_INGENIERIA_LF')
 THEN RAISE EXCEPTION 'CP_CLOSURE_OPERATION_REGISTERED_WITHOUT_PROVENANCE'; END IF;

 -- Runtime caller is absent and/or unauthorised; never touch checkpoint.
 BEGIN
  PERFORM programacion.fn_engineering_checkpoint_close_governed_v1(
   'EXEC-NONEXISTENT-NEGATIVE','IG_CURATOR_VALIDATOR_REFACTOR_V2',
   'M10.5','NEW_RUNS_VNEXT');
  RAISE EXCEPTION 'CP_CLOSURE_UNAUTHORIZED_CALL_WAS_ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  v_message:=SQLERRM;
  IF v_message NOT IN ('ENGINEERING_CLOSE_AUTHORITY_REQUIRED',
                       'ENGINEERING_CLOSE_EXECUTION_NOT_BOUND')
  THEN RAISE EXCEPTION 'CP_CLOSURE_UNEXPECTED_CALL_ERROR:%',v_message; END IF;
 END;
 IF NOT EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints c
    WHERE c.work_item_id=477 AND c.checkpoint_code='NEW_RUNS_VNEXT'
      AND c.status='PENDING' AND c.assertion_receipt_sha256 IS NULL)
 THEN RAISE EXCEPTION 'CP_CLOSURE_UNAUTHORIZED_WRITE_OCCURRED'; END IF;
 -- Ensure function cannot be invoked through PUBLIC/anon/authenticated/service_role.
 IF has_function_privilege('anon',
   'programacion.fn_engineering_checkpoint_close_governed_v1(text,text,text,text)',
   'EXECUTE')
 OR has_function_privilege('authenticated',
   'programacion.fn_engineering_checkpoint_close_governed_v1(text,text,text,text)',
   'EXECUTE')
 OR has_function_privilege('service_role',
   'programacion.fn_engineering_checkpoint_close_governed_v1(text,text,text,text)',
   'EXECUTE')
 THEN RAISE EXCEPTION 'CP_CLOSURE_PREMATURE_EXECUTE_GRANT'; END IF;
 RAISE NOTICE 'CP_CLOSURE_NEGATIVE_TRIAL: ROLLBACK_VERIFIED; UNAUTHORIZED_DENIED';
END $trial_negative$;

-- Canonical EKB finding: original candidate registry requires real provenance.
INSERT INTO transversal.error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,
 severidad,estado,lote_origen,source_context,source_ref)
SELECT
 'ENGINEERING-CHECKPOINT-CLOSURE-PROVENANCE-PREWRITE-002','ENGINEERING_GOVERNANCE',
 'Operación de cierre requiere ejecución de procedencia antes de registrar alta',
 'Alta de operación candidata sin ejecución autorizada sería rechazada por guard transversal.',
 'Script inicial usaba execution_id sintético no persistido; provenance guard impide bypass.',
 'Instalar código como candidato sin activar ni insertar operación hasta disponer de procedencia real y Router autorizado; nunca inventar execution_id ni desactivar el guard.',
 'Readback de operación ausente, binding CANDIDATE, función sin EXECUTE y checkpoint todavía PENDING.',
 'ALTA','ACTIVO','M10.5/CP2','IG_CURATOR_VALIDATOR_REFACTOR_V2',
 'github://cristhianlujan/claude-persona-lf-patch/pull/2657'
WHERE NOT EXISTS(SELECT 1 FROM transversal.error_knowledge
 WHERE codigo='ENGINEERING-CHECKPOINT-CLOSURE-PROVENANCE-PREWRITE-002');

COMMIT;
