-- Synthetic test records only. Real Supabase functions/schema loaded separately.
INSERT INTO public.lf_task_mode_catalog(task_mode,status,description)
 VALUES ('REMEDIATE_EXISTING','ACTIVE','test');
INSERT INTO public.lf_execution_mode_catalog
 (execution_mode,status,description,allows_partial_input,canonical_write_allowed,
  runtime_allowed,promotion_allowed,requires_evidence_complete,reference_source)
 VALUES('GOVERNED','ACTIVE','test',false,true,false,false,true,'ISOLATED_PG17');
INSERT INTO public.lf_operation_mode_bindings
 (operation_code,task_mode,execution_mode,allowed,write_allowed,
  destination_kind,input_completeness,status)
 VALUES('ACTUALIZACION_REGLA_LF','REMEDIATE_EXISTING','GOVERNED',true,true,
  'CANONICAL_CANDIDATE','COMPLETE_REQUIRED','ACTIVE');
INSERT INTO public.lf_operation_registry
 (operation_code,version,status,source_model,source_repo,source_paths,
  operation_family,operation_domain,operation_type,applies_to_asset_type,lifecycle_state_code)
 VALUES('ACTUALIZACION_REGLA_LF','v0.1','SANDBOX_ACTIVE','ISOLATED_SOURCE',
  'cristhianlujan/claude-persona-lf-patch','[]'::jsonb,
  'RULE_OPERATIONS','RULE_GOVERNANCE','UPDATE_PROTOCOL','REGLA','CANDIDATO');
INSERT INTO public.lf_skill_catalog_v1
 (skill_code,description,required_operation,handler_fn,effect,input_required,status,opener_fn)
 VALUES('RULE_UPDATE_APPLY','Existing child opener test',
  'ACTUALIZACION_REGLA_LF','lf_skill_h_rule_update_propose_v1','WRITE_GOVERNED',
  ARRAY['regla_codigo','analysis_snapshot_sha256'],'READY',NULL);
INSERT INTO public.lf_profile_write_authority_v1(profile_code,operation_code,status)
 VALUES('PERFIL-PRODUCT-DIRECTOR-LF','ACTUALIZACION_REGLA_LF','ACTIVE');
INSERT INTO lf_ops.pantallas(id,codigo,nombre,estado,activa,version)
 VALUES(51,'B2B-AUTH-001','Login test','CANDIDATO',true,'v1');
INSERT INTO lf_ops.reglas
 (id,codigo,categoria,titulo,descripcion,razon,valor_config,es_transversal,
  estado,origen,pendiente_decision,pendiente_detalle,created_by)
 VALUES(435,'TEST-RULE-DOC-001','UX','Titulo original de pantalla',
  'Descripcion original validada','Razon original suficiente',
  '{"existing":true}'::jsonb,false,'CANDIDATO','ISOLATED_PG17',true,
  'PENDING_REVIEW','TEST_FIXTURE');
INSERT INTO lf_ops.reglas_pantallas(id,regla_id,pantalla_id,nota)
 VALUES(1,435,51,'sandbox');
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
 SELECT 'ACTUALIZACION_REGLA_LF',o,id,true,keys::text,'source-fixture',true,o FROM s;
INSERT INTO public.lf_operation_judges
 (operation_code,judge_code,judge_path,pass_if,fail_if,result_values,status)
 VALUES('ACTUALIZACION_REGLA_LF','MINI_JUDGE_ACTUALIZACION_REGLA_LF_V1',
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
 SELECT 'ACTUALIZACION_REGLA_LF',id,o,o,'CONTRACT-ACTUALIZACION_REGLA_LF-v0.1',
  'Isolated source-equivalent', '{}'::jsonb,'RULE_OPERATION_DETERMINISTIC',
  keys,'{"required_evidence_present":true}'::jsonb,
  '{"missing_required_evidence":true}'::jsonb,
  'BLOCK_RULE_CHILD','MINI_JUDGE_ACTUALIZACION_REGLA_LF_V1',keys,
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
 SELECT 'ACTUALIZACION_REGLA_LF',o,id,
 'MINI_JUDGE_ACTUALIZACION_REGLA_LF_V1',
 'PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER',keys,'ACTIVE_ENFORCEMENT' FROM s;
INSERT INTO public.lf_operation_execution
 (execution_id,operation_code,target_type,target_code,manifest,status,request_sha256,created_by_execution_id)
 VALUES('EXEC-PROFILE-GATE2-PG17RULECHILD001','EJECUCION_PERFIL_LF',
  'PERFIL','PERFIL-PRODUCT-DIRECTOR-LF',
 '{"read_only":true,"no_write":true,"no_promotion":true,
   "router_profile_handoff":{"router_authorization_receipt":{"profile_execution_allowed":true}},
   "screen_selection_result":{"selected_screen_code":"B2B-AUTH-001"}}'::jsonb,
 'IN_PROGRESS',repeat('f',64),'SYNTHETIC_SOURCE');
INSERT INTO public.lf_operation_execution_steps
(execution_id,step_order,step_id,status,evidence_ref,evidence_payload)
VALUES
('EXEC-PROFILE-GATE2-PG17RULECHILD001',50,'execute_profile','STEP_PASS_WITH_EVIDENCE',
 'ISOLATED_PG17/50',
 '{"profile_output":{
   "worker":"product_director_lf","output_type":"PRODUCT_DIRECTION_SPEC","self_verdict":"PASS",
   "deliverable_created":{
     "authority_status":"SUPPORTED",
     "product_decision":{"decision_id":"PG17-DOC-001",
       "source_refs":[{"authority":"AUTHORITATIVE","current":true,
         "source_ref":"supabase://lf_ops.reglas/TEST-RULE-DOC-001"}]},
     "governed_rule_patch":{"rule_code":"TEST-RULE-DOC-001",
       "change_kind":"DOCUMENTARY_ONLY",
       "changes":{"descripcion":"Descripcion corregida documentada y autorizada por el perfil"}}
   }
 }}'::jsonb),
('EXEC-PROFILE-GATE2-PG17RULECHILD001',60,'output_validate','STEP_PASS_WITH_EVIDENCE',
 'ISOLATED_PG17/60',
 '{"output_contract_result":"PASS"}'::jsonb),
('EXEC-PROFILE-GATE2-PG17RULECHILD001',70,'semantic_judge','STEP_PASS_WITH_EVIDENCE',
 'ISOLATED_PG17/70',
 '{"semantic_judge_result":{"verdict":"PASS_REVIEWED_CURRENT_CONTEXT"},
   "blocking_codes":[]}'::jsonb);
