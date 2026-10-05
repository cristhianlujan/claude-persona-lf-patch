begin;

-- Transversal repair: keep VERIFY read-only; allow exactly one declared-target
-- repair on deterministic CONTRADICTION, then RETEST the same RUN_TEST scope.
-- The typed-evidence registry is append-only, so this migration does NOT update it.

do $guard$
declare
  v_packet text;
  v_action text;
  v_validator text;
begin
  select md5(p.prosrc) into v_packet
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_engineering_execution_packet_from_spec_v1';

  select md5(p.prosrc) into v_action
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_engineering_checkpoint_action_spec_v3';

  select md5(p.prosrc) into v_validator
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='fn_lf_typed_evidence_payload_valid_v3';

  if v_packet is distinct from '46528d222858338f61a7bb4fda1bcae7' then
    raise exception 'EXECUTION_PACKET_DRIFT:%',v_packet;
  end if;
  if v_action is distinct from 'e02948b249d072a8284df32e224ca5e1' then
    raise exception 'ACTION_SPEC_V3_DRIFT:%',v_action;
  end if;
  if v_validator is distinct from 'dc5435dd0ffe28ac2b5a6edd575d7cb9' then
    raise exception 'M3_7_VALIDATOR_DRIFT:%',v_validator;
  end if;

  if not exists (
    select 1
    from private.lf_typed_evidence_schema_registry_v3
    where schema_version='semantic-resolution/v1'
      and validator_version='v3.2'
      and active
      and required_keys=array['evidence_schema_version','final_normalized','trace']::text[]
  ) then
    raise exception 'M3_7_APPEND_ONLY_REGISTRY_BASELINE_DRIFT';
  end if;
end
$guard$;

create or replace function pg_temp.rep(src text,o text,n text)
returns text
language plpgsql
as $r$
begin
  if position(o in src)=0 then
    raise exception 'PATCH_ANCHOR_MISSING:%',left(o,100);
  end if;
  if position(o in substr(src,position(o in src)+length(o)))>0 then
    raise exception 'PATCH_ANCHOR_NON_UNIQUE:%',left(o,100);
  end if;
  return replace(src,o,n);
end
$r$;

-- 1) Action spec: verification remains non-mutating. CONTRADICTION opens one
-- bounded repair sub-loop only when a target was already declared.
do $patch_action$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_engineering_checkpoint_action_spec_v3';

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

-- 2) RUN_TEST: name the capability executor, resolve exact unit/checkpoint
-- cases first, and expose the bounded repair/retest contract.
do $patch_packet$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_engineering_execution_packet_from_spec_v1';

  d:=pg_temp.rep(
    d,
    $o$'missing_scope','MISSING_CANONICAL_TEST_EXECUTOR',$o$,
    $n$'executor','ENGINEERING_AGENT_RUN_TEST_V1',
          'case_resolution','EXACT_UNIT_CHECKPOINT_CASES_ELSE_AUTHORED_NEGATIVE',
          'case_filter',jsonb_build_object('unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code),
          'repair_loop',case
            when p_action_spec#>>'{repair_policy,mode}'='REPAIR_DECLARED_TARGET_THEN_RETEST'
            then jsonb_build_object(
              'enabled',true,
              'trigger','CONTRADICTION',
              'max_repairs',1,
              'declared_targets_only',true,
              'route',jsonb_build_array('WRITE_GIT','WRITE_DB','RUN_TEST'),
              'write_git_mode','MIGRATION',
              'retest_scope','SAME_CASE_SET',
              'stop_on','SECOND_FAILURE_OR_UNDECLARED_TARGET'
            )
            else jsonb_build_object('enabled',false)
          end,$n$
  );
  execute d;
end
$patch_packet$;

-- 3) Canonical M3.7 RUN_TEST case set.
with base as (
  select jsonb_build_object(
    'evidence_schema_version','semantic-resolution/v1',
    'final_normalized',jsonb_build_object(
      'subject_ref','lf://screen/52/field/status',
      'property_path','status',
      'operation','SET',
      'final_value_or_ref','ACTIVE',
      'resolution_type','AUTHORITY_RESOLUTION',
      'authority_refs',jsonb_build_array('supabase://authority/ref'),
      'evidence_refs',jsonb_build_array('supabase://evidence/ref'),
      'verification_status','VERIFIED',
      'human_required',false,
      'canonical_effect',jsonb_build_object('state','ACTIVE')
    ),
    'trace',jsonb_build_object(
      'research','[]'::jsonb,
      'alternatives','[]'::jsonb,
      'contradictions','[]'::jsonb
    )
  ) p
), cases as (
  select 'M3_7_POSITIVE_CONTROL'::text test_code,370700 test_order,'M3.7 SemanticResolution positive control'::text title,'POSITIVE'::text test_type,p input_payload,true expected_boolean from base
  union all
  select 'M3_7_REJECT_READINESS',370701,'M3.7 rejects readiness','NEGATIVE',p||'{"readiness":true}'::jsonb,false from base
  union all
  select 'M3_7_REJECT_UNKNOWN_ROOT',370702,'M3.7 rejects unknown root key','NEGATIVE',p||'{"unexpected_root":1}'::jsonb,false from base
  union all
  select 'M3_7_REJECT_UNKNOWN_FINAL_NORMALIZED',370703,'M3.7 rejects unknown final_normalized key','NEGATIVE',jsonb_set(p,'{final_normalized,unexpected_nested}','1'::jsonb,true),false from base
  union all
  select 'M3_7_REJECT_UNKNOWN_TRACE',370704,'M3.7 rejects unknown trace key','NEGATIVE',jsonb_set(p,'{trace,unexpected_nested}','1'::jsonb,true),false from base
)
insert into public.lf_test_suite_cases(
  suite_code,test_code,test_order,story_code,rule_codes,title,test_type,
  execution_mode,severity,preconditions,input_payload,expected_output,
  prohibited_output,status,metadata,created_by_execution_id,updated_by_execution_id
)
select
  'INPUT_GOVERNANCE_REGRESSION',c.test_code,c.test_order,null,array[]::text[],c.title,c.test_type,
  'AUTOMATED','HIGH','{}'::jsonb,c.input_payload,jsonb_build_object('valid',c.expected_boolean),
  '{}'::jsonb,'CANDIDATO',
  jsonb_build_object(
    'unit_code','M3.7',
    'checkpoint_code','NEGATIVE_READINESS_FIELD',
    'executor','ENGINEERING_AGENT_RUN_TEST_V1',
    'oracle','private.fn_lf_typed_evidence_payload_valid_v3',
    'schema_version','semantic-resolution/v1',
    'expected_boolean',c.expected_boolean
  ),
  'GPT-5.6-SOL-M3.7-RUNTEST-V1','GPT-5.6-SOL-M3.7-RUNTEST-V1'
from cases c
on conflict (suite_code,test_code) do update set
  title=excluded.title,
  test_type=excluded.test_type,
  execution_mode=excluded.execution_mode,
  severity=excluded.severity,
  preconditions=excluded.preconditions,
  input_payload=excluded.input_payload,
  expected_output=excluded.expected_output,
  prohibited_output=excluded.prohibited_output,
  status=excluded.status,
  metadata=excluded.metadata,
  updated_at=now(),
  updated_by_execution_id=excluded.updated_by_execution_id;

-- 4) Repair only the declared M3.7 validator target. The schema registry row
-- stays immutable at its original registration; its validator_version is not
-- consumed by live execution and is therefore historical metadata.
grant lf_governance_owner_v3 to postgres
  with admin false, inherit false, set true
  granted by postgres;
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

reset role;
revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;

-- 5) Reopen only the checkpoint that was closed by incomplete evidence and its
-- terminal checkpoint. Preserve the completed first three checkpoints.
do $reopen$
declare
  v_work_item_id bigint;
  v_bad integer;
begin
  select work_item_id into v_work_item_id
  from programacion.engineering_plan_units
  where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M3.7';

  if v_work_item_id is null then raise exception 'M3_7_WORK_ITEM_MISSING'; end if;

  select count(*) into v_bad
  from programacion.engineering_work_checkpoints
  where work_item_id=v_work_item_id
    and checkpoint_code in ('NEGATIVE_READINESS_FIELD','TERMINAL')
    and status<>'DONE';
  if v_bad<>0 then raise exception 'M3_7_REOPEN_STATE_DRIFT:%',v_bad; end if;

  insert into programacion.engineering_work_updates(
    work_item_id,update_type,summary,detail,next_action,evidence_refs,
    reported_by,observed_at,created_by_execution_id
  ) values (
    v_work_item_id,'PROGRESS','M3.7 reopened after incomplete negative evidence',
    'Previous close proved readiness/root unknown only; nested unknown keys in final_normalized and trace were still accepted. Reopening checkpoint 4 and terminal for canonical RUN_TEST revalidation.',
    'CONTINUE_CURRENT_CHECKPOINT / NEGATIVE_READINESS_FIELD',
    jsonb_build_array('supabase://private.fn_lf_typed_evidence_payload_valid_v3 nested_unknown_final_valid=true nested_unknown_trace_valid=true'),
    'ENGINEERING-RUN-TEST-REPAIR-MICROLOOP-V1',now(),
    'ENGINEERING-RUN-TEST-REPAIR-MICROLOOP-V1'
  );

  update programacion.engineering_work_checkpoints
  set status='IN_PROGRESS',evidence_ref=null,completed_at=null,updated_at=now(),
      updated_by_execution_id='ENGINEERING-RUN-TEST-REPAIR-MICROLOOP-V1'
  where work_item_id=v_work_item_id and checkpoint_code='NEGATIVE_READINESS_FIELD';

  update programacion.engineering_work_checkpoints
  set status='PENDING',evidence_ref=null,completed_at=null,updated_at=now(),
      updated_by_execution_id='ENGINEERING-RUN-TEST-REPAIR-MICROLOOP-V1'
  where work_item_id=v_work_item_id and checkpoint_code='TERMINAL';

  update programacion.engineering_work_items
  set status='IN_PROGRESS',completed_at=null,started_at=coalesce(started_at,now()),updated_at=now()
  where id=v_work_item_id;
end
$reopen$;

-- 6) Atomic self-test: behavior, canonical cases, compiler contract, bootstrap,
-- and restoration of the temporary governance capability.
do $verify$
declare
  v_spec jsonb;
  v_packet jsonb;
  v_boot jsonb;
  v_count integer;
  v_failed integer;
  v_membership_restored boolean;
begin
  select count(*) into v_count
  from public.lf_test_suite_cases
  where metadata->>'unit_code'='M3.7'
    and metadata->>'checkpoint_code'='NEGATIVE_READINESS_FIELD';
  if v_count<>5 then raise exception 'M3_7_CANONICAL_CASE_COUNT:%',v_count; end if;

  select count(*) into v_failed
  from public.lf_test_suite_cases c
  where c.metadata->>'unit_code'='M3.7'
    and c.metadata->>'checkpoint_code'='NEGATIVE_READINESS_FIELD'
    and (c.metadata->>'expected_boolean')::boolean is distinct from
        private.fn_lf_typed_evidence_payload_valid_v3(c.metadata->>'schema_version',c.input_payload);
  if v_failed<>0 then raise exception 'M3_7_CANONICAL_CASE_FAILURES:%',v_failed; end if;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.7','NEGATIVE_READINESS_FIELD'
  );
  if v_spec#>>'{repair_policy,mode}' is distinct from 'REPAIR_DECLARED_TARGET_THEN_RETEST' then
    raise exception 'M3_7_REPAIR_POLICY_MISSING';
  end if;

  v_boot:=programacion.fn_engineering_unit_bootstrap_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.7');
  if v_boot#>>'{current_checkpoint,checkpoint_code}' is distinct from 'NEGATIVE_READINESS_FIELD' then
    raise exception 'M3_7_REOPEN_CURRENT_INVALID:%',v_boot#>>'{current_checkpoint,checkpoint_code}';
  end if;
  if (v_boot#>>'{state,progress_pct}')::numeric <> 65 then
    raise exception 'M3_7_REOPEN_PROGRESS_INVALID:%',v_boot#>>'{state,progress_pct}';
  end if;
  if v_boot#>>'{terminal_action}' is distinct from 'CONTINUE_CURRENT_CHECKPOINT' then
    raise exception 'M3_7_REOPEN_TERMINAL_INVALID:%',v_boot#>>'{terminal_action}';
  end if;

  v_packet:=v_boot->'execution_packet';
  if v_packet->>'execution_capability' is distinct from 'RUN_TEST' then
    raise exception 'M3_7_NOT_RUN_TEST';
  end if;
  if v_packet#>>'{connector_plan,0,executor_contract,executor}' is distinct from 'ENGINEERING_AGENT_RUN_TEST_V1' then
    raise exception 'M3_7_RUN_TEST_EXECUTOR_MISSING';
  end if;
  if v_packet#>>'{connector_plan,0,executor_contract,repair_loop,enabled}' is distinct from 'true' then
    raise exception 'M3_7_REPAIR_LOOP_DISABLED';
  end if;

  select count(*)=1
         and bool_and(pg_get_userbyid(am.grantor)='supabase_admin'
                      and am.admin_option
                      and not am.inherit_option
                      and not am.set_option)
  into v_membership_restored
  from pg_auth_members am
  join pg_roles granted on granted.oid=am.roleid
  join pg_roles member on member.oid=am.member
  where granted.rolname='lf_governance_owner_v3'
    and member.rolname='postgres';

  if not coalesce(v_membership_restored,false) then
    raise exception 'GOVERNANCE_MEMBERSHIP_NOT_RESTORED';
  end if;
  if has_schema_privilege('lf_governance_owner_v3','private','CREATE') then
    raise exception 'GOVERNANCE_CREATE_NOT_RESTORED';
  end if;
end
$verify$;

commit;
