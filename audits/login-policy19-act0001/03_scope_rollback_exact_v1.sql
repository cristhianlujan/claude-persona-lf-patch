-- Manual governed inverse for #3820; do not execute against live without Train/backup authorization.
-- Assert no issued policy19 receipts before removal. Preserve owner receipts and owner policy.
BEGIN;
DO $pre$
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_router_scope_receipt_v1 WHERE scope_code='LF_POLICY19_ADMIN12_OTP_BREVO_CHANGE_V1')
 THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_ROLLBACK_ACTIVE_RECEIPTS'; END IF;
 IF (SELECT count(*) FROM public.lf_router_scope_policy_v1 WHERE scope_code='LF_POLICY19_ADMIN12_OTP_BREVO_CHANGE_V1')<>1
 THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_ROLLBACK_MISSING'; END IF;
 IF position('lf_router_scope_policy19_bind_internal_v1' IN pg_get_functiondef('public.lf_router_scope_bind_v1(text)'::regprocedure))=0
 OR position('lf_router_scope_policy19_consume_internal_v1' IN pg_get_functiondef('public.lf_router_scope_receipt_consume_v2(text,text)'::regprocedure))=0
 THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_ROLLBACK_SOURCE_DRIFT'; END IF;
END $pre$;
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
END $function$
;
CREATE OR REPLACE FUNCTION public.lf_router_scope_receipt_consume_v2(p_execution_id text, p_requested_business_column text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
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
END $function$
;
DELETE FROM public.lf_router_scope_policy_v1 WHERE scope_code='LF_POLICY19_ADMIN12_OTP_BREVO_CHANGE_V1';
DROP FUNCTION public.lf_router_scope_policy19_bind_internal_v1(text);
DROP FUNCTION public.lf_router_scope_policy19_consume_internal_v1(text,text);
DROP FUNCTION public.lf_ig_policy19_apply_v1(text,text,jsonb);
DO $postrollback$
BEGIN
 IF md5(pg_get_functiondef('public.lf_router_scope_bind_v1(text)'::regprocedure))
 IS DISTINCT FROM 'c9fba71dba3f2d5f7f16a40f22d15d6d'
 OR md5(pg_get_functiondef('public.lf_router_scope_receipt_consume_v2(text,text)'::regprocedure))
 IS DISTINCT FROM '29cd88f920e2b9f6dbd7b5e11af3fdb5'
 OR (SELECT count(*) FROM public.lf_router_scope_policy_v1)<>1
 THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_ROLLBACK_READBACK_FAILED'; END IF;
END $postrollback$;
COMMIT;