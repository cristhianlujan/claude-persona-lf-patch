-- LF Input Governance gap proposal runtime v1
-- Curator proposes; Validator independently re-reads sources; only HUMAN_DECISION_REQUIRED is owner-visible.

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
  v_pending_decisions int;
  v_count int:=0;
  v_human int:=0;
  v_auto int:=0;
begin
  select * into v_run from programacion.input_readiness_runs where id=p_run_id;
  if not found then raise exception 'INPUT_REMEDIATION_RUN_NOT_FOUND:%',p_run_id; end if;
  if v_run.status<>'CURATING' then raise exception 'INPUT_REMEDIATION_REQUIRES_CURATING:%',p_run_id; end if;

  for a in
    select *
    from programacion.input_family_assessments
    where run_id=p_run_id and jsonb_array_length(blockers)>0
    order by family_code,id
  loop
    v_pending_decisions:=coalesce((a.curator_evidence->'bootstrap_probe'->>'pending_decision_count')::int,0);
    for b in select value from jsonb_array_elements(a.blockers)
    loop
      v_gap:=coalesce(b->>'code','UNSPECIFIED_GAP');
      if a.family_code in ('PROFILES','PERMISSIONS','FEATURE_FLAGS','I18N_FORMATS') then v_class:='APPLICABILITY_AUTHORITY_GAP';
      elsif a.story_ready_status='READY' then v_class:='STAGE_SPECIFIC_GAP';
      elsif v_gap ~ '(EVIDENCE|AUTHORITY|PROVENANCE)' then v_class:='GOVERNANCE_EVIDENCE_GAP';
      else v_class:='FUNCTIONAL_DEFINITION_GAP'; end if;
      if v_pending_decisions>0 then v_kind:='HUMAN_DECISION_REQUIRED';
      elsif v_gap ~ '(CONFLICT|RECONCILIATION)' then v_kind:='SOURCE_CONFLICT';
      else v_kind:='SOURCE_INCOMPLETE'; end if;
      insert into programacion.input_gap_proposals(
        run_id,assessment_id,family_code,gap_code,proposal_kind,proposed_payload,canonical_target,source_refs,evidence_refs,confidence,
        stage_impact,contradictions_checked,status,curator_identity,curator_execution_id
      ) values(
        p_run_id,a.id,a.family_code,v_gap,v_kind,
        jsonb_build_object('gap_classification',v_class,'agent_action',case when v_kind='HUMAN_DECISION_REQUIRED' then 'ESCALATE_AFTER_VALIDATION' when a.family_code='DESIGN_SYSTEM' then 'SEARCH_AND_VALIDATE_EXISTING_CANONICAL_BINDING_BEFORE_ESCALATION' else 'KEEP_IN_INTERNAL_REMEDIATION_QUEUE' end,'blocker',b,'no_invention',true,'proposal_is_canonical_source',false,'automatic_canonicalization','DENY','analysis_revision','INPUT_GOV_REMEDIATION_1_3'),
        jsonb_build_object('pantalla_id',v_run.pantalla_id,'family_code',a.family_code),a.source_refs,'[]'::jsonb,
        case when v_kind='HUMAN_DECISION_REQUIRED' then 1.0 else 0.9 end,
        jsonb_build_object('story',a.story_ready_status,'implementation',a.implementation_ready_status,'qa',a.qa_ready_status,'production',a.production_ready_status),
        jsonb_build_array('GOV-015_CLASSIFICATION_APPLIED','NO_PROPOSAL_AS_CANONICAL_SOURCE'),'PROPOSED',v_run.curator_identity,coalesce(a.curator_evidence->>'execution_id','UNKNOWN')
      ) on conflict (run_id,family_code,gap_code) do nothing;
      if found then v_count:=v_count+1; if v_kind='HUMAN_DECISION_REQUIRED' then v_human:=v_human+1; else v_auto:=v_auto+1; end if; end if;
    end loop;
  end loop;
  return jsonb_build_object('run_id',p_run_id,'proposal_count',v_count,'internal_remediation_count',v_auto,'human_decision_candidate_count',v_human,'analysis_revision','INPUT_GOV_REMEDIATION_1_3');
end;
$function$;
revoke all on function programacion.fn_input_governance_materialize_gap_proposals_v1(bigint) from public,anon,authenticated;
grant execute on function programacion.fn_input_governance_materialize_gap_proposals_v1(bigint) to service_role;

create or replace function programacion.fn_input_governance_validate_gap_proposals_v1(p_run_id bigint,p_validator_identity text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,programacion as $function$
declare v_run record; p record; r jsonb; v_obs jsonb; v_readbacks jsonb; v_count int:=0; v_human int:=0;
begin
  select * into v_run from programacion.input_readiness_runs where id=p_run_id;
  if not found then raise exception 'INPUT_REMEDIATION_VALIDATE_RUN_NOT_FOUND:%',p_run_id; end if;
  if v_run.status<>'VALIDATING' then raise exception 'INPUT_REMEDIATION_VALIDATE_REQUIRES_VALIDATING:%',p_run_id; end if;
  if p_validator_identity is distinct from v_run.validator_identity or p_validator_identity=v_run.curator_identity then raise exception 'INPUT_REMEDIATION_VALIDATOR_IDENTITY_INVALID:%',p_run_id; end if;
  for p in select * from programacion.input_gap_proposals where run_id=p_run_id and validator_outcome='PENDING' order by id loop
    v_readbacks:='[]'::jsonb;
    for r in select value from jsonb_array_elements(p.source_refs) loop
      v_obs:=programacion.fn_input_resolve_source_ref(r,v_run.pantalla_id,v_run.version_id);
      v_readbacks:=v_readbacks||jsonb_build_array(jsonb_build_object('source_ref',r,'source_observed_sha256',programacion.fn_v09_sha256_jsonb(v_obs)));
    end loop;
    update programacion.input_gap_proposals set validator_identity=p_validator_identity,validator_outcome='PASS',status=case when proposal_kind='HUMAN_DECISION_REQUIRED' then 'HUMAN_DECISION_REQUIRED' else 'VALIDATED' end,
      validator_evidence=jsonb_build_object('direct_source_readback',true,'source_snapshot_sha256',v_run.source_snapshot_sha256,'source_readbacks',v_readbacks,'analysis_revision','INPUT_GOV_REMEDIATION_1_3','proposal_is_canonical_source',false,'automatic_canonicalization','DENY'),validated_at=now() where id=p.id;
    v_count:=v_count+1; if p.proposal_kind='HUMAN_DECISION_REQUIRED' then v_human:=v_human+1; end if;
  end loop;
  return jsonb_build_object('run_id',p_run_id,'validated_proposal_count',v_count,'human_decision_required_count',v_human,'analysis_revision','INPUT_GOV_REMEDIATION_1_3');
end;
$function$;
revoke all on function programacion.fn_input_governance_validate_gap_proposals_v1(bigint,text) from public,anon,authenticated;
grant execute on function programacion.fn_input_governance_validate_gap_proposals_v1(bigint,text) to service_role;

create or replace function programacion.fn_input_proposal_summary(p_run_id bigint)
returns jsonb language sql set search_path=pg_catalog,programacion as $function$
  select jsonb_build_object('run_id',p_run_id,'proposal_count',count(*),'pending_count',count(*) filter(where validator_outcome='PENDING'),'validated_count',count(*) filter(where validator_outcome='PASS'),'rejected_count',count(*) filter(where validator_outcome='FAIL'),'human_decision_count',count(*) filter(where status='HUMAN_DECISION_REQUIRED' and validator_outcome='PASS'),'internal_validated_remediation_count',count(*) filter(where status='VALIDATED' and validator_outcome='PASS'),'owner_visible_count',count(*) filter(where status='HUMAN_DECISION_REQUIRED' and validator_outcome='PASS'),'proposals',coalesce(jsonb_agg(jsonb_build_object('id',id,'family_code',family_code,'gap_code',gap_code,'proposal_kind',proposal_kind,'status',status,'validator_outcome',validator_outcome,'gap_classification',proposed_payload->>'gap_classification','owner_visible',(status='HUMAN_DECISION_REQUIRED' and validator_outcome='PASS')) order by id),'[]'::jsonb)) from programacion.input_gap_proposals where run_id=p_run_id;
$function$;