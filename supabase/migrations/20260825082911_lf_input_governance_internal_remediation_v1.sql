-- INPUT_GOVERNANCE_AGENT execution remediation continuity v1.
-- Implements DEC-INPUT-GOV-SELF-REMEDIATE-001 without widening canonical write authority.
-- Backward-compatible top-level status remains BLOCKED while internal remediation is pending;
-- remediation_state and queue distinguish internal work from owner interruption.

create or replace function programacion.fn_input_internal_remediation_summary(p_run_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
  with q as (
    select
      p.id,
      p.family_code,
      p.gap_code,
      p.proposal_kind,
      p.status,
      p.validator_outcome,
      p.proposed_payload,
      p.canonical_target,
      p.source_refs,
      p.evidence_refs,
      p.confidence,
      p.stage_impact
    from programacion.input_gap_proposals p
    where p.run_id=p_run_id
      and p.validator_outcome='PASS'
      and p.status='VALIDATED'
  )
  select jsonb_build_object(
    'schema_version',1,
    'run_id',p_run_id,
    'internal_remediation_count',count(*),
    'family_count',count(distinct family_code),
    'research_required_count',count(*) filter(where proposal_kind='RESEARCH_REQUIRED'),
    'source_incomplete_count',count(*) filter(where proposal_kind='SOURCE_INCOMPLETE'),
    'source_conflict_count',count(*) filter(where proposal_kind='SOURCE_CONFLICT'),
    'owner_interruption_required',false,
    'proposal_is_canonical_source',false,
    'automatic_canonicalization','DENY',
    'decision_authority','DEC-INPUT-GOV-SELF-REMEDIATE-001',
    'items',coalesce(
      jsonb_agg(
        jsonb_build_object(
          'proposal_id',id,
          'family_code',family_code,
          'gap_code',gap_code,
          'proposal_kind',proposal_kind,
          'status',status,
          'gap_classification',proposed_payload->>'gap_classification',
          'agent_action',proposed_payload->>'agent_action',
          'canonical_target',canonical_target,
          'source_refs',source_refs,
          'evidence_refs',evidence_refs,
          'confidence',confidence,
          'stage_impact',stage_impact
        ) order by id
      ),
      '[]'::jsonb
    )
  )
  from q;
$function$;

revoke all on function programacion.fn_input_internal_remediation_summary(bigint) from public,anon,authenticated;
grant execute on function programacion.fn_input_internal_remediation_summary(bigint) to service_role;

create or replace function programacion.fn_input_governance_execute(
  p_pantalla_id integer,
  p_consumer text default 'STORY_CREATOR'::text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','public','programacion','lf_ops'
as $function$
declare
  v_contract jsonb; v_version bigint; v_code text; v_active boolean; v_run bigint; v_latest bigint; v_family integer;
  v_assessed integer; v_pass integer; v_bad integer; v_human integer; v_internal integer; v_status text; v_remediation_state text;
  v_owner_interruption boolean:=false;
  v_pre jsonb; v_cur jsonb; v_val jsonb; v_story jsonb; v_ctx jsonb; v_close jsonb;
  v_stage jsonb; v_prop jsonb; v_internal_summary jsonb; v_manifest jsonb; v_payload jsonb; v_worker jsonb; v_fresh jsonb; v_summary jsonb;
begin
  select c.version_id,c.especificacion into v_version,v_contract
  from programacion.contratos c
  join programacion.versiones_agente v on v.id=c.version_id
  join programacion.agentes a on a.id=v.agente_id
  where a.agente_codigo='INPUT_GOVERNANCE_AGENT'
    and c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
    and c.estado='defined' and c.fail_closed
  order by c.version_id desc limit 1;
  if v_contract is null then raise exception 'INPUT_GOVERNANCE_EXECUTION_CONTRACT_NOT_RESOLVABLE'; end if;
  if not exists(select 1 from jsonb_array_elements_text(v_contract->'allowed_consumers') x(v) where x.v=p_consumer) then
    raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>');
  end if;
  select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id;
  if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;
  if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;

  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_EXECUTION',p_pantalla_id,null);
  if not (v_pre->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_EXECUTION:%',v_pre->'unhandled_high_critical_codes'; end if;

  select id,family_count into v_run,v_family
  from programacion.input_readiness_runs r
  where r.version_id=v_version and r.pantalla_id=p_pantalla_id and r.status='COMPLETED' and r.invalidated_at is null
    and programacion.fn_input_readiness_run_is_current(r.id)
  order by r.id desc limit 1;

  if v_run is null then
    select id into v_latest from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
    v_worker:=programacion.fn_input_governance_worker_spec(p_pantalla_id,p_consumer);
    v_close:=programacion.fn_input_governance_ekb_checkpoint('CLOSE_EKB',p_pantalla_id,v_latest);
    v_status:=case v_worker->>'required_role' when 'INPUT_VALIDATOR' then 'VALIDATOR_RUNTIME_REQUIRED' else 'CURATOR_RUNTIME_REQUIRED' end;
    v_payload:=jsonb_build_object(
      'schema_version',1,'execution_contract','INPUT_GOVERNANCE_EXECUTION_V1','execution_contract_revision',v_contract->>'contract_revision',
      'agent_code','INPUT_GOVERNANCE_AGENT','version_id',v_version,'pantalla_id',p_pantalla_id,'screen_code',v_code,'consumer',p_consumer,
      'status',v_status,'execution_mode','BOUND_ROLE_RUNTIME_REQUIRED','latest_run_id',v_latest,
      'blocker','ROLE_RUNTIME_REQUIRED','worker_spec',v_worker,
      'checkpoints',jsonb_build_object('PRE_EXECUTION',v_pre,'CLOSE_EKB',v_close),
      'proposal_is_canonical_source',false,'promotion_authorized',false,'production_authorized',false,'generated_at',now()
    );
    return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
  end if;

  v_fresh:=programacion.fn_input_freshness_delta(v_run); v_summary:=v_fresh->'summary';
  if v_fresh->>'run_state'<>'CURRENT'
     or coalesce((v_summary->>'changed_source_count')::integer,-1)<>0
     or coalesce((v_summary->>'affected_family_count')::integer,-1)<>0 then
    raise exception 'INPUT_GOVERNANCE_CURRENT_RUN_FRESHNESS_GATE_FAILED:run=% state=% summary=%',v_run,v_fresh->>'run_state',v_summary;
  end if;

  v_cur:=programacion.fn_input_governance_ekb_checkpoint('PRE_CURATOR',p_pantalla_id,v_run);
  if not (v_cur->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CURATOR:%',v_cur->'unhandled_high_critical_codes'; end if;
  select count(*) into v_assessed from programacion.input_family_assessments where run_id=v_run;
  if v_assessed<>v_family then raise exception 'INPUT_GOVERNANCE_CURATOR_UNIVERSE_INCOMPLETE:run=% expected=% actual=%',v_run,v_family,v_assessed; end if;

  v_val:=programacion.fn_input_governance_ekb_checkpoint('PRE_VALIDATOR',p_pantalla_id,v_run);
  if not (v_val->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_VALIDATOR:%',v_val->'unhandled_high_critical_codes'; end if;
  select count(*) filter(where a.validator_outcome='PASS'),
         count(*) filter(where a.validator_outcome<>'PASS' or a.validator_identity is null
           or not coalesce((a.validator_evidence->>'direct_source_readback')::boolean,false)
           or a.validator_evidence->>'source_snapshot_sha256' is distinct from r.source_snapshot_sha256)
  into v_pass,v_bad
  from programacion.input_family_assessments a
  join programacion.input_readiness_runs r on r.id=a.run_id
  where a.run_id=v_run;
  if v_pass<>v_family or v_bad<>0 then raise exception 'INPUT_GOVERNANCE_VALIDATOR_NOT_FULL_AUTHORIZED_PASS:run=% expected=% pass=% bad=%',v_run,v_family,v_pass,v_bad; end if;

  v_story:=programacion.fn_input_governance_ekb_checkpoint('PRE_STORY_GATE',p_pantalla_id,v_run);
  if not (v_story->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_STORY_GATE:%',v_story->'unhandled_high_critical_codes'; end if;
  v_stage:=programacion.fn_input_stage_gate_summary(v_run);
  v_prop:=programacion.fn_input_proposal_summary(v_run);
  v_internal_summary:=programacion.fn_input_internal_remediation_summary(v_run);
  select count(*) into v_human
  from programacion.input_gap_proposals
  where run_id=v_run and status='HUMAN_DECISION_REQUIRED' and validator_outcome='PASS';
  v_internal:=coalesce((v_internal_summary->>'internal_remediation_count')::integer,0);

  if coalesce((v_stage->>'canonical_story_gate_pass')::boolean,false) then
    v_ctx:=programacion.fn_input_governance_ekb_checkpoint('PRE_CONTEXT_MANIFEST',p_pantalla_id,v_run);
    if not (v_ctx->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CONTEXT_MANIFEST:%',v_ctx->'unhandled_high_critical_codes'; end if;
    v_manifest:=programacion.fn_input_context_manifest(v_run);
    v_status:='READY';
    v_remediation_state:='NONE';
  elsif v_human>0 then
    v_status:='HUMAN_DECISION_REQUIRED';
    v_remediation_state:='HUMAN_DECISION_REQUIRED';
    v_owner_interruption:=true;
  elsif v_internal>0 then
    v_status:='BLOCKED';
    v_remediation_state:='INTERNAL_REMEDIATION_REQUIRED';
    v_owner_interruption:=false;
  else
    v_status:='BLOCKED';
    v_remediation_state:='NO_AUTHORIZED_REMEDIATION_PATH';
    v_owner_interruption:=false;
  end if;

  v_close:=programacion.fn_input_governance_ekb_checkpoint('CLOSE_EKB',p_pantalla_id,v_run);
  if not (v_close->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:CLOSE_EKB:%',v_close->'unhandled_high_critical_codes'; end if;
  v_worker:=programacion.fn_input_governance_worker_spec(p_pantalla_id,p_consumer);
  v_payload:=jsonb_build_object(
    'schema_version',1,'execution_contract','INPUT_GOVERNANCE_EXECUTION_V1','execution_contract_revision',v_contract->>'contract_revision',
    'agent_code','INPUT_GOVERNANCE_AGENT','version_id',v_version,'pantalla_id',p_pantalla_id,'screen_code',v_code,'consumer',p_consumer,
    'status',v_status,'remediation_state',v_remediation_state,'owner_interruption_required',v_owner_interruption,
    'execution_mode','REUSE_COMPLETED_CURRENT_RUN','run_id',v_run,'family_count',v_family,'validator_pass_count',v_pass,
    'human_decision_required_count',v_human,'internal_remediation_required_count',v_internal,'freshness_delta_summary',v_summary,
    'stage_gate',v_stage,'proposal_summary',v_prop,'internal_remediation_summary',v_internal_summary,
    'context_manifest',v_manifest,'worker_spec',v_worker,
    'checkpoints',jsonb_strip_nulls(jsonb_build_object('PRE_EXECUTION',v_pre,'PRE_CURATOR',v_cur,'PRE_VALIDATOR',v_val,'PRE_STORY_GATE',v_story,'PRE_CONTEXT_MANIFEST',v_ctx,'CLOSE_EKB',v_close)),
    'proposal_is_canonical_source',false,'promotion_authorized',false,'production_authorized',false,'generated_at',now()
  );
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

update programacion.contratos
set especificacion =
  (especificacion || jsonb_build_object(
    'contract_revision','1.5',
    'operator_orchestrated_internal_remediation',true,
    'owner_interruption_policy','HUMAN_DECISION_REQUIRED_ONLY'
  ))
  || jsonb_build_object(
    'remediation_loop',
    coalesce(especificacion->'remediation_loop','{}'::jsonb)
    || jsonb_build_object(
      'internal_remediation_queue','programacion.fn_input_internal_remediation_summary(bigint)',
      'internal_remediation_state','INTERNAL_REMEDIATION_REQUIRED',
      'internal_remediation_transport','CALLER_ORCHESTRATOR',
      'owner_interruption_only_when','POSITIVE_OWNER_AUTHORITY_AND_VALIDATOR_PASS',
      'automatic_canonicalization','DENY',
      'proposal_is_canonical_source',false
    )
  )
where version_id=19
  and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
  and estado='defined'
  and fail_closed;

comment on function programacion.fn_input_internal_remediation_summary(bigint)
is 'Validated non-owner gap queue for DEC-INPUT-GOV-SELF-REMEDIATE-001. Read-only; proposals are never canonical sources.';

comment on function programacion.fn_input_governance_execute(integer,text)
is 'Input Governance dispatcher. v1.5 distinguishes internal remediation from positive-authority Human Decision while preserving BLOCKED fail-closed compatibility.';
