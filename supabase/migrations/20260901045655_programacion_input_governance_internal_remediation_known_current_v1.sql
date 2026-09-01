create or replace function programacion.fn_input_internal_remediation_summary_known_current_v1(p_run_id bigint,p_eval jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,programacion
as $function$
declare
  v_count bigint;
  v_families bigint;
  v_research bigint;
  v_incomplete bigint;
  v_conflict bigint;
  v_negative bigint;
  v_later bigint;
  v_items jsonb;
begin
  if coalesce((p_eval->>'run_is_current')::boolean,false) is not true then raise exception 'INPUT_REMEDIATION_KNOWN_CURRENT_REQUIRED:%',p_run_id; end if;
  if (p_eval->>'run_id')::bigint is distinct from p_run_id then raise exception 'INPUT_REMEDIATION_EVAL_RUN_MISMATCH:%',p_run_id; end if;
  with q as (
    select p.id,p.family_code,p.gap_code,p.proposal_kind,p.status,p.proposed_payload,p.canonical_target,p.source_refs,p.evidence_refs,p.confidence,p.stage_impact,
      case when a.validator_outcome<>'PASS' then 'NOT_VALIDATED'
           when a.story_ready_status='READY' then 'POSITIVE'
           when a.story_ready_status='NOT_APPLICABLE' then 'NOT_APPLICABLE'
           when a.story_ready_status='BLOCKED' then 'NEGATIVE_CONFIRMED'
           else 'UNRESOLVED' end as evaluation_outcome
    from programacion.input_gap_proposals p
    join programacion.input_family_assessments a on a.id=p.assessment_id and a.run_id=p.run_id
    where p.run_id=p_run_id and p.validator_outcome='PASS' and p.status='VALIDATED'
  )
  select count(*),count(distinct family_code),count(*) filter(where proposal_kind='RESEARCH_REQUIRED'),count(*) filter(where proposal_kind='SOURCE_INCOMPLETE'),count(*) filter(where proposal_kind='SOURCE_CONFLICT'),count(*) filter(where evaluation_outcome='NEGATIVE_CONFIRMED'),count(*) filter(where evaluation_outcome in ('POSITIVE','NOT_APPLICABLE')),
         coalesce(jsonb_agg(jsonb_build_object('proposal_id',id,'family_code',family_code,'gap_code',gap_code,'proposal_kind',proposal_kind,'status',status,'evaluation_outcome',evaluation_outcome,'terminal_for_current_evaluation',(evaluation_outcome in ('POSITIVE','NOT_APPLICABLE','NEGATIVE_CONFIRMED')),'remediation_continues',true,'gap_classification',proposed_payload->>'gap_classification','agent_action',proposed_payload->>'agent_action','canonical_target',canonical_target,'source_refs',source_refs,'evidence_refs',evidence_refs,'confidence',confidence,'stage_impact',stage_impact) order by id),'[]'::jsonb)
  into v_count,v_families,v_research,v_incomplete,v_conflict,v_negative,v_later,v_items
  from q;
  return jsonb_build_object('schema_version',2,'run_id',p_run_id,'internal_remediation_count',v_count,'family_count',v_families,'research_required_count',v_research,'source_incomplete_count',v_incomplete,'source_conflict_count',v_conflict,'negative_confirmed_remediation_count',v_negative,'later_stage_or_positive_remediation_count',v_later,'owner_interruption_required',false,'proposal_is_canonical_source',false,'automatic_canonicalization','DENY','decision_authority','DEC-INPUT-GOV-SELF-REMEDIATE-001','evaluation_boundary','CURRENT_CUT_RESULT_SEPARATE_FROM_REMEDIATION','current_evaluation_summary',(p_eval-'items'),'items',v_items);
end;
$function$;