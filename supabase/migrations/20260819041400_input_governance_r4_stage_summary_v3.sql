create or replace function programacion.fn_input_stage_gate_summary(p_run_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $$
declare
  v_run programacion.input_readiness_runs%rowtype;
  v_summary jsonb; v_violations jsonb; v_contract jsonb;
begin
  select * into v_run from programacion.input_readiness_runs where id=p_run_id;
  if not found then raise exception 'INPUT_STAGE_GATE_RUN_NOT_FOUND:%',p_run_id; end if;
  select c.especificacion into v_contract from programacion.contratos c where c.version_id=v_run.version_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';

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
    'story_ready_bad_coverage',count(*) filter(where applicability='APPLICABLE' and story_ready_status='READY' and (coverage_status in ('MISSING','PENDING','BLOCKED') or well_defined_status in ('MISSING','PENDING','BLOCKED')) and not coalesce((v_contract->'family_stage_requirements'->family_code->>'allow_story_ready_when_incomplete')::boolean,false)),
    'implementation_ready_incomplete_coverage',count(*) filter(where applicability='APPLICABLE' and implementation_ready_status='READY' and (coverage_status<>'COMPLETE' or well_defined_status<>'COMPLETE') and not coalesce((v_contract->'family_stage_requirements'->family_code->>'allow_implementation_ready_when_incomplete')::boolean,false)),
    'stage_specific_incomplete_allowed',count(*) filter(where applicability='APPLICABLE' and ((story_ready_status='READY' and (coverage_status in ('MISSING','PENDING','BLOCKED') or well_defined_status in ('MISSING','PENDING','BLOCKED')) and coalesce((v_contract->'family_stage_requirements'->family_code->>'allow_story_ready_when_incomplete')::boolean,false)) or (implementation_ready_status='READY' and (coverage_status<>'COMPLETE' or well_defined_status<>'COMPLETE') and coalesce((v_contract->'family_stage_requirements'->family_code->>'allow_implementation_ready_when_incomplete')::boolean,false)))),
    'na_only_absence_authority',count(*) filter(where applicability='NOT_APPLICABLE' and not exists(select 1 from jsonb_array_elements(source_refs) r where r->>'kind'<>'CAPABILITY_ABSENCE'))
  ) into v_summary from programacion.input_family_assessments where run_id=p_run_id;

  select coalesce(jsonb_agg(v order by v->>'family_code',v->>'code'),'[]'::jsonb) into v_violations
  from (
    select jsonb_build_object('family_code',family_code,'code','IMPLEMENTATION_READY_WHILE_STORY_NOT_READY') v from programacion.input_family_assessments where run_id=p_run_id and applicability='APPLICABLE' and implementation_ready_status='READY' and story_ready_status<>'READY'
    union all select jsonb_build_object('family_code',family_code,'code','QA_READY_WHILE_IMPLEMENTATION_NOT_READY') from programacion.input_family_assessments where run_id=p_run_id and applicability='APPLICABLE' and qa_ready_status='READY' and implementation_ready_status<>'READY'
    union all select jsonb_build_object('family_code',family_code,'code','PRODUCTION_READY_WHILE_QA_NOT_READY') from programacion.input_family_assessments where run_id=p_run_id and applicability='APPLICABLE' and production_ready_status='READY' and qa_ready_status<>'READY'
    union all select jsonb_build_object('family_code',family_code,'code','STORY_OPEN_WITHOUT_P0') from programacion.input_family_assessments where run_id=p_run_id and applicability in ('APPLICABLE','UNRESOLVED') and story_ready_status<>'READY' and severity<>'P0'
    union all select jsonb_build_object('family_code',family_code,'code','STORY_READY_WITH_INCOMPLETE_COVERAGE_WITHOUT_STAGE_AUTHORITY') from programacion.input_family_assessments where run_id=p_run_id and applicability='APPLICABLE' and story_ready_status='READY' and (coverage_status in ('MISSING','PENDING','BLOCKED') or well_defined_status in ('MISSING','PENDING','BLOCKED')) and not coalesce((v_contract->'family_stage_requirements'->family_code->>'allow_story_ready_when_incomplete')::boolean,false)
    union all select jsonb_build_object('family_code',family_code,'code','IMPLEMENTATION_READY_WITH_INCOMPLETE_COVERAGE') from programacion.input_family_assessments where run_id=p_run_id and applicability='APPLICABLE' and implementation_ready_status='READY' and (coverage_status<>'COMPLETE' or well_defined_status<>'COMPLETE') and not coalesce((v_contract->'family_stage_requirements'->family_code->>'allow_implementation_ready_when_incomplete')::boolean,false)
  ) z;

  return jsonb_build_object('stage_gate_contract','INPUT_STAGE_GATE_SUMMARY_V3_STAGE_AWARE','run_id',p_run_id,'run_status',v_run.status,
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
