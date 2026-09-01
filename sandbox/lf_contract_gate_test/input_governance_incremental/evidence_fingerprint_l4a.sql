-- L4A candidate only. Read-only benchmark invalidation fingerprint.
-- This MUST NOT be used to bypass run currentness, freshness, Validator, Story Gate,
-- production authorization, or canonical source readback.
-- EKB: EKB-INPUT-GOV-INCREMENTAL-20260901-05

begin;

create or replace function pg_temp.fn_input_governance_evidence_fingerprint_proto(
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
  v_runtime_sha text;
  v_contracts_sha text;
  v_selected_sha text;
  v_source_sha text;
  v_universe_sha text;
  v_contract_snapshot_sha text;
  v_sections_canonical text;
  v_fingerprint text;
begin
  if jsonb_typeof(p_sections)<>'array' or jsonb_array_length(p_sections)<1 or jsonb_array_length(p_sections)>5 then
    raise exception 'FINGERPRINT_SECTIONS_INVALID_CARDINALITY';
  end if;
  select count(*),count(distinct value),count(*) filter(where not(value=any(v_allowed)))
    into v_count,v_distinct,v_bad
  from jsonb_array_elements_text(p_sections);
  if v_count<>v_distinct then raise exception 'FINGERPRINT_SECTIONS_DUPLICATED'; end if;
  if v_bad<>0 then raise exception 'FINGERPRINT_SECTION_NOT_ALLOWED'; end if;

  if not exists(select 1 from programacion.input_readiness_runs where id=p_run_id and version_id=19) then
    raise exception 'FINGERPRINT_RUN_NOT_FOUND';
  end if;

  select source_snapshot_sha256,universe_snapshot_sha256,contract_snapshot_sha256
    into v_source_sha,v_universe_sha,v_contract_snapshot_sha
  from programacion.input_readiness_runs where id=p_run_id;

  select encode(extensions.digest(convert_to(
    string_agg(p.oid::regprocedure::text||E'\n'||pg_get_functiondef(p.oid),E'\n--FUNCTION--\n' order by p.oid::regprocedure::text),
    'UTF8'),'sha256'),'hex')
    into v_runtime_sha
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname in (
      'fn_input_governance_worker_spec',
      'fn_input_stage_gate_summary',
      'fn_input_freshness_delta',
      'fn_input_readiness_run_is_current'
    );

  select programacion.fn_v09_sha256_jsonb(
    jsonb_agg(jsonb_build_object(
      'contrato_codigo',c.contrato_codigo,
      'version_id',c.version_id,
      'estado',c.estado,
      'fail_closed',c.fail_closed,
      'especificacion',c.especificacion
    ) order by c.contrato_codigo)
  ) into v_contracts_sha
  from programacion.contratos c
  where c.version_id=19
    and c.contrato_codigo in ('INPUT_GOVERNANCE_EXECUTION_CONTRACT','INPUT_READINESS_CONTRACT');

  select encode(extensions.digest(convert_to(
    coalesce(string_agg(a.family_code||':'||coalesce(a.validator_sha256,'')||':'||coalesce(a.curator_sha256,''),E'\n' order by a.family_code),''),
    'UTF8'),'sha256'),'hex')
    into v_selected_sha
  from programacion.input_family_assessments a
  join jsonb_array_elements_text(p_sections) s(v) on s.v=a.family_code
  where a.run_id=p_run_id;

  if (select count(*) from programacion.input_family_assessments a join jsonb_array_elements_text(p_sections) s(v) on s.v=a.family_code where a.run_id=p_run_id)<>v_count then
    raise exception 'FINGERPRINT_SELECTED_EVIDENCE_MISSING';
  end if;

  select string_agg(value,',' order by value) into v_sections_canonical
  from jsonb_array_elements_text(p_sections);

  v_fingerprint:=encode(extensions.digest(convert_to(concat_ws(E'\n',
    'sections='||v_sections_canonical,
    v_runtime_sha,
    v_contracts_sha,
    v_source_sha,
    v_universe_sha,
    v_contract_snapshot_sha,
    v_selected_sha
  ),'UTF8'),'sha256'),'hex');

  return jsonb_build_object(
    'fingerprint_schema','INPUT_GOVERNANCE_EVIDENCE_FINGERPRINT_L4A_V1',
    'run_id',p_run_id,
    'sections',p_sections,
    'sections_canonical',v_sections_canonical,
    'runtime_dependency_sha256',v_runtime_sha,
    'contracts_sha256',v_contracts_sha,
    'source_snapshot_sha256',v_source_sha,
    'universe_snapshot_sha256',v_universe_sha,
    'contract_snapshot_sha256',v_contract_snapshot_sha,
    'selected_evidence_sha256',v_selected_sha,
    'fingerprint_sha256',v_fingerprint,
    'use_scope','BENCHMARK_INVALIDATION_ONLY',
    'runtime_bypass_authorized',false,
    'promotion_authorized',false,
    'production_authorized',false
  );
end;$f$;

with a as (
  select pg_temp.fn_input_governance_evidence_fingerprint_proto(
    212,
    '["APPLICABILITY_READINESS","SOURCE_AUTHORITY_PROVENANCE","FRESHNESS_INVALIDATION","NEGATIVE_REQUIREMENTS","CONFLICT_PRECEDENCE"]'::jsonb
  ) x
), b as (
  select pg_temp.fn_input_governance_evidence_fingerprint_proto(
    212,
    '["APPLICABILITY_READINESS","SOURCE_AUTHORITY_PROVENANCE","FRESHNESS_INVALIDATION","NEGATIVE_REQUIREMENTS","CONFLICT_PRECEDENCE"]'::jsonb
  ) x
), c as (
  select pg_temp.fn_input_governance_evidence_fingerprint_proto(
    212,
    '["APPLICABILITY_READINESS","SOURCE_AUTHORITY_PROVENANCE"]'::jsonb
  ) x
)
select
  a.x->>'fingerprint_sha256' as fingerprint_5,
  b.x->>'fingerprint_sha256' as fingerprint_5_repeat,
  (a.x->>'fingerprint_sha256')=(b.x->>'fingerprint_sha256') as deterministic_same_input,
  c.x->>'fingerprint_sha256' as fingerprint_2,
  (a.x->>'fingerprint_sha256')<>(c.x->>'fingerprint_sha256') as section_scope_changes_fingerprint,
  (a.x->>'runtime_bypass_authorized')::boolean=false as no_runtime_bypass_pass
from a,b,c;

rollback;
