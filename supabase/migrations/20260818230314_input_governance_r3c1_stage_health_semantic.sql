create or replace function programacion.fn_input_stage_gate_summary(p_run_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $$
declare v_run programacion.input_readiness_runs%rowtype; v_summary jsonb; v_violations jsonb;
begin
  select * into v_run from programacion.input_readiness_runs where id=p_run_id;
  if not found then raise exception 'INPUT_STAGE_GATE_RUN_NOT_FOUND:%',p_run_id; end if;
  select jsonb_build_object(
    'families_total',count(*),'validator_pass',count(*) filter(where validator_outcome='PASS'),
    'applicable',count(*) filter(where applicability='APPLICABLE'),'not_applicable',count(*) filter(where applicability='NOT_APPLICABLE'),'unresolved',count(*) filter(where applicability='UNRESOLVED'),
    'applicable_p0_story_open',count(*) filter(where applicability='APPLICABLE' and severity='P0' and story_ready_status<>'READY'),
    'story_stage_open',count(*) filter(where applicability='UNRESOLVED' or (applicability='APPLICABLE' and story_ready_status<>'READY')),
    'implementation_stage_open',count(*) filter(where applicability='UNRESOLVED' or (applicability='APPLICABLE' and implementation_ready_status<>'READY')),
    'qa_stage_open',count(*) filter(where applicability='UNRESOLVED' or (applicability='APPLICABLE' and qa_ready_status<>'READY')),
    'production_stage_open',count(*) filter(where applicability='UNRESOLVED' or (applicability='APPLICABLE' and production_ready_status<>'READY')),
    'severity_unresolved',count(*) filter(where severity not in ('P0','P1','P2','P3','P4')),
    'story_open_not_p0',count(*) filter(where applicability in ('APPLICABLE','UNRESOLVED') and story_ready_status<>'READY' and severity<>'P0'),
    'story_ready_bad_coverage',count(*) filter(where applicability='APPLICABLE' and story_ready_status='READY' and (coverage_status in ('MISSING','PENDING','BLOCKED') or well_defined_status in ('MISSING','PENDING','BLOCKED'))),
    'implementation_ready_incomplete_coverage',count(*) filter(where applicability='APPLICABLE' and implementation_ready_status='READY' and (coverage_status<>'COMPLETE' or well_defined_status<>'COMPLETE')),
    'na_only_absence_authority',count(*) filter(where applicability='NOT_APPLICABLE' and not exists(select 1 from jsonb_array_elements(source_refs) r where r->>'kind'<>'CAPABILITY_ABSENCE'))
  ) into v_summary from programacion.input_family_assessments where run_id=p_run_id;

  select coalesce(jsonb_agg(v order by v->>'family_code',v->>'code'),'[]'::jsonb) into v_violations
  from (
    select jsonb_build_object('family_code',family_code,'code','IMPLEMENTATION_READY_WHILE_STORY_NOT_READY') v from programacion.input_family_assessments where run_id=p_run_id and applicability='APPLICABLE' and implementation_ready_status='READY' and story_ready_status<>'READY'
    union all select jsonb_build_object('family_code',family_code,'code','QA_READY_WHILE_IMPLEMENTATION_NOT_READY') from programacion.input_family_assessments where run_id=p_run_id and applicability='APPLICABLE' and qa_ready_status='READY' and implementation_ready_status<>'READY'
    union all select jsonb_build_object('family_code',family_code,'code','PRODUCTION_READY_WHILE_QA_NOT_READY') from programacion.input_family_assessments where run_id=p_run_id and applicability='APPLICABLE' and production_ready_status='READY' and qa_ready_status<>'READY'
    union all select jsonb_build_object('family_code',family_code,'code','STORY_OPEN_WITHOUT_P0') from programacion.input_family_assessments where run_id=p_run_id and applicability in ('APPLICABLE','UNRESOLVED') and story_ready_status<>'READY' and severity<>'P0'
    union all select jsonb_build_object('family_code',family_code,'code','IMPLEMENTATION_READY_WITH_INCOMPLETE_COVERAGE') from programacion.input_family_assessments where run_id=p_run_id and applicability='APPLICABLE' and implementation_ready_status='READY' and (coverage_status<>'COMPLETE' or well_defined_status<>'COMPLETE')
  ) z;

  return jsonb_build_object('stage_gate_contract','INPUT_STAGE_GATE_SUMMARY_V2','run_id',p_run_id,'run_status',v_run.status,
    'run_current',case when v_run.status='COMPLETED' then programacion.fn_input_readiness_run_is_current(p_run_id) else false end,
    'summary',v_summary,
    'canonical_story_gate_pass',coalesce((v_summary->>'story_stage_open')::integer,0)=0 and coalesce((v_summary->>'severity_unresolved')::integer,0)=0 and coalesce((v_summary->>'story_open_not_p0')::integer,0)=0,
    'legacy_no_applicable_p0_open_pass',coalesce((v_summary->>'applicable_p0_story_open')::integer,0)=0,
    'full_story_stage_closed',coalesce((v_summary->>'story_stage_open')::integer,0)=0,
    'full_implementation_stage_closed',coalesce((v_summary->>'implementation_stage_open')::integer,0)=0,
    'full_qa_stage_closed',coalesce((v_summary->>'qa_stage_open')::integer,0)=0,
    'full_production_stage_closed',coalesce((v_summary->>'production_stage_open')::integer,0)=0,
    'hierarchy_violation_count',jsonb_array_length(v_violations),'hierarchy_violations',v_violations);
end;
$$;

create or replace function programacion.fn_input_governance_module_health(p_version_id bigint,p_module_code text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion','lf_ops'
as $$
declare
  v_version record; v_contract record; v_screen_count integer:=0; v_healthy integer:=0; v_mechanics_healthy integer:=0; v_rows jsonb:='[]'::jsonb; v_downstream_contract_count integer:=0; v_payload jsonb;
begin
  select v.id,v.version_codigo,v.estado,a.agente_codigo,a.estado agent_state into v_version from programacion.versiones_agente v join programacion.agentes a on a.id=v.agente_id where v.id=p_version_id;
  if not found or v_version.agente_codigo<>'INPUT_GOVERNANCE_AGENT' then raise exception 'INPUT_GOVERNANCE_MODULE_HEALTH_INVALID_VERSION:%',p_version_id; end if;
  select c.id,c.especificacion->>'contract_revision' contract_revision,jsonb_array_length(c.especificacion->'negative_tests') negative_test_count,c.fail_closed,c.estado into v_contract from programacion.contratos c where c.version_id=p_version_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';
  if not found then raise exception 'INPUT_GOVERNANCE_MODULE_HEALTH_CONTRACT_MISSING:%',p_version_id; end if;
  select count(*) into v_downstream_contract_count from programacion.contratos c where c.version_id=p_version_id and c.contrato_codigo in ('INPUT_CONTEXT_MANIFEST_CONTRACT','INPUT_FRESHNESS_DELTA_CONTRACT','INPUT_RETRIEVAL_HANDLE_CONTRACT');
  with screens as (
    select p.id,p.codigo,p.nombre from lf_ops.pantallas p where p.module_code=p_module_code and p.activa=true
  ), runs as (
    select s.*,r.id run_id,r.status run_status,case when r.id is null then false else programacion.fn_input_readiness_run_is_current(r.id) end run_current
    from screens s left join lateral (select rr.* from programacion.input_readiness_runs rr where rr.pantalla_id=s.id and rr.version_id=p_version_id order by rr.id desc limit 1) r on true
  ), checks as (
    select r.*,
      coalesce((select count(*) from programacion.input_family_assessments a where a.run_id=r.run_id),0) family_count,
      coalesce((select count(*) from programacion.input_family_assessments a where a.run_id=r.run_id and a.validator_outcome='PASS'),0) validator_pass_count,
      coalesce((select count(*) from programacion.input_family_assessments a where a.run_id=r.run_id and a.applicability='APPLICABLE' and 'NOT_APPLICABLE'=any(array[a.coverage_status,a.well_defined_status,a.story_ready_status,a.implementation_ready_status,a.qa_ready_status,a.production_ready_status])),0) applicability_invariant_violations,
      coalesce((select count(*) from programacion.input_family_assessments a where a.run_id=r.run_id and a.applicability='NOT_APPLICABLE' and exists(select 1 from unnest(array[a.coverage_status,a.well_defined_status,a.story_ready_status,a.implementation_ready_status,a.qa_ready_status,a.production_ready_status]) st where st<>'NOT_APPLICABLE')),0) na_invariant_violations,
      coalesce((select count(*) from programacion.input_family_assessments a where a.run_id=r.run_id and a.severity not in ('P0','P1','P2','P3','P4')),0) severity_unresolved,
      coalesce((select count(*) from programacion.input_family_assessments a where a.run_id=r.run_id and a.applicability in ('APPLICABLE','UNRESOLVED') and a.story_ready_status<>'READY' and a.severity<>'P0'),0) story_open_not_p0,
      coalesce((select count(*) from programacion.input_family_assessments a where a.run_id=r.run_id and a.applicability='APPLICABLE' and a.implementation_ready_status='READY' and (a.coverage_status<>'COMPLETE' or a.well_defined_status<>'COMPLETE')),0) implementation_monotonicity_violations,
      coalesce((select count(*) from programacion.input_family_assessments a where a.run_id=r.run_id and a.applicability='NOT_APPLICABLE' and not exists(select 1 from jsonb_array_elements(a.source_refs) sr where sr->>'kind'<>'CAPABILITY_ABSENCE')),0) na_authority_violations,
      case when r.run_id is null then null else programacion.fn_input_stage_gate_summary(r.run_id) end stage_summary
    from runs r
  ), shaped as (
    select *,
      (run_id is not null and run_status='COMPLETED' and run_current and family_count=47 and validator_pass_count=47 and applicability_invariant_violations=0 and na_invariant_violations=0) mechanics_healthy,
      (run_id is not null and run_status='COMPLETED' and run_current and family_count=47 and validator_pass_count=47 and applicability_invariant_violations=0 and na_invariant_violations=0
       and severity_unresolved=0 and story_open_not_p0=0 and implementation_monotonicity_violations=0 and na_authority_violations=0
       and coalesce((stage_summary->>'canonical_story_gate_pass')::boolean,false)) healthy
    from checks
  )
  select count(*),count(*) filter(where healthy),count(*) filter(where mechanics_healthy),coalesce(jsonb_agg(jsonb_build_object(
      'pantalla_id',id,'screen_code',codigo,'name',nombre,'run_id',run_id,'run_status',run_status,'run_current',run_current,
      'family_count',family_count,'validator_pass_count',validator_pass_count,'applicability_invariant_violations',applicability_invariant_violations,'na_invariant_violations',na_invariant_violations,
      'severity_unresolved',severity_unresolved,'story_open_not_p0',story_open_not_p0,'implementation_monotonicity_violations',implementation_monotonicity_violations,'na_authority_violations',na_authority_violations,
      'canonical_story_gate_pass',stage_summary->'canonical_story_gate_pass','mechanics_healthy',mechanics_healthy,'healthy',healthy) order by id),'[]'::jsonb)
    into v_screen_count,v_healthy,v_mechanics_healthy,v_rows from shaped;
  v_payload:=jsonb_build_object('health_contract','INPUT_GOVERNANCE_MODULE_HEALTH_V2',
    'version',jsonb_build_object('version_id',p_version_id,'version_code',v_version.version_codigo,'version_state',v_version.estado,'agent_code',v_version.agente_codigo,'agent_state',v_version.agent_state),
    'readiness_contract',jsonb_build_object('contract_id',v_contract.id,'contract_revision',v_contract.contract_revision,'negative_test_count',v_contract.negative_test_count,'fail_closed',v_contract.fail_closed,'state',v_contract.estado),
    'module_code',p_module_code,'screen_count',v_screen_count,'mechanics_healthy_screen_count',v_mechanics_healthy,'healthy_screen_count',v_healthy,
    'downstream_contract_count',v_downstream_contract_count,'required_downstream_contract_count',3,'screens',v_rows,
    'mechanics_pass',v_screen_count>0 and v_mechanics_healthy=v_screen_count and v_downstream_contract_count=3,
    'health_pass',v_screen_count>0 and v_healthy=v_screen_count and v_downstream_contract_count=3,
    'promotion_authorized',false,'note','V2 separates mechanical integrity from semantic story readiness; health_pass is fail-closed on semantic blockers and current contract pins.');
  return v_payload||jsonb_build_object('health_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$$;