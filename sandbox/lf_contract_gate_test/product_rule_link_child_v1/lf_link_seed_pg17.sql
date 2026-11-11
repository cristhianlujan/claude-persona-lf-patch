-- LF #3774: synthetic PG17 isolated-only seed after original fixture, update seed,
-- migrations 20261109092529 and 20261109093901 and frozen link handler.
-- Does not contain real customer data or production credentials.
CREATE TABLE public.lf_operation_contracts (
  operation_code text, contract_code text, status text
);
INSERT INTO public.lf_operation_contracts VALUES
 ('VINCULACION_REGLA_PANTALLA_LF',
  'CONTRACT-VINCULACION-REGLA-PANTALLA-LF-v1.1.0','ACTIVE_ENFORCEMENT');

CREATE UNIQUE INDEX lf_link_fixture_unique_pair
 ON lf_ops.reglas_pantallas(regla_id,pantalla_id);

INSERT INTO public.lf_operation_registry(
 operation_code,version,status,source_model,source_repo,source_paths,
 operation_family,operation_domain,operation_type,applies_to_asset_type,lifecycle_state_code
) VALUES ('VINCULACION_REGLA_PANTALLA_LF','v1.1.0','PRODUCCION_CONTROLADA',
 'ISOLATED_PG17','cristhianlujan/claude-persona-lf-patch','[]'::jsonb,
 'RULE_OPERATIONS','RULE_GOVERNANCE','INSERT_RELATION','REGLA_PANTALLA_RELATION','OP_OPERATIONAL');

INSERT INTO public.lf_profile_write_authority_v1(profile_code,operation_code,status)
VALUES('PERFIL-PRODUCT-DIRECTOR-LF','VINCULACION_REGLA_PANTALLA_LF','ACTIVE');

INSERT INTO public.lf_skill_catalog_v1(
  skill_code,description,required_operation,handler_fn,effect,input_required,status,opener_fn
) VALUES('RULE_LINK_APPLY','PG17 isolated link',
 'VINCULACION_REGLA_PANTALLA_LF','lf_skill_h_rule_link_propose_v1',
 'WRITE_GOVERNED',
 ARRAY['regla_codigo','pantalla_id','target_type','target_code'],
 'READY',NULL);

WITH v(step_order,step_id,keys) AS (VALUES
 (10,'preflight','["ekb_refs","execution_binding"]'::jsonb),
 (20,'resolve_rule','["rule_code","rule_id","rule_state"]'::jsonb),
 (30,'resolve_screen','["pantalla_id","screen_code","screen_active"]'::jsonb),
 (40,'relation_write','["rule_id","pantalla_id","write_result"]'::jsonb),
 (50,'readback','["relation_row","rule_unchanged","screen_unchanged","no_delete"]'::jsonb))
INSERT INTO public.lf_operation_steps(
  operation_code,step_order,step_id,required,evidence_required,source_path,active,execution_order
)
SELECT 'VINCULACION_REGLA_PANTALLA_LF',step_order,step_id,true,keys::text,
 'supabase://public/lf_operation_steps/'||step_id,true,step_order FROM v;

INSERT INTO public.lf_operation_judges(
  operation_code,judge_code,judge_path,pass_if,fail_if,result_values,status
) VALUES(
 'VINCULACION_REGLA_PANTALLA_LF','MINI_JUDGE_VINCULACION_REGLA_PANTALLA_LF_V1',
 'supabase://public/lf_operation_judges/MINI_JUDGE_VINCULACION_REGLA_PANTALLA_LF_V1',
 '{"required_evidence_present":true}'::jsonb,'{"missing_required_evidence":true}'::jsonb,
 '["PASS_CLEAN","BLOCKED_BY_ENFORCEMENT","RETURN_TO_WORKER"]'::jsonb,
 'ACTIVE_ENFORCEMENT');

WITH v(step_order,step_id,keys,next_step) AS (VALUES
 (10,'preflight','["ekb_refs","execution_binding"]'::jsonb,'resolve_rule'),
 (20,'resolve_rule','["rule_code","rule_id","rule_state"]'::jsonb,'resolve_screen'),
 (30,'resolve_screen','["pantalla_id","screen_code","screen_active"]'::jsonb,'relation_write'),
 (40,'relation_write','["rule_id","pantalla_id","write_result"]'::jsonb,'readback'),
 (50,'readback','["relation_row","rule_unchanged","screen_unchanged","no_delete"]'::jsonb,NULL::text))
INSERT INTO public.lf_operation_step_contracts(
  operation_code,step_id,step_order,execution_order,contract_code,purpose,
  input_required,resolver_ref,output_payload,pass_condition,block_condition,
  blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,status
)
SELECT 'VINCULACION_REGLA_PANTALLA_LF',step_id,step_order,step_order,
 'CONTRACT-VINCULACION-REGLA-PANTALLA-LF-v1.1.0',
 'PG17 source-equivalent link step',
 '{}'::jsonb,'RULE_SCREEN_RELATION_DETERMINISTIC',keys,
 '{"required_evidence_present":true}'::jsonb,
 '{"missing_required_evidence":true}'::jsonb,
 'BLOCK_RULE_LINK_PG17','MINI_JUDGE_VINCULACION_REGLA_PANTALLA_LF_V1',
 keys,next_step,'readback','ACTIVE_ENFORCEMENT' FROM v;

WITH v(step_order,step_id,keys) AS (VALUES
 (10,'preflight','["ekb_refs","execution_binding"]'::jsonb),
 (20,'resolve_rule','["rule_code","rule_id","rule_state"]'::jsonb),
 (30,'resolve_screen','["pantalla_id","screen_code","screen_active"]'::jsonb),
 (40,'relation_write','["rule_id","pantalla_id","write_result"]'::jsonb),
 (50,'readback','["relation_row","rule_unchanged","screen_unchanged","no_delete"]'::jsonb))
INSERT INTO public.lf_operation_step_judge_bindings(
 operation_code,step_order,step_id,judge_code,clean_result_value,
 blocked_result_value,return_result_value,required_evidence_keys,status
)
SELECT 'VINCULACION_REGLA_PANTALLA_LF',step_order,step_id,
 'MINI_JUDGE_VINCULACION_REGLA_PANTALLA_LF_V1',
 'PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER',keys,'ACTIVE_ENFORCEMENT' FROM v;

INSERT INTO lf_ops.reglas(
  id,codigo,categoria,titulo,descripcion,razon,valor_config,es_transversal,
  estado,origen,pendiente_decision,created_by
) VALUES(436,'TEST-RULE-LINK-001','AUTH','Regla vigente aprobada de login',
 'Regla de prueba vigente aprobada para asociación',
 'Demostración de vinculación de reglas aprobadas','{"approved":true}'::jsonb,
 false,'VIGENTE','PG17_TEST_AUTHORITY',false,'TEST_FIXTURE');

INSERT INTO public.lf_operation_execution(
 execution_id,operation_code,target_type,target_code,status,request_sha256,
 manifest,created_by_execution_id
) VALUES('EXEC-PROFILE-GATE2-PG17RULELINK01','EJECUCION_PERFIL_LF',
 'PERFIL','PERFIL-PRODUCT-DIRECTOR-LF','IN_PROGRESS',repeat('f',64),
 '{
  "read_only":true,"no_write":true,"no_promotion":true,
  "router_profile_handoff":{"router_authorization_receipt":{"profile_execution_allowed":true}},
  "screen_selection_result":{"selected_screen_code":"B2B-AUTH-001"}
 }'::jsonb,'ISOLATED_PG17');

-- RAW and judge are deliberately synthetic enforcement fixtures, never
-- evidence that a real model called/decided or that IG approved production.
INSERT INTO public.lf_operation_execution_steps(
  execution_id,step_order,step_id,status,evidence_ref,evidence_payload
) VALUES
('EXEC-PROFILE-GATE2-PG17RULELINK01',50,'execute_profile','STEP_PASS_WITH_EVIDENCE',
 'ISOLATED_LINK_PARENT/50',
 '{
   "profile_output":{
     "worker":"product_director_lf",
     "output_type":"PRODUCT_DIRECTION_SPEC",
     "self_verdict":"PASS",
     "deliverable_created":{
       "authority_status":"SUPPORTED",
       "product_decision":{
         "decision_id":"PG17-LINK-001",
         "source_refs":[
           {"source_ref":"supabase://lf_ops.reglas/TEST-RULE-LINK-001","authority":"AUTHORITATIVE","current":true,"supports":"approved fixture rule"},
           {"source_ref":"supabase://lf_ops.pantallas/51","authority":"AUTHORITATIVE","current":true,"supports":"selected fixture screen"}
         ]
       },
       "governed_rule_link":{"change_kind":"LINK_EXISTING_RULE","rule_code":"TEST-RULE-LINK-001","screen_code":"B2B-AUTH-001"}
     }
   }
 }'::jsonb),
('EXEC-PROFILE-GATE2-PG17RULELINK01',60,'output_validate','STEP_PASS_WITH_EVIDENCE',
 'ISOLATED_LINK_PARENT/60',
 '{"output_contract_result":"PASS","raw_output_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'::jsonb),
('EXEC-PROFILE-GATE2-PG17RULELINK01',70,'semantic_judge','STEP_PASS_WITH_EVIDENCE',
 'ISOLATED_LINK_PARENT/70',
 '{"unsupported_claims":[],"blocking_codes":[],
   "semantic_judge_result":{"status":"PASS","verdict":"PASS_REVIEWED_CURRENT_CONTEXT",
     "candidate_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
     "result":{"unsupported_claims":[],"blocking_codes":[]}}
 }'::jsonb);
