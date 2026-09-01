-- L1A prototype only. No canonical DDL. Execute transactionally and ROLLBACK.
-- Goal: reuse only COMPLETED+current v19 evidence and select only allowlisted governance families.
-- EKB: EKB-INPUT-GOV-INCREMENTAL-20260901-01

begin;

create or replace function pg_temp.fn_input_governance_compact_payload_proto(
  p_run_id bigint,
  p_sections jsonb
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
  v_count integer;
  v_distinct integer;
  v_bad integer;
  v_payload jsonb;
begin
  if jsonb_typeof(p_sections) <> 'array'
     or jsonb_array_length(p_sections) < 1
     or jsonb_array_length(p_sections) > 5 then
    raise exception 'COMPACT_SECTIONS_INVALID_CARDINALITY';
  end if;

  select count(*), count(distinct value),
         count(*) filter (where not (value = any(v_allowed)))
    into v_count, v_distinct, v_bad
  from jsonb_array_elements_text(p_sections);

  if v_count <> v_distinct then raise exception 'COMPACT_SECTIONS_DUPLICATED'; end if;
  if v_bad <> 0 then raise exception 'COMPACT_SECTION_NOT_ALLOWED'; end if;

  select jsonb_agg(
           jsonb_build_object(
             'family_code', a.family_code,
             'applicability', a.applicability,
             'story_ready_status', a.story_ready_status,
             'implementation_ready_status', a.implementation_ready_status,
             'qa_ready_status', a.qa_ready_status,
             'production_ready_status', a.production_ready_status,
             'source_refs', a.source_refs,
             'blockers', a.blockers,
             'negative_requirements', a.negative_requirements,
             'validator_outcome', a.validator_outcome
           ) order by s.ord
         )
    into v_payload
  from jsonb_array_elements_text(p_sections) with ordinality s(section_code, ord)
  join programacion.input_family_assessments a
    on a.run_id = p_run_id
   and a.family_code = s.section_code;

  if coalesce(jsonb_array_length(v_payload), 0) <> v_count then
    raise exception 'COMPACT_SELECTED_FAMILY_MISSING';
  end if;

  if exists (
    select 1
    from programacion.input_family_assessments a
    join jsonb_array_elements_text(p_sections) s(v) on s.v = a.family_code
    where a.run_id = p_run_id
      and a.validator_outcome <> 'PASS'
  ) then
    raise exception 'COMPACT_SELECTED_VALIDATOR_NOT_PASS';
  end if;

  return v_payload;
end;
$f$;

create or replace function pg_temp.fn_input_governance_compact_read_proto(
  p_pantalla_id integer,
  p_sections jsonb,
  p_consumer text default 'MANUAL'
) returns jsonb
language plpgsql
as $f$
declare
  v_version bigint;
  v_contract jsonb;
  v_run bigint;
  v_family integer;
  v_screen text;
  v_source_hash text;
  v_contract_hash text;
  v_contract_rev text;
  v_fresh jsonb;
  v_summary jsonb;
  v_stage jsonb;
  v_payload jsonb;
begin
  select c.version_id, c.especificacion
    into v_version, v_contract
  from programacion.contratos c
  join programacion.versiones_agente v on v.id = c.version_id
  join programacion.agentes a on a.id = v.agente_id
  where a.agente_codigo = 'INPUT_GOVERNANCE_AGENT'
    and c.contrato_codigo = 'INPUT_GOVERNANCE_EXECUTION_CONTRACT'
    and c.estado = 'defined'
    and c.fail_closed
  order by c.version_id desc
  limit 1;

  if v_contract is null then raise exception 'COMPACT_EXECUTION_CONTRACT_NOT_RESOLVABLE'; end if;

  if not exists (
    select 1
    from jsonb_array_elements_text(v_contract->'allowed_consumers') x(v)
    where x.v = p_consumer
  ) then
    return jsonb_build_object(
      'status','BLOCKED','decision','BLOCKED','continuation_allowed',false,
      'blocking_code','COMPACT_CONSUMER_NOT_ALLOWED','consumer',p_consumer
    );
  end if;

  select codigo into v_screen
  from lf_ops.pantallas
  where id = p_pantalla_id and activa;

  if v_screen is null then
    return jsonb_build_object(
      'status','BLOCKED','decision','BLOCKED','continuation_allowed',false,
      'blocking_code','COMPACT_SCREEN_NOT_ACTIVE'
    );
  end if;

  select id, family_count, source_snapshot_sha256, contract_snapshot_sha256, contract_revision
    into v_run, v_family, v_source_hash, v_contract_hash, v_contract_rev
  from programacion.input_readiness_runs r
  where r.version_id = v_version
    and r.pantalla_id = p_pantalla_id
    and r.status = 'COMPLETED'
    and r.invalidated_at is null
    and programacion.fn_input_readiness_run_is_current(r.id)
  order by r.id desc
  limit 1;

  if v_run is null then
    return jsonb_build_object(
      'status','RUNTIME_REQUIRED','decision','PENDING','continuation_allowed',false,
      'blocking_code','COMPACT_CURRENT_RUN_REQUIRED',
      'pantalla_id',p_pantalla_id,'screen_code',v_screen,'consumer',p_consumer,
      'sections_requested',p_sections
    );
  end if;

  v_fresh := programacion.fn_input_freshness_delta(v_run);
  v_summary := v_fresh->'summary';
  if v_fresh->>'run_state' <> 'CURRENT'
     or coalesce((v_summary->>'changed_source_count')::integer,-1) <> 0
     or coalesce((v_summary->>'affected_family_count')::integer,-1) <> 0 then
    return jsonb_build_object(
      'status','BLOCKED','decision','BLOCKED','continuation_allowed',false,
      'blocking_code','COMPACT_FRESHNESS_FAILED','run_id',v_run
    );
  end if;

  if (select count(*) from programacion.input_family_assessments where run_id=v_run) <> v_family
     or exists (
       select 1
       from programacion.input_family_assessments a
       join programacion.input_readiness_runs r on r.id=a.run_id
       where a.run_id=v_run
         and (
           a.validator_outcome <> 'PASS'
           or a.validator_identity is null
           or not coalesce((a.validator_evidence->>'direct_source_readback')::boolean,false)
           or a.validator_evidence->>'source_snapshot_sha256' is distinct from r.source_snapshot_sha256
         )
     ) then
    return jsonb_build_object(
      'status','BLOCKED','decision','BLOCKED','continuation_allowed',false,
      'blocking_code','COMPACT_VALIDATOR_FULL_PASS_REQUIRED','run_id',v_run
    );
  end if;

  v_stage := programacion.fn_input_stage_gate_summary(v_run);
  v_payload := pg_temp.fn_input_governance_compact_payload_proto(v_run,p_sections);

  return jsonb_build_object(
    'status', case when coalesce((v_stage->>'canonical_story_gate_pass')::boolean,false) then 'READY' else 'PARTIAL' end,
    'decision', case when coalesce((v_stage->>'canonical_story_gate_pass')::boolean,false) then 'PASS' else 'PARTIAL' end,
    'continuation_allowed', coalesce((v_stage->>'canonical_story_gate_pass')::boolean,false),
    'execution_mode','COMPACT_CURRENT_RUN_REUSE',
    'run_id',v_run,'pantalla_id',p_pantalla_id,'screen_code',v_screen,'consumer',p_consumer,
    'sections_consumed',p_sections,'families',v_payload,
    'governance_receipt',jsonb_build_object(
      'governance_agent_used',true,
      'governance_version',v_contract_rev,
      'sections_consumed',p_sections,
      'source_refs',jsonb_build_array('programacion.input_readiness_runs/'||v_run::text),
      'snapshot_hash',v_source_hash,
      'contract_snapshot_hash',v_contract_hash,
      'decision',case when coalesce((v_stage->>'canonical_story_gate_pass')::boolean,false) then 'PASS' else 'PARTIAL' end,
      'currentness','LIVE_CURRENT'
    )
  );
end;
$f$;

-- Historical serializer proof only: stale evidence can prove shape/selectivity, never continuation.
select jsonb_array_length(
  pg_temp.fn_input_governance_compact_payload_proto(
    183,
    '["APPLICABILITY_READINESS","SOURCE_AUTHORITY_PROVENANCE"]'::jsonb
  )
) = 2 as compact_selectivity_pass;

-- Live state must remain fail-closed while no COMPLETED+current run exists.
select pg_temp.fn_input_governance_compact_read_proto(
  51,
  '["APPLICABILITY_READINESS"]'::jsonb,
  'MANUAL'
)->>'status' = 'RUNTIME_REQUIRED' as no_current_run_fail_closed_pass;

-- Current execution contract 1.5 does not yet authorize Router/Adapter consumption.
select pg_temp.fn_input_governance_compact_read_proto(
  51,
  '["APPLICABILITY_READINESS"]'::jsonb,
  'ROUTER_ADAPTER'
)->>'blocking_code' = 'COMPACT_CONSUMER_NOT_ALLOWED' as router_adapter_gap_detected;

rollback;
