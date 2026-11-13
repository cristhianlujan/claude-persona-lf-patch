-- ACT-0001 scope extension for policy19. One migration; no modification to policy19 data.
-- Source consumer + issuer pinned by real Supabase pg_get_functiondef md5.
-- Train must supply authenticated operation manifest, not a fabricated receipt.
BEGIN;
DO $before$
BEGIN
 IF md5(pg_get_functiondef('public.lf_router_scope_bind_v1(text)'::regprocedure)) IS DISTINCT FROM 'c9fba71dba3f2d5f7f16a40f22d15d6d'
 OR md5(pg_get_functiondef('public.lf_router_scope_receipt_consume_v2(text,text)'::regprocedure)) IS DISTINCT FROM '29cd88f920e2b9f6dbd7b5e11af3fdb5'
 THEN RAISE EXCEPTION 'LF_POLICY19_ACT0001_ROUTER_PREIMAGE_DRIFT'; END IF;
 IF to_regclass('lf_ops.politicas_seguridad') IS NULL
 OR to_regclass('public.lf_router_scope_policy_v1') IS NULL
 OR to_regclass('public.lf_router_scope_receipt_v1') IS NULL
 THEN RAISE EXCEPTION 'LF_POLICY19_ACT0001_SCHEMA_MISSING'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_router_scope_policy_v1 WHERE scope_code='LF_POLICY19_ADMIN12_OTP_BREVO_CHANGE_V1')
 OR to_regprocedure('public.lf_ig_policy19_apply_v1(text,text,jsonb)') IS NOT NULL
 THEN RAISE EXCEPTION 'LF_POLICY19_ACT0001_ALREADY_INSTALLED'; END IF;
 IF (SELECT count(*) FROM public.lf_router_scope_policy_v1) <> 1
 OR (SELECT policy_sha256 FROM public.lf_router_scope_policy_v1 WHERE scope_code='LF_ACTIVOS_OWNER_NAME_WRITE_V1')
 IS DISTINCT FROM '46fec8cec50bd13eb0687ca99d4c7cd1c3901babcc3946cd24d6527dedad8621'
 THEN RAISE EXCEPTION 'LF_POLICY19_ACT0001_OWNER_POLICY_DRIFT'; END IF;
 IF (SELECT encode(extensions.digest(convert_to(to_jsonb(t)::text,'UTF8'),'sha256'),'hex')
 FROM lf_ops.politicas_seguridad t WHERE t.security_policy_id=19)
 IS DISTINCT FROM 'f82cf4ed0887d8240e1a20d193a7a3a82f92271334de6eb543e4489ecac21b07'
 THEN RAISE EXCEPTION 'LF_POLICY19_ACT0001_POLICY_ROW_DRIFT'; END IF;
 IF (SELECT count(*) FROM public.lf_operation_execution e
 WHERE e.status='IN_PROGRESS' AND e.operation_code='ACTUALIZACION_DB_LF'
 AND e.target_code~'^[0-9]{14}_lf_policy19_act0001_scoped_writer_v1$'
 AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
 AND e.manifest->>'producer'='lf-migration-merge-train'
 AND e.target_path='supabase/migrations/'||e.target_code||'.sql')<>1
 THEN RAISE EXCEPTION 'LF_POLICY19_ACT0001_TRAIN_CONTEXT_MISSING'; END IF;
END $before$;

CREATE OR REPLACE FUNCTION public.lf_ig_policy19_apply_v1(p_execution_id text,p_description text,p_eight jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','lf_ops','programacion','extensions'
AS $policy19$
DECLARE
 v_scope jsonb; v_before lf_ops.politicas_seguridad%ROWTYPE;
 v_after lf_ops.politicas_seguridad%ROWTYPE;
 v_before_sha text;
 v_provenance jsonb;
 v_key text;
BEGIN
 v_scope:=public.lf_router_scope_receipt_consume_v2(p_execution_id,'description');
 IF v_scope->>'status' IS DISTINCT FROM 'SCOPE_RECEIPT_VERIFIED_ROUTE_ONLY'
 OR v_scope->>'scope_attested' IS DISTINCT FROM 'true'
 OR v_scope->>'effect_authority' IS DISTINCT FROM 'false'
 OR v_scope->>'downstream_execution_allowed' IS DISTINCT FROM 'false'
 OR v_scope->>'scope_code' IS DISTINCT FROM 'LF_POLICY19_ADMIN12_OTP_BREVO_CHANGE_V1'
 THEN RAISE EXCEPTION 'LF_POLICY19_WRITER_SCOPE_CONSUMER_REQUIRED'; END IF;
 IF p_eight IS DISTINCT FROM '{"admin_minimum_strength":"APPROVED_MFA","admin_phishing_resistant_requirement":"NOT_REQUIRED_FOR_PROFILES_1_2_OWNER_RISK_ACCEPTED_PENDING_SIGNATURE","phishing_resistant_option_required":false,"admin_primary_method":"USERNAME_PASSWORD_SERVER_VALIDATED","admin_identity_provider":"PENDING_ADR_003_M1_SPIKE","admin_sso_protocol":"PENDING_ADR_003_M1_SPIKE","admin_provider_configuration_status":"PENDING_REAL_IDP_AND_BREVO_INTEGRATION_QA","factor_selection_status":"OWNER_DECIDED_IN_CONVERSATION_PENDING_SIGNATURE_IMPLEMENTATION"}'::jsonb
 OR encode(extensions.digest(convert_to(coalesce(p_description,''),'UTF8'),'sha256'),'hex')
 IS DISTINCT FROM '0beb7404a61197b3d2528de19a210350a02ae83a5d7fbc58d57726645173975b'
 THEN RAISE EXCEPTION 'LF_POLICY19_WRITER_APPROVED_VALUES_DRIFT'; END IF;
 SELECT * INTO v_before FROM lf_ops.politicas_seguridad
 WHERE security_policy_id=19 AND policy_code='SEC-B2B-MFA-FACTOR-ELIGIBILITY' FOR UPDATE;
 IF NOT FOUND OR v_before.status IS DISTINCT FROM 'CANDIDATO'
 THEN RAISE EXCEPTION 'LF_POLICY19_WRITER_TARGET_OR_STATUS_DRIFT'; END IF;
 v_before_sha:=encode(extensions.digest(convert_to(to_jsonb(v_before)::text,'UTF8'),'sha256'),'hex');
 IF v_before_sha IS DISTINCT FROM 'f82cf4ed0887d8240e1a20d193a7a3a82f92271334de6eb543e4489ecac21b07'
 THEN RAISE EXCEPTION 'LF_POLICY19_SOURCE_PREIMAGE_DRIFT'; END IF;
 IF v_before.policy_config->'admin_profile_ids' IS DISTINCT FROM '[1,2]'::jsonb
 OR (SELECT count(*) FROM jsonb_object_keys(p_eight))<>8
 THEN RAISE EXCEPTION 'LF_POLICY19_WRITER_COHORT_DRIFT'; END IF;
 v_provenance:=v_before.parameter_provenance;
 FOR v_key IN SELECT jsonb_object_keys(p_eight) LOOP
   v_provenance:=jsonb_set(v_provenance,ARRAY[v_key],
      jsonb_build_object('origin_type','LF_CANONICAL','value_status','LF_CANONICAL',
       'decision_ref','L36-OWNER-ADMIN-LF-PROFILE1-OTP-BREVO-001',
       'origin_reference','docs/rule-quality-lote36/00_decision_dueno_admin_lf_perfil1_otp_brevo.json',
       'origin_version','2026-11-13','identity_verified',false,
       'source_document_git_blob_sha1','0b41825b9221c5d7a01a80190e2e2924e6fdc203',
       'source_fullrow_sha256',v_before_sha,
       'change_purpose','OWNER_DOCUMENTARY_DECISION_PROFILES_1_2_OTP_BREVO',
       'field',v_key),true);
 END LOOP;
 IF NOT programacion.fn_input_parameter_provenance_valid_v1(v_provenance)
 THEN RAISE EXCEPTION 'LF_POLICY19_WRITER_PROVENANCE_INVALID'; END IF;
 UPDATE lf_ops.politicas_seguridad SET description=p_description,
 policy_config=v_before.policy_config||p_eight, parameter_provenance=v_provenance
 WHERE security_policy_id=19 RETURNING * INTO v_after;
 IF v_after.status IS DISTINCT FROM 'CANDIDATO'
 OR v_after.policy_config IS DISTINCT FROM (v_before.policy_config||p_eight)
 OR v_after.parameter_provenance IS DISTINCT FROM v_provenance
 OR (to_jsonb(v_after)-'description'-'policy_config'-'parameter_provenance'-'updated_at')
    IS DISTINCT FROM (to_jsonb(v_before)-'description'-'policy_config'-'parameter_provenance'-'updated_at')
 THEN RAISE EXCEPTION 'LF_POLICY19_WRITER_READBACK_DRIFT'; END IF;
 RETURN jsonb_build_object('status','CANDIDATO_GOVERNED_READBACK',
   'security_policy_id',19,'execution_id',p_execution_id,
   'scope_receipt_sha256',v_scope->>'receipt_sha256',
   'before_sha256',v_before_sha,
   'description_sha256',encode(extensions.digest(convert_to(v_after.description,'UTF8'),'sha256'),'hex'),
   'config_keys_changed',8,'provenance_keys_refreshed',8,
   'after_sha256',encode(extensions.digest(convert_to(to_jsonb(v_after)::text,'UTF8'),'sha256'),'hex'),
   'identity_verified',false);
END $policy19$;
REVOKE ALL ON FUNCTION public.lf_ig_policy19_apply_v1(text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_ig_policy19_apply_v1(text,text,jsonb) TO service_role;

DO $policyrow$
DECLARE x text; c jsonb; f jsonb; w text; s text; r text;
BEGIN
 SELECT jsonb_agg(column_name ORDER BY column_name),
 jsonb_agg(column_name ORDER BY column_name) FILTER(WHERE column_name NOT IN ('description','policy_config','parameter_provenance','updated_at'))
 INTO c,f FROM information_schema.columns WHERE table_schema='lf_ops' AND table_name='politicas_seguridad';
 IF c IS NULL OR f IS NULL THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_SCHEMA_MISSING'; END IF;
 w:=md5(pg_get_functiondef('public.lf_ig_policy19_apply_v1(text,text,jsonb)'::regprocedure));
 s:=encode(extensions.digest(convert_to(c::text,'UTF8'),'sha256'),'hex');
 r:=encode(extensions.digest(convert_to(jsonb_build_object(
 'scope_code','LF_POLICY19_ADMIN12_OTP_BREVO_CHANGE_V1',
 'operation_code','ACTUALIZACION_DB_LF',
 'entrypoint','public.lf_ig_policy19_apply_v1(text,text,jsonb)',
 'allowed_table','lf_ops.politicas_seguridad','allowed_columns','["description","policy_config","parameter_provenance","updated_at"]'::jsonb,
 'forbidden_columns',f,'schema_columns_sha256',s,'writer_source_md5',w)::text,'UTF8'),'sha256'),'hex');
 INSERT INTO public.lf_router_scope_policy_v1(scope_code,operation_code,effect_entrypoint,allowed_table,
 allowed_columns,forbidden_columns,schema_columns_sha256,writer_source_md5,policy_sha256,created_by_execution_id)
 SELECT 'LF_POLICY19_ADMIN12_OTP_BREVO_CHANGE_V1','ACTUALIZACION_DB_LF',
 'public.lf_ig_policy19_apply_v1(text,text,jsonb)','lf_ops.politicas_seguridad',
 '["description","policy_config","parameter_provenance","updated_at"]'::jsonb,f,s,w,r,e.execution_id
 FROM public.lf_operation_execution e WHERE e.status='IN_PROGRESS'
 AND e.target_code~'^[0-9]{14}_lf_policy19_act0001_scoped_writer_v1$'
 AND e.operation_code='ACTUALIZACION_DB_LF' AND e.manifest->>'producer'='lf-migration-merge-train'
 AND e.target_path='supabase/migrations/'||e.target_code||'.sql';
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_CATALOG_INSERT_FAILED'; END IF;
END $policyrow$;

CREATE OR REPLACE FUNCTION public.lf_router_scope_policy19_consume_internal_v1(p_execution_id text,p_requested_business_column text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $consume19$
DECLARE
 e public.lf_operation_execution%ROWTYPE; r public.lf_router_scope_receipt_v1%ROWTYPE;
 p public.lf_router_scope_policy_v1%ROWTYPE; cols jsonb; denied jsonb; recsha text; polsha text;
 expected_positive jsonb; expected_negative jsonb;
BEGIN
 IF p_requested_business_column IS DISTINCT FROM 'description'
 THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_BUSINESS_COLUMN_FORBIDDEN'; END IF;
 SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id
 AND operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND status='IN_PROGRESS' AND target_repo='cristhianlujan/claude-persona-lf-patch'
 AND target_code~'^[0-9]{14}_lf_b2b_policy19_otp_brevo_profiles12_v1$'
 AND target_path='supabase/migrations/'||target_code||'.sql';
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_TRAIN_NOT_CURRENT'; END IF;
 SELECT * INTO r FROM public.lf_router_scope_receipt_v1 WHERE execution_id=p_execution_id;
 SELECT * INTO p FROM public.lf_router_scope_policy_v1 WHERE scope_code='LF_POLICY19_ADMIN12_OTP_BREVO_CHANGE_V1';
 IF r.execution_id IS NULL THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_RECEIPT_MISSING'; END IF;
 IF p.scope_code IS NULL OR r.scope_code IS DISTINCT FROM p.scope_code
 OR p.operation_code IS DISTINCT FROM 'ACTUALIZACION_DB_LF'
 OR p.effect_entrypoint IS DISTINCT FROM 'public.lf_ig_policy19_apply_v1(text,text,jsonb)'
 OR p.allowed_table IS DISTINCT FROM 'lf_ops.politicas_seguridad'
 OR p.allowed_columns IS DISTINCT FROM '["description","policy_config","parameter_provenance","updated_at"]'::jsonb
 THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_POLICY_DRIFT'; END IF;
 SELECT jsonb_agg(column_name ORDER BY column_name),
 jsonb_agg(column_name ORDER BY column_name) FILTER(WHERE column_name NOT IN ('description','policy_config','parameter_provenance','updated_at'))
 INTO cols,denied FROM information_schema.columns WHERE table_schema='lf_ops' AND table_name='politicas_seguridad';
 IF cols IS NULL OR denied IS DISTINCT FROM p.forbidden_columns
 OR encode(extensions.digest(convert_to(cols::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM p.schema_columns_sha256
 OR md5(pg_get_functiondef('public.lf_ig_policy19_apply_v1(text,text,jsonb)'::regprocedure)) IS DISTINCT FROM p.writer_source_md5
 THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_SCHEMA_OR_WRITER_DRIFT'; END IF;
 polsha:=encode(extensions.digest(convert_to(jsonb_build_object(
 'scope_code',p.scope_code,'operation_code',p.operation_code,'entrypoint',p.effect_entrypoint,
 'allowed_table',p.allowed_table,'allowed_columns',p.allowed_columns,'forbidden_columns',denied,
 'schema_columns_sha256',p.schema_columns_sha256,'writer_source_md5',p.writer_source_md5)::text,'UTF8'),'sha256'),'hex');
 IF polsha IS DISTINCT FROM p.policy_sha256 THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_POLICY_SHA_DRIFT'; END IF;
 expected_positive:=jsonb_build_array(jsonb_build_object('table','lf_ops.politicas_seguridad',
 'row_id',19,'policy_code','SEC-B2B-MFA-FACTOR-ELIGIBILITY','status','CANDIDATO',
 'columns',p.allowed_columns,'policy_config_keys','["admin_minimum_strength","admin_phishing_resistant_requirement","phishing_resistant_option_required","admin_primary_method","admin_identity_provider","admin_sso_protocol","admin_provider_configuration_status","factor_selection_status"]'::jsonb,
 'parameter_provenance_keys','["admin_minimum_strength","admin_phishing_resistant_requirement","phishing_resistant_option_required","admin_primary_method","admin_identity_provider","admin_sso_protocol","admin_provider_configuration_status","factor_selection_status"]'::jsonb,'entrypoint',p.effect_entrypoint));
 expected_negative:=jsonb_build_object('table','lf_ops.politicas_seguridad',
 'forbidden_columns',denied,'all_other_policy_config_keys','DENY',
 'all_other_provenance_keys','DENY','other_rows','DENY','other_business_tables','DENY',
 'other_operations','DENY','project_SALY','DENY','historical_runs','DENY','production_promotion','DENY');
 recsha:=encode(extensions.digest(convert_to(r.receipt::text,'UTF8'),'sha256'),'hex');
 IF r.manifest_sha256 IS DISTINCT FROM encode(extensions.digest(convert_to(e.manifest::text,'UTF8'),'sha256'),'hex')
 OR r.receipt_sha256 IS DISTINCT FROM recsha
 OR r.receipt->>'schema_version' IS DISTINCT FROM 'LF_ROUTER_POSITIVE_NEGATIVE_SCOPE_RECEIPT_V1'
 OR r.receipt->>'router' IS DISTINCT FROM 'ACT-0001'
 OR r.receipt->>'execution_id' IS DISTINCT FROM p_execution_id
 OR r.receipt->>'target_path' IS DISTINCT FROM e.target_path
 OR r.receipt->>'target_code' IS DISTINCT FROM e.target_code
 OR r.receipt->>'request_sha256' IS DISTINCT FROM e.request_sha256
 OR r.receipt->>'manifest_sha256' IS DISTINCT FROM r.manifest_sha256
 OR r.receipt->>'policy_sha256' IS DISTINCT FROM p.policy_sha256
 OR r.receipt->>'scope_code' IS DISTINCT FROM p.scope_code
 OR r.receipt->'positive_scope' IS DISTINCT FROM expected_positive
 OR r.receipt->'negative_scope' IS DISTINCT FROM expected_negative
 OR r.receipt->>'scope_semantics_attested' IS DISTINCT FROM 'true'
 OR r.receipt->>'effect_authority' IS DISTINCT FROM 'false'
 OR r.receipt->>'downstream_execution_allowed' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_RECEIPT_TAMPERED_OR_STALE'; END IF;
 RETURN jsonb_build_object('status','SCOPE_RECEIPT_VERIFIED_ROUTE_ONLY','router','ACT-0001',
 'scope_code',p.scope_code,'execution_id',p_execution_id,'scope_attested',true,
 'receipt_sha256',recsha,'policy_sha256',polsha,
 'allowed_business_column','description','effect_authority',false,'downstream_execution_allowed',false);
END $consume19$;
REVOKE ALL ON FUNCTION public.lf_router_scope_policy19_consume_internal_v1(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_scope_policy19_consume_internal_v1(text,text) TO service_role;

CREATE OR REPLACE FUNCTION public.lf_router_scope_policy19_bind_internal_v1(p_execution_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $bind19$
DECLARE
 e public.lf_operation_execution%ROWTYPE; p public.lf_router_scope_policy_v1%ROWTYPE;
 stored public.lf_router_scope_receipt_v1%ROWTYPE; origin jsonb; cols jsonb; denied jsonb;
 manifest_sha text; policy_sha text; body jsonb; body_sha text; verified jsonb;
BEGIN
 SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id
 AND operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND status='IN_PROGRESS' AND target_repo='cristhianlujan/claude-persona-lf-patch'
 AND target_code~'^[0-9]{14}_lf_b2b_policy19_otp_brevo_profiles12_v1$'
 AND target_path='supabase/migrations/'||target_code||'.sql' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_TRAIN_NOT_CURRENT'; END IF;
 origin:=e.manifest->'router_authority_receipt';
 IF coalesce(e.request_sha256,'') !~ '^[0-9a-f]{64}$'
 OR coalesce(e.manifest->>'head_sha','') !~ '^[0-9a-f]{40}$'
 OR coalesce(e.manifest->>'train_run_id','') !~ '^[0-9]{8,20}$'
 OR coalesce(e.manifest->>'pr','') !~ '^[0-9]{1,10}$'
 OR e.manifest->>'producer' IS DISTINCT FROM 'lf-migration-merge-train'
 OR origin->>'schema_version' IS DISTINCT FROM 'LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1'
 OR origin->>'router' IS DISTINCT FROM 'ACT-0001'
 OR origin->>'operation_code' IS DISTINCT FROM 'ACTUALIZACION_DB_LF'
 OR origin->>'action_code' IS DISTINCT FROM 'UPDATE'
 OR origin->>'target_repo' IS DISTINCT FROM e.target_repo
 OR origin->>'target_code' IS DISTINCT FROM e.target_code
 OR origin->>'target_path' IS DISTINCT FROM e.target_path
 OR origin->>'scope_attested' IS DISTINCT FROM 'false'
 OR origin->>'route_eligibility_only' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_ROUTER_ORIGIN_NOT_GOVERNED'; END IF;
 SELECT * INTO p FROM public.lf_router_scope_policy_v1
 WHERE scope_code='LF_POLICY19_ADMIN12_OTP_BREVO_CHANGE_V1';
 IF NOT FOUND OR p.allowed_table IS DISTINCT FROM 'lf_ops.politicas_seguridad'
 OR p.operation_code IS DISTINCT FROM 'ACTUALIZACION_DB_LF'
 OR p.effect_entrypoint IS DISTINCT FROM 'public.lf_ig_policy19_apply_v1(text,text,jsonb)'
 OR p.allowed_columns IS DISTINCT FROM '["description","policy_config","parameter_provenance","updated_at"]'::jsonb
 THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_POLICY_DRIFT'; END IF;
 SELECT jsonb_agg(column_name ORDER BY column_name),
 jsonb_agg(column_name ORDER BY column_name) FILTER(WHERE column_name NOT IN ('description','policy_config','parameter_provenance','updated_at'))
 INTO cols,denied FROM information_schema.columns WHERE table_schema='lf_ops' AND table_name='politicas_seguridad';
 IF cols IS NULL OR denied IS DISTINCT FROM p.forbidden_columns
 OR encode(extensions.digest(convert_to(cols::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM p.schema_columns_sha256
 OR md5(pg_get_functiondef('public.lf_ig_policy19_apply_v1(text,text,jsonb)'::regprocedure)) IS DISTINCT FROM p.writer_source_md5
 THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_SCHEMA_OR_WRITER_DRIFT'; END IF;
 policy_sha:=encode(extensions.digest(convert_to(jsonb_build_object(
 'scope_code',p.scope_code,'operation_code',p.operation_code,'entrypoint',p.effect_entrypoint,
 'allowed_table',p.allowed_table,'allowed_columns',p.allowed_columns,'forbidden_columns',denied,
 'schema_columns_sha256',p.schema_columns_sha256,'writer_source_md5',p.writer_source_md5)::text,'UTF8'),'sha256'),'hex');
 IF policy_sha IS DISTINCT FROM p.policy_sha256 THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_POLICY_SHA_DRIFT'; END IF;
 manifest_sha:=encode(extensions.digest(convert_to(e.manifest::text,'UTF8'),'sha256'),'hex');
 body:=jsonb_build_object('schema_version','LF_ROUTER_POSITIVE_NEGATIVE_SCOPE_RECEIPT_V1',
 'router','ACT-0001','status','SCOPE_ATTESTED_ROUTE_ONLY',
 'execution_id',p_execution_id,'request_sha256',e.request_sha256,
 'operation_code',e.operation_code,'target_code',e.target_code,'target_path',e.target_path,
 'manifest_sha256',manifest_sha,'scope_code',p.scope_code,'policy_sha256',policy_sha,
 'scope_source','SERVER_CANONICAL_CATALOG_AND_PINNED_POLICY19_WRITER',
 'positive_scope',jsonb_build_array(jsonb_build_object('table','lf_ops.politicas_seguridad',
   'row_id',19,'policy_code','SEC-B2B-MFA-FACTOR-ELIGIBILITY','status','CANDIDATO',
   'columns',p.allowed_columns,'policy_config_keys','["admin_minimum_strength","admin_phishing_resistant_requirement","phishing_resistant_option_required","admin_primary_method","admin_identity_provider","admin_sso_protocol","admin_provider_configuration_status","factor_selection_status"]'::jsonb,
   'parameter_provenance_keys','["admin_minimum_strength","admin_phishing_resistant_requirement","phishing_resistant_option_required","admin_primary_method","admin_identity_provider","admin_sso_protocol","admin_provider_configuration_status","factor_selection_status"]'::jsonb,'entrypoint',p.effect_entrypoint)),
 'negative_scope',jsonb_build_object('table','lf_ops.politicas_seguridad',
   'forbidden_columns',denied,'all_other_policy_config_keys','DENY','all_other_provenance_keys','DENY',
   'other_rows','DENY','other_business_tables','DENY','other_operations','DENY',
   'project_SALY','DENY','historical_runs','DENY','production_promotion','DENY'),
 'scope_semantics_attested',true,'effect_authority',false,
 'downstream_execution_allowed',false,'identity_verified',false);
 body_sha:=encode(extensions.digest(convert_to(body::text,'UTF8'),'sha256'),'hex');
 SELECT * INTO stored FROM public.lf_router_scope_receipt_v1 WHERE execution_id=p_execution_id FOR UPDATE;
 IF FOUND THEN
  IF stored.scope_code IS DISTINCT FROM p.scope_code
  OR stored.manifest_sha256 IS DISTINCT FROM manifest_sha
  OR stored.receipt_sha256 IS DISTINCT FROM body_sha
  OR stored.receipt IS DISTINCT FROM body
  THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_STORED_RECEIPT_DRIFT'; END IF;
 ELSE
  INSERT INTO public.lf_router_scope_receipt_v1(execution_id,scope_code,manifest_sha256,receipt,receipt_sha256)
  VALUES(p_execution_id,p.scope_code,manifest_sha,body,body_sha);
 END IF;
 verified:=public.lf_router_scope_receipt_consume_v2(p_execution_id,'description');
 IF verified->>'status' IS DISTINCT FROM 'SCOPE_RECEIPT_VERIFIED_ROUTE_ONLY'
 OR verified->>'receipt_sha256' IS DISTINCT FROM body_sha
 OR verified->>'policy_sha256' IS DISTINCT FROM p.policy_sha256
 OR verified->>'effect_authority' IS DISTINCT FROM 'false'
 OR verified->>'downstream_execution_allowed' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_CONSUMER_REQUIRED'; END IF;
 RETURN body||jsonb_build_object('receipt_sha256',body_sha);
END $bind19$;
REVOKE ALL ON FUNCTION public.lf_router_scope_policy19_bind_internal_v1(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_router_scope_policy19_bind_internal_v1(text) TO service_role;

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
 IF EXISTS (
  SELECT 1 FROM public.lf_operation_execution AS scope_execution
  WHERE scope_execution.execution_id=p_execution_id
    AND scope_execution.target_code~'^[0-9]{14}_lf_b2b_policy19_otp_brevo_profiles12_v1$'
 ) THEN
  RETURN public.lf_router_scope_policy19_consume_internal_v1(p_execution_id,p_requested_business_column);
 END IF;
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
 IF EXISTS (
  SELECT 1 FROM public.lf_operation_execution AS scope_execution
  WHERE scope_execution.execution_id=p_execution_id
    AND scope_execution.target_code~'^[0-9]{14}_lf_b2b_policy19_otp_brevo_profiles12_v1$'
 ) THEN
  RETURN public.lf_router_scope_policy19_bind_internal_v1(p_execution_id);
 END IF;
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
DO $post$
BEGIN
 IF md5(pg_get_functiondef('public.lf_ig_asset_owner_apply_v2(uuid)'::regprocedure))
   IS DISTINCT FROM (SELECT writer_source_md5 FROM public.lf_router_scope_policy_v1 WHERE scope_code='LF_ACTIVOS_OWNER_NAME_WRITE_V1')
 THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_OWNER_WRITER_REGRESSION'; END IF;
 IF (SELECT count(*) FROM public.lf_router_scope_policy_v1)<>2
 OR (SELECT policy_sha256 FROM public.lf_router_scope_policy_v1 WHERE scope_code='LF_ACTIVOS_OWNER_NAME_WRITE_V1')
 IS DISTINCT FROM '46fec8cec50bd13eb0687ca99d4c7cd1c3901babcc3946cd24d6527dedad8621'
 OR position('public.lf_router_scope_policy19_bind_internal_v1' IN pg_get_functiondef('public.lf_router_scope_bind_v1(text)'::regprocedure))=0
 OR position('public.lf_router_scope_policy19_consume_internal_v1' IN pg_get_functiondef('public.lf_router_scope_receipt_consume_v2(text,text)'::regprocedure))=0
 THEN RAISE EXCEPTION 'LF_POLICY19_SCOPE_POST_READBACK_FAILED'; END IF;
END $post$;
COMMIT;