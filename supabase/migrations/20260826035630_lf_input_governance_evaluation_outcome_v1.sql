-- INPUT_GOVERNANCE_AGENT 5.12
-- Separate the terminal result of the current evaluation cut from the future remediation queue.
-- This migration does NOT relax Story Gate, does NOT canonicalize missing business sources,
-- and does NOT convert BLOCKED families into PASS.

create or replace function programacion.fn_input_evaluation_outcome_summary(p_run_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, programacion
as $$
  with run_meta as (
    select r.id, r.family_count
    from programacion.input_readiness_runs r
    where r.id=p_run_id
  ), classified as (
    select
      a.id as assessment_id,
      a.family_code,
      a.severity,
      a.applicability,
      a.story_ready_status,
      a.coverage_status,
      a.well_defined_status,
      a.blockers,
      a.source_refs,
      a.rationale,
      a.validator_outcome,
      case
        when a.validator_outcome<>'PASS' then 'NOT_VALIDATED'
        when a.story_ready_status='READY' then 'POSITIVE'
        when a.story_ready_status='NOT_APPLICABLE' then 'NOT_APPLICABLE'
        when a.story_ready_status='BLOCKED' then 'NEGATIVE_CONFIRMED'
        else 'UNRESOLVED'
      end as evaluation_outcome,
      (
        a.validator_outcome='PASS'
        and a.story_ready_status in ('READY','NOT_APPLICABLE','BLOCKED')
      ) as terminal_for_current_evaluation
    from programacion.input_family_assessments a
    where a.run_id=p_run_id
  ), agg as (
    select
      count(*) as total_count,
      count(*) filter(where validator_outcome='PASS') as validator_pass_count,
      count(*) filter(where evaluation_outcome='POSITIVE') as positive_count,
      count(*) filter(where evaluation_outcome='NOT_APPLICABLE') as not_applicable_count,
      count(*) filter(where evaluation_outcome='NEGATIVE_CONFIRMED') as negative_confirmed_count,
      count(*) filter(where evaluation_outcome in ('NOT_VALIDATED','UNRESOLVED')) as unresolved_count,
      count(*) filter(where terminal_for_current_evaluation) as terminal_count,
      coalesce(jsonb_agg(
        jsonb_build_object(
          'assessment_id',assessment_id,
          'family_code',family_code,
          'evaluation_outcome',evaluation_outcome,
          'terminal_for_current_evaluation',terminal_for_current_evaluation,
          'story_ready_status',story_ready_status,
          'severity',severity,
          'applicability',applicability,
          'coverage_status',coverage_status,
          'well_defined_status',well_defined_status,
          'blockers',blockers,
          'source_refs',source_refs,
          'rationale',rationale,
          'validator_outcome',validator_outcome
        ) order by family_code
      ),'[]'::jsonb) as items
    from classified
  )
  select jsonb_build_object(
    'schema_version',1,
    'run_id',p_run_id,
    'evaluation_contract','CURRENT_CUT_TERMINAL_OUTCOME_V1',
    'decision_authority','DEC-INPUT-GOV-EVAL-OUTCOME-001',
    'run_is_current',programacion.fn_input_readiness_run_is_current(p_run_id),
    'expected_family_count',coalesce(r.family_count,0),
    'total_family_count',a.total_count,
    'validator_pass_count',a.validator_pass_count,
    'positive_count',a.positive_count,
    'not_applicable_count',a.not_applicable_count,
    'negative_confirmed_count',a.negative_confirmed_count,
    'unresolved_or_not_validated_count',a.unresolved_count,
    'terminal_count',a.terminal_count,
    'current_evaluation_complete',(
      programacion.fn_input_readiness_run_is_current(p_run_id)
      and a.total_count=coalesce(r.family_count,0)
      and a.validator_pass_count=coalesce(r.family_count,0)
      and a.terminal_count=coalesce(r.family_count,0)
      and a.unresolved_count=0
    ),
    'negative_does_not_mean_not_applicable',true,
    'negative_does_not_relax_story_gate',true,
    'remediation_is_separate_from_evaluation',true,
    'items',a.items
  )
  from run_meta r cross join agg a;
$$;

revoke all on function programacion.fn_input_evaluation_outcome_summary(bigint) from public;
revoke all on function programacion.fn_input_evaluation_outcome_summary(bigint) from anon;
revoke all on function programacion.fn_input_evaluation_outcome_summary(bigint) from authenticated;
grant execute on function programacion.fn_input_evaluation_outcome_summary(bigint) to service_role;

comment on function programacion.fn_input_evaluation_outcome_summary(bigint) is
'INPUT_GOVERNANCE_AGENT 5.12: reports terminal current-cut evaluation results separately from future remediation. READY=POSITIVE, governed N/A=NOT_APPLICABLE, Validator-PASS BLOCKED=NEGATIVE_CONFIRMED. It never changes Story Gate.';

create or replace function programacion.fn_input_internal_remediation_summary(p_run_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, programacion
as $$
  with eval as (
    select programacion.fn_input_evaluation_outcome_summary(p_run_id) as j
  ), q as (
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
      p.stage_impact,
      a.story_ready_status,
      case
        when a.validator_outcome<>'PASS' then 'NOT_VALIDATED'
        when a.story_ready_status='READY' then 'POSITIVE'
        when a.story_ready_status='NOT_APPLICABLE' then 'NOT_APPLICABLE'
        when a.story_ready_status='BLOCKED' then 'NEGATIVE_CONFIRMED'
        else 'UNRESOLVED'
      end as evaluation_outcome
    from programacion.input_gap_proposals p
    join programacion.input_family_assessments a
      on a.id=p.assessment_id and a.run_id=p.run_id
    where p.run_id=p_run_id
      and p.validator_outcome='PASS'
      and p.status='VALIDATED'
  )
  select jsonb_build_object(
    'schema_version',2,
    'run_id',p_run_id,
    'internal_remediation_count',count(q.id),
    'family_count',count(distinct q.family_code),
    'research_required_count',count(q.id) filter(where q.proposal_kind='RESEARCH_REQUIRED'),
    'source_incomplete_count',count(q.id) filter(where q.proposal_kind='SOURCE_INCOMPLETE'),
    'source_conflict_count',count(q.id) filter(where q.proposal_kind='SOURCE_CONFLICT'),
    'negative_confirmed_remediation_count',count(q.id) filter(where q.evaluation_outcome='NEGATIVE_CONFIRMED'),
    'later_stage_or_positive_remediation_count',count(q.id) filter(where q.evaluation_outcome in ('POSITIVE','NOT_APPLICABLE')),
    'owner_interruption_required',false,
    'proposal_is_canonical_source',false,
    'automatic_canonicalization','DENY',
    'decision_authority','DEC-INPUT-GOV-SELF-REMEDIATE-001',
    'evaluation_boundary','CURRENT_CUT_RESULT_SEPARATE_FROM_REMEDIATION',
    'current_evaluation_summary',(select (j-'items') from eval),
    'items',coalesce(
      jsonb_agg(
        jsonb_build_object(
          'proposal_id',q.id,
          'family_code',q.family_code,
          'gap_code',q.gap_code,
          'proposal_kind',q.proposal_kind,
          'status',q.status,
          'evaluation_outcome',q.evaluation_outcome,
          'terminal_for_current_evaluation',(q.evaluation_outcome in ('POSITIVE','NOT_APPLICABLE','NEGATIVE_CONFIRMED')),
          'remediation_continues',true,
          'gap_classification',q.proposed_payload->>'gap_classification',
          'agent_action',q.proposed_payload->>'agent_action',
          'canonical_target',q.canonical_target,
          'source_refs',q.source_refs,
          'evidence_refs',q.evidence_refs,
          'confidence',q.confidence,
          'stage_impact',q.stage_impact
        ) order by q.id
      ) filter(where q.id is not null),
      '[]'::jsonb
    )
  )
  from eval left join q on true;
$$;

revoke all on function programacion.fn_input_internal_remediation_summary(bigint) from public;
revoke all on function programacion.fn_input_internal_remediation_summary(bigint) from anon;
revoke all on function programacion.fn_input_internal_remediation_summary(bigint) from authenticated;
grant execute on function programacion.fn_input_internal_remediation_summary(bigint) to service_role;

comment on function programacion.fn_input_internal_remediation_summary(bigint) is
'INPUT_GOVERNANCE_AGENT 5.12: remediation queue is non-terminal future work. Each item now also carries the terminal result of the current validated evaluation cut; SOURCE_INCOMPLETE is never itself presented as the evaluation result.';

create or replace function programacion.fn_input_governance_execute(p_pantalla_id integer, p_consumer text default 'STORY_CREATOR'::text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'programacion', 'lf_ops'
as $function$
declare
  v_contract jsonb; v_version bigint; v_code text; v_active boolean; v_run bigint; v_latest bigint; v_family integer;
  v_assessed integer; v_pass integer; v_bad integer; v_human integer; v_internal integer; v_status text; v_remediation_state text;
  v_owner_interruption boolean:=false;
  v_pre jsonb; v_cur jsonb; v_val jsonb; v_story jsonb; v_ctx jsonb; v_close jsonb;
  v_stage jsonb; v_prop jsonb; v_internal_summary jsonb; v_eval jsonb; v_manifest jsonb; v_payload jsonb; v_worker jsonb; v_fresh jsonb; v_summary jsonb;
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
  v_eval:=programacion.fn_input_evaluation_outcome_summary(v_run);
  if not coalesce((v_eval->>'current_evaluation_complete')::boolean,false) then
    raise exception 'INPUT_GOVERNANCE_CURRENT_EVALUATION_NOT_TERMINAL:run=% summary=%',v_run,(v_eval-'items');
  end if;
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
    'evaluation_summary',v_eval,'stage_gate',v_stage,'proposal_summary',v_prop,'internal_remediation_summary',v_internal_summary,
    'context_manifest',v_manifest,'worker_spec',v_worker,
    'checkpoints',jsonb_strip_nulls(jsonb_build_object('PRE_EXECUTION',v_pre,'PRE_CURATOR',v_cur,'PRE_VALIDATOR',v_val,'PRE_STORY_GATE',v_story,'PRE_CONTEXT_MANIFEST',v_ctx,'CLOSE_EKB',v_close)),
    'proposal_is_canonical_source',false,'promotion_authorized',false,'production_authorized',false,'generated_at',now()
  );
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$function$;

comment on function programacion.fn_input_governance_execute(integer,text) is
'INPUT_GOVERNANCE_AGENT governed dispatcher. Current-cut evaluation result is explicit and terminal only after full Validator PASS; future remediation remains separate. Top-level READY/BLOCKED/HUMAN_DECISION semantics are unchanged.';

insert into public.lf_decision_log(id,adr,titulo,decision,razon,impacto,estado)
select
  gen_random_uuid(),
  'DEC-INPUT-GOV-EVAL-OUTCOME-001',
  'Separar resultado terminal de evaluación de la cola de remediación',
  'INPUT_GOVERNANCE_AGENT debe terminar cada corte validado con un resultado explícito por familia: POSITIVE, NOT_APPLICABLE con autoridad, o NEGATIVE_CONFIRMED. SOURCE_INCOMPLETE, RESEARCH_REQUIRED y SOURCE_CONFLICT describen trabajo futuro y no son el resultado terminal de la evaluación. HUMAN_DECISION_REQUIRED solo interrumpe al owner cuando existe autoridad positiva de escalamiento y Validator PASS.',
  'Evita presentar pendientes internos como si la evaluación no hubiera concluido, sin convertir ausencia en N/A, sin relajar Story Gate y sin canonicalizar fuentes faltantes.',
  'El dispatcher expone evaluation_summary y mantiene separada internal_remediation_summary. Un NEGATIVE_CONFIRMED permanece BLOCKED y puede seguir en remediación. No autoriza promoción ni producción.',
  'VIGENTE'
where not exists (
  select 1 from public.lf_decision_log where adr='DEC-INPUT-GOV-EVAL-OUTCOME-001'
);

-- Self-test against the current REC_001 cut without hardcoding generated run IDs.
do $test$
declare
  v_run bigint;
  v_eval jsonb;
  v_rem jsonb;
begin
  select r.id into v_run
  from programacion.input_readiness_runs r
  join lf_ops.pantallas p on p.id=r.pantalla_id
  where p.codigo='REC_001'
    and r.status='COMPLETED'
    and r.invalidated_at is null
    and programacion.fn_input_readiness_run_is_current(r.id)
  order by r.id desc limit 1;

  if v_run is null then
    raise exception 'EVAL_OUTCOME_SELFTEST_NO_CURRENT_REC001_RUN';
  end if;

  v_eval:=programacion.fn_input_evaluation_outcome_summary(v_run);
  if not coalesce((v_eval->>'current_evaluation_complete')::boolean,false)
     or (v_eval->>'total_family_count')::integer<>47
     or (v_eval->>'validator_pass_count')::integer<>47
     or (v_eval->>'positive_count')::integer<>24
     or (v_eval->>'not_applicable_count')::integer<>2
     or (v_eval->>'negative_confirmed_count')::integer<>21
     or (v_eval->>'unresolved_or_not_validated_count')::integer<>0 then
    raise exception 'EVAL_OUTCOME_SELFTEST_COUNTS_FAILED:%',v_eval-'items';
  end if;

  v_rem:=programacion.fn_input_internal_remediation_summary(v_run);
  if (v_rem->>'schema_version')::integer<>2
     or (v_rem->>'negative_confirmed_remediation_count')::integer<>21
     or (v_rem->>'internal_remediation_count')::integer<21 then
    raise exception 'EVAL_OUTCOME_SELFTEST_REMEDIATION_FAILED:%',v_rem-'items';
  end if;
end;
$test$;
