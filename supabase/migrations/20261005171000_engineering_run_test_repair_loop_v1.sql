begin;

-- Guard exact live compiler/validator identities observed before authoring.
do $guard$
declare
  v_packet text;
  v_action text;
  v_validator text;
begin
  select md5(p.prosrc) into v_packet from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='programacion' and p.proname='fn_engineering_execution_packet_from_spec_v1';
  select md5(p.prosrc) into v_action from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='programacion' and p.proname='fn_engineering_checkpoint_action_spec_v3';
  select md5(p.prosrc) into v_validator from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='fn_lf_typed_evidence_payload_valid_v3';
  if v_packet is distinct from '46528d222858338f61a7bb4fda1bcae7' then raise exception 'EXECUTION_PACKET_DRIFT:%',v_packet; end if;
  if v_action is distinct from 'e02948b249d072a8284df32e224ca5e1' then raise exception 'ACTION_SPEC_V3_DRIFT:%',v_action; end if;
  if v_validator is distinct from 'dc5435dd0ffe28ac2b5a6edd575d7cb9' then raise exception 'M3_7_VALIDATOR_DRIFT:%',v_validator; end if;
end
$guard$;

create or replace function pg_temp.rep(src text,o text,n text)
returns text language plpgsql as $r$
begin
  if position(o in src)=0 then raise exception 'PATCH_ANCHOR_MISSING:%',left(o,100); end if;
  if position(o in substr(src,position(o in src)+length(o)))>0 then raise exception 'PATCH_ANCHOR_NON_UNIQUE:%',left(o,100); end if;
  return replace(src,o,n);
end
$r$;

-- 1) VERIFY remains read-only, but contradiction can open one scoped repair loop on declared targets.
do $patch_action$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='programacion' and p.proname='fn_engineering_checkpoint_action_spec_v3';
  d:=pg_temp.rep(
    d,
    $o$'mutation_policy',case when is_material then 'ONLY_DECLARED_TARGETS' else 'NO_DOMAIN_MUTATION' end,$o$,
    $n$'mutation_policy',case when is_material then 'ONLY_DECLARED_TARGETS' else 'NO_DOMAIN_MUTATION' end,
      'repair_policy',case
        when coalesce(spec->>'action_kind','')='VERIFY_QUERY_ONCE'
         and jsonb_array_length(objects)>0
         and coalesce(spec->'fallback_only_on','[]'::jsonb) ? 'CONTRADICTION'
        then jsonb_build_object(
          'on_result','CONTRADICTION',
          'mode','REPAIR_DECLARED_TARGET_THEN_RETEST',
          'mutation_scope','DECLARED_TARGETS_ONLY',
          'repair_route',jsonb_build_array('WRITE_GIT','WRITE_DB'),
          'retest_capability','RUN_TEST',
          'retest_scope','SAME_CASE_SET',
          'max_repairs',1,
          'no_new_router_capability',true
        )
        else jsonb_build_object('mode','NONE')
      end,
      'action_steps',case
        when coalesce(spec->>'action_kind','')='VERIFY_QUERY_ONCE'
         and jsonb_array_length(objects)>0
         and coalesce(spec->'fallback_only_on','[]'::jsonb) ? 'CONTRADICTION'
        then coalesce(spec->'action_steps','[]'::jsonb) || jsonb_build_array(
          'ON_CONTRADICTION_REPAIR_DECLARED_TARGET',
          'RETEST_SAME_SCOPE',
          'PERSIST_DONE_ONLY_ON_PASS'
        )
        else coalesce(spec->'action_steps','[]'::jsonb)
      end,$n$
  );
  execute d;
end
$patch_action$;

-- 2) RUN_TEST gets one canonical executor contract and a conditional repair/retest loop.
do $patch_packet$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='programacion' and p.proname='fn_engineering_execution_packet_from_spec_v1';
  d:=pg_temp.rep(
    d,
    $o$'missing_scope','MISSING_CANONICAL_TEST_EXECUTOR',$o$,
    $n$'executor','ENGINEERING_AGENT_RUN_TEST_V1',
          'case_resolution','EXACT_UNIT_CHECKPOINT_CASES_ELSE_AUTHORED_NEGATIVE',
          'case_filter',jsonb_build_object('unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code),
          'repair_loop',case
            when p_action_spec#>>'{repair_policy,mode}'='REPAIR_DECLARED_TARGET_THEN_RETEST' then jsonb_build_object(
              'enabled',true,
              'trigger','CONTRADICTION',
              'max_repairs',1,
              'declared_targets_only',true,
              'route',jsonb_build_array('WRITE_GIT','WRITE_DB','RUN_TEST'),
              'write_git_mode','MIGRATION',
              'retest_scope','SAME_CASE_SET',
              'stop_on','SECOND_FAILURE_OR_UNDECLARED_TARGET'
            ) else jsonb_build_object('enabled',false) end,$n$
  );
  execute d;
end
$patch_packet$;

-- 3) Canonical M3.7 RUN_TEST cases: control + every clause of the negative checkpoint.
insert into public.lf_test_suite_cases(
  suite_code,test_code,test_order,story_code,rule_codes,title,test_type,execution_mode,severity,
  preconditions,input_payload,expected_output,prohibited_output,status,metadata,created_by_execution_id,updated_by_execution_id
) values
('INPUT_GOVERNANCE_REGRESSION','M3_7_POSITIVE_CONTROL',370700,null,array[]::text[],'M3.7 SemanticResolution positive control','POSITIVE','AUTOMATED','HIGH','[]'::jsonb,
 '{"evidence_schema_version":"semantic-resolution/v1","final_normalized":{"subject_ref":"lf://screen/52/field/status","property_path":"status","operation":"SET","final_value_or_ref":"ACTIVE","resolution_type":"AUTHORITY_RESOLUTION","authority_refs":["supabase://authority/ref"],"evidence_refs":["supabase://evidence/ref"],"verification_status":"VERIFIED","human_required":false,"canonical_effect":{"state":"ACTIVE"}},"trace":{"research":[],"alternatives":[],"contradictions":[]}}'::jsonb,
 '{"valid":true}'::jsonb,'{}'::jsonb,'CANDIDATO',
 jsonb_build_object('unit_code','M3.7','checkpoint_code','NEGATIVE_READINESS_FIELD','executor','ENGINEERING_AGENT_RUN_TEST_V1','oracle','private.fn_lf_typed_evidence_payload_valid_v3','schema_version','semantic-resolution/v1','expected_boolean',true),'GPT-5.6-SOL-M3.7-RUNTEST-V1','GPT-5.6-SOL-M3.7-RUNTEST-V1'),
('INPUT_GOVERNANCE_REGRESSION','M3_7_REJECT_READINESS',370701,null,array[]::text[],'M3.7 rejects readiness','NEGATIVE','AUTOMATED','HIGH','[]'::jsonb,
 '{"evidence_schema_version":"semantic-resolution/v1","readiness":true,"final_normalized":{"subject_ref":"lf://screen/52/field/status","property_path":"status","operation":"SET","final_value_or_ref":"ACTIVE","resolution_type":"AUTHORITY_RESOLUTION","authority_refs":["supabase://authority/ref"],"evidence_refs":["supabase://evidence/ref"],"verification_status":"VERIFIED","human_required":false,"canonical_effect":{"state":"ACTIVE"}},"trace":{"research":[],"alternatives":[],"contradictions":[]}}'::jsonb,
 '{"valid":false}'::jsonb,'{}'::jsonb,'CANDIDATO',
 jsonb_build_object('unit_code','M3.7','checkpoint_code','NEGATIVE_READINESS_FIELD','executor','ENGINEERING_AGENT_RUN_TEST_V1','oracle','private.fn_lf_typed_evidence_payload_valid_v3','schema_version','semantic-resolution/v1','expected_boolean',false),'GPT-5.6-SOL-M3.7-RUNTEST-V1','GPT-5.6-SOL-M3.7-RUNTEST-V1'),
('INPUT_GOVERNANCE_REGRESSION','M3_7_REJECT_UNKNOWN_ROOT',370702,null,array[]::text[],'M3.7 rejects unknown root key','NEGATIVE','AUTOMATED','HIGH','[]'::jsonb,
 '{"evidence_schema_version":"semantic-resolution/v1","unexpected_root":1,"final_normalized":{"subject_ref":"lf://screen/52/field/status","property_path":"status","operation":"SET","final_value_or_ref":"ACTIVE","resolution_type":"AUTHORITY_RESOLUTION","authority_refs":["supabase://authority/ref"],"evidence_refs":["supabase://evidence/ref"],"verification_status":"VERIFIED","human_required":false,"canonical_effect":{"state":"ACTIVE"}},"trace":{"research":[],"alternatives":[],"contradictions":[]}}'::jsonb,
 '{"valid":false}'::jsonb,'{}'::jsonb,'CANDIDATO',
 jsonb_build_object('unit_code','M3.7','checkpoint_code','NEGATIVE_READINESS_FIELD','executor','ENGINEERING_AGENT_RUN_TEST_V1','oracle','private.fn_lf_typed_evidence_payload_valid_v3','schema_version','semantic-resolution/v1','expected_boolean',false),'GPT-5.6-SOL-M3.7-RUNTEST-V1','GPT-5.6-SOL-M3.7-RUNTEST-V1'),
('INPUT_GOVERNANCE_REGRESSION','M3_7_REJECT_UNKNOWN_FINAL_NORMALIZED',370703,null,array[]::text[],'M3.7 rejects unknown final_normalized key','NEGATIVE','AUTOMATED','HIGH','[]'::jsonb,
 '{"evidence_schema_version":"semantic-resolution/v1","final_normalized":{"subject_ref":"lf://screen/52/field/status","property_path":"status","operation":"SET","final_value_or_ref":"ACTIVE","resolution_type":"AUTHORITY_RESOLUTION","authority_refs":["supabase://authority/ref"],"evidence_refs":["supabase://evidence/ref"],"verification_status":"VERIFIED","human_required":false,"canonical_effect":{"state":"ACTIVE"},"unexpected_nested":1},"trace":{"research":[],"alternatives":[],"contradictions":[]}}'::jsonb,
 '{"valid":false}'::jsonb,'{}'::jsonb,'CANDIDATO',
 jsonb_build_object('unit_code','M3.7','checkpoint_code','NEGATIVE_READINESS_FIELD','executor','ENGINEERING_AGENT_RUN_TEST_V1','oracle','private.fn_lf_typed_evidence_payload_valid_v3','schema_version','semantic-resolution/v1','expected_boolean',false),'GPT-5.6-SOL-M3.7-RUNTEST-V1','GPT-5.6-SOL-M3.7-RUNTEST-V1'),
('INPUT_GOVERNANCE_REGRESSION','M3_7_REJECT_UNKNOWN_TRACE',370704,null,array[]::text[],'M3.7 rejects unknown trace key','NEGATIVE','AUTOMATED','HIGH','[]'::jsonb,
 '{"evidence_schema_version":"semantic-resolution/v1","final_normalized":{"subject_ref":"lf://screen/52/field/status","property_path":"status","operation":"SET","final_value_or_ref":"ACTIVE","resolution_type":"AUTHORITY_RESOLUTION","authority_refs":["supabase://authority/ref"],"evidence_refs":["supabase://evidence/ref"],"verification_status":"VERIFIED","human_required":false,"canonical_effect":{"state":"ACTIVE"}},"trace":{"research":[],"alternatives":[],"contradictions":[],"unexpected_nested":1}}'::jsonb,
 '{"valid":false}'::jsonb,'{}'::jsonb,'CANDIDATO',
 jsonb_build_object('unit_code','M3.7','checkpoint_code','NEGATIVE_READINESS_FIELD','executor','ENGINEERING_AGENT_RUN_TEST_V1','oracle','private.fn_lf_typed_evidence_payload_valid_v3','schema_version','semantic-resolution/v1','expected_boolean',false),'GPT-5.6-SOL-M3.7-RUNTEST-V1','GPT-5.6-SOL-M3.7-RUNTEST-V1')
on conflict (suite_code,test_code) do update set
  title=excluded.title,test_type=excluded.test_type,execution_mode=excluded.execution_mode,severity=excluded.severity,
  preconditions=excluded.preconditions,input_payload=excluded.input_payload,expected_output=excluded.expected_output,
  prohibited_output=excluded.prohibited_output,status=excluded.status,metadata=excluded.metadata,
  updated_at=now(),updated_by_execution_id=excluded.updated_by_execution_id;

-- 4) Close nested SemanticResolution objects, not only the root object.
grant lf_governance_owner_v3 to postgres with admin false, inherit false, set true granted by postgres;
grant create on schema private to lf_governance_owner_v3;
set local role lf_governance_owner_v3;

do $patch_validator$
declare d text;
begin
  select pg_get_functiondef('private.fn_lf_typed_evidence_payload_valid_v3(text,jsonb)'::regprocedure) into d;
  d:=pg_temp.rep(
    d,
    $o$and (p_payload - array['evidence_schema_version','final_normalized','trace']) = '{}'::jsonb
        and jsonb_typeof(p_payload->'final_normalized')='object'$o$,
    $n$and (p_payload - array['evidence_schema_version','final_normalized','trace']) = '{}'::jsonb
        and jsonb_typeof(p_payload->'final_normalized')='object'
        and ((p_payload->'final_normalized') - array['subject_ref','property_path','operation','final_value_or_ref','resolution_type','authority_refs','evidence_refs','verification_status','human_required','canonical_effect']) = '{}'::jsonb
        and ((p_payload->'trace') - array['research','alternatives','contradictions']) = '{}'::jsonb$n$
  );
  execute d;
end
$patch_validator$;

update private.lf_typed_evidence_schema_registry_v3
set validator_version='v3.3',
    description='SemanticResolution closed normalized final evidence; closed trace; readiness forbidden',
    registry_sha256=encode(extensions.digest(convert_to(jsonb_build_object(
      'schema_version','semantic-resolution/v1',
      'validator_version','v3.3',
      'required_keys',to_jsonb(required_keys),
      'description','SemanticResolution closed normalized final evidence; closed trace; readiness forbidden',
      'active',active
    )::text,'UTF8'),'sha256'),'hex'),
    registered_by_execution_id='ENGINEERING-RUN-TEST-REPAIR-MICROLOOP-V1'
where schema_version='semantic-resolution/v1';

reset role;
revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;

-- 5) M3.7 was closed by an incomplete negative. Reopen only checkpoint 4 + terminal with an audit row.
do $reopen$
declare
  v_work_item_id bigint;
  v_bad integer;
begin
  select work_item_id into v_work_item_id from programacion.engineering_plan_units where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M3.7';
  select count(*) into v_bad from programacion.engineering_work_checkpoints where work_item_id=v_work_item_id and checkpoint_code in ('NEGATIVE_READINESS_FIELD','TERMINAL') and status<>'DONE';
  if v_bad<>0 then raise exception 'M3_7_REOPEN_STATE_DRIFT:%',v_bad; end if;

  insert into programacion.engineering_work_updates(
    work_item_id,update_type,summary,detail,next_action,evidence_refs,reported_by,observed_at,created_by_execution_id
  ) values (
    v_work_item_id,'PROGRESS','M3.7 reopened after false closure evidence',
    'Previous negative proved readiness/root unknown only; live validator still accepted unknown nested keys in final_normalized and trace. Reopening checkpoint 4 and terminal for canonical RUN_TEST revalidation.',
    'CONTINUE_CURRENT_CHECKPOINT / NEGATIVE_READINESS_FIELD',
    jsonb_build_array('supabase://private.fn_lf_typed_evidence_payload_valid_v3 nested_unknown_final_valid=true nested_unknown_trace_valid=true'),
    'ENGINEERING-RUN-TEST-REPAIR-MICROLOOP-V1',now(),'ENGINEERING-RUN-TEST-REPAIR-MICROLOOP-V1'
  );

  update programacion.engineering_work_checkpoints
  set status='IN_PROGRESS',evidence_ref=null,completed_at=null,updated_at=now(),updated_by_execution_id='ENGINEERING-RUN-TEST-REPAIR-MICROLOOP-V1'
  where work_item_id=v_work_item_id and checkpoint_code='NEGATIVE_READINESS_FIELD';

  update programacion.engineering_work_checkpoints
  set status='PENDING',evidence_ref=null,completed_at=null,updated_at=now(),updated_by_execution_id='ENGINEERING-RUN-TEST-REPAIR-MICROLOOP-V1'
  where work_item_id=v_work_item_id and checkpoint_code='TERMINAL';

  update programacion.engineering_work_items
  set status='IN_PROGRESS',completed_at=null,started_at=coalesce(started_at,now()),updated_at=now()
  where id=v_work_item_id;
end
$reopen$;

-- 6) Record the transversal learning instead of adding more router branches.
insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,estado,lifecycle_phase,consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-RUN-TEST-REPAIR-MICROLOOP-001','ENGINEERING_GOVERNANCE',
  'RUN_TEST contradiction must repair only declared targets and retest the same scope',
  'A verification checkpoint could detect a deterministic contradiction but action_spec NO_DOMAIN_MUTATION left no executable repair path, while authored negatives could exist without a canonical case set.',
  'VERIFY and REPAIR were modeled as mutually exclusive checkpoint roles instead of phases of one bounded microloop; RUN_TEST also exposed a missing-executor placeholder.',
  'RUN_TEST fail -> CONTRADICTION -> STOP despite declared repair target',
  'Keep VERIFY read-only. If CONTRADICTION is an allowed fallback and the action spec already declares target objects, expose one repair loop using existing WRITE_GIT/WRITE_DB capabilities, then RETEST the exact same RUN_TEST case set. No fifth router capability, no undeclared target, max one repair before block.',
  'PASS when M3.7 checkpoint 4 exposes repair_policy=REPAIR_DECLARED_TARGET_THEN_RETEST, its RUN_TEST packet names ENGINEERING_AGENT_RUN_TEST_V1 with exact unit/checkpoint case resolution, repair_loop enabled, five canonical cases exist, and M3.7 is reopened to 65% until those cases pass.',
  'HIGH','ACTIVO','EXECUTION',array['IG','ENGINEERING_AGENT'],'R5_EROSION_PROCESO','PROCESS_DEPENDENT',
  'Engineering checkpoint microloop and RUN_TEST capability execution','supabase://programacion.fn_engineering_checkpoint_action_spec_v3|supabase://programacion.fn_engineering_execution_packet_from_spec_v1|supabase://public.lf_test_suite_cases/M3.7'
)
on conflict (codigo) do update set
  titulo=excluded.titulo,descripcion=excluded.descripcion,causa_raiz=excluded.causa_raiz,patron=excluded.patron,
  prevencion=excluded.prevencion,validacion=excluded.validacion,severidad=excluded.severidad,estado='ACTIVO',
  lifecycle_phase=excluded.lifecycle_phase,consumer_role=excluded.consumer_role,root_cause_family=excluded.root_cause_family,
  detectability=excluded.detectability,source_context=excluded.source_context,source_ref=excluded.source_ref,ultima_vez=now();

update public.lf_error_knowledge
set prevencion='Bootstrap execution packets route only READ, WRITE_DB, WRITE_GIT or RUN_TEST. RUN_TEST owns case selection/execution; a deterministic CONTRADICTION may invoke exactly one declared-target repair using existing WRITE_GIT/WRITE_DB then RETEST the same scope. No new router branch per casuistic.',
    validacion='PASS when pending IG checkpoints expose only the four stable capabilities, RUN_TEST has a canonical executor contract, and repairable contradictions never require a fifth capability or undeclared mutation.',
    ultima_vez=now()
where codigo='ENGINEERING-EXECUTION-PACKET-001';

-- 7) Atomic self-tests.
do $verify$
declare
  v_spec jsonb;
  v_packet jsonb;
  v_boot jsonb;
  v_count integer;
  v_membership_restored boolean;
  v_ok jsonb := '{"evidence_schema_version":"semantic-resolution/v1","final_normalized":{"subject_ref":"lf://screen/52/field/status","property_path":"status","operation":"SET","final_value_or_ref":"ACTIVE","resolution_type":"AUTHORITY_RESOLUTION","authority_refs":["supabase://authority/ref"],"evidence_refs":["supabase://evidence/ref"],"verification_status":"VERIFIED","human_required":false,"canonical_effect":{"state":"ACTIVE"}},"trace":{"research":[],"alternatives":[],"contradictions":[]}}'::jsonb;
begin
  if private.fn_lf_typed_evidence_payload_valid_v3('semantic-resolution/v1',v_ok) is not true then raise exception 'M3_7_POSITIVE_CONTROL_REJECTED'; end if;
  if private.fn_lf_typed_evidence_payload_valid_v3('semantic-resolution/v1',v_ok||'{"readiness":true}'::jsonb) is true then raise exception 'M3_7_READINESS_FALSE_PASS'; end if;
  if private.fn_lf_typed_evidence_payload_valid_v3('semantic-resolution/v1',v_ok||'{"unexpected_root":1}'::jsonb) is true then raise exception 'M3_7_ROOT_UNKNOWN_FALSE_PASS'; end if;
  if private.fn_lf_typed_evidence_payload_valid_v3('semantic-resolution/v1',jsonb_set(v_ok,'{final_normalized,unexpected_nested}','1'::jsonb,true)) is true then raise exception 'M3_7_FINAL_UNKNOWN_FALSE_PASS'; end if;
  if private.fn_lf_typed_evidence_payload_valid_v3('semantic-resolution/v1',jsonb_set(v_ok,'{trace,unexpected_nested}','1'::jsonb,true)) is true then raise exception 'M3_7_TRACE_UNKNOWN_FALSE_PASS'; end if;

  select count(*) into v_count from public.lf_test_suite_cases where metadata->>'unit_code'='M3.7' and metadata->>'checkpoint_code'='NEGATIVE_READINESS_FIELD';
  if v_count<>5 then raise exception 'M3_7_CANONICAL_CASE_COUNT:%',v_count; end if;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.7','NEGATIVE_READINESS_FIELD');
  if v_spec#>>'{repair_policy,mode}' is distinct from 'REPAIR_DECLARED_TARGET_THEN_RETEST' then raise exception 'M3_7_REPAIR_POLICY_MISSING:%',v_spec; end if;

  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1('IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.7','NEGATIVE_READINESS_FIELD',v_spec,
    jsonb_build_object('inputs',jsonb_build_object('assets','[]'::jsonb,'events','[]'::jsonb,'queries','[]'::jsonb,'artifacts','[]'::jsonb,'db_objects',jsonb_build_array('private.fn_lf_typed_evidence_payload_valid_v3')),'missing','[]'::jsonb,'missing_typed','[]'::jsonb));
  if v_packet->>'execution_capability' is distinct from 'RUN_TEST' then raise exception 'M3_7_NOT_RUN_TEST:%',v_packet; end if;
  if v_packet#>>'{connector_plan,0,executor_contract,executor}' is distinct from 'ENGINEERING_AGENT_RUN_TEST_V1' then raise exception 'M3_7_RUN_TEST_EXECUTOR_MISSING:%',v_packet; end if;
  if v_packet#>>'{connector_plan,0,executor_contract,repair_loop,enabled}' is distinct from 'true' then raise exception 'M3_7_REPAIR_LOOP_DISABLED:%',v_packet; end if;

  v_boot:=programacion.fn_engineering_unit_bootstrap_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.7');
  if v_boot#>>'{current_checkpoint,checkpoint_code}' is distinct from 'NEGATIVE_READINESS_FIELD' then raise exception 'M3_7_REOPEN_CURRENT_INVALID:%',v_boot#>>'{current_checkpoint,checkpoint_code}'; end if;
  if (v_boot#>>'{state,progress_pct}')::numeric <> 65 then raise exception 'M3_7_REOPEN_PROGRESS_INVALID:%',v_boot#>>'{state,progress_pct}'; end if;
  if v_boot#>>'{terminal_action}' is distinct from 'CONTINUE_CURRENT_CHECKPOINT' then raise exception 'M3_7_REOPEN_TERMINAL_INVALID:%',v_boot#>>'{terminal_action}'; end if;

  select count(*)=1 and bool_and(pg_get_userbyid(am.grantor)='supabase_admin' and am.admin_option and not am.inherit_option and not am.set_option)
  into v_membership_restored
  from pg_auth_members am join pg_roles granted on granted.oid=am.roleid join pg_roles member on member.oid=am.member
  where granted.rolname='lf_governance_owner_v3' and member.rolname='postgres';
  if not coalesce(v_membership_restored,false) then raise exception 'GOVERNANCE_MEMBERSHIP_NOT_RESTORED'; end if;
  if has_schema_privilege('lf_governance_owner_v3','private','CREATE') then raise exception 'GOVERNANCE_CREATE_NOT_RESTORED'; end if;
end
$verify$;

commit;
