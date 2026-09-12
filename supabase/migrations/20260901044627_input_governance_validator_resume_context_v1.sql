create or replace function public.fn_input_governance_validator_resume_context_v1(p_run_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,programacion
as $function$
declare
  v_status text;
  v_identity text;
  v_analysis text;
begin
  select status,validator_identity,scope->>'analysis_revision'
    into v_status,v_identity,v_analysis
  from programacion.input_readiness_runs
  where id=p_run_id and version_id=19;
  if v_status is null then raise exception 'INPUT_VALIDATOR_RESUME_RUN_NOT_FOUND:%',p_run_id; end if;
  if v_status='VALIDATING' then
    if v_analysis<>'INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX' then raise exception 'INPUT_VALIDATOR_RESUME_ANALYSIS_REVISION_INVALID:%',coalesce(v_analysis,'<NULL>'); end if;
    if v_identity is null or v_identity !~ '^INPUT_VALIDATOR:EDGE:input-governance-validator-v1:[A-Za-z0-9_-]{6,128}$' then raise exception 'INPUT_VALIDATOR_RESUME_IDENTITY_INVALID:%',p_run_id; end if;
    return jsonb_build_object('run_id',p_run_id,'status',v_status,'validator_identity',v_identity,'resume_allowed',true);
  end if;
  return jsonb_build_object('run_id',p_run_id,'status',v_status,'validator_identity',null,'resume_allowed',false);
end;
$function$;
revoke all on function public.fn_input_governance_validator_resume_context_v1(bigint) from public,anon,authenticated;
grant execute on function public.fn_input_governance_validator_resume_context_v1(bigint) to service_role;