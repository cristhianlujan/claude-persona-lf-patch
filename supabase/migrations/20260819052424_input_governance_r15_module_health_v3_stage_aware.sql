create or replace function programacion.fn_input_governance_module_health(p_version_id bigint,p_module_code text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $$
declare
  v_version record; v_contract record; v_screen_count integer:=0; v_story_healthy integer:=0; v_mechanics_healthy integer:=0;
  v_rows jsonb:='[]'::jsonb; v_downstream_contract_count integer:=0; v_payload jsonb;
begin
  select v.id,v.version_codigo,v.estado,a.agente_codigo,a.estado agent_state
    into v_version
  from programacion.versiones_agente v join programacion.agentes a on a.id=v.agente_id
  where v.id=p_version_id;
  if not found or v_version.agente_codigo<>'INPUT_GOVERNANCE_AGENT' then raise exception 'INPUT_GOVERNANCE_MODULE_HEALTH_INVALID_VERSION:%',p_version_id; end if;

  select c.id,c.especificacion->>'contract_revision' contract_revision,
         jsonb_array_length(c.especificacion->'negative_tests') negative_test_count,c.fail_closed,c.estado
    into v_contract
  from programacion.contratos c
  where c.version_id=p_version_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';
  if not found then raise exception 'INPUT_GOVERNANCE_MODULE_HEALTH_CONTRACT_MISSING:%',p_version_id; end if;

  select count(*) into v_downstream_contract_count
  from programacion.contratos c
  where c.version_id=p_version_id and c.contrato_codigo in ('INPUT_CONTEXT_MANIFEST_CONTRACT','INPUT_FRESHNESS_DELTA_CONTRACT','INPUT_RETRIEVAL_HANDLE_CONTRACT');

  with screens as (
    select p.id,p.codigo,p.nombre from lf_ops.pantallas p where p.module_code=p_module_code and p.activa=true
  ), runs as (
    select s.*,r.id run_id,r.status run_status,r.contract_revision run_contract_revision,
           case when r.id is null then false else programacion.fn_input_readiness_run_is_current(r.id) end run_current
    from screens s
    left join lateral (
      select rr.* from programacion.input_readiness_runs rr
      where rr.pantalla_id=s.id and rr.version_id=p_version_id
      order by rr.id desc limit 1
    ) r on true
  ), checks as (
    select r.*,
      coalesce((select count(*) from programacion.input_family_assessments a where a.run_id=r.run_id),0) family_count,
      coalesce((select count(*) from programacion.input_family_assessments a where a.run_id=r.run_id and a.validator_outcome='PASS'),0) validator_pass_count,
      coalesce((select count(*) from programacion.input_family_assessments a where a.run_id=r.run_id and a.applicability='APPLICABLE' and 'NOT_APPLICABLE'=any(array[a.coverage_status,a.well_defined_status,a.story_ready_status,a.implementation_ready_status,a.qa_ready_status,a.production_ready_status])),0) applicability_invariant_violations,
      coalesce((select count(*) from programacion.input_family_assessments a where a.run_id=r.run_id and a.applicability='NOT_APPLICABLE' and exists(select 1 from unnest(array[a.coverage_status,a.well_defined_status,a.story_ready_status,a.implementation_ready_status,a.qa_ready_status,a.production_ready_status]) st where st<>'NOT_APPLICABLE')),0) na_invariant_violations,
      coalesce((select count(*) from programacion.input_family_assessments a where a.run_id=r.run_id and a.severity not in ('P0','P1','P2','P3','P4')),0) severity_unresolved,
      coalesce((select count(*) from programacion.input_family_assessments a where a.run_id=r.run_id and a.applicability in ('APPLICABLE','UNRESOLVED') and a.story_ready_status<>'READY' and a.severity<>'P0'),0) story_open_not_p0,
      coalesce((select count(*) from programacion.input_family_assessments a where a.run_id=r.run_id and a.applicability='NOT_APPLICABLE' and not exists(select 1 from jsonb_array_elements(a.source_refs) sr where sr->>'kind'<>'CAPABILITY_ABSENCE')),0) na_authority_violations,
      case when r.run_id is null then null else programacion.fn_input_stage_gate_summary(r.run_id) end stage_summary
    from runs r
  ), shaped as (
    select *,
      coalesce((stage_summary->>'hierarchy_violation_count')::integer,999999) hierarchy_violation_count,
      coalesce((stage_summary->'summary'->>'stage_specific_incomplete_allowed')::integer,0) stage_specific_incomplete_allowed,
      coalesce((stage_summary->>'canonical_story_gate_pass')::boolean,false) canonical_story_gate_pass,
      (run_id is not null and run_status='COMPLETED' and run_current and run_contract_revision=v_contract.contract_revision
       and family_count=47 and validator_pass_count=47
       and applicability_invariant_violations=0 and na_invariant_violations=0
       and severity_unresolved=0 and story_open_not_p0=0 and na_authority_violations=0
       and coalesce((stage_summary->>'hierarchy_violation_count')::integer,999999)=0) mechanics_healthy
    from checks
  ), final as (
    select *, (mechanics_healthy and canonical_story_gate_pass) story_healthy from shaped
  )
  select count(*),count(*) filter(where story_healthy),count(*) filter(where mechanics_healthy),
         coalesce(jsonb_agg(jsonb_build_object(
           'pantalla_id',id,'screen_code',codigo,'name',nombre,'run_id',run_id,'run_status',run_status,'run_current',run_current,
           'run_contract_revision',run_contract_revision,'family_count',family_count,'validator_pass_count',validator_pass_count,
           'applicability_invariant_violations',applicability_invariant_violations,'na_invariant_violations',na_invariant_violations,
           'severity_unresolved',severity_unresolved,'story_open_not_p0',story_open_not_p0,'na_authority_violations',na_authority_violations,
           'stage_specific_incomplete_allowed',stage_specific_incomplete_allowed,'hierarchy_violation_count',hierarchy_violation_count,
           'canonical_story_gate_pass',canonical_story_gate_pass,'mechanics_healthy',mechanics_healthy,'story_healthy',story_healthy
         ) order by id),'[]'::jsonb)
    into v_screen_count,v_story_healthy,v_mechanics_healthy,v_rows
  from final;

  v_payload:=jsonb_build_object(
    'health_contract','INPUT_GOVERNANCE_MODULE_HEALTH_V3_STAGE_AWARE',
    'version',jsonb_build_object('version_id',p_version_id,'version_code',v_version.version_codigo,'version_state',v_version.estado,'agent_code',v_version.agente_codigo,'agent_state',v_version.agent_state),
    'readiness_contract',jsonb_build_object('contract_id',v_contract.id,'contract_revision',v_contract.contract_revision,'negative_test_count',v_contract.negative_test_count,'fail_closed',v_contract.fail_closed,'state',v_contract.estado),
    'module_code',p_module_code,'screen_count',v_screen_count,'mechanics_healthy_screen_count',v_mechanics_healthy,'story_healthy_screen_count',v_story_healthy,
    'downstream_contract_count',v_downstream_contract_count,'required_downstream_contract_count',3,'screens',v_rows,
    'mechanics_pass',v_screen_count>0 and v_mechanics_healthy=v_screen_count and v_downstream_contract_count=3,
    'story_health_pass',v_screen_count>0 and v_story_healthy=v_screen_count and v_downstream_contract_count=3,
    'health_pass',v_screen_count>0 and v_story_healthy=v_screen_count and v_downstream_contract_count=3,
    'promotion_authorized',false,
    'note','V3 is stage-aware: authorized later-stage incompleteness is not a mechanical defect. Story health remains fail-closed on canonical Story blockers. Promotion is not authorized by health alone.'
  );
  return v_payload||jsonb_build_object('health_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$$;