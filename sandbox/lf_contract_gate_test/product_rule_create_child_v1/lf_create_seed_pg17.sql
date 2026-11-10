-- LF #3774: isolated synthetic candidate only. Inherits verified update/link fixtures.
CREATE UNIQUE INDEX IF NOT EXISTS lf_rule_create_unique_code_pg17 ON lf_ops.reglas(codigo);
INSERT INTO public.lf_task_mode_catalog(task_mode,status,description) VALUES ('CREATE_NEW','ACTIVE','synthetic');
INSERT INTO public.lf_operation_mode_bindings(operation_code,task_mode,execution_mode,allowed,write_allowed,destination_kind,input_completeness,status)
VALUES('CREACION_REGLA_LF','CREATE_NEW','GOVERNED',true,true,'CANONICAL_CANDIDATE','COMPLETE_REQUIRED','ACTIVE');
INSERT INTO public.lf_operation_registry(operation_code,version,status,source_model,source_repo,source_paths,operation_family,operation_domain,operation_type,applies_to_asset_type,lifecycle_state_code)
VALUES('CREACION_REGLA_LF','v0.1','SANDBOX_ACTIVE','ISOLATED_PG17','cristhianlujan/claude-persona-lf-patch','[]'::jsonb,'RULE_OPERATIONS','RULE_GOVERNANCE','CREATE_PROTOCOL','REGLA','OP_CANDIDATE');
INSERT INTO public.lf_operation_contracts(operation_code,contract_code,status)
VALUES('CREACION_REGLA_LF','CONTRACT-CREACION_REGLA_LF-v0.1','ACTIVE_ENFORCEMENT');
INSERT INTO public.lf_profile_write_authority_v1(profile_code,operation_code,status)
VALUES('PERFIL-PRODUCT-DIRECTOR-LF','CREACION_REGLA_LF','ACTIVE');
INSERT INTO public.lf_skill_catalog_v1(skill_code,description,required_operation,handler_fn,effect,input_required,status,opener_fn)
VALUES('RULE_CREATE_APPLY','synthetic create','CREACION_REGLA_LF','lf_skill_h_rule_create_propose_v1','WRITE_GOVERNED',ARRAY['regla_codigo'],'READY',NULL);
WITH s(o,id,keys) AS (
 VALUES
 (10,'ekb_preflight','["ekb_refs","execution_binding"]'::jsonb),
 (20,'classify','["rule_code","category","candidate_classification"]'::jsonb),
 (30,'existing_check','["rule_code","existing_count","expected_existence"]'::jsonb),
 (40,'destination_validate','["destination_schema","destination_table","unique_code_guard"]'::jsonb),
 (50,'candidate_write','["execution_id","rule_code","write_result","estado"]'::jsonb),
 (60,'readback','["rule_code","readback_row","estado"]'::jsonb),
 (70,'trace_close','["execution_id","operation_code","trace_ref","no_promotion"]'::jsonb)
)
INSERT INTO public.lf_operation_steps
 (operation_code,step_order,step_id,required,evidence_required,source_path,active,execution_order)
 SELECT 'CREACION_REGLA_LF',o,id,true,keys::text,'source-fixture',true,o FROM s;
INSERT INTO public.lf_operation_judges
 (operation_code,judge_code,judge_path,pass_if,fail_if,result_values,status)
 VALUES('CREACION_REGLA_LF','MINI_JUDGE_CREACION_REGLA_LF_V1',
  'source-fixture','{"required_evidence_present":true}'::jsonb,
  '{"missing_required_evidence":true}'::jsonb,
  '["PASS_CLEAN","BLOCKED_BY_ENFORCEMENT","RETURN_TO_WORKER"]'::jsonb,
  'ACTIVE_ENFORCEMENT');
WITH s(o,id,keys,next) AS (
 VALUES
 (10,'ekb_preflight','["ekb_refs","execution_binding"]'::jsonb,'classify'),
 (20,'classify','["rule_code","category","candidate_classification"]'::jsonb,'existing_check'),
 (30,'existing_check','["rule_code","existing_count","expected_existence"]'::jsonb,'destination_validate'),
 (40,'destination_validate','["destination_schema","destination_table","unique_code_guard"]'::jsonb,'candidate_write'),
 (50,'candidate_write','["execution_id","rule_code","write_result","estado"]'::jsonb,'readback'),
 (60,'readback','["rule_code","readback_row","estado"]'::jsonb,'trace_close'),
 (70,'trace_close','["execution_id","operation_code","trace_ref","no_promotion"]'::jsonb,NULL::text)
)
INSERT INTO public.lf_operation_step_contracts
 (operation_code,step_id,step_order,execution_order,contract_code,purpose,
  input_required,resolver_ref,output_payload,pass_condition,block_condition,
  blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,
  next_if_blocked,status)
 SELECT 'CREACION_REGLA_LF',id,o,o,'CONTRACT-CREACION_REGLA_LF-v0.1',
  'Isolated source-equivalent', '{}'::jsonb,'RULE_OPERATION_DETERMINISTIC',
  keys,'{"required_evidence_present":true}'::jsonb,
  '{"missing_required_evidence":true}'::jsonb,
  'BLOCK_RULE_CHILD','MINI_JUDGE_CREACION_REGLA_LF_V1',keys,
  next,'trace_close','ACTIVE_ENFORCEMENT' FROM s;
WITH s(o,id,keys) AS (
 VALUES
 (10,'ekb_preflight','["ekb_refs","execution_binding"]'::jsonb),
 (20,'classify','["rule_code","category","candidate_classification"]'::jsonb),
 (30,'existing_check','["rule_code","existing_count","expected_existence"]'::jsonb),
 (40,'destination_validate','["destination_schema","destination_table","unique_code_guard"]'::jsonb),
 (50,'candidate_write','["execution_id","rule_code","write_result","estado"]'::jsonb),
 (60,'readback','["rule_code","readback_row","estado"]'::jsonb),
 (70,'trace_close','["execution_id","operation_code","trace_ref","no_promotion"]'::jsonb)
)
INSERT INTO public.lf_operation_step_judge_bindings
 (operation_code,step_order,step_id,judge_code,clean_result_value,
  blocked_result_value,return_result_value,required_evidence_keys,status)
 SELECT 'CREACION_REGLA_LF',o,id,
 'MINI_JUDGE_CREACION_REGLA_LF_V1',
 'PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER',keys,'ACTIVE_ENFORCEMENT' FROM s;

INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,request_sha256,manifest,created_by_execution_id)
VALUES('EXEC-PROFILE-GATE2-PG17RULECREATE01','EJECUCION_PERFIL_LF','PERFIL','PERFIL-PRODUCT-DIRECTOR-LF','IN_PROGRESS',repeat('f',64),
'{"read_only":true,"no_write":true,"no_promotion":true,"router_profile_handoff":{"router_authorization_receipt":{"profile_execution_allowed":true}},"screen_selection_result":{"selected_screen_code":"B2B-AUTH-001"}}'::jsonb,'ISOLATED_PG17');
INSERT INTO public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload)
VALUES
('EXEC-PROFILE-GATE2-PG17RULECREATE01',50,'execute_profile','STEP_PASS_WITH_EVIDENCE','SYNTHETIC/50','{"profile_output":{"worker":"product_director_lf","output_type":"PRODUCT_DIRECTION_SPEC","self_verdict":"PASS","deliverable_created":{"authority_status":"SUPPORTED","product_decision":{"decision_id":"PG17-CREATE-001","source_refs":[{"source_ref":"supabase://public.lf_decisiones_gov/101","authority":"AUTHORITATIVE","current":true,"supports":"synthetic approval"},{"source_ref":"supabase://lf_ops.pantallas/51","authority":"CONSTRAINT","current":true,"supports":"selected synthetic screen"}]},"governed_rule_create":{"change_kind":"CREATE_CANDIDATE","rule_code":"TEST-RULE-CREATE-001","category":"AUTH","title":"Control aprobado de acceso","description":"Control funcional aprobado en fuente de decisión sintética","reason":"Materializar definición validada sin promoción","config":{"test":true,"max_retries":0},"transversal":false,"source_decision_ref":"supabase://public.lf_decisiones_gov/101","screen_code":"B2B-AUTH-001"}}}}'::jsonb),
('EXEC-PROFILE-GATE2-PG17RULECREATE01',60,'output_validate','STEP_PASS_WITH_EVIDENCE','SYNTHETIC/60','{"output_contract_result":"PASS","raw_output_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb),
('EXEC-PROFILE-GATE2-PG17RULECREATE01',70,'semantic_judge','STEP_PASS_WITH_EVIDENCE','SYNTHETIC/70','{"unsupported_claims":[],"blocking_codes":[],"semantic_judge_result":{"status":"PASS","verdict":"PASS_REVIEWED_CURRENT_CONTEXT","candidate_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","result":{"unsupported_claims":[],"blocking_codes":[]}}}'::jsonb);
