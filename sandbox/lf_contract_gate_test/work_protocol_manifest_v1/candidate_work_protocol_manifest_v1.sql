-- LF_WORK_PROTOCOL_MANIFEST_V1 candidate DB wiring.
-- SOURCE_ONLY / NOT_APPLIED by this file. No new table and no replacement of generic v1 primitives.

alter table public.lf_operation_step_judge_bindings
  add column if not exists verifier_mode text;

do $verifier_mode_constraint$
begin
  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='public'
      and t.relname='lf_operation_step_judge_bindings'
      and c.conname='lf_operation_step_judge_bindings_verifier_mode_check'
  ) then
    alter table public.lf_operation_step_judge_bindings
      add constraint lf_operation_step_judge_bindings_verifier_mode_check
      check (
        verifier_mode is null
        or verifier_mode in ('DETERMINISTIC','INDEPENDENT_READBACK','SEMANTIC_JUDGE','COMPOSITE')
      );
  end if;
end
$verifier_mode_constraint$;

alter table public.lf_operation_step_contracts
  add column if not exists waiver_allowed boolean,
  add column if not exists irreversible_effect boolean,
  add column if not exists human_approval_required boolean,
  add column if not exists depends_on_step_ids text[],
  add column if not exists closure_unit_id text,
  add column if not exists controller_order integer,
  add column if not exists execution_effect text,
  add column if not exists parallel_safe boolean;

create or replace function public.lf_work_protocol_canonical_json_v1(p_value jsonb)
returns text
language plpgsql
immutable
security invoker
set search_path = pg_catalog, public
as $fn$
declare
  t text;
begin
  case jsonb_typeof(p_value)
    when 'object' then
      select '{' || coalesce(string_agg(to_jsonb(e.key)::text || ':' || public.lf_work_protocol_canonical_json_v1(e.value), ',' order by e.key collate "C"), '') || '}'
      into t
      from jsonb_each(p_value) e;
      return t;
    when 'array' then
      select '[' || coalesce(string_agg(public.lf_work_protocol_canonical_json_v1(a.value), ',' order by a.ord), '') || ']'
      into t
      from jsonb_array_elements(p_value) with ordinality a(value, ord);
      return t;
    else
      return p_value::text;
  end case;
end;
$fn$;

create or replace function public.lf_work_protocol_contract_revision_sha256_v1(p_operation_code text)
returns text
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, extensions
as $fn$
declare
  payload jsonb;
  n integer;
begin
  select count(*) into n
  from public.lf_operation_contracts
  where operation_code=p_operation_code and status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO');

  if n<>1 then
    raise exception 'LF_WORK_PROTOCOL_ACTIVE_CONTRACT_NOT_EXACT:%:%',p_operation_code,n;
  end if;

  select to_jsonb(c)-array['created_at','updated_at','created_by_execution_id','updated_by_execution_id']
  into payload
  from public.lf_operation_contracts c
  where c.operation_code=p_operation_code and c.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')
  limit 1;

  return encode(
    extensions.digest(convert_to(public.lf_work_protocol_canonical_json_v1(payload),'UTF8'),'sha256'),
    'hex'
  );
end;
$fn$;

create or replace function public.lf_work_protocol_policy_set_sha256_v1(p_operation_code text)
returns text
language sql
stable
security invoker
set search_path = pg_catalog, public, extensions
as $fn$
  with payload as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'operation_code', p.operation_code,
          'policy_code', p.policy_code,
          'policy_role', p.policy_role,
          'required', p.required,
          'distribution_modes', p.distribution_modes,
          'policy_version', p.policy_version,
          'policy_sha', p.policy_sha,
          'source_ref', p.source_ref
        ) order by p.policy_code, p.policy_role
      ),
      '[]'::jsonb
    ) as v
    from public.v_lf_operation_policy_snapshot p
    where p.operation_code=p_operation_code
  )
  select encode(
    extensions.digest(convert_to(public.lf_work_protocol_canonical_json_v1(v),'UTF8'),'sha256'),
    'hex'
  )
  from payload;
$fn$;

create or replace function public.lf_work_protocol_obligation_set_sha256_v1(p_operation_code text)
returns text
language sql
stable
security invoker
set search_path = pg_catalog, public, extensions
as $fn$
  with payload as (
    select jsonb_build_object(
      'steps',coalesce((
        select jsonb_agg(
          to_jsonb(s)-array['created_at','updated_at','created_by_execution_id','updated_by_execution_id']
          order by coalesce(s.execution_order,s.step_order),s.step_id
        )
        from public.lf_operation_steps s
        where s.operation_code=p_operation_code and s.active=true
      ),'[]'::jsonb),
      'step_contracts',coalesce((
        select jsonb_agg(
          to_jsonb(sc)-array['created_at','updated_at','created_by_execution_id','updated_by_execution_id']
          order by coalesce(sc.execution_order,sc.step_order),sc.step_id,sc.contract_code
        )
        from public.lf_operation_step_contracts sc
        where sc.operation_code=p_operation_code and sc.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')
      ),'[]'::jsonb),
      'step_judge_bindings',coalesce((
        select jsonb_agg(
          to_jsonb(b)-array['created_at','updated_at','created_by_execution_id','updated_by_execution_id']
          order by b.step_order,b.step_id,b.judge_code
        )
        from public.lf_operation_step_judge_bindings b
        where b.operation_code=p_operation_code and b.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')
      ),'[]'::jsonb)
    ) as v
  )
  select encode(
    extensions.digest(convert_to(public.lf_work_protocol_canonical_json_v1(v),'UTF8'),'sha256'),
    'hex'
  )
  from payload;
$fn$;

create or replace function public.lf_work_protocol_gate_contract_v1(
  p_operation_code text,
  p_step_id text,
  p_closure_step_id text
) returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, extensions
as $fn$
declare
  sc public.lf_operation_step_contracts%rowtype;
  b public.lf_operation_step_judge_bindings%rowtype;
  sc_count integer;
  b_count integer;
  first_required_step text;
  last_nonclosure_step text;
  gate_type text;
  evidence_keys jsonb;
  body jsonb;
  digest_value text;
begin
  select count(*) into sc_count
  from public.lf_operation_step_contracts
  where operation_code=p_operation_code
    and step_id=p_step_id
    and status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO');
  if sc_count<>1 then
    raise exception 'LF_WORK_PROTOCOL_GATE_STEP_CONTRACT_NOT_EXACT:%:%:%',p_operation_code,p_step_id,sc_count;
  end if;

  select * into sc
  from public.lf_operation_step_contracts
  where operation_code=p_operation_code
    and step_id=p_step_id
    and status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')
  limit 1;

  if sc.waiver_allowed is null
     or sc.irreversible_effect is null
     or sc.human_approval_required is null
     or sc.depends_on_step_ids is null
     or btrim(coalesce(sc.closure_unit_id,''))=''
     or sc.controller_order is null or sc.controller_order<0
     or sc.execution_effect not in ('READ_ONLY','MUTATING','JUDGE','CLOSURE')
     or sc.parallel_safe is null
     or (sc.parallel_safe=true and sc.execution_effect<>'READ_ONLY')
     or (sc.irreversible_effect=true and sc.human_approval_required is not true) then
    raise exception 'LF_WORK_PROTOCOL_GATE_CONTROL_AUTHORITY_UNSET:%:%',p_operation_code,p_step_id;
  end if;

  select count(*) into b_count
  from public.lf_operation_step_judge_bindings
  where operation_code=p_operation_code
    and step_id=p_step_id
    and status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO');
  if b_count>1 then
    raise exception 'LF_WORK_PROTOCOL_GATE_JUDGE_BINDING_NOT_UNIQUE:%:%:%',p_operation_code,p_step_id,b_count;
  end if;
  if b_count=1 then
    select * into b
    from public.lf_operation_step_judge_bindings
    where operation_code=p_operation_code
      and step_id=p_step_id
      and status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')
    limit 1;
    if b.verifier_mode is null
       or b.verifier_mode not in ('DETERMINISTIC','INDEPENDENT_READBACK','SEMANTIC_JUDGE','COMPOSITE') then
      raise exception 'LF_WORK_PROTOCOL_GATE_VERIFIER_MODE_UNSET:%:%',p_operation_code,p_step_id;
    end if;
  end if;

  select s.step_id into first_required_step
  from public.lf_operation_steps s
  where s.operation_code=p_operation_code and s.active=true and s.required=true
  order by coalesce(s.execution_order,s.step_order),s.step_id
  limit 1;

  select s.step_id into last_nonclosure_step
  from public.lf_operation_steps s
  where s.operation_code=p_operation_code and s.active=true and s.required=true
    and s.step_id is distinct from p_closure_step_id
  order by coalesce(s.execution_order,s.step_order) desc,s.step_id desc
  limit 1;

  gate_type := case
    when p_step_id=p_closure_step_id then 'CLOSURE'
    when p_step_id=first_required_step then 'ENTRY'
    when p_step_id=last_nonclosure_step then 'EXIT'
    else 'STEP'
  end;

  select coalesce(jsonb_agg(k order by k),'[]'::jsonb) into evidence_keys
  from (
    select distinct x as k
    from jsonb_array_elements_text(coalesce(sc.required_evidence_keys,'[]'::jsonb)) x
    union
    select distinct y as k
    from jsonb_array_elements_text(
      case when b_count=1 then coalesce(b.required_evidence_keys,'[]'::jsonb) else '[]'::jsonb end
    ) y
  ) q;

  body := jsonb_build_object(
    'operation_code',p_operation_code,
    'step_id',p_step_id,
    'gate_type',gate_type,
    'verifier_mode',case when b_count=1 then b.verifier_mode else 'DETERMINISTIC' end,
    'waiver_allowed',sc.waiver_allowed,
    'irreversible_effect',sc.irreversible_effect,
    'human_approval_required',sc.human_approval_required,
    'depends_on_step_ids',to_jsonb(sc.depends_on_step_ids),
    'closure_unit_id',sc.closure_unit_id,
    'controller_order',sc.controller_order,
    'execution_effect',sc.execution_effect,
    'parallel_safe',sc.parallel_safe,
    'preconditions',coalesce(sc.input_required,'[]'::jsonb),
    'deterministic',jsonb_build_object(
      'required',(
        sc.execution_sql is not null
        or sc.pass_condition is not null
        or sc.fail_condition is not null
        or sc.block_condition is not null
      ),
      'execution_sql',sc.execution_sql,
      'pass_condition',sc.pass_condition,
      'fail_condition',sc.fail_condition,
      'block_condition',sc.block_condition
    ),
    'judge',jsonb_build_object(
      'required',b_count=1,
      'judge_code',case when b_count=1 then b.judge_code else null end,
      'clean_result_value',case when b_count=1 then b.clean_result_value else null end,
      'blocked_result_value',case when b_count=1 then b.blocked_result_value else null end,
      'return_result_value',case when b_count=1 then b.return_result_value else null end
    ),
    'required_evidence_keys',evidence_keys,
    'deterministic_before_judge',true,
    'fail_closed',true,
    'normalized_verdict_mapping',jsonb_build_object(
      'clean','PASS',
      'return','FAIL',
      'blocked','BLOCKED'
    )
  );

  digest_value := encode(
    extensions.digest(convert_to(public.lf_work_protocol_canonical_json_v1(body),'UTF8'),'sha256'),
    'hex'
  );
  return body || jsonb_build_object('gate_contract_sha256',digest_value);
end;
$fn$;

create or replace function public.lf_work_protocol_gate_evaluate_v1(
  p_operation_code text,
  p_step_id text,
  p_closure_step_id text,
  p_packet jsonb
) returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public
as $fn$
declare
  gc jsonb;
  required_key text;
  precondition_result text;
  deterministic_result text;
  judge_result text;
  deterministic_seq integer;
  judge_seq integer;
  normalized_result text;
  canonical_result text;
begin
  if p_packet is null or jsonb_typeof(p_packet)<>'object' then
    return jsonb_build_object('result','BLOCKED','code','GATE_PACKET_INVALID');
  end if;

  gc := public.lf_work_protocol_gate_contract_v1(p_operation_code,p_step_id,p_closure_step_id);

  if p_packet->>'gate_contract_sha256' is distinct from gc->>'gate_contract_sha256' then
    return jsonb_build_object(
      'result','BLOCKED',
      'code','GATE_CONTRACT_DIGEST_MISMATCH',
      'expected_gate_contract_sha256',gc->>'gate_contract_sha256'
    );
  end if;

  if jsonb_typeof(p_packet->'evidence') is distinct from 'object' then
    return jsonb_build_object('result','BLOCKED','code','GATE_EVIDENCE_OBJECT_MISSING');
  end if;

  for required_key in
    select jsonb_array_elements_text(gc->'required_evidence_keys')
  loop
    if not (p_packet->'evidence' ? required_key)
       or p_packet->'evidence'->required_key in ('null'::jsonb,'""'::jsonb,'[]'::jsonb,'{}'::jsonb) then
      return jsonb_build_object('result','BLOCKED','code','GATE_REQUIRED_EVIDENCE_MISSING','evidence_key',required_key);
    end if;
  end loop;

  precondition_result := p_packet->>'precondition_result';
  if precondition_result not in ('PASS','FAIL','BLOCKED') then
    return jsonb_build_object('result','BLOCKED','code','GATE_PRECONDITION_RESULT_MISSING_OR_INVALID');
  end if;
  if precondition_result<>'PASS' then
    if p_packet ? 'deterministic_result' or p_packet ? 'judge_result' then
      return jsonb_build_object('result','BLOCKED','code','GATE_EXECUTED_AFTER_PRECONDITION_NONPASS');
    end if;
    return jsonb_build_object('result',precondition_result,'code','GATE_PRECONDITION_'||precondition_result);
  end if;

  if coalesce((gc #>> '{deterministic,required}')::boolean,false) then
    deterministic_result := p_packet->>'deterministic_result';
    if deterministic_result not in ('PASS','FAIL','BLOCKED') then
      return jsonb_build_object('result','BLOCKED','code','GATE_DETERMINISTIC_RESULT_MISSING_OR_INVALID');
    end if;
    if coalesce(p_packet->>'deterministic_seq','') !~ '^[1-9][0-9]*$' then
      return jsonb_build_object('result','BLOCKED','code','GATE_DETERMINISTIC_SEQUENCE_MISSING_OR_INVALID');
    end if;
    deterministic_seq := (p_packet->>'deterministic_seq')::integer;

    if deterministic_result<>'PASS' then
      if p_packet ? 'judge_result' or p_packet ? 'judge_seq' then
        return jsonb_build_object('result','BLOCKED','code','GATE_JUDGE_AFTER_DETERMINISTIC_NONPASS_FORBIDDEN');
      end if;
      return jsonb_build_object(
        'result',deterministic_result,
        'code','GATE_DETERMINISTIC_'||deterministic_result,
        'gate_type',gc->>'gate_type',
        'gate_contract_sha256',gc->>'gate_contract_sha256'
      );
    end if;
  else
    deterministic_seq := 0;
  end if;

  if coalesce((gc #>> '{judge,required}')::boolean,false) then
    judge_result := p_packet->>'judge_result';
    if btrim(coalesce(judge_result,''))='' then
      return jsonb_build_object('result','BLOCKED','code','GATE_JUDGE_RESULT_MISSING');
    end if;
    if coalesce(p_packet->>'judge_seq','') !~ '^[1-9][0-9]*$' then
      return jsonb_build_object('result','BLOCKED','code','GATE_JUDGE_SEQUENCE_MISSING_OR_INVALID');
    end if;
    judge_seq := (p_packet->>'judge_seq')::integer;
    if judge_seq<=deterministic_seq then
      return jsonb_build_object('result','BLOCKED','code','GATE_JUDGE_BEFORE_DETERMINISTIC_FORBIDDEN');
    end if;

    if judge_result=gc #>> '{judge,clean_result_value}' then
      normalized_result := 'PASS';
    elsif judge_result=gc #>> '{judge,return_result_value}' then
      normalized_result := 'FAIL';
    elsif judge_result=gc #>> '{judge,blocked_result_value}' then
      normalized_result := 'BLOCKED';
    else
      return jsonb_build_object('result','BLOCKED','code','GATE_JUDGE_RESULT_NOT_CANONICAL','judge_result',judge_result);
    end if;
    canonical_result := judge_result;
  else
    normalized_result := 'PASS';
    canonical_result := null;
  end if;

  return jsonb_build_object(
    'result',normalized_result,
    'code','GATE_EVALUATED',
    'gate_type',gc->>'gate_type',
    'gate_contract_sha256',gc->>'gate_contract_sha256',
    'canonical_judge_result',canonical_result
  );
end;
$fn$;

create or replace function public.lf_work_protocol_evidence_validate_v1(
  p_execution_id text,
  p_step_id text,
  p_gate_contract_sha256 text,
  p_verifier_mode text,
  p_gate_type text,
  p_authority_ref text,
  p_evidence jsonb,
  p_execution_started_at timestamptz,
  p_evidence_policy jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $fn$
declare
  env jsonb;
  repro jsonb;
  actor_execution_id text;
  observed_at timestamptz;
  max_age_seconds integer;
  skew_seconds integer;
  expected_spec_sha text;
  receipt_uuid uuid;
  ledger private.lf_evidence_ledger_v1%rowtype;
  independent_required boolean;
begin
  if p_evidence is null or jsonb_typeof(p_evidence)<>'object' then
    return jsonb_build_object('result','BLOCKED','code','EVIDENCE_OBJECT_MISSING');
  end if;
  if jsonb_typeof(p_evidence_policy) is distinct from 'object'
     or coalesce((p_evidence_policy->>'exact_envelope_required')::boolean,false) is not true
     or coalesce((p_evidence_policy->>'reproduction_spec_required')::boolean,false) is not true
     or coalesce((p_evidence_policy->>'append_only_ledger_required_for_independent')::boolean,false) is not true
     or coalesce((p_evidence_policy->>'independent_actor_distinct_required')::boolean,false) is not true
     or p_evidence_policy->>'ledger_receipt_kind' is distinct from 'WORK_PROTOCOL_GATE_EVIDENCE'
     or coalesce(p_evidence_policy->>'max_age_seconds','') !~ '^[0-9]+$'
     or coalesce(p_evidence_policy->>'future_clock_skew_seconds','') !~ '^[0-9]+$' then
    return jsonb_build_object('result','BLOCKED','code','EVIDENCE_POLICY_INVALID');
  end if;

  max_age_seconds := (p_evidence_policy->>'max_age_seconds')::integer;
  skew_seconds := (p_evidence_policy->>'future_clock_skew_seconds')::integer;
  if max_age_seconds not between 60 and 86400 or skew_seconds not between 0 and 300 then
    return jsonb_build_object('result','BLOCKED','code','EVIDENCE_POLICY_BOUNDS_INVALID');
  end if;

  env := p_evidence->'work_protocol_evidence';
  if jsonb_typeof(env) is distinct from 'object' then
    return jsonb_build_object('result','BLOCKED','code','EXACT_EVIDENCE_ENVELOPE_MISSING');
  end if;
  if env->>'schema_version' is distinct from 'LF_WORK_PROTOCOL_EVIDENCE_V1'
     or env->>'execution_id' is distinct from p_execution_id
     or env->>'step_id' is distinct from p_step_id
     or env->>'gate_contract_sha256' is distinct from p_gate_contract_sha256 then
    return jsonb_build_object('result','BLOCKED','code','EVIDENCE_IDENTITY_MISMATCH');
  end if;

  actor_execution_id := env->>'actor_execution_id';
  if btrim(coalesce(actor_execution_id,''))='' or not exists (
    select 1 from public.lf_operation_execution a where a.execution_id=actor_execution_id
  ) then
    return jsonb_build_object('result','BLOCKED','code','EVIDENCE_ACTOR_INVALID');
  end if;

  repro := env->'reproduction';
  if jsonb_typeof(repro) is distinct from 'object'
     or repro->>'kind' not in ('SQL','COMMAND','API','READBACK')
     or btrim(coalesce(repro->>'locator',''))=''
     or btrim(coalesce(repro->>'reproduction_spec',''))=''
     or btrim(coalesce(repro->>'result_ref',''))=''
     or coalesce(repro->>'reproduction_spec_sha256','') !~ '^[0-9a-f]{64}$'
     or coalesce(repro->>'input_sha256','') !~ '^[0-9a-f]{64}$'
     or coalesce(repro->>'result_sha256','') !~ '^[0-9a-f]{64}$'
     or coalesce(repro->>'source_revision_sha256','') !~ '^[0-9a-f]{64}$'
     or coalesce(repro->>'result_count','') !~ '^[0-9]+$' then
    return jsonb_build_object('result','BLOCKED','code','EVIDENCE_REPRODUCTION_INVALID');
  end if;

  expected_spec_sha := encode(
    extensions.digest(convert_to(repro->>'reproduction_spec','UTF8'),'sha256'),
    'hex'
  );
  if repro->>'reproduction_spec_sha256' is distinct from expected_spec_sha then
    return jsonb_build_object('result','BLOCKED','code','EVIDENCE_REPRODUCTION_SPEC_DIGEST_MISMATCH');
  end if;

  begin
    observed_at := (env->>'observed_at')::timestamptz;
  exception when others then
    return jsonb_build_object('result','BLOCKED','code','EVIDENCE_TIMESTAMP_INVALID');
  end;
  if observed_at is null or p_execution_started_at is null then
    return jsonb_build_object('result','BLOCKED','code','EVIDENCE_TIMESTAMP_INVALID');
  end if;
  if observed_at < p_execution_started_at then
    return jsonb_build_object('result','BLOCKED','code','EVIDENCE_PRE_EXECUTION');
  end if;
  if observed_at > clock_timestamp() + make_interval(secs=>skew_seconds) then
    return jsonb_build_object('result','BLOCKED','code','EVIDENCE_FUTURE_TIMESTAMP');
  end if;
  if observed_at < clock_timestamp() - make_interval(secs=>max_age_seconds) then
    return jsonb_build_object('result','STALE','code','EVIDENCE_STALE');
  end if;

  independent_required := p_verifier_mode in ('INDEPENDENT_READBACK','SEMANTIC_JUDGE','COMPOSITE')
                          or p_gate_type='CLOSURE';
  if not independent_required then
    return jsonb_build_object(
      'result','PASS',
      'code','EVIDENCE_EXACT_PASS',
      'result_sha256',repro->>'result_sha256',
      'observed_at',observed_at
    );
  end if;

  if btrim(coalesce(env->>'ledger_receipt_id',''))=''
     or coalesce(env->>'ledger_receipt_sha256','') !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_LEDGER_RECEIPT_MISSING');
  end if;
  begin
    receipt_uuid := (env->>'ledger_receipt_id')::uuid;
  exception when others then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_LEDGER_RECEIPT_ID_INVALID');
  end;

  select * into ledger
  from private.lf_evidence_ledger_v1 l
  where l.receipt_id=receipt_uuid;
  if not found then
    return jsonb_build_object('result','BLOCKED','code','EVIDENCE_LEDGER_RECEIPT_NOT_FOUND');
  end if;

  if ledger.receipt_sha256 is distinct from env->>'ledger_receipt_sha256'
     or ledger.execution_id is distinct from p_execution_id
     or ledger.gate_code is distinct from 'WORK_PROTOCOL_GATE:'||p_step_id
     or ledger.receipt_kind is distinct from p_evidence_policy->>'ledger_receipt_kind'
     or ledger.verification_state is distinct from 'VERIFIED'
     or ledger.subject_ref is distinct from repro->>'result_ref'
     or ledger.subject_sha256 is distinct from repro->>'result_sha256'
     or ledger.authority_ref is distinct from p_authority_ref then
    return jsonb_build_object('result','BLOCKED','code','EVIDENCE_LEDGER_BINDING_MISMATCH');
  end if;

  if ledger.created_by_execution_id is distinct from actor_execution_id
     or actor_execution_id=p_execution_id
     or p_evidence->>'verification_actor_execution_id' is distinct from actor_execution_id
     or p_evidence->>'verification_target_execution_id' is distinct from p_execution_id then
    return jsonb_build_object('result','BLOCKED','code','EVIDENCE_INDEPENDENT_ACTOR_MISMATCH');
  end if;

  if not exists (
    select 1
    from public.lf_operation_execution verifier
    where verifier.execution_id=actor_execution_id
      and verifier.execution_id<>p_execution_id
      and verifier.completed_at is not null
      and verifier.status in ('COMPLETED','CLOSED_PASS','CLOSED_WITH_VERIFIED_EVIDENCE','PASS_CLEAN','CONTROLLED_READ_ONLY_PASS')
      and (
        (verifier.target_type='EXECUTION' and verifier.target_code=p_execution_id)
        or verifier.manifest->>'verification_target_execution_id'=p_execution_id
      )
  ) then
    return jsonb_build_object('result','BLOCKED','code','EVIDENCE_INDEPENDENT_VERIFIER_EXECUTION_NOT_PROVEN');
  end if;

  if ledger.verified_at is null
     or ledger.verified_at + make_interval(secs=>skew_seconds) < observed_at then
    return jsonb_build_object('result','BLOCKED','code','EVIDENCE_LEDGER_VERIFIED_AT_INVALID');
  end if;
  if ledger.verified_at < clock_timestamp() - make_interval(secs=>max_age_seconds) then
    return jsonb_build_object('result','STALE','code','EVIDENCE_LEDGER_STALE');
  end if;
  if ledger.verification_payload->'provider_readback_verified' is distinct from 'true'::jsonb
     or ledger.verification_payload->'digest_recomputed' is distinct from 'true'::jsonb then
    return jsonb_build_object('result','BLOCKED','code','EVIDENCE_LEDGER_VERIFICATION_PROOF_INCOMPLETE');
  end if;

  if not exists (
    select 1 from private.lf_evidence_resolver_registry_v1 rr
    where rr.resolver_id=ledger.resolver_id
      and rr.active=true
      and rr.trust_level='TRUSTED_PROVIDER_BOUND'
      and rr.provider=ledger.provider
      and rr.verification_method=ledger.verification_method
  ) then
    return jsonb_build_object('result','BLOCKED','code','EVIDENCE_LEDGER_RESOLVER_NOT_CURRENT');
  end if;

  if ledger.receipt_payload->>'work_protocol_execution_id' is distinct from p_execution_id
     or ledger.receipt_payload->>'work_protocol_step_id' is distinct from p_step_id
     or ledger.receipt_payload->>'work_protocol_gate_contract_sha256' is distinct from p_gate_contract_sha256
     or ledger.receipt_payload->>'evidence_result_sha256' is distinct from repro->>'result_sha256'
     or ledger.receipt_payload->>'reproduction_spec_sha256' is distinct from repro->>'reproduction_spec_sha256'
     or ledger.receipt_payload->>'source_revision_sha256' is distinct from repro->>'source_revision_sha256' then
    return jsonb_build_object('result','BLOCKED','code','EVIDENCE_LEDGER_WORK_PROTOCOL_BINDING_MISMATCH');
  end if;

  return jsonb_build_object(
    'result','PASS',
    'code','EVIDENCE_INDEPENDENT_LEDGER_PASS',
    'receipt_id',ledger.receipt_id,
    'receipt_sha256',ledger.receipt_sha256,
    'verified_at',ledger.verified_at,
    'result_sha256',repro->>'result_sha256'
  );
end;
$fn$;

create or replace function public.lf_work_protocol_control_validate_v1(
  p_work_protocol jsonb
) returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, extensions
as $fn$
declare
  policy jsonb;
  isolation jsonb;
  frozen_at timestamptz;
  waiver_ttl integer;
  w jsonb;
  a jsonb;
  o jsonb;
  exp timestamptz;
  approved_at timestamptz;
  approval_exp timestamptz;
  supersession jsonb;
  predecessor public.lf_operation_execution%rowtype;
  predecessor_wp jsonb;
  previous_scope_sha text;
  new_scope_sha text;
  waiver_count integer := 0;
  irreversible_count integer := 0;
begin
  if p_work_protocol is null or jsonb_typeof(p_work_protocol)<>'object' then
    return jsonb_build_object('result','BLOCKED','code','CONTROL_MANIFEST_INVALID');
  end if;

  policy := p_work_protocol->'control_policy';
  if jsonb_typeof(policy) is distinct from 'object'
     or policy->>'scope_change_mode' is distinct from 'SUPERSEDE_NEW_EXECUTION_FULL_REVALIDATION'
     or coalesce((policy->>'authorization_rebind_required')::boolean,false) is not true
     or coalesce((policy->>'carry_forward_verified_progress')::boolean,true) is not false
     or coalesce((policy->>'required_obligation_waivers_allowed')::boolean,true) is not false
     or coalesce((policy->>'irreversible_human_approval_required')::boolean,false) is not true
     or coalesce(policy->>'waiver_max_ttl_seconds','') !~ '^[0-9]+$'
     or (policy->>'waiver_max_ttl_seconds')::integer not between 60 and 3600 then
    return jsonb_build_object('result','BLOCKED','code','CONTROL_POLICY_INVALID');
  end if;
  waiver_ttl := (policy->>'waiver_max_ttl_seconds')::integer;

  isolation := p_work_protocol->'solution_isolation_policy';
  if jsonb_typeof(isolation) is distinct from 'object'
     or isolation->>'unit_mode' is distinct from 'ONE_SOLUTION_PER_PR'
     or coalesce((isolation->>'mixed_solution_pr_allowed')::boolean,true) is not false
     or coalesce((isolation->>'scope_expansion_requires_new_pr')::boolean,false) is not true
     or coalesce((isolation->>'migration_apply_requires_separate_pr')::boolean,false) is not true
     or coalesce((isolation->>'receipt_must_bind_exact_pr_scope')::boolean,false) is not true then
    return jsonb_build_object('result','BLOCKED','code','SOLUTION_ISOLATION_POLICY_INVALID');
  end if;

  begin
    frozen_at := (p_work_protocol->>'frozen_at')::timestamptz;
  exception when others then
    return jsonb_build_object('result','BLOCKED','code','CONTROL_FROZEN_AT_INVALID');
  end;
  if frozen_at is null then
    return jsonb_build_object('result','BLOCKED','code','CONTROL_FROZEN_AT_INVALID');
  end if;

  if jsonb_typeof(p_work_protocol->'obligations') is distinct from 'array'
     or jsonb_typeof(p_work_protocol->'waivers') is distinct from 'array'
     or jsonb_typeof(p_work_protocol->'irreversible_approvals') is distinct from 'array' then
    return jsonb_build_object('result','BLOCKED','code','CONTROL_ARRAYS_INVALID');
  end if;

  for o in select value from jsonb_array_elements(p_work_protocol->'obligations')
  loop
    if jsonb_typeof(o->'waiver_allowed') is distinct from 'boolean'
       or jsonb_typeof(o->'irreversible_effect') is distinct from 'boolean'
       or jsonb_typeof(o->'human_approval_required') is distinct from 'boolean' then
      return jsonb_build_object('result','BLOCKED','code','CONTROL_FLAGS_INVALID','step_id',o->>'step_id');
    end if;
    if coalesce((o->>'irreversible_effect')::boolean,false)
       and coalesce((o->>'human_approval_required')::boolean,false) is not true then
      return jsonb_build_object('result','BLOCKED','code','IRREVERSIBLE_REQUIRES_HUMAN_APPROVAL','step_id',o->>'step_id');
    end if;
  end loop;

  for w in select value from jsonb_array_elements(p_work_protocol->'waivers')
  loop
    waiver_count := waiver_count + 1;
    select x into o
    from jsonb_array_elements(p_work_protocol->'obligations') x
    where x->>'requirement_id'=w->>'requirement_id'
    limit 1;
    if o is null then
      return jsonb_build_object('result','BLOCKED','code','WAIVER_UNKNOWN_REQUIREMENT','requirement_id',w->>'requirement_id');
    end if;
    if coalesce((o->>'required')::boolean,false)
       or coalesce((o->>'waiver_allowed')::boolean,false) is not true then
      return jsonb_build_object('result','BLOCKED','code','WAIVER_FORBIDDEN','requirement_id',w->>'requirement_id');
    end if;
    if length(btrim(coalesce(w->>'reason','')))<20
       or length(btrim(coalesce(w->>'residual_risk','')))<10
       or btrim(coalesce(w->>'authorized_by',''))=''
       or btrim(coalesce(w->>'authorization_ref',''))=''
       or coalesce(w->>'authorization_sha256','') !~ '^[0-9a-f]{64}$' then
      return jsonb_build_object('result','BLOCKED','code','WAIVER_SHAPE_INVALID','requirement_id',w->>'requirement_id');
    end if;
    begin
      exp := (w->>'expires_at')::timestamptz;
    exception when others then
      return jsonb_build_object('result','BLOCKED','code','WAIVER_EXPIRY_INVALID','requirement_id',w->>'requirement_id');
    end;
    if exp<=frozen_at or exp>frozen_at+make_interval(secs=>waiver_ttl) then
      return jsonb_build_object('result','BLOCKED','code','WAIVER_TTL_INVALID','requirement_id',w->>'requirement_id');
    end if;
  end loop;

  if exists (
    select 1
    from (
      select x->>'requirement_id' rid, count(*) n
      from jsonb_array_elements(p_work_protocol->'waivers') x
      group by x->>'requirement_id'
    ) d where d.rid is null or d.rid='' or d.n<>1
  ) then
    return jsonb_build_object('result','BLOCKED','code','WAIVER_DUPLICATE_OR_INVALID_REQUIREMENT');
  end if;

  for o in
    select value
    from jsonb_array_elements(p_work_protocol->'obligations')
    where coalesce((value->>'irreversible_effect')::boolean,false)
  loop
    select x into a
    from jsonb_array_elements(p_work_protocol->'irreversible_approvals') x
    where x->>'step_id'=o->>'step_id'
    limit 1;
    if a is null then
      return jsonb_build_object('result','BLOCKED','code','IRREVERSIBLE_APPROVAL_MISSING','step_id',o->>'step_id');
    end if;
    irreversible_count := irreversible_count + 1;
    if coalesce(a->>'action_sha256','') !~ '^[0-9a-f]{64}$'
       or coalesce(a->>'approval_sha256','') !~ '^[0-9a-f]{64}$'
       or btrim(coalesce(a->>'approved_by',''))=''
       or btrim(coalesce(a->>'approval_ref',''))='' then
      return jsonb_build_object('result','BLOCKED','code','IRREVERSIBLE_APPROVAL_SHAPE_INVALID','step_id',o->>'step_id');
    end if;
    begin
      approved_at := (a->>'approved_at')::timestamptz;
      approval_exp := (a->>'expires_at')::timestamptz;
    exception when others then
      return jsonb_build_object('result','BLOCKED','code','IRREVERSIBLE_APPROVAL_TIME_INVALID','step_id',o->>'step_id');
    end;
    if approved_at>frozen_at or approval_exp<=frozen_at then
      return jsonb_build_object('result','BLOCKED','code','IRREVERSIBLE_APPROVAL_NOT_CURRENT_AT_FREEZE','step_id',o->>'step_id');
    end if;
  end loop;

  if exists (
    select 1
    from (
      select x->>'step_id' sid, count(*) n
      from jsonb_array_elements(p_work_protocol->'irreversible_approvals') x
      group by x->>'step_id'
    ) d where d.sid is null or d.sid='' or d.n<>1
  ) then
    return jsonb_build_object('result','BLOCKED','code','IRREVERSIBLE_APPROVAL_DUPLICATE_OR_INVALID_STEP');
  end if;
  if jsonb_array_length(p_work_protocol->'irreversible_approvals')<>irreversible_count then
    return jsonb_build_object('result','BLOCKED','code','IRREVERSIBLE_APPROVAL_EXTRA_OR_MISSING');
  end if;

  supersession := p_work_protocol->'supersession';
  if supersession is not null and supersession<>'null'::jsonb then
    if jsonb_typeof(supersession)<>'object'
       or supersession->>'revalidation_mode' is distinct from 'FULL_REQUIRED'
       or supersession->>'previous_execution_id' is not distinct from p_work_protocol->>'execution_id'
       or coalesce(supersession->>'previous_manifest_digest','') !~ '^[0-9a-f]{64}$'
       or btrim(coalesce(supersession->>'change_authorization_ref',''))=''
       or supersession->>'change_authorization_sha256' is distinct from p_work_protocol->>'request_sha256'
       or length(btrim(coalesce(supersession->>'change_reason','')))<20
       or coalesce(supersession->>'previous_scope_sha256','') !~ '^[0-9a-f]{64}$'
       or coalesce(supersession->>'new_scope_sha256','') !~ '^[0-9a-f]{64}$' then
      return jsonb_build_object('result','BLOCKED','code','SUPERSESSION_SHAPE_INVALID');
    end if;

    select * into predecessor
    from public.lf_operation_execution e
    where e.execution_id=supersession->>'previous_execution_id';
    if not found or jsonb_typeof(predecessor.manifest->'work_protocol_manifest')<>'object' then
      return jsonb_build_object('result','BLOCKED','code','SUPERSESSION_PREDECESSOR_NOT_FOUND');
    end if;
    predecessor_wp := predecessor.manifest->'work_protocol_manifest';

    if predecessor_wp->>'manifest_digest' is distinct from supersession->>'previous_manifest_digest'
       or predecessor.operation_code is distinct from p_work_protocol->>'operation_code'
       or predecessor.target_type is distinct from p_work_protocol #>> '{target,type}'
       or predecessor.target_code is distinct from p_work_protocol #>> '{target,code}' then
      return jsonb_build_object(
        'result','BLOCKED',
        'code','SUPERSESSION_PREDECESSOR_BINDING_MISMATCH',
        'expected_manifest_digest',supersession->>'previous_manifest_digest',
        'actual_manifest_digest',predecessor_wp->>'manifest_digest',
        'expected_operation_code',p_work_protocol->>'operation_code',
        'actual_operation_code',predecessor.operation_code,
        'expected_target_type',p_work_protocol #>> '{target,type}',
        'actual_target_type',predecessor.target_type,
        'expected_target_code',p_work_protocol #>> '{target,code}',
        'actual_target_code',predecessor.target_code
      );
    end if;

    previous_scope_sha := encode(
      extensions.digest(
        convert_to(public.lf_work_protocol_canonical_json_v1(predecessor_wp->'authorized_scope'),'UTF8'),
        'sha256'
      ),'hex'
    );
    new_scope_sha := encode(
      extensions.digest(
        convert_to(public.lf_work_protocol_canonical_json_v1(p_work_protocol->'authorized_scope'),'UTF8'),
        'sha256'
      ),'hex'
    );
    if previous_scope_sha is distinct from supersession->>'previous_scope_sha256'
       or new_scope_sha is distinct from supersession->>'new_scope_sha256'
       or previous_scope_sha=new_scope_sha then
      return jsonb_build_object('result','BLOCKED','code','SUPERSESSION_SCOPE_BINDING_MISMATCH');
    end if;
  end if;

  return jsonb_build_object(
    'result','PASS_CONTROL_FROZEN',
    'waiver_count',waiver_count,
    'irreversible_approval_count',irreversible_count,
    'supersedes_execution_id',case
      when supersession is null or supersession='null'::jsonb then null
      else supersession->>'previous_execution_id'
    end
  );
end;
$fn$;

create or replace function public.lf_work_protocol_runtime_control_validate_v1(
  p_work_protocol jsonb,
  p_checkpoint_payload jsonb
) returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public
as $fn$
declare
  w jsonb;
  a jsonb;
  rb jsonb;
  found_match boolean;
  supersession jsonb;
begin
  if public.lf_work_protocol_control_validate_v1(p_work_protocol)->>'result'<>'PASS_CONTROL_FROZEN' then
    return jsonb_build_object('result','BLOCKED','code','CONTROL_FROZEN_INVALID');
  end if;
  if p_checkpoint_payload is null or jsonb_typeof(p_checkpoint_payload)<>'object' then
    p_checkpoint_payload := '{}'::jsonb;
  end if;

  supersession := p_work_protocol->'supersession';
  if supersession is not null and supersession<>'null'::jsonb then
    rb := p_checkpoint_payload #> '{work_protocol_control_readback,change_authorization}';
    if jsonb_typeof(rb)<>'object'
       or rb->>'authorization_ref' is distinct from supersession->>'change_authorization_ref'
       or rb->>'authorization_sha256' is distinct from supersession->>'change_authorization_sha256'
       or coalesce((rb->>'verified')::boolean,false) is not true then
      return jsonb_build_object('result','BLOCKED','code','SUPERSESSION_CHANGE_AUTHORIZATION_NOT_VERIFIED');
    end if;
  end if;

  for w in select value from jsonb_array_elements(p_work_protocol->'waivers')
  loop
    select exists (
      select 1
      from jsonb_array_elements(coalesce(p_checkpoint_payload #> '{work_protocol_control_readback,waiver_authorizations}','[]'::jsonb)) x
      where x->>'requirement_id'=w->>'requirement_id'
        and x->>'authorization_ref'=w->>'authorization_ref'
        and x->>'authorization_sha256'=w->>'authorization_sha256'
        and x->>'authorized_by'=w->>'authorized_by'
        and x->>'actor_type'='HUMAN'
        and coalesce((x->>'verified')::boolean,false)=true
    ) into found_match;
    if not found_match then
      return jsonb_build_object('result','BLOCKED','code','WAIVER_AUTHORIZATION_NOT_VERIFIED','requirement_id',w->>'requirement_id');
    end if;
  end loop;

  return jsonb_build_object('result','PASS_CONTROL_RUNTIME');
end;
$fn$;

create or replace function public.lf_work_protocol_step_control_evaluate_v1(
  p_work_protocol jsonb,
  p_obligation jsonb,
  p_evidence jsonb,
  p_checkpoint_payload jsonb
) returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public
as $fn$
declare
  approval jsonb;
  found_match boolean;
begin
  if coalesce((p_obligation->>'irreversible_effect')::boolean,false) is not true then
    return jsonb_build_object('result','PASS','code','CONTROL_STEP_NOT_IRREVERSIBLE');
  end if;

  select x into approval
  from jsonb_array_elements(p_work_protocol->'irreversible_approvals') x
  where x->>'step_id'=p_obligation->>'step_id'
  limit 1;
  if approval is null then
    return jsonb_build_object('result','BLOCKED','code','IRREVERSIBLE_APPROVAL_MISSING');
  end if;
  if p_evidence->>'irreversible_action_sha256' is distinct from approval->>'action_sha256' then
    return jsonb_build_object('result','BLOCKED','code','IRREVERSIBLE_ACTION_APPROVAL_BINDING_MISMATCH');
  end if;
  if (approval->>'expires_at')::timestamptz <= clock_timestamp() then
    return jsonb_build_object('result','BLOCKED','code','IRREVERSIBLE_APPROVAL_EXPIRED');
  end if;

  select exists (
    select 1
    from jsonb_array_elements(coalesce(p_checkpoint_payload #> '{work_protocol_control_readback,human_approvals}','[]'::jsonb)) x
    where x->>'step_id'=approval->>'step_id'
      and x->>'action_sha256'=approval->>'action_sha256'
      and x->>'approval_ref'=approval->>'approval_ref'
      and x->>'approval_sha256'=approval->>'approval_sha256'
      and x->>'approved_by'=approval->>'approved_by'
      and x->>'actor_type'='HUMAN'
      and coalesce((x->>'verified')::boolean,false)=true
  ) into found_match;
  if not found_match then
    return jsonb_build_object('result','BLOCKED','code','IRREVERSIBLE_HUMAN_APPROVAL_NOT_VERIFIED');
  end if;

  return jsonb_build_object('result','PASS','code','IRREVERSIBLE_HUMAN_APPROVAL_BOUND');
end;
$fn$;

create or replace function public.lf_work_protocol_controller_validate_v1(
  p_work_protocol jsonb
) returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public
as $fn$
declare
  p jsonb;
  o jsonb;
  invalid_count integer;
  cycle_found boolean;
begin
  p := p_work_protocol->'controller_policy';
  if jsonb_typeof(p) is distinct from 'object'
     or p->>'dependency_mode' is distinct from 'CANONICAL_DAG'
     or coalesce(p->>'material_wip_limit','')<>'1'
     or p->>'parallelism_policy' is distinct from 'READ_ONLY_SAME_CLOSURE_UNIT_ONLY'
     or coalesce((p->>'lease_required_for_activation')::boolean,false) is not true
     or coalesce((p->>'fenced_checkpoint_required')::boolean,false) is not true
     or coalesce((p->>'failed_predecessor_blocks_dependents')::boolean,false) is not true
     or coalesce((p->>'resume_from_canonical_state')::boolean,false) is not true then
    return jsonb_build_object('result','BLOCKED','code','CONTROLLER_POLICY_INVALID');
  end if;
  if jsonb_typeof(p_work_protocol->'obligations') is distinct from 'array' then
    return jsonb_build_object('result','BLOCKED','code','CONTROLLER_OBLIGATIONS_INVALID');
  end if;

  select count(*) into invalid_count
  from jsonb_array_elements(p_work_protocol->'obligations') x
  where jsonb_typeof(x->'depends_on_step_ids') is distinct from 'array'
     or btrim(coalesce(x->>'closure_unit_id',''))=''
     or coalesce(x->>'controller_order','') !~ '^[0-9]+$'
     or x->>'execution_effect' not in ('READ_ONLY','MUTATING','JUDGE','CLOSURE')
     or jsonb_typeof(x->'parallel_safe') is distinct from 'boolean'
     or (coalesce((x->>'parallel_safe')::boolean,false) and x->>'execution_effect'<>'READ_ONLY');
  if invalid_count<>0 then
    return jsonb_build_object('result','BLOCKED','code','CONTROLLER_OBLIGATION_SHAPE_INVALID','count',invalid_count);
  end if;

  select count(*) into invalid_count
  from (
    select x->>'controller_order' k,count(*) n
    from jsonb_array_elements(p_work_protocol->'obligations') x
    group by x->>'controller_order'
    having count(*)>1
  ) d;
  if invalid_count<>0 then
    return jsonb_build_object('result','BLOCKED','code','CONTROLLER_ORDER_DUPLICATE');
  end if;

  with obligations as (
    select x->>'step_id' step_id,x->'depends_on_step_ids' deps
    from jsonb_array_elements(p_work_protocol->'obligations') x
  ), edges as (
    select o.step_id, d.dep
    from obligations o
    cross join lateral jsonb_array_elements_text(o.deps) d(dep)
  )
  select count(*) into invalid_count
  from edges e
  left join obligations d on d.step_id=e.dep
  where e.dep=e.step_id or d.step_id is null;
  if invalid_count<>0 then
    return jsonb_build_object('result','BLOCKED','code','CONTROLLER_DEPENDENCY_INVALID','count',invalid_count);
  end if;

  with recursive
  obligations as (
    select x->>'step_id' step_id,x->'depends_on_step_ids' deps
    from jsonb_array_elements(p_work_protocol->'obligations') x
  ),
  edges as (
    select o.step_id, d.dep
    from obligations o
    cross join lateral jsonb_array_elements_text(o.deps) d(dep)
  ),
  walk(start_step,current_step,path,cycle) as (
    select e.step_id,e.dep,array[e.step_id,e.dep],e.dep=e.step_id
    from edges e
    union all
    select w.start_step,e.dep,w.path||e.dep,e.dep=any(w.path)
    from walk w
    join edges e on e.step_id=w.current_step
    where not w.cycle
  )
  select coalesce(bool_or(cycle),false) into cycle_found from walk;
  if cycle_found then
    return jsonb_build_object('result','BLOCKED','code','CONTROLLER_DAG_CYCLE');
  end if;

  return jsonb_build_object('result','PASS_CONTROLLER_FROZEN');
end;
$fn$;

create or replace function public.lf_work_protocol_closure_controller_validate_v1(
  p_work_protocol jsonb
) returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public
as $fn$
declare
  p jsonb;
begin
  p := p_work_protocol->'closure_controller_policy';
  if jsonb_typeof(p) is distinct from 'object'
     or p->>'unit_progression_mode' is distinct from 'CLOSE_OR_BLOCK_WITH_EVIDENCE_BEFORE_NEXT'
     or p->>'blocked_continue_mode' is distinct from 'DEPENDENCY_SAFE_ONLY'
     or p->>'closure_receipt_kind' is distinct from 'WORK_PROTOCOL_CLOSURE_UNIT'
     or p->>'blocked_receipt_kind' is distinct from 'WORK_PROTOCOL_BLOCKED_UNIT'
     or coalesce((p->>'receipt_chain_required')::boolean,false) is not true
     or coalesce((p->>'reopen_on_unit_digest_change')::boolean,false) is not true
     or coalesce((p->>'global_close_requires_zero_debt')::boolean,false) is not true then
    return jsonb_build_object('result','BLOCKED','code','CLOSURE_CONTROLLER_POLICY_INVALID');
  end if;
  if jsonb_typeof(p_work_protocol->'obligations') is distinct from 'array'
     or not exists (
       select 1 from jsonb_array_elements(p_work_protocol->'obligations') o
       where coalesce((o->>'close_required')::boolean,false)
     ) then
    return jsonb_build_object('result','BLOCKED','code','CLOSURE_CONTROLLER_UNITS_MISSING');
  end if;
  return jsonb_build_object('result','PASS_CLOSURE_CONTROLLER_FROZEN');
end;
$fn$;

create or replace function public.lf_work_protocol_step_state_v1(
  p_execution_id text,
  p_step_id text
) returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public
as $fn$
declare
  e public.lf_operation_execution%rowtype;
  wp jsonb;
  o jsonb;
  es public.lf_operation_execution_steps%rowtype;
  checklist_result text;
  gate_eval jsonb;
  evidence_eval jsonb;
  control_eval jsonb;
  independent_ok boolean := true;
begin
  select * into e from public.lf_operation_execution where execution_id=p_execution_id;
  if not found then return jsonb_build_object('state','BLOCKED','code','EXECUTION_NOT_FOUND'); end if;
  wp := e.manifest->'work_protocol_manifest';
  if jsonb_typeof(wp) is distinct from 'object' then
    return jsonb_build_object('state','BLOCKED','code','WORK_PROTOCOL_NOT_BOUND');
  end if;
  select x into o from jsonb_array_elements(wp->'obligations') x where x->>'step_id'=p_step_id limit 1;
  if o is null then return jsonb_build_object('state','BLOCKED','code','STEP_NOT_IN_MANIFEST'); end if;

  select * into es from public.lf_operation_execution_steps
  where execution_id=p_execution_id and step_id=p_step_id;
  if not found then return jsonb_build_object('state','PENDING','code','STEP_NOT_RECORDED'); end if;

  select c.checklist_result into checklist_result
  from public.v_lf_operation_execution_checklist c
  where c.execution_id=p_execution_id and c.step_id=p_step_id;

  gate_eval := public.lf_work_protocol_gate_evaluate_v1(
    e.operation_code,p_step_id,wp #>> '{closure_policy,independent_closure_step_id}',
    case when jsonb_typeof(es.evidence_payload->'work_protocol_gate')='object'
      then es.evidence_payload->'work_protocol_gate'||jsonb_build_object('evidence',es.evidence_payload)
      else jsonb_build_object('evidence',es.evidence_payload) end
  );
  evidence_eval := public.lf_work_protocol_evidence_validate_v1(
    p_execution_id,p_step_id,o->>'gate_contract_sha256',o->>'verifier_mode',
    o->>'gate_type',o->>'authority_ref',es.evidence_payload,e.started_at,wp->'evidence_policy'
  );
  control_eval := public.lf_work_protocol_step_control_evaluate_v1(
    wp,o,es.evidence_payload,coalesce(e.checkpoint_payload,'{}'::jsonb)
  );

  if o->>'verifier_mode' in ('INDEPENDENT_READBACK','SEMANTIC_JUDGE','COMPOSITE') then
    independent_ok := (
      es.created_by_execution_id is distinct from e.execution_id
      and es.evidence_payload->>'verification_actor_execution_id'=es.created_by_execution_id
      and es.evidence_payload->>'verification_target_execution_id'=e.execution_id
      and exists (
        select 1 from public.lf_operation_execution v
        where v.execution_id=es.created_by_execution_id
          and v.execution_id<>e.execution_id
          and v.completed_at is not null
          and v.status in ('COMPLETED','CLOSED_PASS','CLOSED_WITH_VERIFIED_EVIDENCE','PASS_CLEAN','CONTROLLED_READ_ONLY_PASS')
      )
    );
  end if;

  if es.status in ('BLOCKED','FAIL','RETURN_TO_WORKER')
     or gate_eval->>'result' in ('BLOCKED','FAIL')
     or evidence_eval->>'result' in ('BLOCKED','STALE')
     or control_eval->>'result'='BLOCKED'
     or coalesce(checklist_result,'FAIL_MISSING') like 'FAIL%' then
    return jsonb_build_object(
      'state','BLOCKED','code','STEP_RECORDED_NOT_VERIFIED',
      'gate',gate_eval,'evidence',evidence_eval,'control',control_eval,'checklist_result',checklist_result
    );
  end if;

  if independent_ok
     and gate_eval->>'result'='PASS'
     and evidence_eval->>'result'='PASS'
     and control_eval->>'result'='PASS'
     and checklist_result='OK' then
    return jsonb_build_object('state','VERIFIED','code','STEP_VERIFIED');
  end if;

  return jsonb_build_object('state','BLOCKED','code','STEP_RECORDED_NOT_VERIFIED');
end;
$fn$;

create or replace function public.lf_work_protocol_closure_unit_state_v1(
  p_execution_id text,
  p_closure_unit_id text
) returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, private, extensions
as $fn$
declare
  e public.lf_operation_execution%rowtype;
  wp jsonb;
  o jsonb;
  sid text;
  step_state jsonb;
  es public.lf_operation_execution_steps%rowtype;
  step_evidence_sha text;
  steps_state jsonb := '[]'::jsonb;
  verified_count integer := 0;
  blocked_count integer := 0;
  pending_count integer := 0;
  unit_count integer := 0;
  current_unit_order integer;
  previous_unit text;
  previous_state jsonb;
  previous_terminal boolean := true;
  previous_receipt_sha text;
  unit_state_doc jsonb;
  unit_state_sha text;
  receipt private.lf_evidence_ledger_v1%rowtype;
  expected_outcome text;
  expected_kind text;
  receipt_valid boolean := false;
  receipt_blocker jsonb;
begin
  select * into e
  from public.lf_operation_execution
  where execution_id=p_execution_id;
  if not found then
    return jsonb_build_object('state','BLOCKED','code','EXECUTION_NOT_FOUND');
  end if;

  wp := e.manifest->'work_protocol_manifest';
  if jsonb_typeof(wp) is distinct from 'object' then
    return jsonb_build_object('state','BLOCKED','code','WORK_PROTOCOL_NOT_BOUND');
  end if;
  if public.lf_work_protocol_closure_controller_validate_v1(wp)->>'result'
     <> 'PASS_CLOSURE_CONTROLLER_FROZEN' then
    return jsonb_build_object('state','BLOCKED','code','CLOSURE_CONTROLLER_MANIFEST_INVALID');
  end if;

  begin
    perform public.lf_work_protocol_validate_frozen_v1(e.operation_code,e.execution_id,wp);
  exception when others then
    return jsonb_build_object(
      'state','REOPEN_REQUIRED',
      'code','CLOSURE_AUTHORITY_OR_MANIFEST_STALE',
      'detail',sqlerrm
    );
  end;

  select min((x->>'controller_order')::integer),count(*)
  into current_unit_order,unit_count
  from jsonb_array_elements(wp->'obligations') x
  where coalesce((x->>'close_required')::boolean,false)
    and x->>'closure_unit_id'=p_closure_unit_id;

  if unit_count=0 then
    return jsonb_build_object('state','BLOCKED','code','CLOSURE_UNIT_NOT_FOUND');
  end if;

  select u.closure_unit_id into previous_unit
  from (
    select x->>'closure_unit_id' closure_unit_id,
           min((x->>'controller_order')::integer) unit_order
    from jsonb_array_elements(wp->'obligations') x
    where coalesce((x->>'close_required')::boolean,false)
    group by x->>'closure_unit_id'
  ) u
  where u.unit_order<current_unit_order
  order by u.unit_order desc,u.closure_unit_id desc
  limit 1;

  if previous_unit is not null then
    previous_state := public.lf_work_protocol_closure_unit_state_v1(
      p_execution_id,previous_unit
    );
    previous_terminal := previous_state->>'state' in (
      'CLOSED_WITH_EVIDENCE','BLOCKED_WITH_EVIDENCE'
    );
    if previous_terminal then
      previous_receipt_sha := previous_state->>'receipt_sha256';
    end if;
  end if;

  for o in
    select value
    from jsonb_array_elements(wp->'obligations')
    where coalesce((value->>'close_required')::boolean,false)
      and value->>'closure_unit_id'=p_closure_unit_id
    order by (value->>'controller_order')::integer,value->>'step_id'
  loop
    sid := o->>'step_id';
    step_state := public.lf_work_protocol_step_state_v1(p_execution_id,sid);

    select * into es
    from public.lf_operation_execution_steps
    where execution_id=p_execution_id and step_id=sid;

    if found then
      step_evidence_sha := encode(
        extensions.digest(
          convert_to(
            public.lf_work_protocol_canonical_json_v1(
              jsonb_build_object(
                'status',es.status,
                'evidence_ref',es.evidence_ref,
                'evidence_payload',es.evidence_payload,
                'observed_at',es.observed_at
              )
            ),
            'UTF8'
          ),
          'sha256'
        ),
        'hex'
      );
    else
      step_evidence_sha := null;
    end if;

    if step_state->>'state'='VERIFIED' then
      verified_count := verified_count+1;
    elsif step_state->>'state'='PENDING' then
      pending_count := pending_count+1;
    else
      blocked_count := blocked_count+1;
    end if;

    steps_state := steps_state||jsonb_build_array(
      jsonb_build_object(
        'step_id',sid,
        'state',step_state->>'state',
        'step_evidence_sha256',step_evidence_sha,
        'step_evidence_present',
          found
          and btrim(coalesce(es.evidence_ref,''))<>''
          and jsonb_typeof(es.evidence_payload)='object'
          and es.evidence_payload<>'{}'::jsonb
      )
    );
  end loop;

  unit_state_doc := jsonb_build_object(
    'execution_id',p_execution_id,
    'manifest_digest',wp->>'manifest_digest',
    'closure_unit_id',p_closure_unit_id,
    'steps',steps_state
  );
  unit_state_sha := encode(
    extensions.digest(
      convert_to(public.lf_work_protocol_canonical_json_v1(unit_state_doc),'UTF8'),
      'sha256'
    ),
    'hex'
  );

  select * into receipt
  from private.lf_evidence_ledger_v1 l
  where l.execution_id=p_execution_id
    and l.gate_code='WORK_PROTOCOL_CLOSURE:'||p_closure_unit_id
    and l.receipt_kind in (
      wp #>> '{closure_controller_policy,closure_receipt_kind}',
      wp #>> '{closure_controller_policy,blocked_receipt_kind}'
    )
  order by
    (l.subject_sha256=unit_state_sha) desc,
    l.created_at desc,
    l.receipt_id::text desc
  limit 1;

  if verified_count=unit_count then
    expected_outcome := 'CLOSED_WITH_EVIDENCE';
    expected_kind := wp #>> '{closure_controller_policy,closure_receipt_kind}';
  elsif blocked_count>0 then
    expected_outcome := 'BLOCKED_WITH_EVIDENCE';
    expected_kind := wp #>> '{closure_controller_policy,blocked_receipt_kind}';
  else
    expected_outcome := null;
    expected_kind := null;
  end if;

  if receipt.receipt_id is not null then
    receipt_blocker := receipt.receipt_payload->'blocker';
    receipt_valid := (
      receipt.verification_state='VERIFIED'
      and receipt.receipt_kind=expected_kind
      and receipt.subject_sha256=unit_state_sha
      and receipt.receipt_payload->>'work_protocol_execution_id'=p_execution_id
      and receipt.receipt_payload->>'manifest_digest'=wp->>'manifest_digest'
      and receipt.receipt_payload->>'closure_unit_id'=p_closure_unit_id
      and receipt.receipt_payload->>'unit_state_sha256'=unit_state_sha
      and receipt.receipt_payload->>'outcome'=expected_outcome
      and (receipt.receipt_payload->>'previous_unit_receipt_sha256')
          is not distinct from previous_receipt_sha
      and receipt.verification_payload->'provider_readback_verified'='true'::jsonb
      and receipt.verification_payload->'digest_recomputed'='true'::jsonb
      and exists (
        select 1
        from private.lf_evidence_resolver_registry_v1 rr
        where rr.resolver_id=receipt.resolver_id
          and rr.active=true
          and rr.trust_level='TRUSTED_PROVIDER_BOUND'
          and rr.provider=receipt.provider
          and rr.verification_method=receipt.verification_method
      )
      and (
        expected_outcome<>'BLOCKED_WITH_EVIDENCE'
        or (
          jsonb_typeof(receipt_blocker)='object'
          and btrim(coalesce(receipt_blocker->>'ref',''))<>''
          and coalesce(receipt_blocker->>'sha256','') ~ '^[0-9a-f]{64}$'
          and length(btrim(coalesce(receipt_blocker->>'reason','')))>=20
          and btrim(coalesce(receipt_blocker->>'owner',''))<>''
          and length(btrim(coalesce(receipt_blocker->>'next_action','')))>=10
        )
      )
    );

    if not previous_terminal and previous_unit is not null then
      receipt_valid := false;
    end if;

    if receipt_valid then
      return jsonb_build_object(
        'state',expected_outcome,
        'code','CLOSURE_RECEIPT_CURRENT',
        'closure_unit_id',p_closure_unit_id,
        'unit_order',current_unit_order,
        'unit_state_sha256',unit_state_sha,
        'receipt_id',receipt.receipt_id,
        'receipt_sha256',receipt.receipt_sha256,
        'previous_unit_id',previous_unit,
        'previous_unit_receipt_sha256',previous_receipt_sha,
        'blocked_step_count',blocked_count,
        'pending_step_count',pending_count,
        'verified_step_count',verified_count,
        'steps',steps_state,
        'blocker',receipt_blocker
      );
    end if;

    return jsonb_build_object(
      'state','REOPEN_REQUIRED',
      'code','CLOSURE_RECEIPT_STALE_OR_CHAIN_BROKEN',
      'closure_unit_id',p_closure_unit_id,
      'unit_order',current_unit_order,
      'unit_state_sha256',unit_state_sha,
      'receipt_id',receipt.receipt_id,
      'receipt_sha256',receipt.receipt_sha256,
      'previous_unit_id',previous_unit,
      'previous_unit_receipt_sha256',previous_receipt_sha,
      'blocked_step_count',blocked_count,
      'pending_step_count',pending_count,
      'verified_step_count',verified_count,
      'steps',steps_state
    );
  end if;

  if previous_unit is not null and not previous_terminal then
    return jsonb_build_object(
      'state','WAITING_PREVIOUS_CLOSURE',
      'code','PREVIOUS_CLOSURE_NOT_TERMINAL',
      'closure_unit_id',p_closure_unit_id,
      'unit_order',current_unit_order,
      'unit_state_sha256',unit_state_sha,
      'previous_unit_id',previous_unit,
      'blocked_step_count',blocked_count,
      'pending_step_count',pending_count,
      'verified_step_count',verified_count,
      'steps',steps_state
    );
  end if;

  if verified_count=unit_count then
    return jsonb_build_object(
      'state','READY_TO_CLOSE',
      'code','UNIT_VERIFIED_CLOSURE_RECEIPT_REQUIRED',
      'closure_unit_id',p_closure_unit_id,
      'unit_order',current_unit_order,
      'unit_state_sha256',unit_state_sha,
      'previous_unit_id',previous_unit,
      'previous_unit_receipt_sha256',previous_receipt_sha,
      'blocked_step_count',0,
      'pending_step_count',0,
      'verified_step_count',verified_count,
      'steps',steps_state
    );
  elsif blocked_count>0 then
    return jsonb_build_object(
      'state','READY_TO_BLOCK_WITH_EVIDENCE',
      'code','UNIT_BLOCKED_RECEIPT_REQUIRED',
      'closure_unit_id',p_closure_unit_id,
      'unit_order',current_unit_order,
      'unit_state_sha256',unit_state_sha,
      'previous_unit_id',previous_unit,
      'previous_unit_receipt_sha256',previous_receipt_sha,
      'blocked_step_count',blocked_count,
      'pending_step_count',pending_count,
      'verified_step_count',verified_count,
      'steps',steps_state
    );
  end if;

  return jsonb_build_object(
    'state','OPEN',
    'code','UNIT_WORK_INCOMPLETE',
    'closure_unit_id',p_closure_unit_id,
    'unit_order',current_unit_order,
    'unit_state_sha256',unit_state_sha,
    'previous_unit_id',previous_unit,
    'previous_unit_receipt_sha256',previous_receipt_sha,
    'blocked_step_count',blocked_count,
    'pending_step_count',pending_count,
    'verified_step_count',verified_count,
    'steps',steps_state
  );
end;
$fn$;

create or replace function public.lf_work_protocol_closure_mark_v1(
  p_execution_id text,
  p_closure_unit_id text,
  p_outcome text,
  p_lease_owner text,
  p_lease_fence bigint,
  p_source_head_sha text,
  p_blocker_ref text,
  p_blocker_sha256 text,
  p_blocker_reason text,
  p_blocker_owner text,
  p_blocker_next_action text,
  p_actor_execution_id text
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = pg_catalog, public, private, extensions
as $fn$
declare
  e public.lf_operation_execution%rowtype;
  wp jsonb;
  state jsonb;
  kind text;
  subject_ref text;
  gate_code text;
  authority_ref text;
  provider_ref text;
  capability_code text := 'DB_WRITE_TRANSPORT';
  blocker jsonb := null;
  payload jsonb;
  receipt jsonb;
  unit_count integer;
begin
  if p_outcome not in ('CLOSED_WITH_EVIDENCE','BLOCKED_WITH_EVIDENCE') then
    raise exception 'LF_WORK_PROTOCOL_CLOSURE_OUTCOME_INVALID';
  end if;
  if coalesce(p_source_head_sha,'') !~ '^[0-9a-f]{40}$' then
    raise exception 'LF_WORK_PROTOCOL_CLOSURE_SOURCE_HEAD_INVALID';
  end if;

  select * into e
  from public.lf_operation_execution
  where execution_id=p_execution_id
  for update;
  if not found then raise exception 'EXECUTION_NOT_FOUND'; end if;
  if e.lease_owner is distinct from p_lease_owner
     or e.lease_fence is distinct from p_lease_fence
     or e.lease_expires_at is null
     or e.lease_expires_at<=clock_timestamp() then
    raise exception 'LF_WORK_PROTOCOL_CLOSURE_STALE_OR_MISSING_LEASE';
  end if;

  wp := e.manifest->'work_protocol_manifest';
  state := public.lf_work_protocol_closure_unit_state_v1(
    p_execution_id,p_closure_unit_id
  );

  select count(*) into unit_count
  from jsonb_array_elements(wp->'obligations') o
  where coalesce((o->>'close_required')::boolean,false)
    and o->>'closure_unit_id'=p_closure_unit_id;

  if state->>'state'=p_outcome then
    return jsonb_build_object(
      'result','REPLAY_CLOSURE_RECEIPT',
      'closure_unit_id',p_closure_unit_id,
      'outcome',p_outcome,
      'receipt_id',state->>'receipt_id',
      'receipt_sha256',state->>'receipt_sha256'
    );
  end if;

  if p_outcome='CLOSED_WITH_EVIDENCE'
     and not (
       state->>'state'='READY_TO_CLOSE'
       or (
         state->>'state'='REOPEN_REQUIRED'
         and coalesce((state->>'verified_step_count')::integer,0)=unit_count
         and coalesce((state->>'blocked_step_count')::integer,0)=0
         and coalesce((state->>'pending_step_count')::integer,0)=0
       )
     ) then
    raise exception 'LF_WORK_PROTOCOL_CLOSURE_NOT_READY:%',state;
  end if;

  if p_outcome='BLOCKED_WITH_EVIDENCE' then
    if not (
      state->>'state'='READY_TO_BLOCK_WITH_EVIDENCE'
      or (
        state->>'state'='REOPEN_REQUIRED'
        and coalesce((state->>'blocked_step_count')::integer,0)>0
      )
    ) then
      raise exception 'LF_WORK_PROTOCOL_BLOCKED_CLOSURE_NOT_READY:%',state;
    end if;

    if btrim(coalesce(p_blocker_ref,''))=''
       or coalesce(p_blocker_sha256,'') !~ '^[0-9a-f]{64}$'
       or length(btrim(coalesce(p_blocker_reason,'')))<20
       or btrim(coalesce(p_blocker_owner,''))=''
       or length(btrim(coalesce(p_blocker_next_action,'')))<10 then
      raise exception 'LF_WORK_PROTOCOL_BLOCKED_CLOSURE_EVIDENCE_INVALID';
    end if;

    if not exists (
      select 1
      from jsonb_array_elements(coalesce(state->'steps','[]'::jsonb)) s
      where s->>'state'='BLOCKED'
        and coalesce((s->>'step_evidence_present')::boolean,false)
        and s->>'step_evidence_sha256'=p_blocker_sha256
        and p_blocker_ref=
          'supabase://public/lf_operation_execution_steps/'||
          p_execution_id||'/'||(s->>'step_id')
    ) then
      raise exception 'LF_WORK_PROTOCOL_BLOCKED_CLOSURE_EVIDENCE_NOT_EXACT';
    end if;

    blocker := jsonb_build_object(
      'ref',p_blocker_ref,
      'sha256',p_blocker_sha256,
      'reason',p_blocker_reason,
      'owner',p_blocker_owner,
      'next_action',p_blocker_next_action,
      'debt_id',encode(
        extensions.digest(
          convert_to(
            p_execution_id||'|'||p_closure_unit_id||'|'||(state->>'unit_state_sha256'),
            'UTF8'
          ),
          'sha256'
        ),
        'hex'
      )
    );
  end if;

  kind := case
    when p_outcome='CLOSED_WITH_EVIDENCE'
      then wp #>> '{closure_controller_policy,closure_receipt_kind}'
    else wp #>> '{closure_controller_policy,blocked_receipt_kind}'
  end;

  subject_ref := 'supabase://work-protocol/'||p_execution_id||
                 '/closure/'||p_closure_unit_id;
  gate_code := 'WORK_PROTOCOL_CLOSURE:'||p_closure_unit_id;
  authority_ref := 'supabase://public/lf_operation_execution/'||p_execution_id;
  provider_ref := subject_ref;

  payload := jsonb_build_object(
    'execution_id',p_execution_id,
    'capability_code',capability_code,
    'gate_code',gate_code,
    'receipt_kind',kind,
    'subject_type','WORK_PROTOCOL_CLOSURE_UNIT_STATE',
    'subject_ref',subject_ref,
    'subject_sha256',state->>'unit_state_sha256',
    'source_head_sha',p_source_head_sha,
    'authority_ref',authority_ref,
    'resolver_id','LF_SUPABASE_READBACK_V1',
    'provider','SUPABASE',
    'provider_ref',provider_ref,
    'work_protocol_execution_id',p_execution_id,
    'manifest_digest',wp->>'manifest_digest',
    'closure_unit_id',p_closure_unit_id,
    'unit_state_sha256',state->>'unit_state_sha256',
    'outcome',p_outcome,
    'previous_unit_receipt_sha256',state->'previous_unit_receipt_sha256',
    'blocker',blocker
  );

  receipt := public.fn_lf_evidence_ledger_anchor_v1(
    p_execution_id,
    capability_code,
    gate_code,
    kind,
    'WORK_PROTOCOL_CLOSURE_UNIT_STATE',
    subject_ref,
    state->>'unit_state_sha256',
    p_source_head_sha,
    authority_ref,
    'LF_SUPABASE_READBACK_V1',
    'SUPABASE',
    provider_ref,
    'SUPABASE_SQL_READBACK_PLUS_DB_DIGEST',
    'VERIFIED',
    jsonb_build_object(
      'provider_readback_verified',true,
      'digest_recomputed',true,
      'closure_controller_verified',true
    ),
    payload,
    p_actor_execution_id
  );

  state := public.lf_work_protocol_closure_unit_state_v1(
    p_execution_id,p_closure_unit_id
  );

  if state->>'state'<>p_outcome then
    raise exception 'LF_WORK_PROTOCOL_CLOSURE_RECEIPT_READBACK_FAILED:%',state;
  end if;

  return jsonb_build_object(
    'result','CLOSURE_RECEIPT_ANCHORED',
    'closure_unit_id',p_closure_unit_id,
    'outcome',p_outcome,
    'receipt',receipt,
    'readback',state
  );
end;
$fn$;

create or replace function public.lf_work_protocol_closure_status_v1(
  p_execution_id text
) returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public
as $fn$
declare
  e public.lf_operation_execution%rowtype;
  wp jsonb;
  u record;
  st jsonb;
  units jsonb := '[]'::jsonb;
  total_count integer := 0;
  closed_count integer := 0;
  debt_count integer := 0;
  reopen_count integer := 0;
  unclosed_count integer := 0;
begin
  select * into e
  from public.lf_operation_execution
  where execution_id=p_execution_id;
  if not found then
    return jsonb_build_object('result','BLOCKED','code','EXECUTION_NOT_FOUND');
  end if;
  wp := e.manifest->'work_protocol_manifest';
  if jsonb_typeof(wp) is distinct from 'object' then
    return jsonb_build_object('result','BLOCKED','code','WORK_PROTOCOL_NOT_BOUND');
  end if;

  for u in
    select x->>'closure_unit_id' closure_unit_id,
           min((x->>'controller_order')::integer) unit_order
    from jsonb_array_elements(wp->'obligations') x
    where coalesce((x->>'close_required')::boolean,false)
    group by x->>'closure_unit_id'
    order by min((x->>'controller_order')::integer),x->>'closure_unit_id'
  loop
    st := public.lf_work_protocol_closure_unit_state_v1(
      p_execution_id,u.closure_unit_id
    );
    total_count := total_count+1;
    units := units||jsonb_build_array(st);

    if st->>'state'='CLOSED_WITH_EVIDENCE' then
      closed_count := closed_count+1;
    elsif st->>'state'='BLOCKED_WITH_EVIDENCE' then
      debt_count := debt_count+1;
      unclosed_count := unclosed_count+1;
    elsif st->>'state'='REOPEN_REQUIRED' then
      reopen_count := reopen_count+1;
      unclosed_count := unclosed_count+1;
    else
      unclosed_count := unclosed_count+1;
    end if;
  end loop;

  return jsonb_build_object(
    'result','PASS_CLOSURE_STATUS',
    'execution_id',p_execution_id,
    'unit_count',total_count,
    'closed_unit_count',closed_count,
    'closure_debt_count',debt_count,
    'reopen_required_count',reopen_count,
    'unclosed_unit_count',unclosed_count,
    'global_close_allowed',
      total_count>0
      and closed_count=total_count
      and debt_count=0
      and reopen_count=0
      and unclosed_count=0,
    'units',units
  );
end;
$fn$;

create or replace function public.lf_work_protocol_controller_plan_v1(
  p_execution_id text
) returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, extensions
as $fn$
declare
  e public.lf_operation_execution%rowtype;
  wp jsonb;
  o jsonb;
  dep text;
  st jsonb;
  dep_state jsonb;
  ready jsonb := '[]'::jsonb;
  waiting jsonb := '[]'::jsonb;
  blocked jsonb := '[]'::jsonb;
  verified jsonb := '[]'::jsonb;
  active_unit text;
  material_step text;
  nonparallel_step text;
  allowed jsonb := '[]'::jsonb;
  plan jsonb;
  plan_sha text;
  closure_status jsonb;
  first_nonterminal jsonb;
  active_unit_closure_state jsonb;
begin
  select * into e from public.lf_operation_execution where execution_id=p_execution_id;
  if not found then return jsonb_build_object('result','BLOCKED','code','EXECUTION_NOT_FOUND'); end if;
  wp := e.manifest->'work_protocol_manifest';
  if jsonb_typeof(wp) is distinct from 'object' then
    return jsonb_build_object('result','BLOCKED','code','WORK_PROTOCOL_NOT_BOUND');
  end if;
  if public.lf_work_protocol_controller_validate_v1(wp)->>'result'<>'PASS_CONTROLLER_FROZEN' then
    return jsonb_build_object('result','BLOCKED','code','CONTROLLER_MANIFEST_INVALID');
  end if;
  begin
    perform public.lf_work_protocol_validate_frozen_v1(e.operation_code,e.execution_id,wp);
  exception when others then
    return jsonb_build_object('result','BLOCKED','code','CONTROLLER_FROZEN_CURRENTNESS_FAILED','detail',sqlerrm);
  end;

  for o in
    select value from jsonb_array_elements(wp->'obligations')
    order by (value->>'controller_order')::integer,value->>'step_id'
  loop
    st := public.lf_work_protocol_step_state_v1(p_execution_id,o->>'step_id');
    if st->>'state'='VERIFIED' then
      verified := verified||jsonb_build_array(o->>'step_id');
      continue;
    end if;

    declare
      has_blocked boolean := false;
      has_waiting boolean := false;
    begin
      for dep in select jsonb_array_elements_text(o->'depends_on_step_ids')
      loop
        dep_state := public.lf_work_protocol_step_state_v1(p_execution_id,dep);
        if dep_state->>'state'='VERIFIED' then
          null;
        elsif dep_state->>'state'='PENDING' then
          has_waiting := true;
        else
          has_blocked := true;
        end if;
      end loop;
      if has_blocked then
        blocked := blocked||jsonb_build_array(o->>'step_id');
      elsif has_waiting then
        waiting := waiting||jsonb_build_array(o->>'step_id');
      else
        ready := ready||jsonb_build_array(o);
      end if;
    end;
  end loop;

  closure_status := public.lf_work_protocol_closure_status_v1(p_execution_id);
  if closure_status->>'result'<>'PASS_CLOSURE_STATUS' then
    return jsonb_build_object(
      'result','BLOCKED',
      'code','CLOSURE_STATUS_UNAVAILABLE',
      'closure_status',closure_status
    );
  end if;

  select x into first_nonterminal
  from jsonb_array_elements(closure_status->'units') x
  where x->>'state' not in ('CLOSED_WITH_EVIDENCE','BLOCKED_WITH_EVIDENCE')
  order by (x->>'unit_order')::integer,x->>'closure_unit_id'
  limit 1;

  if jsonb_array_length(ready)>0 then
    select x->>'closure_unit_id' into active_unit
    from jsonb_array_elements(ready) x
    order by (x->>'controller_order')::integer,x->>'step_id'
    limit 1;

    active_unit_closure_state := public.lf_work_protocol_closure_unit_state_v1(
      p_execution_id,active_unit
    );

    if active_unit_closure_state->>'state'<>'BLOCKED_WITH_EVIDENCE'
       and first_nonterminal is not null
       and (
         first_nonterminal->>'closure_unit_id' is distinct from active_unit
         or first_nonterminal->>'state' in (
           'READY_TO_CLOSE','READY_TO_BLOCK_WITH_EVIDENCE',
           'REOPEN_REQUIRED','WAITING_PREVIOUS_CLOSURE'
         )
       ) then
      return jsonb_build_object(
        'result','BLOCKED_CLOSURE_REQUIRED',
        'code','CLOSE_CURRENT_UNIT_BEFORE_NEXT',
        'execution_id',p_execution_id,
        'closure_unit',first_nonterminal,
        'candidate_active_closure_unit_id',active_unit,
        'verified_step_ids',verified,
        'waiting_step_ids',waiting,
        'blocked_by_predecessor_step_ids',blocked
      );
    end if;

    select x->>'step_id' into material_step
    from jsonb_array_elements(ready) x
    where x->>'closure_unit_id'=active_unit
      and x->>'execution_effect'<>'READ_ONLY'
    order by (x->>'controller_order')::integer,x->>'step_id'
    limit 1;

    if material_step is not null then
      allowed := jsonb_build_array(material_step);
      select allowed || coalesce(jsonb_agg(x->>'step_id' order by (x->>'controller_order')::integer,x->>'step_id'),'[]'::jsonb)
      into allowed
      from jsonb_array_elements(ready) x
      where x->>'closure_unit_id'=active_unit
        and x->>'execution_effect'='READ_ONLY'
        and coalesce((x->>'parallel_safe')::boolean,false);
    else
      select x->>'step_id' into nonparallel_step
      from jsonb_array_elements(ready) x
      where x->>'closure_unit_id'=active_unit
        and coalesce((x->>'parallel_safe')::boolean,false) is not true
      order by (x->>'controller_order')::integer,x->>'step_id'
      limit 1;
      if nonparallel_step is not null then
        allowed := jsonb_build_array(nonparallel_step);
      else
        select coalesce(jsonb_agg(x->>'step_id' order by (x->>'controller_order')::integer,x->>'step_id'),'[]'::jsonb)
        into allowed
        from jsonb_array_elements(ready) x
        where x->>'closure_unit_id'=active_unit;
      end if;
    end if;
  end if;

  if jsonb_array_length(ready)=0
     and first_nonterminal is not null
     and first_nonterminal->>'state' in (
       'READY_TO_CLOSE','READY_TO_BLOCK_WITH_EVIDENCE',
       'REOPEN_REQUIRED','WAITING_PREVIOUS_CLOSURE'
     ) then
    return jsonb_build_object(
      'result','BLOCKED_CLOSURE_REQUIRED',
      'code','CLOSE_CURRENT_UNIT_BEFORE_NEXT',
      'execution_id',p_execution_id,
      'closure_unit',first_nonterminal,
      'verified_step_ids',verified,
      'waiting_step_ids',waiting,
      'blocked_by_predecessor_step_ids',blocked
    );
  end if;

  plan := jsonb_build_object(
    'result','PASS_CONTROLLER_PLAN',
    'execution_id',p_execution_id,
    'manifest_digest',wp->>'manifest_digest',
    'active_closure_unit_id',active_unit,
    'allowed_step_ids',allowed,
    'verified_step_ids',verified,
    'waiting_step_ids',waiting,
    'blocked_by_predecessor_step_ids',blocked,
    'closure_status',closure_status
  );
  plan_sha := encode(extensions.digest(convert_to(public.lf_work_protocol_canonical_json_v1(plan),'UTF8'),'sha256'),'hex');
  return plan||jsonb_build_object('plan_sha256',plan_sha);
end;
$fn$;

create or replace function public.lf_work_protocol_controller_activate_v1(
  p_execution_id text,
  p_lease_owner text,
  p_lease_fence bigint,
  p_requested_step_ids text[],
  p_actor_execution_id text
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = pg_catalog, public
as $fn$
declare
  e public.lf_operation_execution%rowtype;
  plan jsonb;
  sid text;
  payload jsonb;
  cp jsonb;
begin
  if p_requested_step_ids is null or cardinality(p_requested_step_ids)<1
     or cardinality(p_requested_step_ids)<>cardinality(array(select distinct unnest(p_requested_step_ids))) then
    raise exception 'LF_WORK_PROTOCOL_CONTROLLER_REQUEST_INVALID';
  end if;
  select * into e from public.lf_operation_execution where execution_id=p_execution_id for update;
  if not found then raise exception 'EXECUTION_NOT_FOUND'; end if;
  if e.lease_owner is distinct from p_lease_owner
     or e.lease_fence is distinct from p_lease_fence
     or e.lease_expires_at is null or e.lease_expires_at<=clock_timestamp() then
    raise exception 'LF_WORK_PROTOCOL_CONTROLLER_STALE_OR_MISSING_LEASE';
  end if;

  plan := public.lf_work_protocol_controller_plan_v1(p_execution_id);
  if plan->>'result'<>'PASS_CONTROLLER_PLAN' then
    raise exception 'LF_WORK_PROTOCOL_CONTROLLER_PLAN_BLOCKED:%',plan;
  end if;
  foreach sid in array p_requested_step_ids loop
    if not exists (
      select 1 from jsonb_array_elements_text(plan->'allowed_step_ids') x where x=sid
    ) then
      raise exception 'LF_WORK_PROTOCOL_CONTROLLER_STEP_NOT_ALLOWED:%',sid;
    end if;
  end loop;

  payload := coalesce(e.checkpoint_payload,'{}'::jsonb)
    || jsonb_build_object(
      'work_protocol_controller',
      jsonb_build_object(
        'controller_version','LF_WORK_PROTOCOL_CONTROLLER_V1',
        'manifest_digest',plan->>'manifest_digest',
        'plan_sha256',plan->>'plan_sha256',
        'active_closure_unit_id',plan->>'active_closure_unit_id',
        'active_step_ids',to_jsonb(p_requested_step_ids),
        'lease_owner',p_lease_owner,
        'lease_fence',p_lease_fence,
        'activated_at',clock_timestamp()
      )
    );
  cp := public.fn_lf_operation_checkpoint_v1(
    p_execution_id,p_lease_owner,p_lease_fence,e.checkpoint_seq+1,payload,p_actor_execution_id
  );
  return jsonb_build_object('result','CONTROLLER_ACTIVATED','plan',plan,'checkpoint',cp);
end;
$fn$;

create or replace function public.lf_work_protocol_authority_snapshot_v1(p_operation_code text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, extensions
as $fn$
declare
  c public.lf_operation_contracts%rowtype;
  contract_count integer;
  op_rev text;
  contract_rev text;
  policy_sha text;
  obligation_sha text;
begin
  if btrim(coalesce(p_operation_code,''))='' then
    raise exception 'LF_WORK_PROTOCOL_OPERATION_CODE_INVALID';
  end if;

  op_rev := public.lf_operation_revision_sha256_v1(p_operation_code);

  select count(*) into contract_count
  from public.lf_operation_contracts
  where operation_code=p_operation_code and status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO');

  if contract_count<>1 then
    raise exception 'LF_WORK_PROTOCOL_ACTIVE_CONTRACT_NOT_EXACT:%:%',p_operation_code,contract_count;
  end if;

  select * into c
  from public.lf_operation_contracts
  where operation_code=p_operation_code and status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')
  limit 1;

  contract_rev := public.lf_work_protocol_contract_revision_sha256_v1(p_operation_code);
  policy_sha := public.lf_work_protocol_policy_set_sha256_v1(p_operation_code);
  obligation_sha := public.lf_work_protocol_obligation_set_sha256_v1(p_operation_code);

  return jsonb_build_object(
    'operation_revision_sha256', op_rev,
    'contract_code', c.contract_code,
    'contract_sha', c.contract_sha,
    'contract_revision_sha256', contract_rev,
    'policy_set_sha256', policy_sha,
    'obligation_set_sha256', obligation_sha,
    'source_refs', jsonb_build_array(
      'supabase://public/lf_operation_registry/' || p_operation_code || '@sha256:' || op_rev,
      'supabase://public/lf_operation_contracts/' || p_operation_code || '/' || c.contract_code || '@sha256:' || contract_rev,
      'supabase://public/v_lf_operation_policy_snapshot/' || p_operation_code || '@sha256:' || policy_sha,
      'supabase://public/lf_operation_steps+step_contracts+step_judge_bindings/' || p_operation_code || '@sha256:' || obligation_sha
    )
  );
end;
$fn$;

create or replace function public.lf_work_protocol_freeze_v1(
  p_operation_code text,
  p_execution_id text,
  p_request_sha256 text,
  p_work_protocol jsonb
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = pg_catalog, public, extensions
as $fn$
declare
  current_authority jsonb;
  supplied_authority jsonb;
  frozen jsonb;
  digest_computed text;
  obligation_count integer;
  duplicate_count integer;
  missing_required_count integer;
  unknown_step_count integer;
  missing_evidence_contract_count integer;
  invalid_execution_contract_count integer;
  invalid_gate_contract_count integer;
  control_result jsonb;
  controller_result jsonb;
  closure_controller_result jsonb;
begin
  if p_work_protocol is null or jsonb_typeof(p_work_protocol)<>'object' then
    raise exception 'LF_WORK_PROTOCOL_MANIFEST_INVALID';
  end if;
  if p_work_protocol->>'manifest_version'<>'LF_WORK_PROTOCOL_MANIFEST_V1' then
    raise exception 'LF_WORK_PROTOCOL_MANIFEST_VERSION_INVALID';
  end if;
  if (p_work_protocol->>'operation_code') is distinct from p_operation_code then
    raise exception 'LF_WORK_PROTOCOL_OPERATION_BINDING_MISMATCH';
  end if;
  if coalesce(p_request_sha256,'') !~ '^[0-9a-f]{64}$'
     or (p_work_protocol->>'request_sha256') is distinct from p_request_sha256 then
    raise exception 'LF_WORK_PROTOCOL_REQUEST_BINDING_MISMATCH';
  end if;
  if jsonb_typeof(p_work_protocol->'work_owner') is distinct from 'object'
     or btrim(coalesce(p_work_protocol->'work_owner'->>'owner_id',''))=''
     or p_work_protocol->'work_owner'->>'owner_type' not in ('HUMAN','AGENT','TEAM')
     or btrim(coalesce(p_work_protocol->'work_owner'->>'declaration_ref',''))=''
     or coalesce(p_work_protocol->'work_owner'->>'declaration_sha256','') !~ '^[0-9a-f]{64}$'
     or (p_work_protocol->'work_owner'->>'declaration_sha256') is distinct from p_request_sha256
     or p_work_protocol->'work_owner'->>'change_mode' is distinct from 'SUPERSEDE_NEW_EXECUTION' then
    raise exception 'LF_WORK_PROTOCOL_OWNER_BINDING_INVALID';
  end if;
  if btrim(coalesce(p_work_protocol->'authorized_scope'->>'authorization_ref',''))=''
     or coalesce(p_work_protocol->'authorized_scope'->>'authorization_sha256','') !~ '^[0-9a-f]{64}$'
     or (p_work_protocol->'authorized_scope'->>'authorization_sha256') is distinct from p_request_sha256 then
    raise exception 'LF_WORK_PROTOCOL_SCOPE_PROVENANCE_INVALID';
  end if;
  if btrim(coalesce(p_execution_id,''))='' or btrim(coalesce(p_work_protocol->>'manifest_id',''))='' then
    raise exception 'LF_WORK_PROTOCOL_IDENTITY_INVALID';
  end if;
  if (p_work_protocol->>'execution_id') is distinct from p_execution_id then
    raise exception 'LF_WORK_PROTOCOL_EXECUTION_BINDING_MISMATCH';
  end if;
  if jsonb_typeof(p_work_protocol->'target') is distinct from 'object'
     or btrim(coalesce(p_work_protocol->'target'->>'type',''))=''
     or btrim(coalesce(p_work_protocol->'target'->>'code',''))='' then
    raise exception 'LF_WORK_PROTOCOL_TARGET_INVALID';
  end if;
  if jsonb_typeof(p_work_protocol->'authorized_scope') is distinct from 'object'
     or jsonb_typeof(p_work_protocol->'authorized_scope'->'read') is distinct from 'array'
     or jsonb_typeof(p_work_protocol->'authorized_scope'->'write') is distinct from 'array'
     or jsonb_typeof(p_work_protocol->'authorized_scope'->'effects') is distinct from 'array' then
    raise exception 'LF_WORK_PROTOCOL_SCOPE_INVALID';
  end if;
  if p_work_protocol->'closure_policy'->>'progress_formula' is distinct from 'VERIFIED_REQUIRED_OBLIGATIONS_DIV_REQUIRED_OBLIGATIONS'
     or coalesce((p_work_protocol->'closure_policy'->>'zero_blockers_required')::boolean,false) is not true
     or coalesce((p_work_protocol->'closure_policy'->>'authority_currentness_required')::boolean,false) is not true
     or coalesce((p_work_protocol->'closure_policy'->>'manifest_digest_immutable')::boolean,false) is not true then
    raise exception 'LF_WORK_PROTOCOL_CLOSURE_POLICY_INVALID';
  end if;
  if coalesce((p_work_protocol->'closure_policy'->>'self_reported_progress_allowed')::boolean,true) is not false then
    raise exception 'LF_WORK_PROTOCOL_SELF_REPORTED_PROGRESS_FORBIDDEN';
  end if;
  if coalesce((p_work_protocol->'closure_policy'->>'independent_closure_required')::boolean,false) is not true then
    raise exception 'LF_WORK_PROTOCOL_INDEPENDENT_CLOSURE_REQUIRED';
  end if;
  if jsonb_typeof(p_work_protocol->'execution_policy') is distinct from 'object'
     or coalesce((p_work_protocol->'execution_policy'->>'timeout_recovery_required')::boolean,false) is not true
     or coalesce((p_work_protocol->'execution_policy'->>'preserve_verified_progress')::boolean,false) is not true
     or coalesce(p_work_protocol->'execution_policy'->>'exhausted_timeout_result','') <> 'BLOCKED_OPERATIONAL_TIMEOUT'
     or coalesce(p_work_protocol->'execution_policy'->>'max_recovery_attempts','') !~ '^[1-9][0-9]*$'
     or (p_work_protocol->'execution_policy'->>'max_recovery_attempts')::integer < 1
     or (p_work_protocol->'execution_policy'->>'max_recovery_attempts')::integer > 10 then
    raise exception 'LF_WORK_PROTOCOL_EXECUTION_POLICY_INVALID';
  end if;
  if jsonb_typeof(p_work_protocol->'evidence_policy') is distinct from 'object'
     or coalesce((p_work_protocol->'evidence_policy'->>'exact_envelope_required')::boolean,false) is not true
     or coalesce((p_work_protocol->'evidence_policy'->>'reproduction_spec_required')::boolean,false) is not true
     or coalesce((p_work_protocol->'evidence_policy'->>'append_only_ledger_required_for_independent')::boolean,false) is not true
     or coalesce((p_work_protocol->'evidence_policy'->>'independent_actor_distinct_required')::boolean,false) is not true
     or p_work_protocol->'evidence_policy'->>'ledger_receipt_kind' is distinct from 'WORK_PROTOCOL_GATE_EVIDENCE'
     or coalesce(p_work_protocol->'evidence_policy'->>'max_age_seconds','') !~ '^[0-9]+$'
     or (p_work_protocol->'evidence_policy'->>'max_age_seconds')::integer not between 60 and 86400
     or coalesce(p_work_protocol->'evidence_policy'->>'future_clock_skew_seconds','') !~ '^[0-9]+$'
     or (p_work_protocol->'evidence_policy'->>'future_clock_skew_seconds')::integer not between 0 and 300 then
    raise exception 'LF_WORK_PROTOCOL_EVIDENCE_POLICY_INVALID';
  end if;
  if jsonb_typeof(p_work_protocol->'obligations') is distinct from 'array' then
    raise exception 'LF_WORK_PROTOCOL_OBLIGATIONS_INVALID';
  end if;

  select count(*), count(*)-count(distinct x->>'step_id')
  into obligation_count, duplicate_count
  from jsonb_array_elements(p_work_protocol->'obligations') x;
  if obligation_count<1 or duplicate_count<>0 then
    raise exception 'LF_WORK_PROTOCOL_OBLIGATIONS_EMPTY_OR_DUPLICATED';
  end if;

  select count(*) into invalid_execution_contract_count
  from jsonb_array_elements(p_work_protocol->'obligations') o
  where coalesce(o->>'execution_class','') not in ('ATOMIC','CHUNKABLE','CHECKPOINTABLE')
     or coalesce(o->>'timeout_recovery_mode','') not in ('RETRY_ATOMIC','REDUCE_UNIT','RESUME_CHECKPOINT')
     or jsonb_typeof(o->'checkpoint_required') is distinct from 'boolean'
     or jsonb_typeof(o->'idempotent') is distinct from 'boolean'
     or (o->>'execution_class'='ATOMIC' and o->>'timeout_recovery_mode'<>'RETRY_ATOMIC')
     or (o->>'execution_class'='CHUNKABLE' and (
          o->>'timeout_recovery_mode'<>'REDUCE_UNIT'
          or coalesce((o->>'idempotent')::boolean,false) is not true
        ))
     or (o->>'execution_class'='CHECKPOINTABLE' and (
          o->>'timeout_recovery_mode'<>'RESUME_CHECKPOINT'
          or coalesce((o->>'checkpoint_required')::boolean,false) is not true
        ));
  if invalid_execution_contract_count<>0 then
    raise exception 'LF_WORK_PROTOCOL_EXECUTION_CONTRACT_INVALID:%',invalid_execution_contract_count;
  end if;

  select count(*) into invalid_gate_contract_count
  from jsonb_array_elements(p_work_protocol->'obligations') o
  cross join lateral public.lf_work_protocol_gate_contract_v1(
    p_operation_code,
    o->>'step_id',
    p_work_protocol #>> '{closure_policy,independent_closure_step_id}'
  ) gc
  where o->>'gate_type' is distinct from gc->>'gate_type'
     or o->>'verifier_mode' is distinct from gc->>'verifier_mode'
     or coalesce((o->>'waiver_allowed')::boolean,false) is distinct from coalesce((gc->>'waiver_allowed')::boolean,false)
     or coalesce((o->>'irreversible_effect')::boolean,false) is distinct from coalesce((gc->>'irreversible_effect')::boolean,false)
     or coalesce((o->>'human_approval_required')::boolean,false) is distinct from coalesce((gc->>'human_approval_required')::boolean,false)
     or o->'depends_on_step_ids' is distinct from gc->'depends_on_step_ids'
     or o->>'closure_unit_id' is distinct from gc->>'closure_unit_id'
     or o->>'controller_order' is distinct from gc->>'controller_order'
     or o->>'execution_effect' is distinct from gc->>'execution_effect'
     or coalesce((o->>'parallel_safe')::boolean,false) is distinct from coalesce((gc->>'parallel_safe')::boolean,false)
     or o->>'gate_contract_sha256' is distinct from gc->>'gate_contract_sha256';
  if invalid_gate_contract_count<>0 then
    raise exception 'LF_WORK_PROTOCOL_GATE_CONTRACT_MISMATCH:%',invalid_gate_contract_count;
  end if;

  control_result := public.lf_work_protocol_control_validate_v1(p_work_protocol);
  if control_result->>'result'<>'PASS_CONTROL_FROZEN' then
    raise exception 'LF_WORK_PROTOCOL_CONTROL_INVALID:%',control_result;
  end if;

  controller_result := public.lf_work_protocol_controller_validate_v1(p_work_protocol);
  if controller_result->>'result'<>'PASS_CONTROLLER_FROZEN' then
    raise exception 'LF_WORK_PROTOCOL_CONTROLLER_INVALID:%',controller_result;
  end if;

  closure_controller_result := public.lf_work_protocol_closure_controller_validate_v1(p_work_protocol);
  if closure_controller_result->>'result'<>'PASS_CLOSURE_CONTROLLER_FROZEN' then
    raise exception 'LF_WORK_PROTOCOL_CLOSURE_CONTROLLER_INVALID:%',closure_controller_result;
  end if;

  if not exists (
    select 1 from jsonb_array_elements(p_work_protocol->'obligations') o
    where o->>'step_id'=p_work_protocol->'closure_policy'->>'independent_closure_step_id'
      and coalesce((o->>'required')::boolean,false)=true
      and o->>'verifier_mode' in ('INDEPENDENT_READBACK','SEMANTIC_JUDGE','COMPOSITE')
  ) then
    raise exception 'LF_WORK_PROTOCOL_INDEPENDENT_CLOSURE_STEP_INVALID';
  end if;

  select count(*) into unknown_step_count
  from jsonb_array_elements(p_work_protocol->'obligations') o
  left join public.lf_operation_steps s
    on s.operation_code=p_operation_code and s.step_id=o->>'step_id' and s.active=true
  where s.step_id is null;
  if unknown_step_count<>0 then
    raise exception 'LF_WORK_PROTOCOL_UNKNOWN_ACTIVE_STEP:%',unknown_step_count;
  end if;

  select count(*) into missing_required_count
  from public.lf_operation_steps s
  where s.operation_code=p_operation_code and s.active=true and s.required=true
    and not exists (
      select 1 from jsonb_array_elements(p_work_protocol->'obligations') o
      where o->>'step_id'=s.step_id and coalesce((o->>'required')::boolean,false)=true
    );
  if missing_required_count<>0 then
    raise exception 'LF_WORK_PROTOCOL_REQUIRED_STEP_COVERAGE_MISMATCH:%',missing_required_count;
  end if;

  with required_key as (
    select sc.step_id, k.key
    from public.lf_operation_step_contracts sc
    cross join lateral jsonb_array_elements_text(coalesce(sc.required_evidence_keys,'[]'::jsonb)) k(key)
    where sc.operation_code=p_operation_code
      and sc.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')
    union
    select b.step_id, k.key
    from public.lf_operation_step_judge_bindings b
    cross join lateral jsonb_array_elements_text(coalesce(b.required_evidence_keys,'[]'::jsonb)) k(key)
    where b.operation_code=p_operation_code
      and b.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')
  )
  select count(*) into missing_evidence_contract_count
  from required_key rk
  join jsonb_array_elements(p_work_protocol->'obligations') o on o->>'step_id'=rk.step_id
  where not exists (
    select 1
    from jsonb_array_elements_text(coalesce(o->'evidence_keys','[]'::jsonb)) mk
    where mk=rk.key
  );
  if missing_evidence_contract_count<>0 then
    raise exception 'LF_WORK_PROTOCOL_REQUIRED_EVIDENCE_CONTRACT_MISMATCH:%',missing_evidence_contract_count;
  end if;

  current_authority := public.lf_work_protocol_authority_snapshot_v1(p_operation_code);
  supplied_authority := p_work_protocol->'authority_snapshot';
  if supplied_authority->>'operation_revision_sha256' is distinct from current_authority->>'operation_revision_sha256' then
    raise exception 'LF_WORK_PROTOCOL_STALE_OPERATION_REVISION';
  end if;
  if (supplied_authority->>'contract_code') is distinct from (current_authority->>'contract_code')
     or (supplied_authority->>'contract_revision_sha256') is distinct from (current_authority->>'contract_revision_sha256') then
    raise exception 'LF_WORK_PROTOCOL_STALE_CONTRACT';
  end if;
  if (supplied_authority->>'obligation_set_sha256') is distinct from (current_authority->>'obligation_set_sha256') then
    raise exception 'LF_WORK_PROTOCOL_STALE_OBLIGATION_SET';
  end if;
  if (supplied_authority->>'policy_set_sha256') is distinct from (current_authority->>'policy_set_sha256') then
    raise exception 'LF_WORK_PROTOCOL_STALE_POLICY_SET';
  end if;

  frozen := (p_work_protocol - 'manifest_digest' - 'frozen_at' - 'execution_id') || jsonb_build_object(
    'execution_id', p_execution_id,
    'frozen_at', to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  );
  digest_computed := encode(extensions.digest(convert_to(public.lf_work_protocol_canonical_json_v1(frozen),'UTF8'),'sha256'),'hex');
  return frozen || jsonb_build_object('manifest_digest',digest_computed);
end;
$fn$;

create or replace function public.lf_work_protocol_validate_frozen_v1(
  p_operation_code text,
  p_execution_id text,
  p_work_protocol jsonb
) returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, extensions
as $fn$
declare
  current_authority jsonb;
  digest_supplied text;
  digest_computed text;
  invalid_execution_contract_count integer;
  invalid_gate_contract_count integer;
  control_result jsonb;
  controller_result jsonb;
  closure_controller_result jsonb;
begin
  if p_work_protocol is null or jsonb_typeof(p_work_protocol)<>'object' then
    raise exception 'LF_WORK_PROTOCOL_MANIFEST_INVALID';
  end if;
  if jsonb_typeof(p_work_protocol->'work_owner') is distinct from 'object'
     or btrim(coalesce(p_work_protocol->'work_owner'->>'owner_id',''))=''
     or p_work_protocol->'work_owner'->>'owner_type' not in ('HUMAN','AGENT','TEAM')
     or btrim(coalesce(p_work_protocol->'work_owner'->>'declaration_ref',''))=''
     or coalesce(p_work_protocol->'work_owner'->>'declaration_sha256','') !~ '^[0-9a-f]{64}$'
     or (p_work_protocol->'work_owner'->>'declaration_sha256') is distinct from p_work_protocol->>'request_sha256'
     or p_work_protocol->'work_owner'->>'change_mode' is distinct from 'SUPERSEDE_NEW_EXECUTION' then
    raise exception 'LF_WORK_PROTOCOL_OWNER_BINDING_INVALID';
  end if;
  if jsonb_typeof(p_work_protocol->'execution_policy') is distinct from 'object'
     or coalesce((p_work_protocol->'execution_policy'->>'timeout_recovery_required')::boolean,false) is not true
     or coalesce((p_work_protocol->'execution_policy'->>'preserve_verified_progress')::boolean,false) is not true
     or coalesce(p_work_protocol->'execution_policy'->>'exhausted_timeout_result','') <> 'BLOCKED_OPERATIONAL_TIMEOUT'
     or coalesce(p_work_protocol->'execution_policy'->>'max_recovery_attempts','') !~ '^[1-9][0-9]*$'
     or (p_work_protocol->'execution_policy'->>'max_recovery_attempts')::integer < 1
     or (p_work_protocol->'execution_policy'->>'max_recovery_attempts')::integer > 10 then
    raise exception 'LF_WORK_PROTOCOL_EXECUTION_POLICY_INVALID';
  end if;
  if jsonb_typeof(p_work_protocol->'evidence_policy') is distinct from 'object'
     or coalesce((p_work_protocol->'evidence_policy'->>'exact_envelope_required')::boolean,false) is not true
     or coalesce((p_work_protocol->'evidence_policy'->>'reproduction_spec_required')::boolean,false) is not true
     or coalesce((p_work_protocol->'evidence_policy'->>'append_only_ledger_required_for_independent')::boolean,false) is not true
     or coalesce((p_work_protocol->'evidence_policy'->>'independent_actor_distinct_required')::boolean,false) is not true
     or p_work_protocol->'evidence_policy'->>'ledger_receipt_kind' is distinct from 'WORK_PROTOCOL_GATE_EVIDENCE'
     or coalesce(p_work_protocol->'evidence_policy'->>'max_age_seconds','') !~ '^[0-9]+$'
     or (p_work_protocol->'evidence_policy'->>'max_age_seconds')::integer not between 60 and 86400
     or coalesce(p_work_protocol->'evidence_policy'->>'future_clock_skew_seconds','') !~ '^[0-9]+$'
     or (p_work_protocol->'evidence_policy'->>'future_clock_skew_seconds')::integer not between 0 and 300 then
    raise exception 'LF_WORK_PROTOCOL_EVIDENCE_POLICY_INVALID';
  end if;
  if jsonb_typeof(p_work_protocol->'obligations') is distinct from 'array' then
    raise exception 'LF_WORK_PROTOCOL_OBLIGATIONS_INVALID';
  end if;
  select count(*) into invalid_execution_contract_count
  from jsonb_array_elements(p_work_protocol->'obligations') o
  where coalesce(o->>'execution_class','') not in ('ATOMIC','CHUNKABLE','CHECKPOINTABLE')
     or coalesce(o->>'timeout_recovery_mode','') not in ('RETRY_ATOMIC','REDUCE_UNIT','RESUME_CHECKPOINT')
     or jsonb_typeof(o->'checkpoint_required') is distinct from 'boolean'
     or jsonb_typeof(o->'idempotent') is distinct from 'boolean'
     or (o->>'execution_class'='ATOMIC' and o->>'timeout_recovery_mode'<>'RETRY_ATOMIC')
     or (o->>'execution_class'='CHUNKABLE' and (
          o->>'timeout_recovery_mode'<>'REDUCE_UNIT'
          or coalesce((o->>'idempotent')::boolean,false) is not true
        ))
     or (o->>'execution_class'='CHECKPOINTABLE' and (
          o->>'timeout_recovery_mode'<>'RESUME_CHECKPOINT'
          or coalesce((o->>'checkpoint_required')::boolean,false) is not true
        ));
  if invalid_execution_contract_count<>0 then
    raise exception 'LF_WORK_PROTOCOL_EXECUTION_CONTRACT_INVALID:%',invalid_execution_contract_count;
  end if;

  select count(*) into invalid_gate_contract_count
  from jsonb_array_elements(p_work_protocol->'obligations') o
  cross join lateral public.lf_work_protocol_gate_contract_v1(
    p_operation_code,
    o->>'step_id',
    p_work_protocol #>> '{closure_policy,independent_closure_step_id}'
  ) gc
  where o->>'gate_type' is distinct from gc->>'gate_type'
     or o->>'verifier_mode' is distinct from gc->>'verifier_mode'
     or coalesce((o->>'waiver_allowed')::boolean,false) is distinct from coalesce((gc->>'waiver_allowed')::boolean,false)
     or coalesce((o->>'irreversible_effect')::boolean,false) is distinct from coalesce((gc->>'irreversible_effect')::boolean,false)
     or coalesce((o->>'human_approval_required')::boolean,false) is distinct from coalesce((gc->>'human_approval_required')::boolean,false)
     or o->'depends_on_step_ids' is distinct from gc->'depends_on_step_ids'
     or o->>'closure_unit_id' is distinct from gc->>'closure_unit_id'
     or o->>'controller_order' is distinct from gc->>'controller_order'
     or o->>'execution_effect' is distinct from gc->>'execution_effect'
     or coalesce((o->>'parallel_safe')::boolean,false) is distinct from coalesce((gc->>'parallel_safe')::boolean,false)
     or o->>'gate_contract_sha256' is distinct from gc->>'gate_contract_sha256';
  if invalid_gate_contract_count<>0 then
    raise exception 'LF_WORK_PROTOCOL_GATE_CONTRACT_MISMATCH:%',invalid_gate_contract_count;
  end if;

  control_result := public.lf_work_protocol_control_validate_v1(p_work_protocol);
  if control_result->>'result'<>'PASS_CONTROL_FROZEN' then
    raise exception 'LF_WORK_PROTOCOL_CONTROL_INVALID:%',control_result;
  end if;

  controller_result := public.lf_work_protocol_controller_validate_v1(p_work_protocol);
  if controller_result->>'result'<>'PASS_CONTROLLER_FROZEN' then
    raise exception 'LF_WORK_PROTOCOL_CONTROLLER_INVALID:%',controller_result;
  end if;

  closure_controller_result := public.lf_work_protocol_closure_controller_validate_v1(p_work_protocol);
  if closure_controller_result->>'result'<>'PASS_CLOSURE_CONTROLLER_FROZEN' then
    raise exception 'LF_WORK_PROTOCOL_CLOSURE_CONTROLLER_INVALID:%',closure_controller_result;
  end if;

  if p_work_protocol->>'operation_code' is distinct from p_operation_code
     or p_work_protocol->>'execution_id' is distinct from p_execution_id then
    raise exception 'LF_WORK_PROTOCOL_FROZEN_IDENTITY_MISMATCH';
  end if;
  digest_supplied := p_work_protocol->>'manifest_digest';
  digest_computed := encode(
    extensions.digest(convert_to(public.lf_work_protocol_canonical_json_v1(p_work_protocol-'manifest_digest'),'UTF8'),'sha256'),'hex'
  );
  if digest_supplied is distinct from digest_computed then
    raise exception 'LF_WORK_PROTOCOL_MANIFEST_DIGEST_MISMATCH';
  end if;
  current_authority := public.lf_work_protocol_authority_snapshot_v1(p_operation_code);
  if p_work_protocol->'authority_snapshot'->>'operation_revision_sha256' is distinct from current_authority->>'operation_revision_sha256' then
    raise exception 'LF_WORK_PROTOCOL_STALE_OPERATION_REVISION';
  end if;
  if (p_work_protocol->'authority_snapshot'->>'contract_code') is distinct from (current_authority->>'contract_code')
     or (p_work_protocol->'authority_snapshot'->>'contract_revision_sha256') is distinct from (current_authority->>'contract_revision_sha256') then
    raise exception 'LF_WORK_PROTOCOL_STALE_CONTRACT';
  end if;
  if (p_work_protocol->'authority_snapshot'->>'obligation_set_sha256') is distinct from (current_authority->>'obligation_set_sha256') then
    raise exception 'LF_WORK_PROTOCOL_STALE_OBLIGATION_SET';
  end if;
  if (p_work_protocol->'authority_snapshot'->>'policy_set_sha256') is distinct from (current_authority->>'policy_set_sha256') then
    raise exception 'LF_WORK_PROTOCOL_STALE_POLICY_SET';
  end if;
  return jsonb_build_object('result','PASS_FROZEN_CURRENT','authority_snapshot',current_authority,'manifest_digest',digest_supplied);
end;
$fn$;

create or replace function public.lf_work_protocol_controller_step_guard_v1()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $fn$
declare
  e public.lf_operation_execution%rowtype;
  wp jsonb;
  ctrl jsonb;
  plan jsonb;
  first_step text;
begin
  select * into e from public.lf_operation_execution where execution_id=new.execution_id;
  if not found then return new; end if;

  wp := e.manifest->'work_protocol_manifest';
  if jsonb_typeof(wp) is distinct from 'object' then return new; end if;

  select x->>'step_id' into first_step
  from jsonb_array_elements(wp->'obligations') x
  order by (x->>'controller_order')::integer,x->>'step_id'
  limit 1;

  ctrl := e.checkpoint_payload->'work_protocol_controller';

  if tg_op='INSERT'
     and new.step_id=first_step
     and jsonb_typeof(ctrl) is distinct from 'object'
     and btrim(coalesce(new.evidence_payload->>'recorded_by_rpc',''))<>''
     and not exists (
       select 1 from public.lf_operation_execution_steps s
       where s.execution_id=new.execution_id
     ) then
    return new;
  end if;

  if tg_op='UPDATE'
     and new.step_id=first_step
     and jsonb_typeof(ctrl) is distinct from 'object'
     and btrim(coalesce(old.evidence_payload->>'recorded_by_rpc',''))<>''
     and jsonb_typeof(old.evidence_payload->'work_protocol_gate') is distinct from 'object'
     and jsonb_typeof(new.evidence_payload->'work_protocol_gate')='object'
     and old.status=new.status then
    return new;
  end if;

  if jsonb_typeof(ctrl) is distinct from 'object' then
    raise exception 'LF_WORK_PROTOCOL_CONTROLLER_ACTIVATION_REQUIRED:%',new.step_id;
  end if;
  if (ctrl->>'manifest_digest') is distinct from (wp->>'manifest_digest')
     or jsonb_typeof(ctrl->'lease_fence') is distinct from 'number'
     or coalesce((ctrl->>'lease_fence')::bigint,-1) <> e.lease_fence
     or (ctrl->>'lease_owner') is distinct from e.lease_owner
     or e.lease_expires_at is null
     or e.lease_expires_at<=clock_timestamp() then
    raise exception 'LF_WORK_PROTOCOL_CONTROLLER_CHECKPOINT_STALE:%',new.step_id;
  end if;
  if not exists (
    select 1
    from jsonb_array_elements_text(coalesce(ctrl->'active_step_ids','[]'::jsonb)) x
    where x=new.step_id
  ) then
    raise exception 'LF_WORK_PROTOCOL_CONTROLLER_STEP_NOT_ACTIVE:%',new.step_id;
  end if;

  plan := public.lf_work_protocol_controller_plan_v1(new.execution_id);
  if plan->>'result'<>'PASS_CONTROLLER_PLAN'
     or plan->>'plan_sha256' is distinct from ctrl->>'plan_sha256'
     or plan->>'active_closure_unit_id' is distinct from ctrl->>'active_closure_unit_id' then
    raise exception 'LF_WORK_PROTOCOL_CONTROLLER_PLAN_STALE:%',new.step_id;
  end if;
  if not exists (
    select 1 from jsonb_array_elements_text(plan->'allowed_step_ids') x
    where x=new.step_id
  ) then
    raise exception 'LF_WORK_PROTOCOL_CONTROLLER_PLAN_FORBIDS_STEP:%',new.step_id;
  end if;

  return new;
end;
$fn$;

create trigger trg_03_lf_work_protocol_controller_step_insert_guard_v1
before insert on public.lf_operation_execution_steps
for each row execute function public.lf_work_protocol_controller_step_guard_v1();

create trigger trg_03_lf_work_protocol_controller_step_update_guard_v1
before update of status,evidence_ref,evidence_payload,notes
on public.lf_operation_execution_steps
for each row execute function public.lf_work_protocol_controller_step_guard_v1();

create or replace function public.lf_work_protocol_manifest_guard_v1()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $fn$
begin
  if tg_op='INSERT' then
    if new.manifest ? 'work_protocol_manifest' then
      perform public.lf_work_protocol_validate_frozen_v1(
        new.operation_code,
        new.execution_id,
        new.manifest->'work_protocol_manifest'
      );
      if new.manifest->'work_protocol_manifest'->>'request_sha256' is distinct from new.request_sha256 then
        raise exception 'LF_WORK_PROTOCOL_PERSISTED_REQUEST_BINDING_MISMATCH';
      end if;
      if new.manifest->'work_protocol_manifest'->'target'->>'type' is distinct from new.target_type
         or new.manifest->'work_protocol_manifest'->'target'->>'code' is distinct from new.target_code then
        raise exception 'LF_WORK_PROTOCOL_PERSISTED_TARGET_BINDING_MISMATCH';
      end if;
    end if;
    return new;
  end if;

  if old.manifest ? 'work_protocol_manifest' then
    if new.operation_code is distinct from old.operation_code
       or new.target_type is distinct from old.target_type
       or new.target_code is distinct from old.target_code
       or new.target_repo is distinct from old.target_repo
       or new.target_path is distinct from old.target_path
       or new.request_sha256 is distinct from old.request_sha256 then
      raise exception 'LF_WORK_PROTOCOL_PERSISTED_IDENTITY_IMMUTABLE';
    end if;
    if new.manifest->'work_protocol_manifest'
       is distinct from old.manifest->'work_protocol_manifest' then
      raise exception 'LF_WORK_PROTOCOL_MANIFEST_IMMUTABLE';
    end if;
  elsif new.manifest ? 'work_protocol_manifest' then
    raise exception 'LF_WORK_PROTOCOL_LATE_ATTACH_FORBIDDEN';
  end if;
  return new;
end;
$fn$;

create trigger trg_02_lf_work_protocol_manifest_insert_guard_v1
before insert on public.lf_operation_execution
for each row execute function public.lf_work_protocol_manifest_guard_v1();

create trigger trg_02_lf_work_protocol_manifest_update_guard_v1
before update of operation_code,target_type,target_code,target_repo,target_path,request_sha256,manifest
on public.lf_operation_execution
for each row execute function public.lf_work_protocol_manifest_guard_v1();

-- Opt-in manifest binder. It does NOT reserve executions and cannot bypass operation-specific begin functions.
create or replace function public.lf_work_protocol_bind_manifest_v1(
  p_operation_code text,
  p_execution_id text,
  p_request_sha256 text,
  p_work_protocol jsonb,
  p_manifest_extra jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = pg_catalog, public
as $fn$
declare
  frozen jsonb;
begin
  if p_manifest_extra is null or jsonb_typeof(p_manifest_extra)<>'object' then
    raise exception 'LF_WORK_PROTOCOL_MANIFEST_EXTRA_INVALID';
  end if;
  if p_manifest_extra ? 'work_protocol_manifest' then
    raise exception 'LF_WORK_PROTOCOL_MANIFEST_EXTRA_OVERRIDE_FORBIDDEN';
  end if;
  frozen := public.lf_work_protocol_freeze_v1(p_operation_code,p_execution_id,p_request_sha256,p_work_protocol);
  perform public.lf_work_protocol_validate_frozen_v1(p_operation_code,p_execution_id,frozen);
  return p_manifest_extra || jsonb_build_object('work_protocol_manifest',frozen);
end;
$fn$;

-- Safe Strategy adapter: preserves lf_strategy_execution_begin_v1 as the execution authority.
create or replace function public.lf_strategy_execution_begin_work_protocol_v1(
  p_execution_id text,
  p_snapshot_id bigint,
  p_request_sha256 text,
  p_idempotency_key text,
  p_actor_execution_id text,
  p_work_protocol jsonb,
  p_manifest_extra jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, public
as $fn$
declare
  bound_manifest jsonb;
  snapshot_code text;
  begin_result jsonb;
  init_status text;
  init_evidence jsonb;
  init_evidence_ref text;
  init_observed_at timestamptz;
  init_actor_execution_id text;
  init_authority_ref text;
  init_verifier_mode text;
  init_gate_contract jsonb;
  init_gate_eval jsonb;
  init_evidence_eval jsonb;
  closure_step_id text;
  reproduction_spec text;
  reproduction_spec_sha text;
  result_sha text;
begin
  select s.snapshot_code into snapshot_code
  from public.lf_strategy_snapshots s
  where s.id=p_snapshot_id;

  if snapshot_code is null then
    raise exception 'LF_WORK_PROTOCOL_STRATEGY_TARGET_NOT_FOUND:%',p_snapshot_id;
  end if;

  if (p_work_protocol->'target'->>'type') is distinct from 'STRATEGY'
     or (p_work_protocol->'target'->>'code') is distinct from snapshot_code then
    raise exception 'LF_WORK_PROTOCOL_STRATEGY_TARGET_BINDING_MISMATCH';
  end if;

  bound_manifest := public.lf_work_protocol_bind_manifest_v1(
    'EJECUCION_ESTRATEGIA_LF', p_execution_id, p_request_sha256, p_work_protocol, p_manifest_extra
  );

  begin_result := public.lf_strategy_execution_begin_v1(
    p_execution_id,p_snapshot_id,p_request_sha256,p_idempotency_key,
    p_actor_execution_id,bound_manifest
  );

  closure_step_id := bound_manifest #>> '{work_protocol_manifest,closure_policy,independent_closure_step_id}';
  init_gate_contract := public.lf_work_protocol_gate_contract_v1(
    'EJECUCION_ESTRATEGIA_LF','init_execution',closure_step_id
  );

  select es.status,es.evidence_payload,es.evidence_ref,es.observed_at,es.created_by_execution_id
  into init_status,init_evidence,init_evidence_ref,init_observed_at,init_actor_execution_id
  from public.lf_operation_execution_steps es
  where es.execution_id=p_execution_id and es.step_id='init_execution';

  select o->>'authority_ref',o->>'verifier_mode'
  into init_authority_ref,init_verifier_mode
  from jsonb_array_elements(bound_manifest #> '{work_protocol_manifest,obligations}') o
  where o->>'step_id'='init_execution'
  limit 1;

  if init_status is null or init_evidence is null then
    raise exception 'LF_WORK_PROTOCOL_STRATEGY_INIT_GATE_SOURCE_MISSING';
  end if;

  reproduction_spec := 'lf_strategy_execution_begin_v1:init_execution';
  reproduction_spec_sha := encode(
    extensions.digest(convert_to(reproduction_spec,'UTF8'),'sha256'),'hex'
  );
  result_sha := encode(
    extensions.digest(
      convert_to(public.lf_work_protocol_canonical_json_v1(init_evidence),'UTF8'),
      'sha256'
    ),
    'hex'
  );

  update public.lf_operation_execution_steps
  set evidence_payload = init_evidence || jsonb_build_object(
    'work_protocol_evidence',
    jsonb_build_object(
      'schema_version','LF_WORK_PROTOCOL_EVIDENCE_V1',
      'execution_id',p_execution_id,
      'step_id','init_execution',
      'gate_contract_sha256',init_gate_contract->>'gate_contract_sha256',
      'actor_execution_id',init_actor_execution_id,
      'observed_at',init_observed_at,
      'reproduction',jsonb_build_object(
        'kind','READBACK',
        'locator',coalesce(init_evidence_ref,'supabase://public/lf_operation_execution_steps/'||p_execution_id||'/init_execution'),
        'reproduction_spec',reproduction_spec,
        'reproduction_spec_sha256',reproduction_spec_sha,
        'input_sha256',p_request_sha256,
        'result_ref',coalesce(init_evidence_ref,'supabase://public/lf_operation_execution_steps/'||p_execution_id||'/init_execution'),
        'result_sha256',result_sha,
        'result_count',1,
        'source_revision_sha256',bound_manifest #>> '{work_protocol_manifest,authority_snapshot,operation_revision_sha256}'
      )
    ),
    'work_protocol_gate',
    jsonb_build_object(
      'gate_contract_sha256',init_gate_contract->>'gate_contract_sha256',
      'precondition_result','PASS',
      'deterministic_result','PASS',
      'deterministic_seq',1,
      'judge_result',init_status,
      'judge_seq',2
    )
  )
  where execution_id=p_execution_id and step_id='init_execution';

  select public.lf_work_protocol_gate_evaluate_v1(
    'EJECUCION_ESTRATEGIA_LF',
    'init_execution',
    closure_step_id,
    (es.evidence_payload->'work_protocol_gate')
      || jsonb_build_object('evidence',es.evidence_payload)
  )
  into init_gate_eval
  from public.lf_operation_execution_steps es
  where es.execution_id=p_execution_id and es.step_id='init_execution';

  if init_gate_eval->>'result'<>'PASS' then
    raise exception 'LF_WORK_PROTOCOL_STRATEGY_INIT_GATE_READBACK_FAILED:%',init_gate_eval;
  end if;

  select public.lf_work_protocol_evidence_validate_v1(
    p_execution_id,
    'init_execution',
    init_gate_contract->>'gate_contract_sha256',
    init_verifier_mode,
    init_gate_contract->>'gate_type',
    init_authority_ref,
    es.evidence_payload,
    exec.started_at,
    bound_manifest #> '{work_protocol_manifest,evidence_policy}'
  )
  into init_evidence_eval
  from public.lf_operation_execution_steps es
  join public.lf_operation_execution exec on exec.execution_id=es.execution_id
  where es.execution_id=p_execution_id and es.step_id='init_execution';

  if init_evidence_eval->>'result'<>'PASS' then
    raise exception 'LF_WORK_PROTOCOL_STRATEGY_INIT_EVIDENCE_READBACK_FAILED:%',init_evidence_eval;
  end if;

  return begin_result || jsonb_build_object(
    'work_protocol_init_gate_result',init_gate_eval,
    'work_protocol_init_evidence_result',init_evidence_eval
  );
end;
$fn$;

create or replace view public.v_lf_work_protocol_execution_status_v1
with (security_invoker=true)
as
with protocol_exec as (
  select e.*,
         e.manifest->'work_protocol_manifest' as wp,
         public.lf_work_protocol_authority_snapshot_v1(e.operation_code) as current_authority,
         public.lf_work_protocol_runtime_control_validate_v1(
           e.manifest->'work_protocol_manifest',
           coalesce(e.checkpoint_payload,'{}'::jsonb)
         ) as runtime_control,
         public.lf_work_protocol_closure_status_v1(e.execution_id) as closure_status
  from public.lf_operation_execution e
  where jsonb_typeof(e.manifest->'work_protocol_manifest')='object'
), obligation as (
  select e.execution_id,
         o as obligation_json,
         o->>'requirement_id' as requirement_id,
         o->>'step_id' as step_id,
         coalesce((o->>'required')::boolean,false) as required,
         coalesce((o->>'blocking')::boolean,false) as blocking,
         o->>'verifier_mode' as verifier_mode
  from protocol_exec e
  cross join lateral jsonb_array_elements(e.wp->'obligations') o
), evaluated as (
  select e.execution_id,
         o.requirement_id,
         o.step_id,
         o.required,
         o.blocking,
         c.checklist_result,
         es.status as execution_step_status,
         ge.gate_eval->>'result' as gate_result,
         ge.gate_eval->>'code' as gate_code,
         ee.evidence_eval->>'result' as evidence_result,
         ee.evidence_eval->>'code' as evidence_code,
         ce.control_eval->>'result' as step_control_result,
         ce.control_eval->>'code' as step_control_code,
         case
           when es.status is null then false
           when ce.control_eval->>'result'<>'PASS' then false
           when ee.evidence_eval->>'result'<>'PASS' then false
           when ge.gate_eval->>'result'<>'PASS' then false
           when c.checklist_result<>'OK' then false
           when exists (
             select 1
             from jsonb_array_elements_text(coalesce(o.obligation_json->'evidence_keys','[]'::jsonb)) k
             where es.evidence_payload is null or not (es.evidence_payload ? k)
           ) then false
           when o.verifier_mode in ('INDEPENDENT_READBACK','SEMANTIC_JUDGE','COMPOSITE')
             and not (
               es.created_by_execution_id is distinct from e.execution_id
               and es.evidence_payload->>'verification_role' in ('INDEPENDENT_READER','INDEPENDENT_JUDGE','INDEPENDENT_COMPOSITE')
               and es.evidence_payload->>'verification_actor_execution_id'=es.created_by_execution_id
               and es.evidence_payload->>'verification_target_execution_id'=e.execution_id
               and exists (
                 select 1
                 from public.lf_operation_execution verifier
                 where verifier.execution_id=es.created_by_execution_id
                   and verifier.execution_id<>e.execution_id
                   and verifier.completed_at is not null
                   and verifier.status in ('COMPLETED','CLOSED_PASS','CLOSED_WITH_VERIFIED_EVIDENCE','PASS_CLEAN','CONTROLLED_READ_ONLY_PASS')
               )
             ) then false
           else true
         end as verified
  from protocol_exec e
  join obligation o on o.execution_id=e.execution_id
  left join public.v_lf_operation_execution_checklist c
    on c.execution_id=o.execution_id and c.step_id=o.step_id
  left join public.lf_operation_execution_steps es
    on es.execution_id=o.execution_id and es.step_id=o.step_id
  left join lateral (
    select public.lf_work_protocol_gate_evaluate_v1(
      e.operation_code,
      o.step_id,
      e.wp #>> '{closure_policy,independent_closure_step_id}',
      case
        when jsonb_typeof(es.evidence_payload->'work_protocol_gate')='object'
        then (es.evidence_payload->'work_protocol_gate')
             || jsonb_build_object('evidence',coalesce(es.evidence_payload,'{}'::jsonb))
        else jsonb_build_object('evidence',coalesce(es.evidence_payload,'{}'::jsonb))
      end
    ) as gate_eval
  ) ge on true
  left join lateral (
    select public.lf_work_protocol_evidence_validate_v1(
      e.execution_id,
      o.step_id,
      o.obligation_json->>'gate_contract_sha256',
      o.verifier_mode,
      o.obligation_json->>'gate_type',
      o.obligation_json->>'authority_ref',
      coalesce(es.evidence_payload,'{}'::jsonb),
      e.started_at,
      e.wp->'evidence_policy'
    ) as evidence_eval
  ) ee on true
  left join lateral (
    select public.lf_work_protocol_step_control_evaluate_v1(
      e.wp,
      o.obligation_json,
      coalesce(es.evidence_payload,'{}'::jsonb),
      coalesce(e.checkpoint_payload,'{}'::jsonb)
    ) as control_eval
  ) ce on true
), rollup as (
  select execution_id,
         count(*) filter (where required) as required_total,
         count(*) filter (where required and verified) as required_verified,
         count(*) filter (
           where required
             and execution_step_status is not null
             and coalesce(checklist_result,'FAIL_MISSING') like 'FAIL%'
         ) as fail_count,
         count(*) filter (
           where required
             and blocking
             and execution_step_status is not null
             and coalesce(checklist_result,'FAIL_MISSING') like 'FAIL%'
         ) as blocking_fail_count,
         count(*) filter (where required and execution_step_status is not null and gate_result='FAIL') as gate_fail_count,
         count(*) filter (where required and execution_step_status is not null and gate_result='BLOCKED') as gate_blocked_count,
         count(*) filter (where required and execution_step_status is not null and evidence_result='BLOCKED') as evidence_blocked_count,
         count(*) filter (where required and execution_step_status is not null and evidence_result='STALE') as evidence_stale_count,
         count(*) filter (where required and execution_step_status is not null and step_control_result='BLOCKED') as control_blocked_count
  from evaluated
  group by execution_id
), recovery as (
  select
    e.execution_id,
    e.checkpoint_payload->'work_protocol_recovery' as recovery_json,
    o.obligation_json,
    case
      when coalesce(e.checkpoint_payload #>> '{work_protocol_recovery,attempt}','') ~ '^[1-9][0-9]*$'
      then (e.checkpoint_payload #>> '{work_protocol_recovery,attempt}')::integer
      else null
    end as attempt,
    (e.wp #>> '{execution_policy,max_recovery_attempts}')::integer as max_attempts,
    exists (
      select 1
      from evaluated ev
      where ev.execution_id=e.execution_id
        and ev.step_id=e.checkpoint_payload #>> '{work_protocol_recovery,step_id}'
        and ev.verified
    ) as step_already_verified
  from protocol_exec e
  left join obligation o
    on o.execution_id=e.execution_id
   and o.step_id=e.checkpoint_payload #>> '{work_protocol_recovery,step_id}'
), recovery_eval as (
  select
    execution_id,
    (recovery_json is not null) as recovery_present,
    coalesce(attempt > max_attempts,false) as recovery_exhausted,
    case
      when recovery_json is null then true
      when jsonb_typeof(recovery_json)<>'object' then false
      when recovery_json->>'condition' not in ('TIMEOUT_RECOVERING','RETRYING_SMALLER','RESUMING') then false
      when obligation_json is null then false
      when attempt is null or attempt<1 or attempt>max_attempts then false
      when recovery_json->>'strategy' is distinct from obligation_json->>'timeout_recovery_mode' then false
      when step_already_verified then false
      when coalesce((obligation_json->>'checkpoint_required')::boolean,false)
           and btrim(coalesce(recovery_json->>'checkpoint_ref',''))='' then false
      when obligation_json->>'execution_class'='CHUNKABLE' and not (
           coalesce(recovery_json->>'previous_work_unit','') ~ '^[0-9]+([.][0-9]+)?$'
           and coalesce(recovery_json->>'next_work_unit','') ~ '^[0-9]+([.][0-9]+)?$'
           and (recovery_json->>'previous_work_unit')::numeric > 0
           and (recovery_json->>'next_work_unit')::numeric > 0
           and (recovery_json->>'next_work_unit')::numeric < (recovery_json->>'previous_work_unit')::numeric
      ) then false
      else true
    end as recovery_protocol_valid,
    recovery_json
  from recovery
)
select
  e.execution_id,
  e.operation_code,
  e.target_type,
  e.target_code,
  e.status as execution_status,
  e.wp->>'manifest_id' as manifest_id,
  e.wp->>'manifest_digest' as manifest_digest,
  (e.wp->>'request_sha256'=e.request_sha256) as request_binding_match,
  (e.wp->'target'->>'type'=e.target_type and e.wp->'target'->>'code'=e.target_code) as target_binding_match,
  e.wp->'authority_snapshot'->>'operation_revision_sha256' as frozen_operation_revision_sha256,
  e.current_authority->>'operation_revision_sha256' as current_operation_revision_sha256,
  (
    e.wp->'authority_snapshot'->>'operation_revision_sha256'=e.current_authority->>'operation_revision_sha256'
    and e.wp->'authority_snapshot'->>'contract_code'=e.current_authority->>'contract_code'
    and e.wp->'authority_snapshot'->>'contract_revision_sha256'=e.current_authority->>'contract_revision_sha256'
    and e.wp->'authority_snapshot'->>'obligation_set_sha256'=e.current_authority->>'obligation_set_sha256'
    and e.wp->'authority_snapshot'->>'policy_set_sha256'=e.current_authority->>'policy_set_sha256'
  ) as authority_current,
  (
    e.wp->>'manifest_digest'=encode(
      extensions.digest(
        convert_to(public.lf_work_protocol_canonical_json_v1(e.wp-'manifest_digest'),'UTF8'),
        'sha256'
      ),
      'hex'
    )
  ) as manifest_digest_match,
  r.required_total,
  r.required_verified,
  case when r.required_total=0 then 0 else floor(100.0*r.required_verified/r.required_total)::integer end as progress_percent,
  r.fail_count,
  r.blocking_fail_count,
  r.gate_fail_count,
  r.gate_blocked_count,
  r.evidence_blocked_count,
  r.evidence_stale_count,
  r.control_blocked_count,
  e.runtime_control->>'result' as runtime_control_result,
  e.runtime_control->>'code' as runtime_control_code,
  jsonb_array_length(coalesce(e.wp->'waivers','[]'::jsonb)) as active_waiver_count,
  e.wp #>> '{supersession,previous_execution_id}' as supersedes_execution_id,
  e.closure_status->>'result' as closure_status_result,
  coalesce((e.closure_status->>'closure_debt_count')::integer,0) as closure_debt_count,
  coalesce((e.closure_status->>'reopen_required_count')::integer,0) as closure_reopen_required_count,
  coalesce((e.closure_status->>'unclosed_unit_count')::integer,0) as closure_unclosed_unit_count,
  coalesce((e.closure_status->>'global_close_allowed')::boolean,false) as global_close_allowed,
  e.closure_status->'units' as closure_units,
  re.recovery_present,
  re.recovery_protocol_valid,
  re.recovery_exhausted,
  re.recovery_json,
  case
    when exists (
      select 1
      from public.lf_operation_execution successor
      where successor.execution_id<>e.execution_id
        and successor.manifest #>> '{work_protocol_manifest,supersession,previous_execution_id}'=e.execution_id
        and successor.manifest #>> '{work_protocol_manifest,supersession,previous_manifest_digest}'=e.wp->>'manifest_digest'
    ) then 'SUPERSEDED_SCOPE_CHANGE'
    when e.runtime_control->>'result'<>'PASS_CONTROL_RUNTIME' then 'BLOCKED_CONTROL'
    when r.control_blocked_count>0 then 'BLOCKED_CONTROL'
    when (e.wp->>'request_sha256') is distinct from e.request_sha256 then 'BLOCKED_REQUEST_BINDING_MISMATCH'
    when not (e.wp->'target'->>'type'=e.target_type and e.wp->'target'->>'code'=e.target_code) then 'BLOCKED_TARGET_BINDING_MISMATCH'
    when e.wp->>'manifest_digest' is distinct from encode(
      extensions.digest(
        convert_to(public.lf_work_protocol_canonical_json_v1(e.wp-'manifest_digest'),'UTF8'),
        'sha256'
      ),
      'hex'
    ) then 'BLOCKED_MANIFEST_DIGEST_MISMATCH'
    when e.wp->'authority_snapshot'->>'operation_revision_sha256' is distinct from e.current_authority->>'operation_revision_sha256'
      or e.wp->'authority_snapshot'->>'contract_code' is distinct from e.current_authority->>'contract_code'
      or e.wp->'authority_snapshot'->>'contract_revision_sha256' is distinct from e.current_authority->>'contract_revision_sha256'
      or e.wp->'authority_snapshot'->>'obligation_set_sha256' is distinct from e.current_authority->>'obligation_set_sha256'
      or e.wp->'authority_snapshot'->>'policy_set_sha256' is distinct from e.current_authority->>'policy_set_sha256'
      then 'STALE_AUTHORITY'
    when r.evidence_stale_count>0 then 'BLOCKED_STALE_EVIDENCE'
    when r.evidence_blocked_count>0 then 'BLOCKED_EVIDENCE'
    when r.gate_blocked_count>0 then 'BLOCKED'
    when r.gate_fail_count>0 then 'RETURN_TO_WORKER'
    when re.recovery_present and re.recovery_exhausted then 'BLOCKED_OPERATIONAL_TIMEOUT'
    when re.recovery_present and not re.recovery_protocol_valid then 'BLOCKED_RECOVERY_PROTOCOL'
    when re.recovery_present and re.recovery_protocol_valid then 'RECOVERING'
    when r.blocking_fail_count>0 then 'BLOCKED'
    when e.closure_status->>'result'<>'PASS_CLOSURE_STATUS' then 'BLOCKED_CLOSURE_CONTROLLER'
    when coalesce((e.closure_status->>'reopen_required_count')::integer,0)>0 then 'REOPEN_REQUIRED'
    when coalesce((e.closure_status->>'closure_debt_count')::integer,0)>0 then 'BLOCKED_CLOSURE_DEBT'
    when r.required_verified<r.required_total then 'IN_PROGRESS'
    when coalesce((e.closure_status->>'global_close_allowed')::boolean,false) is not true then 'CLOSURE_REQUIRED'
    else 'PASS_WITH_EVIDENCE'
  end as derived_state
from protocol_exec e
join rollup r on r.execution_id=e.execution_id
join recovery_eval re on re.execution_id=e.execution_id;

revoke all on function public.lf_work_protocol_canonical_json_v1(jsonb) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_contract_revision_sha256_v1(text) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_policy_set_sha256_v1(text) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_obligation_set_sha256_v1(text) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_gate_contract_v1(text,text,text) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_gate_evaluate_v1(text,text,text,jsonb) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_evidence_validate_v1(text,text,text,text,text,text,jsonb,timestamptz,jsonb) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_control_validate_v1(jsonb) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_runtime_control_validate_v1(jsonb,jsonb) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_step_control_evaluate_v1(jsonb,jsonb,jsonb,jsonb) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_controller_validate_v1(jsonb) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_closure_controller_validate_v1(jsonb) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_closure_unit_state_v1(text,text) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_closure_mark_v1(text,text,text,text,bigint,text,text,text,text,text,text,text) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_closure_status_v1(text) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_step_state_v1(text,text) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_controller_plan_v1(text) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_controller_activate_v1(text,text,bigint,text[],text) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_controller_step_guard_v1() from public, anon, authenticated;
revoke all on function public.lf_work_protocol_authority_snapshot_v1(text) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_freeze_v1(text,text,text,jsonb) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_validate_frozen_v1(text,text,jsonb) from public, anon, authenticated;
revoke all on function public.lf_work_protocol_manifest_guard_v1() from public, anon, authenticated;
revoke all on function public.lf_work_protocol_bind_manifest_v1(text,text,text,jsonb,jsonb) from public, anon, authenticated;
revoke all on function public.lf_strategy_execution_begin_work_protocol_v1(text,bigint,text,text,text,jsonb,jsonb) from public, anon, authenticated;
grant execute on function public.lf_work_protocol_canonical_json_v1(jsonb) to service_role;
grant execute on function public.lf_work_protocol_contract_revision_sha256_v1(text) to service_role;
grant execute on function public.lf_work_protocol_policy_set_sha256_v1(text) to service_role;
grant execute on function public.lf_work_protocol_obligation_set_sha256_v1(text) to service_role;
grant execute on function public.lf_work_protocol_gate_contract_v1(text,text,text) to service_role;
grant execute on function public.lf_work_protocol_gate_evaluate_v1(text,text,text,jsonb) to service_role;
grant execute on function public.lf_work_protocol_evidence_validate_v1(text,text,text,text,text,text,jsonb,timestamptz,jsonb) to service_role;
grant execute on function public.lf_work_protocol_control_validate_v1(jsonb) to service_role;
grant execute on function public.lf_work_protocol_runtime_control_validate_v1(jsonb,jsonb) to service_role;
grant execute on function public.lf_work_protocol_step_control_evaluate_v1(jsonb,jsonb,jsonb,jsonb) to service_role;
grant execute on function public.lf_work_protocol_controller_validate_v1(jsonb) to service_role;
grant execute on function public.lf_work_protocol_closure_controller_validate_v1(jsonb) to service_role;
grant execute on function public.lf_work_protocol_closure_unit_state_v1(text,text) to service_role;
grant execute on function public.lf_work_protocol_closure_mark_v1(text,text,text,text,bigint,text,text,text,text,text,text,text) to service_role;
grant execute on function public.lf_work_protocol_closure_status_v1(text) to service_role;
grant execute on function public.lf_work_protocol_step_state_v1(text,text) to service_role;
grant execute on function public.lf_work_protocol_controller_plan_v1(text) to service_role;
grant execute on function public.lf_work_protocol_controller_activate_v1(text,text,bigint,text[],text) to service_role;
grant execute on function public.lf_work_protocol_authority_snapshot_v1(text) to service_role;
grant execute on function public.lf_work_protocol_freeze_v1(text,text,text,jsonb) to service_role;
grant execute on function public.lf_work_protocol_validate_frozen_v1(text,text,jsonb) to service_role;
grant execute on function public.lf_work_protocol_bind_manifest_v1(text,text,text,jsonb,jsonb) to service_role;
grant execute on function public.lf_strategy_execution_begin_work_protocol_v1(text,bigint,text,text,text,jsonb,jsonb) to service_role;
