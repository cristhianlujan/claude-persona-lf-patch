-- LF B07 SALY / gobernado ACT-0001 -> Profile Creator -> official Merge Train.
-- DRAFT / NO-GO until native CREACION_PERFIL_LF receipt exists and gates PASS.
-- Does NOT activate SALY writes, call a live writer, change existing RUNs,
-- deploy B07 history tables or enable production. No parallel RPC introduced.
-- Decision (documentary only): owner="Cristhian Luján", literal="Si me designo",
-- local date 2026-11-13 12:53 America/Lima; identity_verified=false.
-- The owner_sub generated below is an opaque internal UUID, NOT Supabase Auth.
BEGIN;
DO $saly_b07_register$
DECLARE
 v_train public.lf_operation_execution%ROWTYPE;
 v_native_profile public.lf_operation_execution%ROWTYPE;
 v_bootstrap text; v_sha text; v_reserved jsonb; v_decision jsonb;
 v_decision_sha text; v_internal_owner_sub uuid; v_profile text;
 v_count integer;
BEGIN
 v_profile:='PERFIL-PRODUCT-DIRECTOR-SALY';
 IF EXISTS(SELECT 1 FROM public.lf_operation_registry
           WHERE operation_code='ACTUALIZACION_REGLA_SALY')
    OR EXISTS(SELECT 1 FROM public.lf_ig_project_owner_v2
           WHERE project_code='SALY')
    OR EXISTS(SELECT 1 FROM public.lf_router_action_registry
           WHERE asset_type='REGLA' AND action_code='SALY_RULE_UPDATE')
 THEN RAISE EXCEPTION 'B07_SALY_REGISTRATION_ALREADY_EXISTS'; END IF;

 -- Native profile is the only allowed profile creator. A Git pack alone is not a DB profile.
 SELECT * INTO v_native_profile FROM public.lf_operation_execution e
 WHERE e.operation_code='CREACION_PERFIL_LF'
   AND e.target_type='PERFIL' AND e.target_code=v_profile
   AND e.status='COMPLETED'
   AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
 ORDER BY e.completed_at DESC NULLS LAST LIMIT 1;
 IF NOT FOUND OR NOT EXISTS(
   SELECT 1 FROM public.lf_activos a
   WHERE a.codigo_activo=v_profile AND a.tipo_activo='PERFIL'
     AND a.archived_at IS NULL AND a.estado_operativo='READ_ONLY'
     AND a.estado_documental='CANDIDATO'
     AND a.created_by_execution_id=v_native_profile.execution_id
 ) THEN RAISE EXCEPTION 'B07_SALY_PROFILE_NATIVE_CREATION_RECEIPT_REQUIRED'; END IF;

 SELECT count(*) INTO v_count FROM public.lf_operation_execution e
 WHERE e.operation_code='ACTUALIZACION_DB_LF'
   AND e.target_type='MIGRATION'
   AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
   AND e.target_code ~ '^[0-9]{14}_lf_ig_b07_saly_operation_owner_register_v1$'
   AND e.target_path='supabase/migrations/'||e.target_code||'.sql'
   AND e.status='IN_PROGRESS'
   AND e.manifest->>'producer'='lf-migration-merge-train'
   AND e.manifest->>'pr'='3832'
   AND e.manifest->>'head_sha' ~ '^[0-9a-f]{40}$'
   AND e.manifest->>'train_run_id' ~ '^[0-9]{8,20}$'
   AND e.manifest->'router_authority_receipt'->>'schema_version'='LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1'
   AND e.manifest->'router_authority_receipt'->>'router'='ACT-0001'
   AND e.manifest->'router_authority_receipt'->>'operation_code'='ACTUALIZACION_DB_LF'
   AND e.manifest->'router_authority_receipt'->>'action_code'='UPDATE'
   AND e.manifest->'router_authority_receipt'->>'target_code'=e.target_code
   AND e.manifest->'router_authority_receipt'->>'target_repo'=e.target_repo
   AND e.manifest->'router_authority_receipt'->>'target_path'=e.target_path
   AND e.manifest->'router_authority_receipt'->>'route_eligibility_only'='true'
   AND e.manifest->'router_authority_receipt'->>'scope_attested'='false'
   AND e.created_by_execution_id='LF-MIGRATION-TRAIN-RUN-'||(e.manifest->>'train_run_id')
   AND e.request_sha256 ~ '^[0-9a-f]{64}$'
   AND EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s
      WHERE s.execution_id=e.execution_id AND s.step_id='preflight' AND s.status='PASS_CLEAN');
 IF v_count<>1 THEN RAISE EXCEPTION 'B07_SALY_EXACT_OFFICIAL_TRAIN_REQUIRED:%',v_count; END IF;
 SELECT * INTO STRICT v_train FROM public.lf_operation_execution e
 WHERE e.operation_code='ACTUALIZACION_DB_LF'
   AND e.target_code ~ '^[0-9]{14}_lf_ig_b07_saly_operation_owner_register_v1$'
   AND e.manifest->>'pr'='3832' AND e.status='IN_PROGRESS' FOR SHARE;

 v_decision:='{"decision_interpretada":"designacion expresa de owner documental SALY y autorizacion para crear/homologar perfil SALY propio sin heredar el perfil LF","fecha_local":"2026-11-13T12:53:00-05:00","fuente":"declaracion textual del dueno reportada en la conversacion del arquitecto, 2026-11-13","identity_mode":"UNVERIFIED_CHAT_DECLARATION","identity_verified":false,"literal":"Si me designo","owner_name":"Cristhian Luján","production_authorized":false,"proyecto":"SALY"}'::jsonb;
 IF v_decision->>'literal'<>'Si me designo'
   OR v_decision->>'owner_name'<>'Cristhian Luján'
   OR v_decision->>'fecha_local'<>'2026-11-13T12:53:00-05:00'
   OR v_decision->>'proyecto'<>'SALY'
   OR v_decision->>'identity_verified'<>'false'
   OR v_decision->>'production_authorized'<>'false'
 THEN RAISE EXCEPTION 'B07_SALY_DOCUMENTARY_OWNER_DECISION_DRIFT'; END IF;
 v_decision_sha:=encode(extensions.digest(convert_to(v_decision::text,'UTF8'),'sha256'),'hex');

 -- Native registrar already used by PROMOCION_REGLA_LF, not a new writer.
 v_bootstrap:='EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-SALY-R'||(v_train.manifest->>'train_run_id');
 v_sha:=encode(extensions.digest(convert_to(
  'ACTUALIZACION_REGLA_SALY|'||v_train.execution_id||'|'||v_train.request_sha256,
  'UTF8'),'sha256'),'hex');
 v_reserved:=public.fn_lf_operation_reserve_execution_v1(
  v_bootstrap,'VULNERABILITY_COVERAGE_REPAIR_LF','OPERATION_PROTOCOL_REPAIR',
  'ACTUALIZACION_REGLA_SALY','governed-operation-bootstrap:'||v_train.execution_id,
  v_sha,v_train.execution_id,NULL,NULL,
  jsonb_build_object('mode','B07_SALY_OWNER_OPERATION_GOVERNANCE_BOOTSTRAP_V1',
   'governance_bootstrap',true,
   'bootstrap_operation_code','ACTUALIZACION_REGLA_SALY',
   'bootstrap_status_ceiling','SANDBOX_ACTIVE',
   'candidate_only',true,'production_allowed',false,'runtime_activation',false,
   'owner_decision_record_sha256',v_decision_sha,
   'identity_verified',false,'source_train_execution_id',v_train.execution_id,
   'source_train_request_sha256',v_train.request_sha256));
 IF v_reserved->>'result'<>'RESERVED_NEW_EXECUTION'
   OR v_reserved->>'execution_id' IS DISTINCT FROM v_bootstrap
   OR v_reserved->>'status'<>'IN_PROGRESS'
 THEN RAISE EXCEPTION 'B07_SALY_OFFICIAL_BOOTSTRAP_FAILED'; END IF;

 INSERT INTO public.lf_operation_registry(
  operation_code,version,status,source_model,source_repo,source_paths,notes,
  operation_family,operation_domain,operation_type,applies_to_asset_type,
  created_by_execution_id,lifecycle_state_code)
 VALUES('ACTUALIZACION_REGLA_SALY','v0.1','SANDBOX_ACTIVE','GIT_FIRST_YAML',
  'cristhianlujan/claude-persona-lf-patch',
  '["public.lf_ig_saly_rule_finalize_b07_v1","saly.reglas","saly.decisiones","saly.reglas_versiones_b07"]'::jsonb,
  'Documentary-only SALY owner. Finalizer in separate owner-approved B07 DDL. No production activation.',
  'RULE_OPERATIONS','RULE_GOVERNANCE','UPDATE_DOCUMENTARY_VALIDADO','REGLA',
  v_bootstrap,'OP_CANDIDATE');

 -- Distinct SALY internal correlation ID; not an Auth subject or credential.
 v_internal_owner_sub:=gen_random_uuid();
 INSERT INTO public.lf_ig_project_owner_v2(
   project_code,owner_sub,owner_name,owner_profile_code,identity_mode,
   authority_receipt_sha256,status,source_execution_id)
 VALUES('SALY',v_internal_owner_sub,'Cristhian Luján',v_profile,
   'UNVERIFIED_CHAT_DECLARATION',v_decision_sha,
   'TEMP_DOCUMENTARY_ACTIVE',v_train.execution_id);

 -- Candidate-only routing metadata; NO runtime writer or privilege enabled.
 INSERT INTO public.lf_router_action_registry(
  asset_type,action_code,operation_code,operation_resolution,
  requires_existing_target,requires_missing_target,write_allowed,status,
  notes,created_by_execution_id)
 VALUES('REGLA','SALY_RULE_UPDATE','ACTUALIZACION_REGLA_SALY','STATIC',
  true,false,false,'CANDIDATO_READ_ONLY',
  'Proposed SALY owner flow; ACT-0001 router implementation/negative gates must be verified separately.',
  v_bootstrap);
 INSERT INTO public.lf_operation_mode_bindings(
  operation_code,task_mode,execution_mode,allowed,write_allowed,
  destination_kind,input_completeness,status,notes,created_by_execution_id)
 VALUES('ACTUALIZACION_REGLA_SALY','REMEDIATE_EXISTING','GOVERNED',
  false,false,'NO_WRITE','READ_ONLY','ACTIVE',
  'Disabled until SALY router, owner decision V2, 7-step child, security reviews and separate B07 Train.',
  v_bootstrap);
 INSERT INTO public.lf_profile_write_authority_v1(
  profile_code,operation_code,status,basis,self_update_allowed)
 VALUES(v_profile,'ACTUALIZACION_REGLA_SALY','PROPOSED',
  'Owner SALY documentary declaration 2026-11-13 12:53 America/Lima; identity_verified=false, production_authorized=false.',
  false);

 IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_registry r
    JOIN public.lf_operation_execution e ON e.execution_id=r.created_by_execution_id
    WHERE r.operation_code='ACTUALIZACION_REGLA_SALY'
      AND r.status='SANDBOX_ACTIVE' AND r.lifecycle_state_code='OP_CANDIDATE'
      AND e.operation_code='VULNERABILITY_COVERAGE_REPAIR_LF'
      AND e.manifest->>'source_train_execution_id'=v_train.execution_id
      AND e.manifest->>'owner_decision_record_sha256'=v_decision_sha
 ) OR NOT EXISTS (
    SELECT 1 FROM public.lf_ig_project_owner_v2
    WHERE project_code='SALY' AND owner_sub=v_internal_owner_sub
      AND owner_profile_code=v_profile AND authority_receipt_sha256=v_decision_sha
      AND identity_mode='UNVERIFIED_CHAT_DECLARATION'
      AND status='TEMP_DOCUMENTARY_ACTIVE'
      AND source_execution_id=v_train.execution_id
 ) OR NOT EXISTS (
    SELECT 1 FROM public.lf_router_action_registry
    WHERE asset_type='REGLA' AND action_code='SALY_RULE_UPDATE'
      AND status='CANDIDATO_READ_ONLY' AND NOT write_allowed
 ) OR NOT EXISTS (
    SELECT 1 FROM public.lf_operation_mode_bindings
    WHERE operation_code='ACTUALIZACION_REGLA_SALY'
      AND NOT allowed AND NOT write_allowed
 ) OR NOT EXISTS (
    SELECT 1 FROM public.lf_profile_write_authority_v1
    WHERE profile_code=v_profile AND operation_code='ACTUALIZACION_REGLA_SALY'
      AND status='PROPOSED' AND NOT self_update_allowed
 ) THEN RAISE EXCEPTION 'B07_SALY_REGISTER_READBACK_FAILED'; END IF;
END $saly_b07_register$;
COMMIT;
