insert into public.lf_test_suites(
  suite_code,module_code,name,version,status,rule_set_code,execution_policy,metadata,created_by_execution_id,updated_by_execution_id
) values (
  'TS-PROFILE-OP-CREATE-V1','PROFILE_GOVERNANCE','Profile Creation Operation Qualification Matrix','v1','CANDIDATO',null,
  '{"exact_revision":true,"deterministic_first":true,"false_pass_tolerance":0}'::jsonb,
  '{"matrix_family":"OPERATION_QUALIFICATION","operation_code":"CREACION_PERFIL_LF"}'::jsonb,
  'EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001'
) on conflict (suite_code) do update set
  module_code=excluded.module_code,name=excluded.name,version=excluded.version,status=excluded.status,
  execution_policy=excluded.execution_policy,metadata=excluded.metadata,updated_at=clock_timestamp(),updated_by_execution_id=excluded.updated_by_execution_id;

insert into public.lf_test_suite_cases(
  suite_code,test_code,test_order,story_code,rule_codes,title,test_type,execution_mode,severity,
  preconditions,input_payload,expected_output,prohibited_output,status,metadata,created_by_execution_id,updated_by_execution_id
) values
('TS-PROFILE-OP-CREATE-V1','P01',10,null,'{}','Operation state is catalog-bound','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"OP_REGISTRY_STATE_VALID"}','{"passed":true}','{}','CANDIDATO','{}','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001'),
('TS-PROFILE-OP-CREATE-V1','P02',20,null,'{}','Router PROFILE_CREATE is active','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"ROUTER_ACTIVE"}','{"passed":true}','{}','CANDIDATO','{}','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001'),
('TS-PROFILE-OP-CREATE-V1','P03',30,null,'{}','Active enforcement contract exists','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"ACTIVE_CONTRACT_PRESENT"}','{"passed":true}','{}','CANDIDATO','{}','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001'),
('TS-PROFILE-OP-CREATE-V1','P04',40,null,'{}','Active step contracts exist','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"ACTIVE_STEPS_PRESENT"}','{"passed":true}','{}','CANDIDATO','{}','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001'),
('TS-PROFILE-OP-CREATE-V1','P05',50,null,'{}','All active steps have active judges','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"ALL_ACTIVE_STEPS_JUDGED"}','{"passed":true}','{}','CANDIDATO','{}','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001'),
('TS-PROFILE-OP-CREATE-V1','P06',60,null,'{}','Pre-write execution binding gate is present','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"STEP_PRESENT","step_id":"pre_write_execution_binding_gate"}','{"passed":true}','{}','CANDIDATO','{}','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001'),
('TS-PROFILE-OP-CREATE-V1','P07',70,null,'{}','Pre-destination resolution gate is present','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"STEP_PRESENT","step_id":"pre_destination_resolution_gate"}','{"passed":true}','{}','CANDIDATO','{}','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001'),
('TS-PROFILE-OP-CREATE-V1','P08',80,null,'{}','GitHub write step is present','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"STEP_PRESENT","step_id":"github_write"}','{"passed":true}','{}','CANDIDATO','{}','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001'),
('TS-PROFILE-OP-CREATE-V1','P09',90,null,'{}','GitHub readback step is present','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"STEP_PRESENT","step_id":"github_readback"}','{"passed":true}','{}','CANDIDATO','{}','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001'),
('TS-PROFILE-OP-CREATE-V1','P10',100,null,'{}','Contract judge step is present','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"STEP_PRESENT","step_id":"contract_judge"}','{"passed":true}','{}','CANDIDATO','{}','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001'),
('TS-PROFILE-OP-CREATE-V1','P11',110,null,'{}','Write requires canonical execution binding','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"OP_CONTRACT_BOOL","key":"write_allowed_only_after_canonical_execution_binding","expected":true}','{"passed":true}','{}','CANDIDATO','{}','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001'),
('TS-PROFILE-OP-CREATE-V1','P12',120,null,'{}','Runtime enable is forbidden by creation contract','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"OP_CONTRACT_BOOL","key":"runtime_enable_allowed","expected":false}','{"passed":true}','{}','CANDIDATO','{}','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001'),
('TS-PROFILE-OP-CREATE-V1','P13',130,null,'{}','Qualification binding is registered','DETERMINISTIC','AUTOMATED','CRITICAL','{}','{"probe_code":"QUALIFICATION_BINDING_PRESENT"}','{"passed":true}','{}','CANDIDATO','{}','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001')
on conflict (suite_code,test_code) do update set
  test_order=excluded.test_order,title=excluded.title,test_type=excluded.test_type,execution_mode=excluded.execution_mode,severity=excluded.severity,
  preconditions=excluded.preconditions,input_payload=excluded.input_payload,expected_output=excluded.expected_output,prohibited_output=excluded.prohibited_output,
  status=excluded.status,metadata=excluded.metadata,updated_at=clock_timestamp(),updated_by_execution_id=excluded.updated_by_execution_id;

insert into public.lf_test_requirement_bindings(
  binding_code,subject_type,subject_code,characteristic_code,suite_code,required,min_pass_rate,false_pass_tolerance,
  independent_review_required,rollback_required,currentness_mode,activation_condition,effective_from,status,created_by_execution_id,updated_by_execution_id
) values (
  'BIND-OP-PROFILE-CREATE-V1','OPERATION','CREACION_PERFIL_LF',null,'TS-PROFILE-OP-CREATE-V1',true,1.0,0,false,false,
  'EXACT_REVISION','{"type":"ALWAYS"}'::jsonb,clock_timestamp(),'ACTIVE',
  'EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001'
) on conflict (binding_code) do update set
  subject_type=excluded.subject_type,subject_code=excluded.subject_code,characteristic_code=excluded.characteristic_code,suite_code=excluded.suite_code,
  required=excluded.required,min_pass_rate=excluded.min_pass_rate,false_pass_tolerance=excluded.false_pass_tolerance,
  independent_review_required=excluded.independent_review_required,rollback_required=excluded.rollback_required,currentness_mode=excluded.currentness_mode,
  activation_condition=excluded.activation_condition,effective_from=excluded.effective_from,status=excluded.status,
  updated_at=clock_timestamp(),updated_by_execution_id=excluded.updated_by_execution_id;
