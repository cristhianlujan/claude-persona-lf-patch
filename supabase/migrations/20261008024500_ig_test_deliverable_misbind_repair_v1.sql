
-- IG regression-deliverable routing repair, generic by (plan, unit, checkpoint).
-- Reuse the existing bounded-checkpoint test compiler and runner; never mutate
-- production Curator functions as a substitute for authoring regression cases.
create or replace function programacion.fn_engineering_test_deliverable_contract_repair_v1(
 p_plan_code text,p_unit_code text,p_checkpoint_code text,
 p_suite_code text,p_cases jsonb
) returns jsonb
language plpgsql volatile
set search_path to 'programacion','public','pg_catalog'
as $fn$
declare
 v_metadata jsonb;
 v_old jsonb;
 v_fixed jsonb;
 v_contract jsonb;
 v_packet jsonb;
 v_n integer;
begin
 if jsonb_typeof(p_cases)<>'array' or jsonb_array_length(p_cases)=0
    or nullif(p_suite_code,'') is null then
   raise exception 'ENGINEERING_TEST_REPAIR_TYPED_CASES_REQUIRED';
 end if;
 if exists (
   select 1 from jsonb_array_elements(p_cases) c(v)
   where nullif(c.v->>'test_code','') is null
      or nullif(c.v->>'expected_behavior','') is null
 ) then raise exception 'ENGINEERING_TEST_REPAIR_CASE_INPUT_INCOMPLETE'; end if;
 select pu.unit_metadata into v_metadata
 from programacion.engineering_plan_units pu
 join programacion.engineering_work_checkpoints c
   on c.work_item_id=pu.work_item_id and c.checkpoint_code=p_checkpoint_code
 where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code
   and pu.disposition='ASSIGNED' and c.status not in ('DONE','NOT_APPLICABLE')
 for update of pu;
 if v_metadata is null then raise exception 'ENGINEERING_TEST_REPAIR_CHECKPOINT_NOT_EDITABLE'; end if;
 v_old:=v_metadata#>array['action_specs_v1',p_checkpoint_code];
 if v_old is null or coalesce(v_old->>'contract_source','')<>'EXPLICIT_ACTION_SPEC' then
   raise exception 'ENGINEERING_TEST_REPAIR_EXPLICIT_ACTION_SPEC_REQUIRED';
 end if;
 if coalesce(v_old->>'contract_family','') not in
      ('BOUNDED_IMPLEMENTATION_AUTHORING','BOUNDED_CHECKPOINT_TEST') then
   raise exception 'ENGINEERING_TEST_REPAIR_UNSUPPORTED_CONTRACT_FAMILY:%',v_old->>'contract_family';
 end if;
 v_fixed:=programacion.fn_engineering_bounded_checkpoint_test_spec_v1(
   p_plan_code,p_unit_code,p_checkpoint_code,v_old
 );
 v_contract:=coalesce(v_fixed->'test_execution_contract','{}'::jsonb)
    ||jsonb_build_object(
     'suite_code',p_suite_code,
     'case_codes',(select jsonb_agg(c.v->>'test_code') from jsonb_array_elements(p_cases) c(v)),
     'case_contracts',p_cases,
     'required_case_count',jsonb_array_length(p_cases),
     'require_real_run_test',true,
     'candidate_catalog_is_not_pass',true,
     'source_function_mutation_allowed',false
    );
 v_fixed:=v_fixed || jsonb_build_object(
   'test_execution_contract',v_contract,
   'test_case_repair_contract',jsonb_build_object(
     'schema_version','ENGINEERING_TEST_DELIVERABLE_REPAIR_V1',
     'source','EXPLICIT_CASE_MANIFEST',
     'reused_compiler','programacion.fn_engineering_bounded_checkpoint_test_spec_v1',
     'suite_code',p_suite_code,
     'case_count',jsonb_array_length(p_cases),
     'production_functions_read_only',true,
     'no_synthetic_pass',true
   ),
   'target',(v_fixed->'target')||jsonb_build_object(
     'declared_objects',jsonb_build_array(
       'public.lf_test_suite_cases',
       'public.lf_test_suite_runs',
       'public.lf_test_runs',
       'public.lf_test_assertion_results'
     )
   ),
   'verification_queries',jsonb_build_array(
     format('select test_code,status,expected_output from public.lf_test_suite_cases where suite_code=%L and test_code=any(%L::text[])',p_suite_code,
      (select array_agg(c.v->>'test_code')::text from jsonb_array_elements(p_cases) c(v)))
   ),
   'expected','Implement exact declared scenarios as executable checkpoint tests. Only an actual PASS runner and current assertion receipt authorize DONE.'
 );
 update programacion.engineering_plan_units pu
 set unit_metadata=jsonb_set(pu.unit_metadata,array['action_specs_v1',p_checkpoint_code],v_fixed,true)
 where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code;
 -- Compile readback after update: the existing packet compiler must own
 -- WRITE_GIT -> SentinelX RUN_TEST -> assertion -> transition.
 v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
   p_plan_code,p_unit_code,p_checkpoint_code,
   programacion.fn_engineering_checkpoint_action_spec_v3(p_plan_code,p_unit_code,p_checkpoint_code),
   '{}'::jsonb
 );
 if v_packet->>'status' is distinct from 'READY'
    or v_packet->>'execution_capability' is distinct from 'RUN_TEST'
    or v_packet#>>'{connector_plan,1,provider}' is distinct from 'SENTINELX'
    or v_packet#>>'{connector_plan,1,operation}' is distinct from 'RUN_TEST'
    or v_packet#>>'{connector_plan,0,operation}' is distinct from 'WRITE_GIT' then
    raise exception 'ENGINEERING_TEST_REPAIR_PACKET_INVALID:%',v_packet->>'status';
 end if;
 return jsonb_build_object('status','REPAIRED','plan',p_plan_code,'unit',p_unit_code,
  'checkpoint',p_checkpoint_code,'suite',p_suite_code,
  'case_count',jsonb_array_length(p_cases),
  'capability',v_packet->>'execution_capability',
  'runner',v_packet#>>'{connector_plan,1,provider}');
end;
$fn$;
comment on function programacion.fn_engineering_test_deliverable_contract_repair_v1(text,text,text,text,jsonb)
is 'Generic explicit test-case checkpoint repair: reuse bounded test compiler, route test artifacts only and retain real-run evidence/merge guards.';

do $m79$
declare
 v_cases jsonb:=jsonb_build_array(
   jsonb_build_object('test_code','M7_9_REBIND_ELIGIBLE','expected_behavior','eligible rebind produces governed successor run, validator remains PENDING'),
   jsonb_build_object('test_code','M7_9_REBIND_INELIGIBLE','expected_behavior','ineligible rebind produces no new write'),
   jsonb_build_object('test_code','M7_9_REBIND_RESOLUTION_ERROR','expected_behavior','source RESOLUTION_ERROR blocks or fails closed, without promotion'),
   jsonb_build_object('test_code','M7_9_REBIND_COPY_PENDING','expected_behavior','parent assessment copy preserves data lineage and resets validator outcome to PENDING')
 );
 v_result jsonb;
begin
 v_result:=programacion.fn_engineering_test_deliverable_contract_repair_v1(
  'IG_CURATOR_VALIDATOR_REFACTOR_V2','M7.9','REBIND_CASES',
  'INPUT_GOVERNANCE_REGRESSION',v_cases
 );
 if v_result->>'status'<>'REPAIRED' or (v_result->>'case_count')::int<>4 then
   raise exception 'M7_9_TEST_CONTRACT_NOT_REPAIRED:%',v_result;
 end if;
 -- Catalog-only registration, NOT execution or PASS.
 with cases(test_code,idx,title,expectation) as (
  values
  ('M7_9_REBIND_ELIGIBLE',1,'M7.9 eligible rebind','eligible rebind produces governed successor run, validator remains PENDING'),
  ('M7_9_REBIND_INELIGIBLE',2,'M7.9 ineligible rebind','ineligible rebind produces no new write'),
  ('M7_9_REBIND_RESOLUTION_ERROR',3,'M7.9 resolution error fail closed','source RESOLUTION_ERROR blocks or fails closed, without promotion'),
  ('M7_9_REBIND_COPY_PENDING',4,'M7.9 parent copy and PENDING','parent assessment copy preserves data lineage and resets validator outcome to PENDING')
 ), fresh as (
   select cases.*,
    (select coalesce(max(c.test_order),0) from public.lf_test_suite_cases c
       where c.suite_code='INPUT_GOVERNANCE_REGRESSION')
      +row_number() over(order by idx) as test_order
   from cases where not exists(
     select 1 from public.lf_test_suite_cases c
      where c.suite_code='INPUT_GOVERNANCE_REGRESSION' and c.test_code=cases.test_code
   )
 )
 insert into public.lf_test_suite_cases
 (suite_code,test_code,test_order,title,test_type,execution_mode,severity,
 input_payload,expected_output,prohibited_output,status,metadata,created_by_execution_id)
 select 'INPUT_GOVERNANCE_REGRESSION',test_code,test_order,title,'DETERMINISTIC',
 'AUTOMATED','HIGH',
 jsonb_build_object('scenario',test_code,'canonical_unit','M7.9','mutating_fixture','ROLLBACK_ONLY'),
 jsonb_build_object('behavior',expectation,'validated',false),
 jsonb_build_object('synthetic_pass',true,'unexpected_production_write',true),
 'CANDIDATO',
 jsonb_build_object('test_path','sandbox/lf_contract_gate_test/engineering_checkpoints/m7_9/rebind_cases.py',
 'requires_real_execution',true,'candidate_not_pass',true,'checkpoint','REBIND_CASES',
 'test_contract','ENGINEERING_TEST_DELIVERABLE_REPAIR_V1'),
 'IG_M7_9_CONTRACT_REPAIR'
 from fresh;
 if (select count(*) from public.lf_test_suite_cases
    where suite_code='INPUT_GOVERNANCE_REGRESSION'
      and test_code in ('M7_9_REBIND_ELIGIBLE','M7_9_REBIND_INELIGIBLE',
                        'M7_9_REBIND_RESOLUTION_ERROR','M7_9_REBIND_COPY_PENDING'))<>4 then
   raise exception 'M7_9_TEST_CASE_REGISTRATION_INCOMPLETE';
 end if;
end;
$m79$;
