begin;

do $guard$
declare
  v_action text;
begin
  select md5(p.prosrc) into v_action
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_engineering_checkpoint_action_spec_v3';

  if v_action is distinct from 'e5eb8ff49535e1e1485c7a5609006dde' then
    raise exception 'ACTION_SPEC_V3_DRIFT:%',v_action;
  end if;
end
$guard$;

create or replace function pg_temp.rep_once(src text,o text,n text)
returns text
language plpgsql
as $r$
begin
  if position(o in src)=0 then
    raise exception 'PATCH_ANCHOR_MISSING:%',left(o,180);
  end if;
  if position(o in substr(src,position(o in src)+length(o)))>0 then
    raise exception 'PATCH_ANCHOR_NON_UNIQUE:%',left(o,180);
  end if;
  return replace(src,o,n);
end
$r$;

do $patch_action$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_engineering_checkpoint_action_spec_v3';

  d:=pg_temp.rep_once(
    d,
    '''corpus_screen_ids'',jsonb_build_array(1,2,3,5,43,51,52,53,54,55,56,57,58)',
    '''corpus_screen_ids'',jsonb_build_array(1,43,58)'
  );
  d:=pg_temp.rep_once(
    d,
    'values (1),(2),(3),(5),(43),(51),(52),(53),(54),(55),(56),(57),(58)',
    'values (1),(43),(58)'
  );
  d:=pg_temp.rep_once(
    d,
    '''screen_count'',13',
    '''screen_count'',3'
  );

  execute d;
end
$patch_action$;

update public.lf_test_suite_cases
   set input_payload=jsonb_set(coalesce(input_payload,'{}'::jsonb),'{corpus_screen_ids}','[1,43,58]'::jsonb,true),
       expected_output=jsonb_set(coalesce(expected_output,'{}'::jsonb),'{screen_count}','3'::jsonb,true),
       metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
         'sample_policy','RUN_HISTORY_EFFECTIVENESS_SAMPLE_V1',
         'fresh_sample_size',3,
         'sample_screen_ids',jsonb_build_array(1,43,58)
       ),
       updated_at=now(),
       updated_by_execution_id='GPT-5.6-SOL-M3.9-SAMPLE3-20261005'
 where suite_code='INPUT_GOVERNANCE_REGRESSION'
   and test_code='M3_9_SHADOW_T_EQUIV_CORPUS';

do $verify$
declare
  v_spec jsonb;
  v_case record;
begin
  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.9','SHADOW_RUN'
  );

  if v_spec#>'{capability_execution,corpus_screen_ids}' is distinct from '[1,43,58]'::jsonb then
    raise exception 'M3_9_SAMPLE_IDS_INVALID:%',v_spec#>'{capability_execution,corpus_screen_ids}';
  end if;
  if (v_spec#>>'{capability_execution,result_contract,pass_when,screen_count}')::int is distinct from 3 then
    raise exception 'M3_9_SAMPLE_COUNT_INVALID:%',v_spec#>>'{capability_execution,result_contract,pass_when,screen_count}';
  end if;
  if position('values (1),(43),(58)' in v_spec#>>'{verification_queries,0}')=0 then
    raise exception 'M3_9_SAMPLE_QUERY_INVALID';
  end if;

  select input_payload,expected_output,metadata into v_case
  from public.lf_test_suite_cases
  where suite_code='INPUT_GOVERNANCE_REGRESSION'
    and test_code='M3_9_SHADOW_T_EQUIV_CORPUS';

  if v_case.input_payload->'corpus_screen_ids' is distinct from '[1,43,58]'::jsonb
     or (v_case.expected_output->>'screen_count')::int is distinct from 3
     or (v_case.metadata->>'fresh_sample_size')::int is distinct from 3 then
    raise exception 'M3_9_CANONICAL_CASE_SAMPLE_INVALID';
  end if;
end
$verify$;

commit;
