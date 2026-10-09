create or replace function programacion.fn_engineering_blocker_resolve_v1(
  p_plan_code text,
  p_unit_code text,
  p_blocker_code text,
  p_resolution_ref text,
  p_actor text
)
returns jsonb
language plpgsql
volatile
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_work_item_id bigint;
  v_id bigint;
begin
  select pu.work_item_id into v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code
    and pu.disposition='ASSIGNED';

  if v_work_item_id is null then
    raise exception 'ENGINEERING_BLOCKER_RESOLVE_UNIT_NOT_FOUND:%/%',p_plan_code,p_unit_code;
  end if;
  if nullif(btrim(coalesce(p_resolution_ref,'')),'') is null then
    raise exception 'ENGINEERING_BLOCKER_RESOLUTION_REF_REQUIRED';
  end if;

  update programacion.engineering_work_blockers
     set status='RESOLVED',
         resolved_at=now(),
         resolution_ref=p_resolution_ref,
         updated_by_execution_id=p_actor
   where work_item_id=v_work_item_id
     and blocker_code=p_blocker_code
     and status='OPEN'
  returning id into v_id;

  if v_id is null then
    if exists(
      select 1 from programacion.engineering_work_blockers
      where work_item_id=v_work_item_id
        and blocker_code=p_blocker_code
        and status='RESOLVED'
    ) then
      return jsonb_build_object(
        'status','ALREADY_RESOLVED',
        'unit_code',p_unit_code,
        'blocker_code',p_blocker_code
      );
    end if;
    raise exception 'ENGINEERING_OPEN_BLOCKER_NOT_FOUND:%/%',p_unit_code,p_blocker_code;
  end if;

  return jsonb_build_object(
    'status','RESOLVED',
    'unit_code',p_unit_code,
    'blocker_code',p_blocker_code,
    'blocker_id',v_id,
    'resolution_ref',p_resolution_ref
  );
end
$function$;

create or replace function programacion.fn_engineering_ig_validator_mismatch_probe_v1(
  p_pantalla_id integer default null
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path to 'pg_catalog','programacion','public','lf_ops'
as $function$
declare
  v_sig regprocedure:='programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure;
  v_screen integer:=p_pantalla_id;
  v_orig text; v_candidate text; v_md5 text;
  v_curator_id text:='INPUT_CURATOR:EDGE:input-governance-curator-v1:M47'||substr(replace(gen_random_uuid()::text,'-',''),1,12);
  v_validator_id text:='INPUT_VALIDATOR:EDGE:input-governance-validator-v1:M47'||substr(replace(gen_random_uuid()::text,'-',''),1,12);
  v_cur jsonb; v_val jsonb; v_run bigint; v_i integer;
  v_pending integer:=0; v_fail integer:=0; v_blocked integer:=0; v_findings integer:=0;
  v_result jsonb:='{}'::jsonb; v_err text; v_rollback boolean:=false;
begin
  perform pg_advisory_xact_lock(hashtextextended('IG_VALIDATOR_MISMATCH_PROBE',0));

  if v_screen is null then
    select r.pantalla_id into v_screen
    from programacion.input_readiness_runs r
    join lf_ops.pantallas p on p.id=r.pantalla_id and p.activa
    where r.status='COMPLETED'
      and r.invalidated_at is null
      and (select count(*) from programacion.input_family_assessments a where a.run_id=r.id)=r.family_count
    order by r.id desc
    limit 1;
  end if;
  if v_screen is null then raise exception 'PROBE_NO_ELIGIBLE_BASELINE_SCREEN'; end if;

  v_orig:=pg_get_functiondef(v_sig);
  v_md5:=md5(v_orig);

  begin
    v_cur:=programacion.fn_input_governance_curator_rebind_v1(
      v_screen,'MANUAL',v_curator_id,true
    );
    v_run:=coalesce((v_cur->>'run_id')::bigint,(v_cur->>'latest_run_id')::bigint);
    if v_run is null then raise exception 'PROBE_NO_SELFTEST_RUN:%',v_cur; end if;

    v_candidate:=replace(
      v_orig,
      'v:=v-''classifier_sha256'';',
      'if p_family_code=''VISUAL_EVIDENCE'' then v:=jsonb_set(v,''{source_refs}'',coalesce(v->''source_refs'',''[]''::jsonb)||jsonb_build_array(jsonb_build_object(''kind'',''RULE'',''codigo'',''B2B-RULE-AUTH-033'')),true); end if; v:=v-''classifier_sha256'';'
    );
    if v_candidate=v_orig then raise exception 'PROBE_CLASSIFIER_PATCH_NOT_APPLIED'; end if;
    execute v_candidate;

    for v_i in 1..8 loop
      v_val:=programacion.fn_input_governance_validate_v2(v_run,v_validator_id);
      select count(*) filter(where validator_outcome='PENDING')
        into v_pending
      from programacion.input_family_assessments where run_id=v_run;
      exit when v_pending=0;
    end loop;

    select count(*) filter(where validator_outcome='FAIL'),
           count(*) filter(where validator_outcome='BLOCKED'),
           count(*) filter(where jsonb_array_length(coalesce(validator_findings,'[]'::jsonb))>0)
      into v_fail,v_blocked,v_findings
    from programacion.input_family_assessments where run_id=v_run;

    v_result:=jsonb_build_object(
      'status',case when v_fail+v_blocked>0 then 'PASS' else 'FAIL' end,
      'scenario','POST_CURATOR_CLASSIFIER_DRIFT',
      'pantalla_id',v_screen,
      'validator_terminal',v_val->>'status',
      'validator_fail_count',v_fail,
      'validator_blocked_count',v_blocked,
      'typed_findings',v_findings,
      'promotion_authorized',coalesce((v_val->>'promotion_authorized')::boolean,false),
      'run_completed',(select status='COMPLETED' from programacion.input_readiness_runs where id=v_run),
      'test_passed',(v_fail+v_blocked>0 and v_findings>0 and not coalesce((v_val->>'promotion_authorized')::boolean,false))
    );

    if not coalesce((v_result->>'test_passed')::boolean,false) then
      raise exception 'PROBE_FALSE_PASS:%',v_result;
    end if;
    raise exception 'IG_M47_PROBE_ROLLBACK_OK';
  exception when others then
    v_err:=sqlerrm;
    if v_err='IG_M47_PROBE_ROLLBACK_OK' then v_rollback:=true; else raise; end if;
  end;

  if not v_rollback then raise exception 'PROBE_ROLLBACK_NOT_OBSERVED'; end if;
  if md5(pg_get_functiondef(v_sig))<>v_md5 then raise exception 'PROBE_CLASSIFIER_RESIDUE'; end if;
  if exists(
    select 1 from programacion.input_readiness_runs
    where curator_identity=v_curator_id or validator_identity=v_validator_id
  ) then raise exception 'PROBE_RUN_RESIDUE'; end if;

  return v_result||jsonb_build_object(
    'durable_residue',false,
    'classifier_restored',true,
    'semantic_authority_bound',true,
    'adversarial_case_executed',true
  );
end
$function$;

revoke all on function programacion.fn_engineering_blocker_resolve_v1(text,text,text,text,text) from public;
grant execute on function programacion.fn_engineering_blocker_resolve_v1(text,text,text,text,text) to postgres;
revoke all on function programacion.fn_engineering_ig_validator_mismatch_probe_v1(integer) from public;
grant execute on function programacion.fn_engineering_ig_validator_mismatch_probe_v1(integer) to postgres;

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  unit_metadata,
  '{action_specs_v1,NEG_NO_PROMOTION}',
  (unit_metadata#>'{action_specs_v1,NEG_NO_PROMOTION}')
  || jsonb_build_object(
    'status','READY',
    'precision','REAL_VALIDATOR_ROLLBACK_FIXTURE_V1',
    'blocking_codes','[]'::jsonb,
    'verification_queries',jsonb_build_array(
      'select programacion.fn_engineering_ig_validator_mismatch_probe_v1(null) as result'
    ),
    'handler_requirement',jsonb_build_object(
      'status','READY',
      'handler','REAL_VALIDATOR_ROLLBACK_FIXTURE',
      'entrypoint','programacion.fn_engineering_ig_validator_mismatch_probe_v1',
      'fixture_selection','DYNAMIC_ELIGIBLE_COMPLETED_SCREEN',
      'rollback_required',true,
      'synthetic_pass','FORBIDDEN'
    ),
    'required_contract',jsonb_build_object(
      'validator_terminal','VALIDATION_BLOCKED_OR_VALIDATION_FAILED',
      'typed_findings_min',1,
      'promotion_authorized',false,
      'run_completed',false,
      'durable_residue',false,
      'classifier_restored',true
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M4.7';