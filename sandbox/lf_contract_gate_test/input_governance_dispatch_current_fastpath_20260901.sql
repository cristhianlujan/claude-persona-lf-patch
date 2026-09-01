-- Current-run dispatcher fastpath.
-- Safety invariant: fn_input_governance_execute still executes the full
-- fn_input_readiness_run_is_current check before these helpers are used.
-- The helpers only avoid re-running that same 47-family currentness proof
-- multiple times inside the same dispatcher invocation.

create or replace function programacion.fn_input_stage_gate_summary_known_current_v1(
  p_run_id bigint,
  p_run_current boolean
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,programacion
as $function$
declare
  v_run programacion.input_readiness_runs%rowtype;
  v_summary jsonb; v_violations jsonb; v_contract jsonb;
begin
  select * into v_run from programacion.input_readiness_runs where id=p_run_id;
  if not found then raise exception 'INPUT_STAGE_GATE_RUN_NOT_FOUND:%',p_run_id; end if;
  if v_run.status='COMPLETED' and not p_run_current then raise exception 'INPUT_STAGE_GATE_KNOWN_CURRENT_REQUIRED:%',p_run_id; end if;
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
    'story_ready_bad_coverage',count(*) filter(where applicability='APPLICABLE' and story_ready_status='READY' and (coverage_status in ('MISSING','PENDING','BLOCKED') or well_defined_status in ('MISSING','PENDING','BLOCKED')) and not (coalesce((v_contract->'family_stage_requirements'->family_code->>'allow_story_ready_when_incomplete')::boolean,false) and programacion.fn_input_stage_authority_applies_v1(family_code,v_run.pantalla_id,v_run.version_id,coverage_status,well_defined_status))),
    'implementation_ready_incomplete_coverage',count(*) filter(where applicability='APPLICABLE' and implementation_ready_status='READY' and (coverage_status<>'COMPLETE' or well_defined_status<>'COMPLETE') and not (coalesce((v_contract->'family_stage_requirements'->family_code->>'allow_implementation_ready_when_incomplete')::boolean,false) and programacion.fn_input_stage_authority_applies_v1(family_code,v_run.pantalla_id,v_run.version_id,coverage_status,well_defined_status))),
    'stage_specific_incomplete_allowed',count(*) filter(where applicability='APPLICABLE' and ((story_ready_status='READY' and (coverage_status in ('MISSING','PENDING','BLOCKED') or well_defined_status in ('MISSING','PENDING','BLOCKED')) and (coalesce((v_contract->'family_stage_requirements'->family_code->>'allow_story_ready_when_incomplete')::boolean,false) and programacion.fn_input_stage_authority_applies_v1(family_code,v_run.pantalla_id,v_run.version_id,coverage_status,well_defined_status))) or (implementation_ready_status='READY' and (coverage_status<>'COMPLETE' or well_defined_status<>'COMPLETE') and (coalesce((v_contract->'family_stage_requirements'->family_code->>'allow_implementation_ready_when_incomplete')::boolean,false) and programacion.fn_input_stage_authority_applies_v1(family_code,v_run.pantalla_id,v_run.version_id,coverage_status,well_defined_status))))),
    'na_only_absence_authority',count(*) filter(where applicability='NOT_APPLICABLE' and not exists(select 1 from jsonb_array_elements(source_refs) r where r->>'kind'<>'CAPABILITY_ABSENCE'))
  ) into v_summary from programacion.input_family_assessments where run_id=p_run_id;

  select coalesce(jsonb_agg(v order by v->>'family_code',v->>'code'),'[]'::jsonb) into v_violations
  from (
    select jsonb_build_object('family_code',family_code,'code','IMPLEMENTATION_READY_WHILE_STORY_NOT_READY') v from programacion.input_family_assessments where run_id=p_run_id and applicability='APPLICABLE' and implementation_ready_status='READY' and story_ready_status<>'READY'
    union all select jsonb_build_object('family_code',family_code,'code','QA_READY_WHILE_IMPLEMENTATION_NOT_READY') from programacion.input_family_assessments where run_id=p_run_id and applicability='APPLICABLE' and qa_ready_status='READY' and implementation_ready_status<>'READY'
    union all select jsonb_build_object('family_code',family_code,'code','PRODUCTION_READY_WHILE_QA_NOT_READY') from programacion.input_family_assessments where run_id=p_run_id and applicability='APPLICABLE' and production_ready_status='READY' and qa_ready_status<>'READY'
    union all select jsonb_build_object('family_code',family_code,'code','STORY_OPEN_WITHOUT_P0') from programacion.input_family_assessments where run_id=p_run_id and applicability in ('APPLICABLE','UNRESOLVED') and story_ready_status<>'READY' and severity<>'P0'
    union all select jsonb_build_object('family_code',family_code,'code','STORY_READY_WITH_INCOMPLETE_COVERAGE_WITHOUT_STAGE_AUTHORITY') from programacion.input_family_assessments where run_id=p_run_id and applicability='APPLICABLE' and story_ready_status='READY' and (coverage_status in ('MISSING','PENDING','BLOCKED') or well_defined_status in ('MISSING','PENDING','BLOCKED')) and not (coalesce((v_contract->'family_stage_requirements'->family_code->>'allow_story_ready_when_incomplete')::boolean,false) and programacion.fn_input_stage_authority_applies_v1(family_code,v_run.pantalla_id,v_run.version_id,coverage_status,well_defined_status))
    union all select jsonb_build_object('family_code',family_code,'code','IMPLEMENTATION_READY_WITH_INCOMPLETE_COVERAGE') from programacion.input_family_assessments where run_id=p_run_id and applicability='APPLICABLE' and implementation_ready_status='READY' and (coverage_status<>'COMPLETE' or well_defined_status<>'COMPLETE') and not (coalesce((v_contract->'family_stage_requirements'->family_code->>'allow_implementation_ready_when_incomplete')::boolean,false) and programacion.fn_input_stage_authority_applies_v1(family_code,v_run.pantalla_id,v_run.version_id,coverage_status,well_defined_status))
  ) z;

  return jsonb_build_object('stage_gate_contract','INPUT_STAGE_GATE_SUMMARY_V4_CONDITIONAL_STAGE_AUTHORITY','run_id',p_run_id,'run_status',v_run.status,
    'run_current',case when v_run.status='COMPLETED' then p_run_current else false end,
    'summary',v_summary,
    'canonical_story_gate_pass',coalesce((v_summary->>'story_stage_open')::integer,0)=0 and coalesce((v_summary->>'severity_unresolved')::integer,0)=0 and coalesce((v_summary->>'story_open_not_p0')::integer,0)=0,
    'legacy_no_applicable_p0_open_pass',coalesce((v_summary->>'applicable_p0_story_open')::integer,0)=0,
    'full_story_stage_closed',coalesce((v_summary->>'story_stage_open')::integer,0)=0,
    'full_implementation_stage_closed',coalesce((v_summary->>'implementation_stage_open')::integer,0)=0,
    'full_qa_stage_closed',coalesce((v_summary->>'qa_stage_open')::integer,0)=0,
    'full_production_stage_closed',coalesce((v_summary->>'production_stage_open')::integer,0)=0,
    'hierarchy_violation_count',jsonb_array_length(v_violations),'hierarchy_violations',v_violations);
end;
$function$;

create or replace function programacion.fn_input_evaluation_outcome_summary_known_current_v1(
  p_run_id bigint,
  p_run_current boolean
) returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,programacion
as $function$
  with run_meta as (
    select r.id,r.family_count from programacion.input_readiness_runs r where r.id=p_run_id
  ), classified as (
    select a.id assessment_id,a.family_code,a.severity,a.applicability,a.story_ready_status,a.coverage_status,a.well_defined_status,a.blockers,a.source_refs,a.rationale,a.validator_outcome,
      case when a.validator_outcome<>'PASS' then 'NOT_VALIDATED' when a.story_ready_status='READY' then 'POSITIVE' when a.story_ready_status='NOT_APPLICABLE' then 'NOT_APPLICABLE' when a.story_ready_status='BLOCKED' then 'NEGATIVE_CONFIRMED' else 'UNRESOLVED' end evaluation_outcome,
      (a.validator_outcome='PASS' and a.story_ready_status in ('READY','NOT_APPLICABLE','BLOCKED')) terminal_for_current_evaluation
    from programacion.input_family_assessments a where a.run_id=p_run_id
  ), agg as (
    select count(*) total_count,count(*) filter(where validator_outcome='PASS') validator_pass_count,count(*) filter(where evaluation_outcome='POSITIVE') positive_count,
      count(*) filter(where evaluation_outcome='NOT_APPLICABLE') not_applicable_count,count(*) filter(where evaluation_outcome='NEGATIVE_CONFIRMED') negative_confirmed_count,
      count(*) filter(where evaluation_outcome in ('NOT_VALIDATED','UNRESOLVED')) unresolved_count,count(*) filter(where terminal_for_current_evaluation) terminal_count,
      coalesce(jsonb_agg(jsonb_build_object('assessment_id',assessment_id,'family_code',family_code,'evaluation_outcome',evaluation_outcome,'terminal_for_current_evaluation',terminal_for_current_evaluation,'story_ready_status',story_ready_status,'severity',severity,'applicability',applicability,'coverage_status',coverage_status,'well_defined_status',well_defined_status,'blockers',blockers,'source_refs',source_refs,'rationale',rationale,'validator_outcome',validator_outcome) order by family_code),'[]'::jsonb) items
    from classified
  )
  select jsonb_build_object(
    'schema_version',1,'run_id',p_run_id,'evaluation_contract','CURRENT_CUT_TERMINAL_OUTCOME_V1','decision_authority','DEC-INPUT-GOV-EVAL-OUTCOME-001',
    'run_is_current',p_run_current,'expected_family_count',coalesce(r.family_count,0),'total_family_count',a.total_count,'validator_pass_count',a.validator_pass_count,
    'positive_count',a.positive_count,'not_applicable_count',a.not_applicable_count,'negative_confirmed_count',a.negative_confirmed_count,
    'unresolved_or_not_validated_count',a.unresolved_count,'terminal_count',a.terminal_count,
    'current_evaluation_complete',(p_run_current and a.total_count=coalesce(r.family_count,0) and a.validator_pass_count=coalesce(r.family_count,0) and a.terminal_count=coalesce(r.family_count,0) and a.unresolved_count=0),
    'negative_does_not_mean_not_applicable',true,'negative_does_not_relax_story_gate',true,'remediation_is_separate_from_evaluation',true,'items',a.items)
  from run_meta r cross join agg a;
$function$;

create or replace function programacion.fn_input_internal_remediation_summary_known_current_v1(
  p_run_id bigint,
  p_eval jsonb
) returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,programacion
as $function$
  with q as (
    select p.id,p.family_code,p.gap_code,p.proposal_kind,p.status,p.validator_outcome,p.proposed_payload,p.canonical_target,p.source_refs,p.evidence_refs,p.confidence,p.stage_impact,a.story_ready_status,
      case when a.validator_outcome<>'PASS' then 'NOT_VALIDATED' when a.story_ready_status='READY' then 'POSITIVE' when a.story_ready_status='NOT_APPLICABLE' then 'NOT_APPLICABLE' when a.story_ready_status='BLOCKED' then 'NEGATIVE_CONFIRMED' else 'UNRESOLVED' end evaluation_outcome
    from programacion.input_gap_proposals p
    join programacion.input_family_assessments a on a.id=p.assessment_id and a.run_id=p.run_id
    where p.run_id=p_run_id and p.validator_outcome='PASS' and p.status='VALIDATED'
  )
  select jsonb_build_object(
    'schema_version',2,'run_id',p_run_id,'internal_remediation_count',count(q.id),'family_count',count(distinct q.family_code),
    'research_required_count',count(q.id) filter(where q.proposal_kind='RESEARCH_REQUIRED'),'source_incomplete_count',count(q.id) filter(where q.proposal_kind='SOURCE_INCOMPLETE'),
    'source_conflict_count',count(q.id) filter(where q.proposal_kind='SOURCE_CONFLICT'),'negative_confirmed_remediation_count',count(q.id) filter(where q.evaluation_outcome='NEGATIVE_CONFIRMED'),
    'later_stage_or_positive_remediation_count',count(q.id) filter(where q.evaluation_outcome in ('POSITIVE','NOT_APPLICABLE')),'owner_interruption_required',false,
    'proposal_is_canonical_source',false,'automatic_canonicalization','DENY','decision_authority','DEC-INPUT-GOV-SELF-REMEDIATE-001','evaluation_boundary','CURRENT_CUT_RESULT_SEPARATE_FROM_REMEDIATION',
    'current_evaluation_summary',(p_eval-'items'),
    'items',coalesce(jsonb_agg(jsonb_build_object('proposal_id',q.id,'family_code',q.family_code,'gap_code',q.gap_code,'proposal_kind',q.proposal_kind,'status',q.status,'evaluation_outcome',q.evaluation_outcome,'terminal_for_current_evaluation',(q.evaluation_outcome in ('POSITIVE','NOT_APPLICABLE','NEGATIVE_CONFIRMED')),'remediation_continues',true,'gap_classification',q.proposed_payload->>'gap_classification','agent_action',q.proposed_payload->>'agent_action','canonical_target',q.canonical_target,'source_refs',q.source_refs,'evidence_refs',q.evidence_refs,'confidence',q.confidence,'stage_impact',q.stage_impact) order by q.id) filter(where q.id is not null),'[]'::jsonb))
  from q;
$function$;

do $migration$
declare
  v_def text;
  v_sha text;
  v_new text;
begin
  select pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure),
         encode(digest(pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure),'sha256'),'hex')
    into v_def,v_sha;
  if v_sha<>'14d6433fbaf1f024cc960eef934983fe47f68a3b8ede913627ea3b20e980d444' then
    raise exception 'INPUT_GOV_DISPATCH_BASELINE_SHA_MISMATCH:%',v_sha;
  end if;
  v_new:=replace(v_def,'v_stage:=programacion.fn_input_stage_gate_summary(v_run);','v_stage:=programacion.fn_input_stage_gate_summary_known_current_v1(v_run,true);');
  v_new:=replace(v_new,'v_eval:=programacion.fn_input_evaluation_outcome_summary(v_run);','v_eval:=programacion.fn_input_evaluation_outcome_summary_known_current_v1(v_run,true);');
  v_new:=replace(v_new,'v_internal_summary:=programacion.fn_input_internal_remediation_summary(v_run);','v_internal_summary:=programacion.fn_input_internal_remediation_summary_known_current_v1(v_run,v_eval);');
  if v_new=v_def then raise exception 'INPUT_GOV_DISPATCH_FASTPATH_REPLACEMENT_NOT_APPLIED'; end if;
  if position('fn_input_stage_gate_summary_known_current_v1' in v_new)=0 or position('fn_input_evaluation_outcome_summary_known_current_v1' in v_new)=0 or position('fn_input_internal_remediation_summary_known_current_v1' in v_new)=0 then
    raise exception 'INPUT_GOV_DISPATCH_FASTPATH_INCOMPLETE';
  end if;
  execute v_new;
end;
$migration$;
