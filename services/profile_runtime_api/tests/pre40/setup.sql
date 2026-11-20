-- Disposable schema and boundary doubles. The four functions in preimage.sql
-- are loaded verbatim before the actual migration, with its digest guards.
CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE TABLE lf_operation_execution(execution_id text PRIMARY KEY, operation_code text, target_type text,
 target_code text, target_repo text, target_path text, status text, manifest jsonb,
 updated_at timestamptz, updated_by_execution_id text, created_at timestamptz DEFAULT now());
CREATE TABLE lf_operation_execution_steps(execution_id text, step_id text, status text,
 evidence_ref text, evidence_payload jsonb, PRIMARY KEY(execution_id,step_id));
CREATE TABLE lf_activos(codigo_activo text,tipo_activo text,metadata jsonb,archived_at date);
INSERT INTO lf_activos VALUES('PROFILE-A','PERFIL','{"profile_slug":"pre40"}',NULL);
CREATE TABLE lf_profile_selection_registry_v1(profile_code text,descriptor_status text);
CREATE TABLE lf_profile_selector_policy_v1(profile_code text,channels text[]);
CREATE TABLE lf_skill_selector_policy_v1(profile_code text,skill_code text,selection_mode text,
 required_operation text,allowed_effects text[],enabled boolean,channels text[],
 applicability_contract jsonb,owner_decision_required boolean);
CREATE TABLE lf_skill_catalog_v1(skill_code text,status text,effect text,required_operation text,
 handler_fn text,input_required text[]);
CREATE TABLE lf_skill_selection_registry_v1(skill_code text,descriptor_status text,descriptor jsonb,
 source_revision text,source_ref text);
INSERT INTO lf_profile_selection_registry_v1 VALUES ('PROFILE-A','CURRENT');
INSERT INTO lf_profile_selector_policy_v1 VALUES ('PROFILE-A','{PRODUCTO}');
INSERT INTO lf_skill_selector_policy_v1 SELECT 'PROFILE-A',skill,'SEMANTIC_OPTIONAL','EJECUCION_PERFIL_LF',
 '{READ_ONLY}',true,'{PRODUCTO}','{}',false FROM unnest(ARRAY['A','B']) skill;
INSERT INTO lf_skill_catalog_v1 SELECT skill_code,'READY','READ_ONLY',required_operation,
 'fixture_handler','{scope}' FROM lf_skill_selector_policy_v1;
INSERT INTO lf_skill_selection_registry_v1 SELECT skill_code,'CURRENT',
 '{"schema_version":"LF_SKILL_SELECTION_DESCRIPTOR_V1"}','rev','fixture' FROM lf_skill_catalog_v1;

CREATE FUNCTION fixture_run(id text) RETURNS void LANGUAGE sql AS $$
 INSERT INTO lf_operation_execution(execution_id,operation_code,target_type,target_code,target_repo,target_path,status,manifest)
 VALUES(id,'EJECUCION_PERFIL_LF','PERFIL','PROFILE-A','fixture/lf','profiles/pre40/SKILL.md','IN_PROGRESS',
 '{"executor_mode":"GPT_NATIVE","executor_provider":"OPENAI_CHATGPT_NATIVE","read_only":true,"no_write":true,"no_promotion":true,"governed_repair_write":false,
 "router_profile_handoff":{"literal_request":"fixture","channel":"PRODUCTO","profile_code":"PROFILE-A","router_authorization_receipt":{"profile_code":"PROFILE-A","profile_execution_allowed":true,"effect_authority":false}}}');
 INSERT INTO lf_operation_execution_steps SELECT id,step,'STEP_PASS_WITH_EVIDENCE','fixture','{}'
 FROM unnest(ARRAY['stage1','stage2']) step;
$$;
CREATE FUNCTION lf_router_profile_execution_handoff_validate_v1(jsonb,text,text) RETURNS jsonb
 LANGUAGE sql AS $$ SELECT '{"valid":true}'::jsonb $$;
CREATE FUNCTION lf_profile_execution_input_validate_v1(text,text,text,jsonb) RETURNS jsonb
 LANGUAGE sql AS $$ SELECT '{"status":"READY","resolved_scope":{"target_type":"PROFILE"}}'::jsonb $$;
CREATE FUNCTION lf_profile_execution_plan_v1(text,text,jsonb) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('profile_code',$1,'operation_code','EJECUCION_PERFIL_LF','steps',jsonb_agg(i)) FROM generate_series(1,11)i $$;
CREATE FUNCTION lf_record_profile_execution_step_v1(text,text,text,jsonb,text) RETURNS jsonb LANGUAGE sql AS $$
 INSERT INTO lf_operation_execution_steps VALUES($1,$2,'STEP_PASS_WITH_EVIDENCE',$3,$4);
 SELECT '{"status":"STEP_PASS_WITH_EVIDENCE"}'::jsonb $$;
CREATE FUNCTION lf_profile_skill_reconcile_late_v1(text) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"status":"READY"}'::jsonb $$;
CREATE FUNCTION lf_profile_execution_context_admission_v1(text) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"status":"READY"}'::jsonb $$;
CREATE FUNCTION lf_profile_execution_channel_context_v1(text,jsonb,jsonb) RETURNS jsonb LANGUAGE sql AS $$ SELECT $2 $$;
CREATE FUNCTION lf_profile_execution_research_baseline_v1(text,jsonb,text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT lf_record_profile_execution_step_v1($1,'research_baseline_freeze','fixture','{}',$3);
 SELECT '{"outcome":"STEP_RECORDED"}'::jsonb $$;
CREATE FUNCTION lf_profile_policy_selection_prepare_v1(text) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"status":"READY"}'::jsonb $$;
CREATE FUNCTION lf_profile_ig_open_work_v1(text) RETURNS jsonb LANGUAGE sql AS $$ SELECT '[]'::jsonb $$;
CREATE FUNCTION lf_profile_ig_open_work_output_field_v2(text,jsonb) RETURNS text LANGUAGE sql AS $$ SELECT 'fixture'::text $$;
