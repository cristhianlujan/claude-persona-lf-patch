-- LF Input Governance ACT-0001 follow-up — ONE MIGRATION ONLY.
-- Based on PR #3803 HEAD c3435fcb24af6de64721ca5cb043b011a9dba029.
-- Scope readback/verifier for the already-existing receipt issuer.
-- Does NOT rewrite Router, create RUNs, grant effect authority or touch rules.
-- Fail closed if caller asserts that scoped routing is permission to write.
BEGIN;

DO $preflight$
BEGIN
 IF to_regclass('public.lf_router_scope_receipt_v1') IS NULL
    OR to_regclass('public.lf_router_scope_policy_v1') IS NULL
    OR to_regprocedure('public.lf_router_scope_bind_v1(text)') IS NULL
    OR to_regprocedure('public.lf_ig_asset_owner_apply_v2(uuid)') IS NULL
    OR md5(pg_get_functiondef('public.lf_router_scope_bind_v1(text)'::regprocedure))
       IS DISTINCT FROM '41d48c7b836188547dc3fee85f4444f9'
    OR md5(pg_get_functiondef('public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure))
       IS DISTINCT FROM 'db59290a1c4ca6d87661a6ec5038d3f6'
    OR to_regprocedure('public.lf_router_scope_receipt_consume_v2(text,text)') IS NOT NULL
 THEN RAISE EXCEPTION 'LF_ACT0001_V2_PREIMAGE_MISSING_OR_ALREADY_APPLIED'; END IF;
END $preflight$;

CREATE FUNCTION public.lf_router_scope_receipt_consume_v2(
 p_execution_id text,
 p_requested_business_column text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER VOLATILE
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE
 e public.lf_operation_execution%ROWTYPE;
 r public.lf_router_scope_receipt_v1%ROWTYPE;
 p public.lf_router_scope_policy_v1%ROWTYPE;
 current_columns jsonb;
 current_negative jsonb;
 manifest_sha text;
 receipt_sha text;
 policy_sha text;
BEGIN
 -- Only the governed owner_name writer is in scope. The caller cannot turn
 -- this into open-ended UPDATE permission through a column parameter.
 IF p_requested_business_column IS DISTINCT FROM 'owner_name'
 THEN RAISE EXCEPTION 'LF_SCOPE_V2_BUSINESS_COLUMN_FORBIDDEN'; END IF;
 SELECT * INTO e FROM public.lf_operation_execution
 WHERE execution_id=p_execution_id AND operation_code='ACTUALIZACION_DB_LF'
   AND target_type='MIGRATION' AND status='IN_PROGRESS'
   AND target_repo='cristhianlujan/claude-persona-lf-patch'
   AND target_path='supabase/migrations/'||target_code||'.sql';
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_SCOPE_V2_TRAIN_NOT_CURRENT'; END IF;
 SELECT * INTO r FROM public.lf_router_scope_receipt_v1
 WHERE execution_id=p_execution_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_SCOPE_V2_RECEIPT_MISSING'; END IF;
 SELECT * INTO p FROM public.lf_router_scope_policy_v1
 WHERE scope_code=r.scope_code;
 IF NOT FOUND OR p.scope_code<>'LF_ACTIVOS_OWNER_NAME_WRITE_V1'
    OR p.allowed_table<>'public.lf_activos'
    OR p.operation_code<>'ACTUALIZACION_DB_LF'
    OR p.effect_entrypoint<>'public.lf_ig_asset_owner_apply_v2(uuid)'
    OR p.allowed_columns IS DISTINCT FROM
       '["owner_name","updated_at","updated_by_execution_id"]'::jsonb
 THEN RAISE EXCEPTION 'LF_SCOPE_V2_POLICY_DRIFT'; END IF;
 SELECT jsonb_agg(column_name ORDER BY column_name),
        jsonb_agg(column_name ORDER BY column_name)
          FILTER(WHERE column_name NOT IN
            ('owner_name','updated_at','updated_by_execution_id'))
 INTO current_columns,current_negative
 FROM information_schema.columns
 WHERE table_schema='public' AND table_name='lf_activos';
 IF current_columns IS NULL OR current_negative IS DISTINCT FROM p.forbidden_columns
    OR encode(extensions.digest(convert_to(current_columns::text,'UTF8'),'sha256'),'hex')
       IS DISTINCT FROM p.schema_columns_sha256
    OR md5(pg_get_functiondef('public.lf_ig_asset_owner_apply_v2(uuid)'::regprocedure))
       IS DISTINCT FROM p.writer_source_md5
 THEN RAISE EXCEPTION 'LF_SCOPE_V2_SCHEMA_OR_WRITER_DRIFT'; END IF;
 policy_sha:=encode(extensions.digest(convert_to(
   jsonb_build_object(
     'scope_code',p.scope_code,'operation_code',p.operation_code,
     'entrypoint',p.effect_entrypoint,'allowed_table',p.allowed_table,
     'allowed_columns',p.allowed_columns,
     'forbidden_columns',p.forbidden_columns,
     'schema_columns_sha256',p.schema_columns_sha256,
     'writer_source_md5',p.writer_source_md5)::text,
   'UTF8'),'sha256'),'hex');
 IF policy_sha IS DISTINCT FROM p.policy_sha256
 THEN RAISE EXCEPTION 'LF_SCOPE_V2_POLICY_SHA_DRIFT'; END IF;
 manifest_sha:=encode(extensions.digest(convert_to(e.manifest::text,'UTF8'),'sha256'),'hex');
 receipt_sha:=encode(extensions.digest(convert_to(r.receipt::text,'UTF8'),'sha256'),'hex');
 IF r.manifest_sha256 IS DISTINCT FROM manifest_sha
    OR r.receipt_sha256 IS DISTINCT FROM receipt_sha
    OR r.receipt->>'schema_version'
        IS DISTINCT FROM 'LF_ROUTER_POSITIVE_NEGATIVE_SCOPE_RECEIPT_V1'
    OR r.receipt->>'router' IS DISTINCT FROM 'ACT-0001'
    OR r.receipt->>'execution_id' IS DISTINCT FROM p_execution_id
    OR r.receipt->>'operation_code' IS DISTINCT FROM e.operation_code
    OR r.receipt->>'target_path' IS DISTINCT FROM e.target_path
    OR r.receipt->>'request_sha256' IS DISTINCT FROM e.request_sha256
    OR r.receipt->>'policy_sha256' IS DISTINCT FROM p.policy_sha256
    OR r.receipt->>'manifest_sha256' IS DISTINCT FROM manifest_sha
    OR r.receipt->>'scope_code' IS DISTINCT FROM p.scope_code
    OR r.receipt->>'scope_semantics_attested' IS DISTINCT FROM 'true'
    OR r.receipt->>'effect_authority' IS DISTINCT FROM 'false'
    OR r.receipt->>'downstream_execution_allowed' IS DISTINCT FROM 'false'
    OR r.receipt->'positive_scope' IS DISTINCT FROM
      jsonb_build_array(jsonb_build_object(
        'table','public.lf_activos',
        'columns',p.allowed_columns,
        'business_field','owner_name',
        'audit_columns',jsonb_build_array('updated_at','updated_by_execution_id'),
        'entrypoint',p.effect_entrypoint))
    OR r.receipt->'negative_scope' IS DISTINCT FROM
      jsonb_build_object(
        'table','public.lf_activos',
        'forbidden_columns',p.forbidden_columns,
        'other_business_tables','DENY',
        'allowed_auxiliary_receipt_tables',jsonb_build_array(
          'public.lf_ig_asset_owner_receipt_v2',
          'public.lf_router_scope_receipt_v1'),
        'other_operations','DENY','project_SALY','DENY',
        'historical_runs','DENY','production_promotion','DENY')
 THEN RAISE EXCEPTION 'LF_SCOPE_V2_RECEIPT_TAMPERED_OR_STALE'; END IF;
 RETURN jsonb_build_object(
    'status','SCOPE_RECEIPT_VERIFIED_ROUTE_ONLY',
    'router','ACT-0001','execution_id',p_execution_id,
    'receipt_sha256',receipt_sha,'policy_sha256',policy_sha,
    'allowed_business_column','owner_name',
    'scope_attested',true,
    'effect_authority',false,
    'downstream_execution_allowed',false);
END $fn$;

REVOKE ALL ON FUNCTION public.lf_router_scope_receipt_consume_v2(text,text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.lf_router_scope_receipt_consume_v2(text,text)
 TO service_role;
DO $readback$
BEGIN
 IF to_regprocedure('public.lf_router_scope_receipt_consume_v2(text,text)') IS NULL
    OR has_function_privilege('anon',
       'public.lf_router_scope_receipt_consume_v2(text,text)','EXECUTE')
    OR has_function_privilege('authenticated',
       'public.lf_router_scope_receipt_consume_v2(text,text)','EXECUTE')
    OR NOT has_function_privilege('service_role',
       'public.lf_router_scope_receipt_consume_v2(text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'LF_ACT0001_V2_POSTSTATE_OR_ACL_FAILED'; END IF;
END $readback$;
-- Exact-source guarded modification of the canonical ACT-0001 scoped issuer.
DO $source_preimage$
BEGIN
 IF md5(pg_get_functiondef('public.lf_router_scope_bind_v1(text)'::regprocedure))
    IS DISTINCT FROM '41d48c7b836188547dc3fee85f4444f9'
 THEN RAISE EXCEPTION 'LF_ACT0001_SCOPE_ISSUER_PREIMAGE_DRIFT'; END IF;
END $source_preimage$;

CREATE OR REPLACE FUNCTION public.lf_router_scope_bind_v1(p_execution_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE e public.lf_operation_execution%ROWTYPE;
 policy public.lf_router_scope_policy_v1%ROWTYPE;
 stored public.lf_router_scope_receipt_v1%ROWTYPE;
 cols jsonb; negative jsonb; current_sha text; manifest_sha text; body jsonb;
 body_sha text; origin jsonb; consumer_readback jsonb;
BEGIN
 SELECT * INTO e FROM public.lf_operation_execution
 WHERE execution_id=p_execution_id AND operation_code='ACTUALIZACION_DB_LF'
   AND target_type='MIGRATION'
   AND target_repo='cristhianlujan/claude-persona-lf-patch'
   AND target_path='supabase/migrations/'||target_code||'.sql'
   AND status='IN_PROGRESS'
 FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_SCOPE_TRAIN_EXECUTION_NOT_BOUND'; END IF;
 origin:=e.manifest->'router_authority_receipt';
 IF coalesce(e.request_sha256,'') !~ '^[0-9a-f]{64}$'
    OR coalesce(e.manifest->>'head_sha','') !~ '^[0-9a-f]{40}$'
    OR coalesce(e.manifest->>'train_run_id','') !~ '^[0-9]{8,20}$'
    OR coalesce(e.manifest->>'pr','') !~ '^[0-9]{1,10}$'
    OR e.manifest->>'producer'<>'lf-migration-merge-train'
    OR origin->>'schema_version'<>'LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1'
    OR origin->>'router'<>'ACT-0001'
    OR origin->>'operation_code'<>'ACTUALIZACION_DB_LF'
    OR origin->>'action_code'<>'UPDATE'
    OR origin->>'target_repo' IS DISTINCT FROM e.target_repo
    OR origin->>'target_path' IS DISTINCT FROM e.target_path
    OR origin->>'target_code' IS DISTINCT FROM e.target_code
    OR origin->>'scope_attested'<>'false'
    OR origin->>'route_eligibility_only'<>'true'
 THEN RAISE EXCEPTION 'LF_SCOPE_ROUTER_ORIGIN_NOT_GOVERNED'; END IF;
 SELECT * INTO policy FROM public.lf_router_scope_policy_v1
 WHERE scope_code='LF_ACTIVOS_OWNER_NAME_WRITE_V1';
 IF NOT FOUND OR policy.operation_code<>'ACTUALIZACION_DB_LF'
    OR policy.effect_entrypoint<>'public.lf_ig_asset_owner_apply_v2(uuid)'
    OR policy.allowed_table<>'public.lf_activos'
    OR policy.allowed_columns IS DISTINCT FROM '["owner_name","updated_at","updated_by_execution_id"]'::jsonb
 THEN RAISE EXCEPTION 'LF_SCOPE_POLICY_NOT_CURRENT'; END IF;
 SELECT jsonb_agg(column_name ORDER BY column_name),
        jsonb_agg(column_name ORDER BY column_name)
          FILTER(WHERE column_name NOT IN ('owner_name','updated_at','updated_by_execution_id'))
 INTO cols,negative FROM information_schema.columns
 WHERE table_schema='public' AND table_name='lf_activos';
 IF cols IS NULL OR negative IS DISTINCT FROM policy.forbidden_columns
    OR encode(extensions.digest(convert_to(cols::text,'UTF8'),'sha256'),'hex')
       IS DISTINCT FROM policy.schema_columns_sha256
    OR md5(pg_get_functiondef('public.lf_ig_asset_owner_apply_v2(uuid)'::regprocedure))
       IS DISTINCT FROM policy.writer_source_md5
 THEN RAISE EXCEPTION 'LF_SCOPE_SCHEMA_OR_WRITER_DRIFT'; END IF;
 current_sha:=encode(extensions.digest(convert_to(
   jsonb_build_object('scope_code',policy.scope_code,'operation_code',policy.operation_code,
     'entrypoint',policy.effect_entrypoint,'allowed_table',policy.allowed_table,
     'allowed_columns',policy.allowed_columns,'forbidden_columns',negative,
     'schema_columns_sha256',policy.schema_columns_sha256,
     'writer_source_md5',policy.writer_source_md5)::text,'UTF8'),'sha256'),'hex');
 IF current_sha IS DISTINCT FROM policy.policy_sha256
 THEN RAISE EXCEPTION 'LF_SCOPE_POLICY_SHA_MISMATCH'; END IF;
 manifest_sha:=encode(extensions.digest(convert_to(e.manifest::text,'UTF8'),'sha256'),'hex');
 body:=jsonb_build_object('schema_version','LF_ROUTER_POSITIVE_NEGATIVE_SCOPE_RECEIPT_V1',
   'router','ACT-0001','status','SCOPE_ATTESTED_ROUTE_ONLY',
   'execution_id',e.execution_id,'request_sha256',e.request_sha256,
   'operation_code',e.operation_code,'target_code',e.target_code,
   'target_path',e.target_path,'manifest_sha256',manifest_sha,
   'scope_source','SERVER_CANONICAL_CATALOG_AND_PINNED_OWNER_WRITER',
   'scope_code',policy.scope_code,'policy_sha256',policy.policy_sha256,
   'positive_scope',jsonb_build_array(jsonb_build_object('table','public.lf_activos',
      'columns',jsonb_build_array('owner_name','updated_at','updated_by_execution_id'),
      'business_field','owner_name',
      'audit_columns',jsonb_build_array('updated_at','updated_by_execution_id'),
      'entrypoint',policy.effect_entrypoint)),
   'negative_scope',jsonb_build_object('table','public.lf_activos',
      'forbidden_columns',negative,'other_business_tables','DENY',
      'allowed_auxiliary_receipt_tables',jsonb_build_array(
        'public.lf_ig_asset_owner_receipt_v2','public.lf_router_scope_receipt_v1'),
      'other_operations','DENY','project_SALY','DENY',
      'historical_runs','DENY','production_promotion','DENY'),
   'scope_semantics_attested',true,'effect_authority',false,
   'downstream_execution_allowed',false,
   'identity_verified',false);
 body_sha:=encode(extensions.digest(convert_to(body::text,'UTF8'),'sha256'),'hex');
 SELECT * INTO stored FROM public.lf_router_scope_receipt_v1
 WHERE execution_id=p_execution_id FOR UPDATE;
 IF FOUND THEN
   IF stored.manifest_sha256 IS DISTINCT FROM manifest_sha
      OR stored.receipt_sha256 IS DISTINCT FROM body_sha
      OR stored.receipt IS DISTINCT FROM body
   THEN RAISE EXCEPTION 'LF_SCOPE_STORED_RECEIPT_DRIFT'; END IF;
 ELSE
   INSERT INTO public.lf_router_scope_receipt_v1(
     execution_id,scope_code,manifest_sha256,receipt,receipt_sha256)
   VALUES(p_execution_id,policy.scope_code,manifest_sha,body,body_sha);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_router_scope_receipt_v1
     WHERE execution_id=p_execution_id AND receipt=body AND receipt_sha256=body_sha)
 THEN RAISE EXCEPTION 'LF_SCOPE_RECEIPT_READBACK_FAILED'; END IF;
 -- Canonical ACT-0001 scope issuer validates the persisted positive/negative
 -- receipt before the official owner approval/apply consumers may advance.
 consumer_readback:=public.lf_router_scope_receipt_consume_v2(p_execution_id,'owner_name');
 IF consumer_readback->>'status' IS DISTINCT FROM 'SCOPE_RECEIPT_VERIFIED_ROUTE_ONLY'
    OR consumer_readback->>'receipt_sha256' IS DISTINCT FROM body_sha
    OR consumer_readback->>'policy_sha256' IS DISTINCT FROM policy.policy_sha256
    OR consumer_readback->>'effect_authority' IS DISTINCT FROM 'false'
    OR consumer_readback->>'downstream_execution_allowed' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'LF_ACT0001_SCOPE_VERIFIED_CONSUMER_REQUIRED'; END IF;
 RETURN body||jsonb_build_object('receipt_sha256',body_sha);
END $function$;


DO $issuer_readback$
BEGIN
 IF md5(pg_get_functiondef('public.lf_router_scope_bind_v1(text)'::regprocedure))
      = '41d48c7b836188547dc3fee85f4444f9'
 OR position('lf_router_scope_receipt_consume_v2' in
    pg_get_functiondef('public.lf_router_scope_bind_v1(text)'::regprocedure))=0
 THEN RAISE EXCEPTION 'LF_ACT0001_ISSUER_VERIFIER_NOT_HOOKED'; END IF;
END $issuer_readback$;

-- The canonical Step70 bridge (not a new recorder) enforces missing provider
-- provenance only on effects-bearing Product Director runs.
DO $step70_preimage$
BEGIN
 IF md5(pg_get_functiondef('public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure))
    IS DISTINCT FROM 'db59290a1c4ca6d87661a6ec5038d3f6'
 THEN RAISE EXCEPTION 'LF_STEP70_PROVIDER_BRIDGE_PREIMAGE_DRIFT'; END IF;
END $step70_preimage$;
CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_record_semantic_v1(p_execution_id text, p_semantic_judge_result jsonb, p_evidence_ref text, p_actor_execution_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_actor text;
  v_existing text;
  v_step jsonb;
  v_clean integer;
  v_verified_native jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR jsonb_typeof(p_semantic_judge_result)<>'object'
     OR nullif(btrim(coalesce(p_evidence_ref,'')),'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_INPUT_INVALID'
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.status<>'IN_PROGRESS'
     OR NOT COALESCE(
       (e.manifest->>'executor_mode'='GPT_NATIVE'
        AND e.manifest->>'executor_provider'='OPENAI_CHATGPT_NATIVE')
       OR
       (e.manifest->>'executor_mode'='CLAUDE_NATIVE'
        AND e.manifest->>'executor_provider'='ANTHROPIC_CLAUDE_NATIVE'),
       false
     )
     OR e.manifest ? 'queue_request_id'
     OR nullif(e.manifest->>'runtime_target','') IS NOT NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_EXECUTION_INVALID'
    );
  END IF;

  -- Effects-bearing LF Product Director Step70 requires a genuinely
  -- verified independent native provider receipt. Read-only profiles retain
  -- their pre-existing current-context path. No HMAC / asserted-JSON bypass.
  IF e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
    AND NOT (
      coalesce((e.manifest->>'read_only')::boolean,false) IS TRUE
      AND coalesce((e.manifest->>'no_write')::boolean,false) IS TRUE
      AND coalesce((e.manifest->>'no_promotion')::boolean,false) IS TRUE
    )
  THEN
    IF p_semantic_judge_result->>'review_mode'
       IN ('CURRENT_CONTEXT_REVIEW','HMAC_TEST','MOCK')
    THEN RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','LF_STEP70_NATIVE_SELF_REVIEW_FORBIDDEN'); END IF;
    IF to_regprocedure('public.lf_ig_verified_native_provider_receipt_v1(text)') IS NULL
    THEN RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','LF_STEP70_NATIVE_PROVIDER_VERIFIER_MISSING'); END IF;
    EXECUTE 'SELECT public.lf_ig_verified_native_provider_receipt_v1($1)'
      INTO v_verified_native USING p_execution_id;
    IF jsonb_typeof(v_verified_native)<>'object'
      OR v_verified_native->>'status' IS DISTINCT FROM 'CRYPTOGRAPHICALLY_VERIFIED'
      OR v_verified_native->>'execution_id' IS DISTINCT FROM p_execution_id
      OR v_verified_native->>'provider_receipt_ref'
           IS DISTINCT FROM p_semantic_judge_result->>'provider_receipt_ref'
      OR v_verified_native->>'candidate_sha256'
           IS DISTINCT FROM p_semantic_judge_result->>'candidate_sha256'
      OR v_verified_native->>'scope_packet_sha256'
           IS DISTINCT FROM p_semantic_judge_result->>'scope_packet_sha256'
      OR coalesce(p_semantic_judge_result->>'provider_receipt_ref','')=''
      OR p_semantic_judge_result->>'producer_independence_proven'
           IS DISTINCT FROM 'true'
      OR p_semantic_judge_result->>'model_call_count'
           IS DISTINCT FROM '1'
    THEN RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','LF_STEP70_NATIVE_RECEIPT_NOT_VERIFIED'); END IF;
  END IF;

  IF p_semantic_judge_result->>'status' IS DISTINCT FROM 'PASS'
     OR p_semantic_judge_result->>'validator_status' IS DISTINCT FROM 'PASS'
     OR NOT (
       (
         p_semantic_judge_result->>'verdict'='PASS_INDEPENDENT_SEMANTIC'
         AND coalesce((p_semantic_judge_result->>'producer_independence_proven')::boolean,false) IS TRUE
         AND coalesce((p_semantic_judge_result->>'model_call_count')::integer,-1)=1
       ) OR (
         p_semantic_judge_result->>'verdict'='PASS_REVIEWED_CURRENT_CONTEXT'
         AND p_semantic_judge_result->>'review_mode'='CURRENT_CONTEXT_REVIEW'
         AND p_semantic_judge_result->>'reviewer_is_producer'='true'
         AND coalesce((p_semantic_judge_result->>'producer_independence_proven')::boolean,true) IS FALSE
         AND coalesce((p_semantic_judge_result->>'model_call_count')::integer,-1)=0
         AND coalesce((e.manifest->>'read_only')::boolean,false) IS TRUE
         AND coalesce((e.manifest->>'no_write')::boolean,false) IS TRUE
         AND coalesce((e.manifest->>'no_promotion')::boolean,false) IS TRUE
       )
     )
     OR jsonb_typeof(p_semantic_judge_result#>'{result,unsupported_claims}')<>'array'
     OR jsonb_array_length(p_semantic_judge_result#>'{result,unsupported_claims}')<>0
     OR jsonb_typeof(p_semantic_judge_result#>'{result,blocking_codes}')<>'array'
     OR jsonb_array_length(p_semantic_judge_result#>'{result,blocking_codes}')<>0 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_JUDGE_NOT_PASS'
    );
  END IF;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='semantic_judge';

  IF v_existing IS NULL OR v_existing IN ('BLOCKED_STEP_NOT_CLEAN', 'RETURN_TO_ROUTER') THEN
    -- Reuse the canonical recorder retry path, retaining attempt_history on the same RUN.
    v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);

    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'semantic_judge',
      p_evidence_ref,
      jsonb_build_object(
        'semantic_judge_result',p_semantic_judge_result,
        'unsupported_claims','[]'::jsonb,
        'semantic_review_receipt_ref',p_evidence_ref,
        'independent_semantic_receipt_ref',case
          when p_semantic_judge_result->>'review_mode'='CURRENT_CONTEXT_REVIEW' then null
          else p_evidence_ref end
      ),
      v_actor
    );

    IF coalesce(v_step->>'status',v_step->>'step_status')
       IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_RECORD_REJECTED',
        'recorder_result',v_step
      );
    END IF;

  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_EXISTING_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_clean<>10 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_POST_STEP_COUNT',
      'clean_step_count',v_clean,
      'expected_clean_step_count',10
    );
  END IF;

  RETURN jsonb_build_object(
    'status','SEMANTIC_JUDGE_RECORDED',
    'execution_id',p_execution_id,
    'profile_code',e.target_code,
    'clean_step_count',v_clean,
    'last_completed_step','semantic_judge',
    'next_step','report_output',
    'next_action','RECORD_EXISTING_REPORT_OUTPUT'
  );
END
$function$;

DO $step70_poststate$
BEGIN
 IF position('LF_STEP70_NATIVE_PROVIDER_VERIFIER_MISSING' in
   pg_get_functiondef('public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure))=0
 THEN RAISE EXCEPTION 'LF_STEP70_NATIVE_VERIFIER_GATE_NOT_INSTALLED'; END IF;
END $step70_poststate$;

COMMIT;
