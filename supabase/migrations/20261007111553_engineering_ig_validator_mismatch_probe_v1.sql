create or replace function programacion.fn_engineering_ig_validator_mismatch_probe_v1(
  p_pantalla_id integer default 54
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path to 'pg_catalog','programacion','public','lf_ops'
as $function$
declare
  v_sig regprocedure:='programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure;
  v_orig text; v_candidate text; v_md5 text;
  v_curator_id text:='INPUT_CURATOR:EDGE:input-governance-curator-v1:M47'||substr(replace(gen_random_uuid()::text,'-',''),1,12);
  v_validator_id text:='INPUT_VALIDATOR:EDGE:input-governance-validator-v1:M47'||substr(replace(gen_random_uuid()::text,'-',''),1,12);
  v_cur jsonb; v_val jsonb; v_run bigint; v_i integer;
  v_pending integer:=0; v_fail integer:=0; v_blocked integer:=0; v_findings integer:=0;
  v_result jsonb:='{}'::jsonb; v_err text; v_rollback boolean:=false;
begin
  perform pg_advisory_xact_lock(hashtextextended('IG_VALIDATOR_MISMATCH_PROBE',0));
  v_orig:=pg_get_functiondef(v_sig);
  v_md5:=md5(v_orig);

  begin
    v_cur:=programacion.fn_input_governance_curator_rebind_v1(
      p_pantalla_id,'MANUAL',v_curator_id,true
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
    if v_err='IG_M47_PROBE_ROLLBACK_OK' then
      v_rollback:=true;
    else
      raise;
    end if;
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

revoke all on function programacion.fn_engineering_ig_validator_mismatch_probe_v1(integer) from public;
grant execute on function programacion.fn_engineering_ig_validator_mismatch_probe_v1(integer) to postgres;