-- Manual inverse for PR #3807 ONLY; not a Supabase forward migration.
-- Does not reverse the upstream #3803 scope issuer, owners or RUNs.
-- Run in isolated PG18/PG17.6 for verification; Merge Train approval
-- required before any real restoration.
BEGIN;
DO $preflight$
BEGIN
 IF to_regprocedure('public.lf_router_scope_receipt_consume_v2(text,text)') IS NULL
 OR to_regprocedure('public.lf_router_scope_bind_v1(text)') IS NULL
 OR to_regclass('public.lf_router_scope_receipt_v1') IS NULL
 OR to_regclass('public.lf_router_scope_policy_v1') IS NULL
 OR NOT has_function_privilege('service_role',
    'public.lf_router_scope_receipt_consume_v2(text,text)','EXECUTE')
 OR has_function_privilege('anon',
    'public.lf_router_scope_receipt_consume_v2(text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'LF_ACT0001_V2_ROLLBACK_PREIMAGE_DRIFT'; END IF;
END $preflight$;
-- Restore exact original scope issuer before dropping the new verifier.
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
 body_sha text; origin jsonb;
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
 RETURN body||jsonb_build_object('receipt_sha256',body_sha);
END $function$;
DO $restored_source$
BEGIN
 IF md5(pg_get_functiondef('public.lf_router_scope_bind_v1(text)'::regprocedure))
    IS DISTINCT FROM '41d48c7b836188547dc3fee85f4444f9'
 THEN RAISE EXCEPTION 'LF_ACT0001_ISSUER_ROLLBACK_PREIMAGE_DRIFT'; END IF;
END $restored_source$;

-- Restore Step70 exact preimage before removing the scope receipt consumer.
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
DO $step70_restored$
BEGIN
 IF md5(pg_get_functiondef('public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure))
    IS DISTINCT FROM 'db59290a1c4ca6d87661a6ec5038d3f6'
 THEN RAISE EXCEPTION 'LF_STEP70_PROVIDER_BRIDGE_ROLLBACK_SOURCE_DRIFT'; END IF;
END $step70_restored$;
DROP FUNCTION public.lf_router_scope_receipt_consume_v2(text,text) RESTRICT;
DO $readback$
BEGIN
 IF to_regprocedure('public.lf_router_scope_receipt_consume_v2(text,text)') IS NOT NULL
 OR to_regprocedure('public.lf_router_scope_bind_v1(text)') IS NULL
 OR to_regclass('public.lf_router_scope_receipt_v1') IS NULL
 THEN RAISE EXCEPTION 'LF_ACT0001_V2_ROLLBACK_READBACK_FAILED'; END IF;
END $readback$;
COMMIT;
