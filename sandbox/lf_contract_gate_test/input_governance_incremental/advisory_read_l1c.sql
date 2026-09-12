-- L1C candidate only. No canonical DDL. Execute transactionally and ROLLBACK.
-- Purpose: expose current/fresh/validated selected governance sections for read-only
-- diagnostic/planning context without converting partial screen readiness into PASS.
-- EKB: EKB-INPUT-GOV-INCREMENTAL-20260901-04

begin;

create or replace function pg_temp.fn_input_governance_advisory_read_proto(
  p_pantalla_id integer,
  p_sections jsonb,
  p_consumer text default 'MANUAL'
) returns jsonb
language plpgsql
as $f$
declare
  v_allowed constant text[] := array[
    'APPLICABILITY_READINESS',
    'SOURCE_AUTHORITY_PROVENANCE',
    'FRESHNESS_INVALIDATION',
    'NEGATIVE_REQUIREMENTS',
    'CONFLICT_PRECEDENCE'
  ];
  v_contract jsonb;
  v_version bigint;
  v_run bigint;
  v_screen text;
  v_family_count integer;
  v_count integer;
  v_distinct integer;
  v_bad integer;
  v_fresh jsonb;
  v_stage jsonb;
  v_payload jsonb;
begin
  select c.version_id,c.especificacion into v_version,v_contract
  from programacion.contratos c
  join programacion.versiones_agente v on v.id=c.version_id
  join programacion.agentes a on a.id=v.agente_id
  where a.agente_codigo='INPUT_GOVERNANCE_AGENT'
    and c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
    and c.estado='defined' and c.fail_closed
  order by c.version_id desc limit 1;

  if v_contract is null then raise exception 'ADVISORY_EXECUTION_CONTRACT_NOT_RESOLVABLE'; end if;
  if not exists(select 1 from jsonb_array_elements_text(v_contract->'allowed_consumers') x(v) where x.v=p_consumer) then
    return jsonb_build_object('status','BLOCKED','decision','BLOCKED','continuation_allowed',false,'blocking_code','ADVISORY_CONSUMER_NOT_ALLOWED');
  end if;

  if jsonb_typeof(p_sections)<>'array' or jsonb_array_length(p_sections)<1 or jsonb_array_length(p_sections)>5 then
    raise exception 'ADVISORY_SECTIONS_INVALID_CARDINALITY';
  end if;
  select count(*),count(distinct value),count(*) filter(where not(value=any(v_allowed)))
    into v_count,v_distinct,v_bad from jsonb_array_elements_text(p_sections);
  if v_count<>v_distinct then raise exception 'ADVISORY_SECTIONS_DUPLICATED'; end if;
  if v_bad<>0 then raise exception 'ADVISORY_SECTION_NOT_ALLOWED'; end if;

  select codigo into v_screen from lf_ops.pantallas where id=p_pantalla_id and activa;
  if v_screen is null then return jsonb_build_object('status','BLOCKED','decision','BLOCKED','continuation_allowed',false,'blocking_code','ADVISORY_SCREEN_NOT_ACTIVE'); end if;

  select id,family_count into v_run,v_family_count
  from programacion.input_readiness_runs r
  where r.version_id=v_version and r.pantalla_id=p_pantalla_id
    and r.status='COMPLETED' and r.invalidated_at is null
    and programacion.fn_input_readiness_run_is_current(r.id)
  order by r.id desc limit 1;
  if v_run is null then
    return jsonb_build_object('status','RUNTIME_REQUIRED','decision','PENDING','continuation_allowed',false,'blocking_code','ADVISORY_CURRENT_RUN_REQUIRED');
  end if;

  v_fresh:=programacion.fn_input_freshness_delta(v_run);
  if v_fresh->>'run_state'<>'CURRENT'
     or coalesce((v_fresh->'summary'->>'changed_source_count')::integer,-1)<>0
     or coalesce((v_fresh->'summary'->>'affected_family_count')::integer,-1)<>0 then
    return jsonb_build_object('status','BLOCKED','decision','BLOCKED','continuation_allowed',false,'blocking_code','ADVISORY_FRESHNESS_FAILED','run_id',v_run);
  end if;

  select jsonb_agg(jsonb_build_object(
      'family_code',a.family_code,
      'applicability',a.applicability,
      'story_ready_status',a.story_ready_status,
      'source_refs',a.source_refs,
      'blockers',a.blockers,
      'negative_requirements',a.negative_requirements,
      'validator_outcome',a.validator_outcome
    ) order by s.ord)
    into v_payload
  from jsonb_array_elements_text(p_sections) with ordinality s(section_code,ord)
  join programacion.input_family_assessments a on a.run_id=v_run and a.family_code=s.section_code
  join programacion.input_readiness_runs r on r.id=a.run_id
  where a.validator_outcome='PASS'
    and a.story_ready_status='READY'
    and a.validator_identity is not null
    and coalesce((a.validator_evidence->>'direct_source_readback')::boolean,false)
    and a.validator_evidence->>'source_snapshot_sha256' is not distinct from r.source_snapshot_sha256;

  if coalesce(jsonb_array_length(v_payload),0)<>v_count then
    return jsonb_build_object('status','BLOCKED','decision','BLOCKED','continuation_allowed',false,'blocking_code','ADVISORY_SELECTED_SCOPE_NOT_READY','run_id',v_run);
  end if;

  v_stage:=programacion.fn_input_stage_gate_summary(v_run);
  return jsonb_build_object(
    'status','ADVISORY_READY',
    'decision','PARTIAL',
    'continuation_allowed',false,
    'usage_scope',jsonb_build_array('DIAGNOSTIC','PLANNING','CONTEXT_ONLY'),
    'receipt_type','ADVISORY_RECEIPT_NOT_GOVERNANCE_PASS',
    'run_id',v_run,
    'pantalla_id',p_pantalla_id,
    'screen_code',v_screen,
    'consumer',p_consumer,
    'sections_consumed',p_sections,
    'families',v_payload,
    'global_story_gate_pass',coalesce((v_stage->>'canonical_story_gate_pass')::boolean,false),
    'global_story_open_count',coalesce((v_stage->'summary'->>'story_stage_open')::integer,0),
    'promotion_authorized',false,
    'production_authorized',false
  );
end;$f$;

-- Real current canary: ONB_002 / run 212.
select pg_temp.fn_input_governance_advisory_read_proto(
  2,
  '["APPLICABILITY_READINESS","SOURCE_AUTHORITY_PROVENANCE","FRESHNESS_INVALIDATION","NEGATIVE_REQUIREMENTS","CONFLICT_PRECEDENCE"]'::jsonb,
  'MANUAL'
) as advisory_canary;

rollback;
