-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M5.8 / PAULO-073
-- APPLY_POLICY: route CREATE / INHERIT / CLOSE evaluation through the single gap materializer.
-- Scope: programacion.fn_input_governance_materialize_gap_proposals_v1 + input_gap_proposals only.
-- No canonical business-source write and no production/runtime activation.

create or replace function programacion.fn_input_governance_materialize_gap_proposals_v1(p_run_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_run record;
  a record;
  b jsonb;
  v_gap text;
  v_kind text;
  v_class text;
  v_synthesis text;
  v_result text;
  v_positive_owner_authority boolean;
  v_policy jsonb;
  v_policy_ref text;
  v_count int:=0;
  v_human int:=0;
  v_auto int:=0;
  v_create int:=0;
  v_inherit int:=0;
  v_close_candidates int:=0;
begin
  select c.especificacion->'gap_policy_contract',
         c.especificacion->>'gap_policy_decision'
    into v_policy,v_policy_ref
  from programacion.contratos c
  where c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
    and c.estado='defined'
    and c.fail_closed
  order by c.version_id desc,c.id desc
  limit 1;

  if coalesce(v_policy->>'schema_version','')<>'INPUT_GAP_POLICY_V1'
     or v_policy_ref<>'DEC-INPUT-GOV-GAP-POLICY-001'
     or v_policy->>'targeted_evidence_before_escalation'<>'TARGETED_EVIDENCE_ACQUISITION'
     or v_policy->>'canonical_change_admission'<>'SAFE_CHANGE_ADMISSION' then
    raise exception 'INPUT_GAP_POLICY_NOT_CURRENT_OR_INCOMPLETE';
  end if;

  select * into v_run
  from programacion.input_readiness_runs
  where id=p_run_id;

  if not found then
    raise exception 'INPUT_REMEDIATION_RUN_NOT_FOUND:%',p_run_id;
  end if;
  if v_run.status<>'CURATING' then
    raise exception 'INPUT_REMEDIATION_REQUIRES_CURATING:%',p_run_id;
  end if;

  for a in
    select *
    from programacion.input_family_assessments
    where run_id=p_run_id
      and jsonb_array_length(blockers)>0
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

      v_positive_owner_authority:=
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

      if v_kind in ('HUMAN_DECISION_REQUIRED','SOURCE_CONFLICT') then
        v_synthesis:='BOUNDED_ALTERNATIVES';
      elsif jsonb_array_length(coalesce(a.source_refs,'[]'::jsonb))>0
            and v_kind='SOURCE_INCOMPLETE' then
        v_synthesis:='SINGLE_EXACT';
      else
        v_synthesis:='HOLD_FOR_EVIDENCE';
      end if;

      if exists (
        select 1
        from programacion.input_gap_proposals p
        where p.run_id=p_run_id
          and p.family_code=a.family_code
          and p.gap_code=v_gap
      ) then
        -- INHERIT: preserve the existing row and any validator evidence/hash exactly.
        v_inherit:=v_inherit+1;
        continue;
      end if;

      v_result:=case
        when v_kind='HUMAN_DECISION_REQUIRED' then 'REQUIERE_DECISION'
        when v_kind in ('SOURCE_CONFLICT','RESEARCH_REQUIRED','SOURCE_INCOMPLETE') then 'RECOMENDADA'
        else 'UNKNOWN'
      end;

      insert into programacion.input_gap_proposals(
        run_id,assessment_id,family_code,gap_code,proposal_kind,proposed_payload,canonical_target,
        source_refs,evidence_refs,confidence,stage_impact,contradictions_checked,status,
        curator_identity,curator_execution_id
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
          'gap_policy_ref',v_policy_ref,
          'gap_policy_schema',v_policy->>'schema_version',
          'gap_policy_action','CREATE',
          'synthesis_mode',v_synthesis,
          'policy_result',v_result,
          'targeted_evidence_before_escalation',v_policy->>'targeted_evidence_before_escalation',
          'canonical_change_admission',v_policy->>'canonical_change_admission',
          'no_effective_change_result',v_policy->>'no_effective_change_result',
          'positive_owner_escalation_authority',v_positive_owner_authority,
          'pending_marker_is_not_owner_authority',true,
          'no_invention',true,
          'proposal_is_canonical_source',false,
          'automatic_canonicalization','DENY',
          'analysis_revision',coalesce(v_run.scope->>'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX'),
          'remediation_policy_revision','INPUT_GAP_POLICY_V1'
        ),
        jsonb_build_object('pantalla_id',v_run.pantalla_id,'family_code',a.family_code),
        a.source_refs,'[]'::jsonb,
        case when v_positive_owner_authority then 1.0 else 0.9 end,
        jsonb_build_object(
          'story',a.story_ready_status,
          'implementation',a.implementation_ready_status,
          'qa',a.qa_ready_status,
          'production',a.production_ready_status
        ),
        jsonb_build_array(
          'GOV-015_CLASSIFICATION_APPLIED',
          'POSITIVE_OWNER_AUTHORITY_REQUIRED',
          'NO_PROPOSAL_AS_CANONICAL_SOURCE',
          'INPUT_GAP_POLICY_V1_APPLIED'
        ),
        'PROPOSED',
        v_run.curator_identity,
        coalesce(a.curator_evidence->>'execution_id','UNKNOWN')
      )
      on conflict (run_id,family_code,gap_code) do nothing;

      if found then
        v_count:=v_count+1;
        v_create:=v_create+1;
        if v_kind='HUMAN_DECISION_REQUIRED' then
          v_human:=v_human+1;
        else
          v_auto:=v_auto+1;
        end if;
      else
        -- Concurrent equivalent became current: policy action is INHERIT, never duplicate.
        v_inherit:=v_inherit+1;
      end if;
    end loop;
  end loop;

  -- CLOSE is evaluated but cannot execute during CURATING because independent
  -- validation is not yet available. Preserve history and hold for evidence.
  select count(*)
    into v_close_candidates
  from programacion.input_gap_proposals p
  where p.run_id=p_run_id
    and not exists (
      select 1
      from programacion.input_family_assessments a2
      cross join lateral jsonb_array_elements(a2.blockers) bx(value)
      where a2.run_id=p_run_id
        and a2.family_code=p.family_code
        and coalesce(bx.value->>'code','UNSPECIFIED_GAP')=p.gap_code
    );

  return jsonb_build_object(
    'run_id',p_run_id,
    'proposal_count',v_count,
    'internal_remediation_count',v_auto,
    'human_decision_candidate_count',v_human,
    'gap_policy_ref',v_policy_ref,
    'gap_policy_schema',v_policy->>'schema_version',
    'strategy_results',jsonb_build_object(
      'CREATE',jsonb_build_object('executed_count',v_create,'duplicate_policy','DENY'),
      'INHERIT',jsonb_build_object('reused_count',v_inherit,'mutated_existing_validated_row',false),
      'CLOSE',jsonb_build_object(
        'candidate_count',v_close_candidates,
        'executed_count',0,
        'state','HOLD_FOR_EVIDENCE',
        'reason','INDEPENDENT_VALIDATION_REQUIRED'
      )
    ),
    'synthesis_modes',v_policy->'dynamic_synthesis_modes',
    'targeted_evidence_before_escalation',v_policy->>'targeted_evidence_before_escalation',
    'canonical_change_admission',v_policy->>'canonical_change_admission',
    'no_effective_change_result',v_policy->>'no_effective_change_result',
    'owner_escalation_policy','POSITIVE_OWNER_AUTHORITY_ONLY',
    'proposal_is_canonical_source',false,
    'automatic_canonicalization','DENY'
  );
end;
$function$;

comment on function programacion.fn_input_governance_materialize_gap_proposals_v1(bigint) is
'M5.8 INPUT_GAP_POLICY_V1 consumer. CREATE inserts a non-canonical proposal only when no equivalent exists; INHERIT reuses without mutating validator evidence; CLOSE candidates remain HOLD_FOR_EVIDENCE until independent validation. Canonical change requires SAFE_CHANGE_ADMISSION.';

do $verify$
declare
  v_def text;
begin
  select pg_get_functiondef('programacion.fn_input_governance_materialize_gap_proposals_v1(bigint)'::regprocedure)
    into v_def;

  if position('INPUT_GAP_POLICY_V1' in v_def)=0
     or position('TARGETED_EVIDENCE_ACQUISITION' in v_def)=0
     or position('SAFE_CHANGE_ADMISSION' in v_def)=0
     or position('SINGLE_EXACT' in v_def)=0
     or position('BOUNDED_ALTERNATIVES' in v_def)=0
     or position('HOLD_FOR_EVIDENCE' in v_def)=0
     or position('mutated_existing_validated_row' in v_def)=0 then
    raise exception 'BLOCK_M58_APPLY_POLICY_SOURCE_READBACK';
  end if;

  if not exists (
    select 1
    from programacion.contratos c
    where c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
      and c.estado='defined'
      and c.fail_closed
      and c.especificacion->>'contract_revision'='1.7'
      and c.especificacion#>>'{gap_policy_contract,schema_version}'='INPUT_GAP_POLICY_V1'
  ) then
    raise exception 'BLOCK_M58_APPLY_POLICY_CONTRACT_READBACK';
  end if;
end
$verify$;
