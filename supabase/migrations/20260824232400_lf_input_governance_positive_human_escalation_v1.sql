-- LF Input Governance positive human escalation authority v1
-- GOV-015 recurrence: pending_decision marker alone is not owner escalation authority.

update transversal.decision_log
set decision = decision || ' HUMAN_DECISION_REQUIRED requiere autoridad positiva explícita de owner escalation; pendiente_decision, evidencia faltante o candidato técnico por sí solos permanecen en remediación interna.',
    impacto = impacto || ' Owner escalation is fail-closed: no positive authority => internal remediation, not user interruption.'
where adr='DEC-INPUT-GOV-SELF-REMEDIATE-001';

update programacion.contratos
set especificacion=jsonb_set(
  especificacion,
  '{remediation_loop,owner_escalation}',
  '"POSITIVE_OWNER_AUTHORITY_ONLY"'::jsonb,
  true
)
where version_id=19 and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT';

create or replace function programacion.fn_input_governance_materialize_gap_proposals_v1(
  p_run_id bigint
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,programacion
as $function$
declare
  v_run record;
  a record;
  b jsonb;
  v_gap text;
  v_kind text;
  v_class text;
  v_positive_owner_authority boolean;
  v_count int:=0;
  v_human int:=0;
  v_auto int:=0;
begin
  select * into v_run from programacion.input_readiness_runs where id=p_run_id;
  if not found then raise exception 'INPUT_REMEDIATION_RUN_NOT_FOUND:%',p_run_id; end if;
  if v_run.status<>'CURATING' then raise exception 'INPUT_REMEDIATION_REQUIRES_CURATING:%',p_run_id; end if;

  for a in
    select * from programacion.input_family_assessments
    where run_id=p_run_id and jsonb_array_length(blockers)>0
    order by family_code,id
  loop
    for b in select value from jsonb_array_elements(a.blockers)
    loop
      v_gap:=coalesce(b->>'code','UNSPECIFIED_GAP');
      if a.family_code in ('PROFILES','PERMISSIONS','FEATURE_FLAGS','I18N_FORMATS') then
        v_class:='APPLICABILITY_AUTHORITY_GAP';
      elsif a.story_ready_status='READY' then
        v_class:='STAGE_SPECIFIC_GAP';
      elsif v_gap ~ '(EVIDENCE|AUTHORITY|PROVENANCE)' then
        v_class:='GOVERNANCE_EVIDENCE_GAP';
      else
        v_class:='FUNCTIONAL_DEFINITION_GAP';
      end if;

      v_positive_owner_authority :=
        coalesce((b->>'owner_decision_required')::boolean,false)
        and nullif(b->>'owner_decision_authority','') is not null;

      if v_positive_owner_authority then
        v_kind:='HUMAN_DECISION_REQUIRED';
      elsif v_gap ~ '(CONFLICT|RECONCILIATION)' then
        v_kind:='SOURCE_CONFLICT';
      elsif coalesce((a.curator_evidence->'bootstrap_probe'->>'pending_decision_count')::int,0)>0 then
        v_kind:='RESEARCH_REQUIRED';
      else
        v_kind:='SOURCE_INCOMPLETE';
      end if;

      insert into programacion.input_gap_proposals(
        run_id,assessment_id,family_code,gap_code,proposal_kind,
        proposed_payload,canonical_target,source_refs,evidence_refs,confidence,
        stage_impact,contradictions_checked,status,curator_identity,curator_execution_id
      ) values(
        p_run_id,a.id,a.family_code,v_gap,v_kind,
        jsonb_build_object(
          'gap_classification',v_class,
          'agent_action',case
            when v_kind='HUMAN_DECISION_REQUIRED' then 'ESCALATE_AFTER_VALIDATION'
            when a.family_code='DESIGN_SYSTEM' then 'SEARCH_AND_VALIDATE_EXISTING_CANONICAL_BINDING_BEFORE_ESCALATION'
            when v_kind='RESEARCH_REQUIRED' then 'RESOLVE_PENDING_SOURCE_OR_EVIDENCE_INTERNALLY'
            else 'KEEP_IN_INTERNAL_REMEDIATION_QUEUE'
          end,
          'blocker',b,
          'positive_owner_escalation_authority',v_positive_owner_authority,
          'pending_marker_is_not_owner_authority',true,
          'no_invention',true,
          'proposal_is_canonical_source',false,
          'automatic_canonicalization','DENY',
          'analysis_revision',coalesce(v_run.scope->>'analysis_revision','INPUT_GOV_REMEDIATION_1_3')
        ),
        jsonb_build_object('pantalla_id',v_run.pantalla_id,'family_code',a.family_code),
        a.source_refs,'[]'::jsonb,
        case when v_positive_owner_authority then 1.0 else 0.9 end,
        jsonb_build_object('story',a.story_ready_status,'implementation',a.implementation_ready_status,'qa',a.qa_ready_status,'production',a.production_ready_status),
        jsonb_build_array('GOV-015_CLASSIFICATION_APPLIED','POSITIVE_OWNER_AUTHORITY_REQUIRED','NO_PROPOSAL_AS_CANONICAL_SOURCE'),
        'PROPOSED',v_run.curator_identity,coalesce(a.curator_evidence->>'execution_id','UNKNOWN')
      ) on conflict (run_id,family_code,gap_code) do nothing;
      if found then
        v_count:=v_count+1;
        if v_kind='HUMAN_DECISION_REQUIRED' then v_human:=v_human+1; else v_auto:=v_auto+1; end if;
      end if;
    end loop;
  end loop;
  return jsonb_build_object('run_id',p_run_id,'proposal_count',v_count,'internal_remediation_count',v_auto,'human_decision_candidate_count',v_human,'owner_escalation_policy','POSITIVE_OWNER_AUTHORITY_ONLY');
end;
$function$;

-- Preserve run 195 as evidence of the over-escalation defect; do not rewrite its immutable proposals.
update programacion.input_readiness_runs
set invalidated_at=now(),
    invalidated_reason='GOV-015_PENDING_MARKER_NOT_OWNER_AUTHORITY'
where id=195 and pantalla_id=2 and status='COMPLETED' and invalidated_at is null;

-- Negative regression: no ONB_002 blocker currently carries positive owner escalation authority.
do $block$
declare v_count int;
begin
  select count(*) into v_count
  from programacion.input_family_assessments a,
       lateral jsonb_array_elements(a.blockers) b
  where a.run_id=195
    and coalesce((b->>'owner_decision_required')::boolean,false)
    and nullif(b->>'owner_decision_authority','') is not null;
  if v_count<>0 then raise exception 'POSITIVE_OWNER_AUTHORITY_REGRESSION_EXPECTED_ZERO:%',v_count; end if;
end;
$block$;