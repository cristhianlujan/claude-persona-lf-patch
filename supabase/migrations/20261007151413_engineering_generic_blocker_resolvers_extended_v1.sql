create or replace function programacion.fn_engineering_historical_evidence_reevaluate_v1(
  p_plan_code text,p_unit_code text,p_checkpoint_code text,p_apply boolean default true
) returns jsonb
language plpgsql
set search_path to programacion,public,pg_catalog
as $$
declare
  v_work_item_id bigint; v_meta jsonb; v_policy jsonb; v_readback jsonb; v_blocker text;
  v_screen_threshold int; v_family_threshold int; v_false_pass_required int; v_d4_required int;
  v_cohort jsonb; v_families jsonb; v_screen_total int:=0; v_screen_ok int:=0;
  v_family_total int:=0; v_family_ok int:=0; v_screen_gaps jsonb:='[]'::jsonb;
  v_family_gaps jsonb:='[]'::jsonb; v_false_pass int:=0; v_d4_state text;
  v_pass boolean:=false; v_resolution text; v_res jsonb;
begin
  select pu.work_item_id,pu.unit_metadata into v_work_item_id,v_meta
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and pu.disposition='ASSIGNED';

  select b.blocker_code into v_blocker
  from programacion.engineering_work_blockers b
  where b.work_item_id=v_work_item_id and b.status='OPEN'
    and b.blocker_code ilike '%HISTORY_REEVALUATION_REQUIRED%'
  order by b.id limit 1;

  if v_blocker is null then
    return jsonb_build_object('schema_version','ENGINEERING_HISTORICAL_EVIDENCE_REEVALUATOR_V1','status','NOT_APPLICABLE','state_changed',false);
  end if;

  v_policy:=coalesce(v_meta->'soak_observation_policy_v2','{}'::jsonb);
  v_readback:=coalesce(v_meta->'soak_observation_readback_v1',v_meta->'m9_11_soak_readback_v1','{}'::jsonb);
  v_screen_threshold:=coalesce(nullif(v_policy->>'screen_threshold','')::int,2);
  v_family_threshold:=coalesce(nullif(v_policy->>'critical_family_threshold','')::int,2);
  v_false_pass_required:=coalesce(nullif(v_policy->>'false_pass_required','')::int,0);
  v_d4_required:=coalesce(nullif(v_policy->>'unresolved_d4_required','')::int,0);
  v_cohort:=coalesce(v_readback#>'{coverage,covered_screen_ids}','[]'::jsonb)
            ||coalesce(v_readback#>'{coverage,missing_screen_ids}','[]'::jsonb);
  v_families:=coalesce(v_readback#>'{coverage,critical_family_codes}','[]'::jsonb);
  v_d4_state:=coalesce(v_readback#>>'{d4,state}','UNKNOWN_NOT_PROVEN_ZERO');

  if jsonb_array_length(v_cohort)=0 or jsonb_array_length(v_families)=0 then
    return jsonb_build_object(
      'schema_version','ENGINEERING_HISTORICAL_EVIDENCE_REEVALUATOR_V1',
      'status','INPUT_REQUIRED_COHORT_OR_CRITICAL_FAMILIES','blocker_code',v_blocker,'state_changed',false
    );
  end if;

  with cohort as (
    select distinct value::int pantalla_id from jsonb_array_elements_text(v_cohort)
  ), eligible as (
    select r.id,r.pantalla_id
    from programacion.input_readiness_runs r
    join cohort c on c.pantalla_id=r.pantalla_id
    where r.status='COMPLETED'
      and r.invalidated_at is null
      and r.source_snapshot_sha256 is not null
      and r.contract_snapshot_sha256 is not null
      and r.validator_identity is not null
  ), counts as (
    select c.pantalla_id,count(e.id)::int n
    from cohort c left join eligible e on e.pantalla_id=c.pantalla_id
    group by c.pantalla_id
  )
  select count(*)::int,
         count(*) filter(where n>=v_screen_threshold)::int,
         coalesce(jsonb_agg(pantalla_id order by pantalla_id) filter(where n<v_screen_threshold),'[]'::jsonb)
    into v_screen_total,v_screen_ok,v_screen_gaps
  from counts;

  with fam as (
    select distinct value family_code from jsonb_array_elements_text(v_families)
  ), eligible as (
    select r.id
    from programacion.input_readiness_runs r
    where r.status='COMPLETED'
      and r.invalidated_at is null
      and r.source_snapshot_sha256 is not null
      and r.contract_snapshot_sha256 is not null
      and r.validator_identity is not null
      and r.pantalla_id in (select distinct value::int from jsonb_array_elements_text(v_cohort))
  ), counts as (
    select f.family_code,count(distinct a.run_id)::int n
    from fam f
    left join programacion.input_family_assessments a
      on a.family_code=f.family_code
     and a.validator_outcome='PASS'
     and a.run_id in (select id from eligible)
    group by f.family_code
  )
  select count(*)::int,
         count(*) filter(where n>=v_family_threshold)::int,
         coalesce(jsonb_agg(family_code order by family_code) filter(where n<v_family_threshold),'[]'::jsonb)
    into v_family_total,v_family_ok,v_family_gaps
  from counts;

  select coalesce((s.manifest->>'false_pass_count')::int,0)
    into v_false_pass
  from public.lf_test_suite_runs s
  where s.manifest ? 'false_pass_count'
    and s.metadata->>'plan_code'=p_plan_code
  order by s.created_at desc limit 1;
  v_false_pass:=coalesce(v_false_pass,0);

  v_pass:=
    v_screen_ok=v_screen_total
    and v_family_ok=v_family_total
    and v_false_pass=v_false_pass_required
    and (v_d4_required<>0 or v_d4_state in ('PROVEN_ZERO','ZERO','RESOLVED_ZERO','PASS_ZERO'));

  if not v_pass then
    return jsonb_build_object(
      'schema_version','ENGINEERING_HISTORICAL_EVIDENCE_REEVALUATOR_V1',
      'status',case
        when v_screen_ok<v_screen_total then 'HISTORY_GAPS_REMAIN'
        when v_family_ok<v_family_total then 'CRITICAL_FAMILY_GAPS_REMAIN'
        when v_false_pass<>v_false_pass_required then 'FALSE_PASS_GAP_REMAINS'
        else 'WAIT_D4_PROOF' end,
      'blocker_code',v_blocker,
      'screen_threshold',v_screen_threshold,'screens_total',v_screen_total,
      'screens_meeting_threshold',v_screen_ok,'screen_gaps',v_screen_gaps,
      'critical_family_threshold',v_family_threshold,'critical_families_total',v_family_total,
      'critical_families_meeting_threshold',v_family_ok,'critical_family_gaps',v_family_gaps,
      'false_pass_count',v_false_pass,'d4_state',v_d4_state,
      'new_runs_policy','ONLY_TARGETED_FOR_REMAINING_GAPS','state_changed',false
    );
  end if;

  v_resolution:='supabase://programacion.fn_engineering_historical_evidence_reevaluate_v1/'
    ||p_plan_code||'/'||p_unit_code||'/'||p_checkpoint_code
    ||'#screens='||v_screen_ok||'/'||v_screen_total
    ||';families='||v_family_ok||'/'||v_family_total||';false_pass=0;d4=0';

  if not p_apply then
    return jsonb_build_object('schema_version','ENGINEERING_HISTORICAL_EVIDENCE_REEVALUATOR_V1',
      'status','DRY_RUN_READY','resolution_ref',v_resolution,'state_changed',false);
  end if;

  v_res:=programacion.fn_engineering_blocker_resolve_v1(
    p_plan_code,p_unit_code,v_blocker,v_resolution,'ENGINEERING_HISTORICAL_EVIDENCE_REEVALUATOR_V1'
  );

  return jsonb_build_object(
    'schema_version','ENGINEERING_HISTORICAL_EVIDENCE_REEVALUATOR_V1',
    'status',case when coalesce(v_res->>'status','') in ('RESOLVED','ALREADY_RESOLVED') then 'RECONCILED' else 'RESOLUTION_FAILED' end,
    'blocker_code',v_blocker,'resolution_ref',v_resolution,'result',v_res,
    'state_changed',coalesce(v_res->>'status','')='RESOLVED'
  );
end; $$;

create or replace function programacion.fn_engineering_execution_context_bind_v1(
  p_plan_code text,p_unit_code text,p_checkpoint_code text,p_apply boolean default true
) returns jsonb
language plpgsql
set search_path to programacion,public,pg_catalog
as $$
declare
  v_work_item_id bigint; v_meta jsonb; v_blocker text; v_execution_id text;
  v_request_sha text; v_idempotency text; v_reserve jsonb; v_resolution text; v_res jsonb;
  v_cp_input jsonb; v_runtime jsonb;
begin
  select pu.work_item_id,pu.unit_metadata into v_work_item_id,v_meta
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and pu.disposition='ASSIGNED';

  select b.blocker_code into v_blocker
  from programacion.engineering_work_blockers b
  where b.work_item_id=v_work_item_id and b.status='OPEN'
    and b.blocker_code='EVIDENCE_LEDGER_EXECUTION_BINDING_MISSING'
  order by b.id limit 1;

  if v_blocker is null then
    return jsonb_build_object('schema_version','ENGINEERING_EXECUTION_CONTEXT_BINDER_V1','status','NOT_APPLICABLE','state_changed',false);
  end if;

  v_execution_id:=nullif(v_meta#>>array['runtime_repair_inputs_v1',p_checkpoint_code,'execution_context','execution_id'],'');
  if v_execution_id is not null
     and exists(select 1 from public.lf_operation_execution e where e.execution_id=v_execution_id) then
    v_resolution:='supabase://public.lf_operation_execution/'||v_execution_id||'#bound';
  else
    select e.execution_id into v_execution_id
    from public.lf_operation_execution e
    where e.operation_code='ENGINEERING_CHECKPOINT_EVIDENCE'
      and e.manifest->>'plan_code'=p_plan_code
      and e.manifest->>'unit_code'=p_unit_code
      and e.manifest->>'checkpoint_code'=p_checkpoint_code
    order by e.created_at desc limit 1;

    if v_execution_id is null and not p_apply then
      return jsonb_build_object(
        'schema_version','ENGINEERING_EXECUTION_CONTEXT_BINDER_V1',
        'status','DRY_RUN_READY_RESERVE','blocker_code',v_blocker,
        'operation_code','ENGINEERING_CHECKPOINT_EVIDENCE','state_changed',false
      );
    end if;

    if v_execution_id is null then
      v_request_sha:=encode(digest(convert_to(
        p_plan_code||'|'||p_unit_code||'|'||p_checkpoint_code||'|ENGINEERING_CHECKPOINT_EVIDENCE','UTF8'
      ),'sha256'),'hex');
      v_idempotency:='eng-evidence:'||p_plan_code||':'||p_unit_code||':'||p_checkpoint_code;
      v_execution_id:='ENGCTX-'||substr(v_request_sha,1,32);

      v_reserve:=public.fn_lf_operation_reserve_execution_v1(
        v_execution_id,'ENGINEERING_CHECKPOINT_EVIDENCE','ENGINEERING_CHECKPOINT',
        p_plan_code||'/'||p_unit_code||'/'||p_checkpoint_code,
        v_idempotency,v_request_sha,'ENGINEERING_EXECUTION_CONTEXT_BINDER_V1',
        null,null,
        jsonb_build_object(
          'schema_version','ENGINEERING_EXECUTION_CONTEXT_BINDING_V1',
          'plan_code',p_plan_code,'unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code,
          'purpose','EVIDENCE_LEDGER_EXECUTION_BINDING'
        )
      );
      v_execution_id:=v_reserve->>'execution_id';
    end if;

    v_runtime:=coalesce(v_meta->'runtime_repair_inputs_v1','{}'::jsonb);
    v_cp_input:=coalesce(v_runtime->p_checkpoint_code,'{}'::jsonb)
      ||jsonb_build_object('execution_context',jsonb_build_object(
          'execution_id',v_execution_id,'operation_code','ENGINEERING_CHECKPOINT_EVIDENCE',
          'binding_source','ENGINEERING_EXECUTION_CONTEXT_BINDER_V1'));

    update programacion.engineering_plan_units
       set unit_metadata=jsonb_set(unit_metadata,'{runtime_repair_inputs_v1}',
         v_runtime||jsonb_build_object(p_checkpoint_code,v_cp_input),true)
     where plan_code=p_plan_code and unit_code=p_unit_code and disposition='ASSIGNED';

    v_resolution:='supabase://public.lf_operation_execution/'||v_execution_id||'#canonical-checkpoint-context';
  end if;

  if not p_apply then
    return jsonb_build_object('schema_version','ENGINEERING_EXECUTION_CONTEXT_BINDER_V1',
      'status','DRY_RUN_READY','execution_id',v_execution_id,'state_changed',false);
  end if;

  v_res:=programacion.fn_engineering_blocker_resolve_v1(
    p_plan_code,p_unit_code,v_blocker,v_resolution,'ENGINEERING_EXECUTION_CONTEXT_BINDER_V1'
  );

  return jsonb_build_object(
    'schema_version','ENGINEERING_EXECUTION_CONTEXT_BINDER_V1',
    'status',case when coalesce(v_res->>'status','') in ('RESOLVED','ALREADY_RESOLVED') then 'BOUND' else 'RESOLUTION_FAILED' end,
    'execution_id',v_execution_id,'result',v_res,
    'state_changed',coalesce(v_res->>'status','')='RESOLVED'
  );
end; $$;

create or replace function programacion.fn_engineering_blocker_family_dispatch_v1(
  p_plan_code text,p_unit_code text,p_checkpoint_code text,p_apply boolean default true
) returns jsonb
language plpgsql
set search_path to programacion,public,pg_catalog
as $$
declare
  v_work_item_id bigint; v_code text; v_spec_status text; v_dep jsonb; v_result jsonb;
begin
  select pu.work_item_id into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and pu.disposition='ASSIGNED';

  if v_work_item_id is null then
    return jsonb_build_object('schema_version','ENGINEERING_BLOCKER_FAMILY_DISPATCH_V1',
      'status','UNIT_NOT_FOUND','supported_blocker_families',5,'state_changed',false);
  end if;

  v_spec_status:=coalesce(programacion.fn_engineering_checkpoint_action_spec_v3(
    p_plan_code,p_unit_code,p_checkpoint_code)->>'status','');

  select b.blocker_code into v_code
  from programacion.engineering_work_blockers b
  where b.work_item_id=v_work_item_id and b.status='OPEN'
  order by b.id limit 1;

  if v_spec_status='BLOCK_OWNER_DECISION_REQUIRED' then
    return jsonb_build_object(
      'schema_version','ENGINEERING_BLOCKER_FAMILY_DISPATCH_V1',
      'status','PRESERVED_OWNER_DECISION_REQUIRED','repair_family','OWNER_DECISION_GATE',
      'auto_repair','FORBIDDEN','supported_blocker_families',5,'state_changed',false
    );
  elsif v_code ilike '%CURRENTNESS_DRIFT%' then
    v_result:=programacion.fn_engineering_currentness_drift_reconcile_v1(p_plan_code,p_unit_code,p_checkpoint_code,p_apply);
    return v_result||jsonb_build_object('repair_family','CURRENTNESS_DRIFT','supported_blocker_families',5);
  elsif v_code ilike '%CANONICAL_IDENTITY_MISSING%' then
    v_result:=programacion.fn_engineering_canonical_identity_resolve_v1(p_plan_code,p_unit_code,p_checkpoint_code,p_apply);
    return v_result||jsonb_build_object('repair_family','CANONICAL_IDENTITY','supported_blocker_families',5);
  elsif v_code ilike '%HISTORY_REEVALUATION_REQUIRED%' then
    v_result:=programacion.fn_engineering_historical_evidence_reevaluate_v1(p_plan_code,p_unit_code,p_checkpoint_code,p_apply);
    return v_result||jsonb_build_object('repair_family','HISTORICAL_EVIDENCE','supported_blocker_families',5);
  elsif v_code='EVIDENCE_LEDGER_EXECUTION_BINDING_MISSING' then
    v_result:=programacion.fn_engineering_execution_context_bind_v1(p_plan_code,p_unit_code,p_checkpoint_code,p_apply);
    return v_result||jsonb_build_object('repair_family','EXECUTION_CONTEXT','supported_blocker_families',5);
  elsif v_code='D-V2.3_ASSURANCE_EVALUATOR_ACTIVATION_DECISION' then
    return jsonb_build_object(
      'schema_version','ENGINEERING_BLOCKER_FAMILY_DISPATCH_V1',
      'status','PRESERVED_OWNER_ACTIVATION_REQUIRED','repair_family','OWNER_ACTIVATION_GATE',
      'blocker_code',v_code,'auto_repair','FORBIDDEN',
      'supported_blocker_families',5,'state_changed',false
    );
  end if;

  v_dep:=programacion.fn_engineering_dependency_auto_release_v1(p_plan_code,p_unit_code,p_apply);
  if v_dep->>'status'='WAIT_DEPENDENCIES' then
    return v_dep||jsonb_build_object('repair_family','DEPENDENCY_AUTO_RELEASE','supported_blocker_families',5);
  end if;

  return jsonb_build_object(
    'schema_version','ENGINEERING_BLOCKER_FAMILY_DISPATCH_V1','status','NOT_APPLICABLE',
    'blocker_code',v_code,'dependency_state',v_dep->>'status',
    'supported_blocker_families',5,'state_changed',false
  );
end; $$;

create or replace function programacion.fn_engineering_plan_blocker_repair_prepass_v1(
  p_plan_code text
) returns jsonb
language plpgsql
set search_path to programacion,public,pg_catalog
as $$
declare
  r record; v_cp text; v_result jsonb; v_results jsonb:='[]'::jsonb;
  v_attempted int:=0; v_changed int:=0;
begin
  for r in
    select pu.unit_code
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_items w on w.id=pu.work_item_id
    where pu.plan_code=p_plan_code and pu.disposition='ASSIGNED'
      and w.status in ('BACKLOG','READY','IN_PROGRESS','BLOCKED')
      and (
        programacion.fn_engineering_effective_open_blocker_count_v1(w.id)>0
        or exists(select 1 from programacion.fn_engineering_effective_dependencies_v1(w.id) d where d.is_unmet)
      )
    order by pu.id
  loop
    select c.checkpoint_code into v_cp
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_checkpoints c on c.work_item_id=pu.work_item_id
    where pu.plan_code=p_plan_code and pu.unit_code=r.unit_code
      and c.status not in ('DONE','NOT_APPLICABLE')
    order by c.sequence_no limit 1;

    if v_cp is null then continue; end if;

    v_result:=programacion.fn_engineering_blocker_family_dispatch_v1(
      p_plan_code,r.unit_code,v_cp,true
    );
    v_attempted:=v_attempted+1;
    if coalesce((v_result->>'state_changed')::boolean,false) then v_changed:=v_changed+1; end if;
    v_results:=v_results||jsonb_build_array(
      jsonb_build_object('unit_code',r.unit_code,'checkpoint_code',v_cp,'result',v_result)
    );
  end loop;

  return jsonb_build_object(
    'schema_version','ENGINEERING_PLAN_BLOCKER_REPAIR_PREPASS_V1','plan_code',p_plan_code,
    'attempted',v_attempted,'changed',v_changed,'results',v_results
  );
end; $$;