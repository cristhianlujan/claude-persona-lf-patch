create or replace function programacion.fn_input_governance_validate_gap_proposals_v1(p_run_id bigint,p_validator_identity text)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,programacion
as $function$
declare
  v_run record;
  p record;
  r jsonb;
  u record;
  v_obs jsonb;
  v_readbacks jsonb;
  v_cache jsonb:='{}'::jsonb;
  v_key text;
  v_count int:=0;
  v_human int:=0;
begin
  select * into v_run from programacion.input_readiness_runs where id=p_run_id;
  if not found then raise exception 'INPUT_REMEDIATION_VALIDATE_RUN_NOT_FOUND:%',p_run_id; end if;
  if v_run.status<>'VALIDATING' then raise exception 'INPUT_REMEDIATION_VALIDATE_REQUIRES_VALIDATING:%',p_run_id; end if;
  if p_validator_identity is distinct from v_run.validator_identity or p_validator_identity=v_run.curator_identity then raise exception 'INPUT_REMEDIATION_VALIDATOR_IDENTITY_INVALID:%',p_run_id; end if;
  for u in
    select distinct r.value as source_ref
    from programacion.input_gap_proposals gp
    cross join lateral jsonb_array_elements(coalesce(gp.source_refs,'[]'::jsonb)) r(value)
    where gp.run_id=p_run_id and gp.validator_outcome='PENDING'
  loop
    v_key:=u.source_ref::text;
    v_obs:=programacion.fn_input_resolve_source_ref(u.source_ref,v_run.pantalla_id,v_run.version_id);
    v_cache:=v_cache||jsonb_build_object(v_key,v_obs);
  end loop;
  for p in select * from programacion.input_gap_proposals where run_id=p_run_id and validator_outcome='PENDING' order by id loop
    v_readbacks:='[]'::jsonb;
    for r in select value from jsonb_array_elements(p.source_refs) loop
      v_key:=r::text;
      if not (v_cache ? v_key) then raise exception 'INPUT_REMEDIATION_SOURCE_CACHE_MISS:%',v_key; end if;
      v_obs:=v_cache->v_key;
      v_readbacks:=v_readbacks||jsonb_build_array(jsonb_build_object('source_ref',r,'source_observed_sha256',programacion.fn_v09_sha256_jsonb(v_obs)));
    end loop;
    update programacion.input_gap_proposals set validator_identity=p_validator_identity,validator_outcome='PASS',status=case when proposal_kind='HUMAN_DECISION_REQUIRED' then 'HUMAN_DECISION_REQUIRED' else 'VALIDATED' end,
      validator_evidence=jsonb_build_object('direct_source_readback',true,'source_snapshot_sha256',v_run.source_snapshot_sha256,'source_readbacks',v_readbacks,'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','proposal_is_canonical_source',false,'automatic_canonicalization','DENY'),validated_at=now() where id=p.id;
    v_count:=v_count+1;
    if p.proposal_kind='HUMAN_DECISION_REQUIRED' then v_human:=v_human+1; end if;
  end loop;
  return jsonb_build_object('run_id',p_run_id,'validated_proposal_count',v_count,'human_decision_required_count',v_human,'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX');
end;
$function$;