create or replace function programacion.fn_input_evaluation_outcome_summary_known_current_v1(p_run_id bigint,p_run_current boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,programacion
as $function$
declare
  v_expected bigint;
  v_total bigint;
  v_pass bigint;
  v_positive bigint;
  v_na bigint;
  v_negative bigint;
  v_unresolved bigint;
  v_terminal bigint;
  v_items jsonb;
begin
  if not p_run_current then raise exception 'INPUT_EVALUATION_KNOWN_CURRENT_REQUIRED:%',p_run_id; end if;
  select family_count into v_expected from programacion.input_readiness_runs where id=p_run_id;
  if v_expected is null then raise exception 'INPUT_EVALUATION_RUN_NOT_FOUND:%',p_run_id; end if;
  with classified as (
    select a.*,
      case when a.validator_outcome<>'PASS' then 'NOT_VALIDATED'
           when a.story_ready_status='READY' then 'POSITIVE'
           when a.story_ready_status='NOT_APPLICABLE' then 'NOT_APPLICABLE'
           when a.story_ready_status='BLOCKED' then 'NEGATIVE_CONFIRMED'
           else 'UNRESOLVED' end as evaluation_outcome,
      (a.validator_outcome='PASS' and a.story_ready_status in ('READY','NOT_APPLICABLE','BLOCKED')) as terminal_eval
    from programacion.input_family_assessments a where a.run_id=p_run_id
  )
  select count(*),count(*) filter(where validator_outcome='PASS'),count(*) filter(where evaluation_outcome='POSITIVE'),
         count(*) filter(where evaluation_outcome='NOT_APPLICABLE'),count(*) filter(where evaluation_outcome='NEGATIVE_CONFIRMED'),
         count(*) filter(where evaluation_outcome in ('NOT_VALIDATED','UNRESOLVED')),count(*) filter(where terminal_eval),
         coalesce(jsonb_agg(jsonb_build_object('assessment_id',id,'family_code',family_code,'evaluation_outcome',evaluation_outcome,'terminal_for_current_evaluation',terminal_eval,'story_ready_status',story_ready_status,'severity',severity,'applicability',applicability,'coverage_status',coverage_status,'well_defined_status',well_defined_status,'blockers',blockers,'source_refs',source_refs,'rationale',rationale,'validator_outcome',validator_outcome) order by family_code),'[]'::jsonb)
  into v_total,v_pass,v_positive,v_na,v_negative,v_unresolved,v_terminal,v_items
  from classified;
  return jsonb_build_object('schema_version',1,'run_id',p_run_id,'evaluation_contract','CURRENT_CUT_TERMINAL_OUTCOME_V1','decision_authority','DEC-INPUT-GOV-EVAL-OUTCOME-001','run_is_current',true,'expected_family_count',v_expected,'total_family_count',v_total,'validator_pass_count',v_pass,'positive_count',v_positive,'not_applicable_count',v_na,'negative_confirmed_count',v_negative,'unresolved_or_not_validated_count',v_unresolved,'terminal_count',v_terminal,'current_evaluation_complete',(v_total=v_expected and v_pass=v_expected and v_terminal=v_expected and v_unresolved=0),'negative_does_not_mean_not_applicable',true,'negative_does_not_relax_story_gate',true,'remediation_is_separate_from_evaluation',true,'items',v_items);
end;
$function$;