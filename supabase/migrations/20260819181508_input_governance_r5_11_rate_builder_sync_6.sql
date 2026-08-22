create or replace function programacion.fn_input_rate_enrichment_assertions(p_new_run_id bigint, p_parent_run_id bigint, p_family_code text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'programacion'
as $function$
declare
  v_screen integer;
  v_specs jsonb;
begin
  select pantalla_id into v_screen from programacion.input_readiness_runs where id=p_new_run_id;
  if v_screen is null then raise exception 'RATE_ENRICHMENT_RUN_NOT_FOUND:%',p_new_run_id; end if;

  if v_screen in (52,56) and p_family_code='RATE_LIMIT' then
    v_specs:=jsonb_build_array(
      jsonb_build_object(
        'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',v_screen),
        'path',jsonb_build_array('observed','canonical_contract','policies','rate_limit'),
        'operator','CONTAINS',
        'expected',jsonb_build_array(jsonb_build_object(
          'rate_limit_policy_id',7,
          'policy_code','RATE-B2B-PASSWORD-RECOVERY-OTP',
          'resource_code','AUTH_PASSWORD_RECOVERY_OTP_SEND',
          'window_seconds',900,
          'max_requests',6,
          'burst_limit',6,
          'scope_key','USER',
          'status','CANDIDATO'
        ))
      )
    );
    return programacion.fn_input_rebind_assertion_specs(p_new_run_id,p_family_code,v_specs);
  end if;

  return programacion.fn_input_owner_decision_assertions(p_new_run_id,p_parent_run_id,p_family_code);
end;
$function$;