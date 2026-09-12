-- L1D candidate only. Execute transactionally and ROLLBACK.
-- A current_run_id is trusted ONLY when produced earlier in the same governed request
-- by authoritative currentness resolution. It must never be accepted as an external bypass token.
-- EKB: EKB-INPUT-GOV-INCREMENTAL-20260901-06

begin;

create or replace function pg_temp.fn_input_governance_known_current_advisory_proto(
  p_pantalla_id integer,
  p_consumer text,
  p_current_run_id bigint,
  p_sections jsonb
) returns jsonb
language plpgsql
as $f$
declare
  v_contract jsonb;
  v_version bigint;
  v_run record;
  v_fresh jsonb;
  v_payload jsonb;
  v_stage jsonb;
  v_count integer;
  v_ready integer;
begin
  select c.version_id,c.especificacion into v_version,v_contract
  from programacion.contratos c
  join programacion.versiones_agente v on v.id=c.version_id
  join programacion.agentes a on a.id=v.agente_id
  where a.agente_codigo='INPUT_GOVERNANCE_AGENT'
    and c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
    and c.estado='defined' and c.fail_closed
  order by c.version_id desc limit 1;

  if v_contract is null then raise exception 'KNOWN_CURRENT_EXECUTION_CONTRACT_NOT_RESOLVABLE'; end if;
  if not exists(select 1 from jsonb_array_elements_text(v_contract->'allowed_consumers') x(v) where x.v=p_consumer) then
    return jsonb_build_object('status','BLOCKED','blocking_code','KNOWN_CURRENT_CONSUMER_NOT_ALLOWED','continuation_allowed',false);
  end if;

  select r.* into v_run
  from programacion.input_readiness_runs r
  where r.id=p_current_run_id
    and r.version_id=v_version
    and r.pantalla_id=p_pantalla_id
    and r.status='COMPLETED'
    and r.invalidated_at is null;
  if not found then
    return jsonb_build_object('status','BLOCKED','blocking_code','KNOWN_CURRENT_BINDING_INVALID','continuation_allowed',false);
  end if;

  if jsonb_typeof(p_sections)<>'array' or jsonb_array_length(p_sections)<1 or jsonb_array_length(p_sections)>5 then
    raise exception 'KNOWN_CURRENT_SECTIONS_INVALID';
  end if;
  select count(*) into v_count from jsonb_array_elements_text(p_sections);

  v_fresh:=programacion.fn_input_freshness_delta(p_current_run_id);
  if v_fresh->>'run_state'<>'CURRENT'
     or coalesce((v_fresh->'summary'->>'changed_source_count')::integer,-1)<>0
     or coalesce((v_fresh->'summary'->>'affected_family_count')::integer,-1)<>0 then
    return jsonb_build_object('status','BLOCKED','blocking_code','KNOWN_CURRENT_FRESHNESS_FAILED','continuation_allowed',false,'run_id',p_current_run_id);
  end if;

  select count(*) into v_ready
  from programacion.input_family_assessments a
  join jsonb_array_elements_text(p_sections) s(v) on s.v=a.family_code
  where a.run_id=p_current_run_id
    and a.validator_outcome='PASS'
    and a.story_ready_status='READY'
    and a.validator_identity is not null
    and coalesce((a.validator_evidence->>'direct_source_readback')::boolean,false)
    and a.validator_evidence->>'source_snapshot_sha256' is not distinct from v_run.source_snapshot_sha256;
  if v_ready<>v_count then
    return jsonb_build_object('status','BLOCKED','blocking_code','KNOWN_CURRENT_SELECTED_SCOPE_NOT_READY','continuation_allowed',false,'run_id',p_current_run_id);
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
  join programacion.input_family_assessments a
    on a.run_id=p_current_run_id and a.family_code=s.section_code;

  v_stage:=programacion.fn_input_stage_gate_summary_known_current_v1(p_current_run_id,true);

  return jsonb_build_object(
    'status','ADVISORY_READY',
    'decision','PARTIAL',
    'continuation_allowed',false,
    'currentness_resolution_reused',true,
    'currentness_recomputed',false,
    'run_id',p_current_run_id,
    'pantalla_id',p_pantalla_id,
    'consumer',p_consumer,
    'sections_consumed',p_sections,
    'families',v_payload,
    'freshness_summary',v_fresh->'summary',
    'global_story_gate_pass',coalesce((v_stage->>'canonical_story_gate_pass')::boolean,false),
    'global_story_open_count',coalesce((v_stage->'summary'->>'story_stage_open')::integer,0),
    'receipt_type','ADVISORY_RECEIPT_NOT_GOVERNANCE_PASS',
    'runtime_bypass_authorized',false,
    'promotion_authorized',false,
    'production_authorized',false
  );
end;$f$;

-- Canary uses run 212 only because currentness was authoritatively proven immediately before this prototype.
explain (analyze, format json, timing on)
select pg_temp.fn_input_governance_known_current_advisory_proto(
  2,
  'MANUAL',
  212,
  '["APPLICABILITY_READINESS","SOURCE_AUTHORITY_PROVENANCE","FRESHNESS_INVALIDATION","NEGATIVE_REQUIREMENTS","CONFLICT_PRECEDENCE"]'::jsonb
);

rollback;
