-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / N-13 / PAULO-178
-- IGQ-002: currentness at every material validator continuation/checkpoint
--          + requiredness-aware consumer aggregation.
-- Git-first. No runtime/production activation is performed by this migration.

begin;

create or replace function programacion.fn_input_governance_continuation_currentness_decide_v1(
  p_run_status text,
  p_authority_readback jsonb
) returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,programacion
as $function$
declare
  v_status text:=upper(btrim(coalesce(p_run_status,'')));
  v_authority text:=coalesce(p_authority_readback->>'authority','');
  v_allowed boolean:=false;
  v_code text:='CURRENTNESS_UNKNOWN';
begin
  if jsonb_typeof(coalesce(p_authority_readback,'null'::jsonb))<>'object'
     or v_authority<>'CURRENTNESS_AUTHORITY' then
    return jsonb_build_object(
      'schema_version','IG_CONTINUATION_CURRENTNESS_DECISION_V1',
      'continuation_current',false,
      'code','CURRENTNESS_AUTHORITY_UNRESOLVED',
      'run_status',nullif(v_status,''),
      'authority',nullif(v_authority,'')
    );
  end if;

  if v_status='VALIDATING' then
    v_allowed :=
      coalesce((p_authority_readback#>>'{dimensions,readiness_contract,current}')::boolean,false)
      and coalesce((p_authority_readback#>>'{dimensions,execution_policy,current}')::boolean,false)
      and coalesce((p_authority_readback#>>'{dimensions,source_manifest,current}')::boolean,false);
    v_code:=case when v_allowed then 'VALIDATING_CURRENT' else 'VALIDATING_STALE_OR_UNKNOWN' end;
  elsif v_status='COMPLETED' then
    v_allowed:=coalesce((p_authority_readback->>'source_current')::boolean,false);
    v_code:=case when v_allowed then 'COMPLETED_CURRENT' else 'COMPLETED_STALE_OR_UNKNOWN' end;
  else
    v_allowed:=false;
    v_code:='RUN_STATUS_NOT_CONTINUABLE';
  end if;

  return jsonb_build_object(
    'schema_version','IG_CONTINUATION_CURRENTNESS_DECISION_V1',
    'continuation_current',v_allowed,
    'code',v_code,
    'run_status',nullif(v_status,''),
    'authority','CURRENTNESS_AUTHORITY'
  );
end;
$function$;

comment on function programacion.fn_input_governance_continuation_currentness_decide_v1(text,jsonb)
is 'N-13 policy adapter. It consumes CURRENTNESS_AUTHORITY readback; it is not a second currentness authority.';

create or replace function programacion.fn_input_governance_continuation_currentness_v1(
  p_run_id bigint
) returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public,programacion
as $function$
declare
  v_status text;
  v_currentness jsonb;
  v_decision jsonb;
begin
  select r.status
    into v_status
  from programacion.input_readiness_runs r
  where r.id=p_run_id;

  if not found then
    return jsonb_build_object(
      'schema_version','IG_CONTINUATION_CURRENTNESS_V1',
      'run_id',p_run_id,
      'continuation_current',false,
      'code','RUN_NOT_FOUND',
      'authority','CURRENTNESS_AUTHORITY'
    );
  end if;

  v_currentness:=programacion.fn_input_run_source_currentness_v1(p_run_id);
  v_decision:=programacion.fn_input_governance_continuation_currentness_decide_v1(v_status,v_currentness);

  return v_decision || jsonb_build_object(
    'schema_version','IG_CONTINUATION_CURRENTNESS_V1',
    'run_id',p_run_id,
    'authority_readback',v_currentness
  );
end;
$function$;

comment on function programacion.fn_input_governance_continuation_currentness_v1(bigint)
is 'N-13 admission readback for validator continuation. Status is only a control-flow precondition; CURRENTNESS_AUTHORITY dimensions decide vigencia.';

create or replace function programacion.fn_guard_input_governance_continuation_currentness_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,programacion
as $function$
declare
  v_admission jsonb;
begin
  v_admission:=programacion.fn_input_governance_continuation_currentness_v1(new.run_id);
  if not coalesce((v_admission->>'continuation_current')::boolean,false) then
    raise exception 'INPUT_GOVERNANCE_CONTINUATION_CURRENTNESS_BLOCKED:table=%:run=%:code=%',
      tg_table_name,new.run_id,coalesce(v_admission->>'code','CURRENTNESS_UNKNOWN');
  end if;
  return new;
end;
$function$;

-- Every validator-owned assessment write is admitted against current canonical authority.
drop trigger if exists trg_input_family_assessment_00a_continuation_currentness_update
  on programacion.input_family_assessments;
create trigger trg_input_family_assessment_00a_continuation_currentness_update
before update of validator_outcome,validator_findings,validator_evidence,validator_identity,validator_sha256,validator_assessed_at
on programacion.input_family_assessments
for each row
when (
  old.validator_outcome is distinct from new.validator_outcome
  or old.validator_findings is distinct from new.validator_findings
  or old.validator_evidence is distinct from new.validator_evidence
  or old.validator_identity is distinct from new.validator_identity
  or old.validator_sha256 is distinct from new.validator_sha256
  or old.validator_assessed_at is distinct from new.validator_assessed_at
)
execute function programacion.fn_guard_input_governance_continuation_currentness_v1();

-- Proposal validation is another continuation phase and must not write against stale authority.
drop trigger if exists trg_input_gap_proposal_00_continuation_currentness_update
  on programacion.input_gap_proposals;
create trigger trg_input_gap_proposal_00_continuation_currentness_update
before update of validator_identity,validator_outcome,validator_evidence,validator_sha256,validated_at
on programacion.input_gap_proposals
for each row
when (
  old.validator_identity is distinct from new.validator_identity
  or old.validator_outcome is distinct from new.validator_outcome
  or old.validator_evidence is distinct from new.validator_evidence
  or old.validator_sha256 is distinct from new.validator_sha256
  or old.validated_at is distinct from new.validated_at
)
execute function programacion.fn_guard_input_governance_continuation_currentness_v1();

-- A persisted chunk/checkpoint is evidence. It cannot be emitted from a stale run.
drop trigger if exists trg_input_validator_chunk_timing_00_currentness_insert
  on programacion.input_validator_chunk_timings;
create trigger trg_input_validator_chunk_timing_00_currentness_insert
before insert on programacion.input_validator_chunk_timings
for each row
execute function programacion.fn_guard_input_governance_continuation_currentness_v1();

create or replace function public.fn_input_governance_validator_resume_context_v1(p_run_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public,programacion
as $function$
declare
  v_status text;
  v_identity text;
  v_analysis text;
  v_admission jsonb;
begin
  select status,validator_identity,scope->>'analysis_revision'
    into v_status,v_identity,v_analysis
  from programacion.input_readiness_runs
  where id=p_run_id
    and version_id=public.fn_lf_version_compatibility_current_version_id_v1(
      'PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT'
    );

  if v_status is null then
    raise exception 'INPUT_VALIDATOR_RESUME_RUN_NOT_FOUND:%',p_run_id;
  end if;

  if v_status='VALIDATING' then
    if v_analysis<>'INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX' then
      raise exception 'INPUT_VALIDATOR_RESUME_ANALYSIS_REVISION_INVALID:%',coalesce(v_analysis,'<NULL>');
    end if;
    if v_identity is null
       or v_identity !~ '^INPUT_VALIDATOR:EDGE:input-governance-validator-v1:[A-Za-z0-9_-]{6,128}$' then
      raise exception 'INPUT_VALIDATOR_RESUME_IDENTITY_INVALID:%',p_run_id;
    end if;

    v_admission:=programacion.fn_input_governance_continuation_currentness_v1(p_run_id);
    if not coalesce((v_admission->>'continuation_current')::boolean,false) then
      raise exception 'INPUT_VALIDATOR_RESUME_CURRENTNESS_BLOCKED:%:%',
        p_run_id,coalesce(v_admission->>'code','CURRENTNESS_UNKNOWN');
    end if;

    return jsonb_build_object(
      'run_id',p_run_id,
      'status',v_status,
      'validator_identity',v_identity,
      'resume_allowed',true,
      'currentness',v_admission
    );
  end if;

  return jsonb_build_object(
    'run_id',p_run_id,
    'status',v_status,
    'validator_identity',null,
    'resume_allowed',false
  );
end;
$function$;

create or replace function programacion.fn_input_governance_validator_validate_v1(
  p_run_id bigint,
  p_validator_identity text
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,programacion
as $function$
declare
  v_analysis text;
  v_bootstrap boolean;
  v_status text;
  v_admission jsonb;
  v_result jsonb;
  v_started timestamptz:=clock_timestamp();
  v_completed timestamptz;
  v_route text;
  v_chunk_no integer;
begin
  perform pg_advisory_xact_lock(
    pg_catalog.hashtextextended('IG_VALIDATOR_CHUNK:'||p_run_id::text||':'||coalesce(p_validator_identity,''),0)
  );

  select r.scope->>'analysis_revision',
         r.supersedes_run_id is null and r.scope->>'mode'='GOVERNED_CANONICAL_BOOTSTRAP_V1',
         r.status
    into v_analysis,v_bootstrap,v_status
  from programacion.input_readiness_runs r
  where r.id=p_run_id
    and r.version_id=public.fn_lf_version_compatibility_current_version_id_v1(
      'PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT'
    );

  if v_status is null then
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_RUN_NOT_FOUND:%',p_run_id;
  end if;

  -- Every repeated chunk and terminal NOOP is re-admitted. CURATING is the first
  -- call; its transition trigger pins the source manifest before validator writes.
  if v_status in ('VALIDATING','COMPLETED') then
    v_admission:=programacion.fn_input_governance_continuation_currentness_v1(p_run_id);
    if not coalesce((v_admission->>'continuation_current')::boolean,false) then
      raise exception 'INPUT_GOVERNANCE_VALIDATOR_CONTINUATION_CURRENTNESS_BLOCKED:%:%',
        p_run_id,coalesce(v_admission->>'code','CURRENTNESS_UNKNOWN');
    end if;
  end if;

  if v_analysis='INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX' then
    return programacion.fn_input_governance_validate_v2(p_run_id,p_validator_identity);
  end if;

  if coalesce(v_bootstrap,false) then
    v_route:='BOOTSTRAP_VALIDATE_V1';
    v_result:=programacion.fn_input_governance_bootstrap_validate_v1(p_run_id,p_validator_identity);
  else
    v_route:='VALIDATOR_REBIND_V1';
    v_result:=programacion.fn_input_governance_validator_rebind_v1(p_run_id,p_validator_identity);
  end if;

  v_completed:=clock_timestamp();
  select coalesce(max(chunk_no),0)+1
    into v_chunk_no
  from programacion.input_validator_chunk_timings
  where run_id=p_run_id and validator_identity=p_validator_identity;

  insert into programacion.input_validator_chunk_timings(
    run_id,validator_identity,chunk_no,route,started_at,completed_at,duration_ms,
    result_status,validator_pass_count,family_count,pending_count
  ) values(
    p_run_id,p_validator_identity,v_chunk_no,v_route,v_started,v_completed,
    round(extract(epoch from(v_completed-v_started))*1000)::bigint,
    v_result->>'status',
    nullif(v_result->>'validator_pass_count','')::integer,
    nullif(v_result->>'family_count','')::integer,
    nullif(v_result->>'pending_count','')::integer
  );

  return v_result;
end;
$function$;

-- Pure aggregate policy. It consumes explicit consumer requiredness; it does not
-- create or replace consumer authority/persistence.
create or replace function programacion.fn_input_governance_aggregate_requiredness_v1(
  p_results jsonb
) returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,programacion
as $function$
declare
  v_required integer:=0;
  v_required_fail integer:=0;
  v_optional integer:=0;
  v_optional_fail integer:=0;
  v_na integer:=0;
  v_invalid integer:=0;
  v_failures jsonb:='[]'::jsonb;
  v_items jsonb:=coalesce(p_results,'[]'::jsonb);
begin
  if jsonb_typeof(v_items)<>'array' then
    return jsonb_build_object(
      'schema_version','IG_CONSUMER_REQUIREDNESS_AGGREGATE_V1',
      'status','BLOCKED','decision','BLOCKED','continuation_allowed',false,
      'blocking_code','AGGREGATE_INPUT_INVALID','required_count',0,
      'required_failure_count',0,'invalid_count',1
    );
  end if;

  with q as (
    select
      nullif(btrim(e.value->>'consumer'),'') as consumer,
      upper(btrim(coalesce(e.value->>'requiredness',''))) as requiredness,
      upper(btrim(coalesce(e.value->>'decision',''))) as decision,
      e.value as item
    from jsonb_array_elements(v_items) e(value)
  )
  select
    count(*) filter(where requiredness='REQUIRED'),
    count(*) filter(where requiredness='REQUIRED' and decision<>'PASS'),
    count(*) filter(where requiredness='OPTIONAL'),
    count(*) filter(where requiredness='OPTIONAL' and decision<>'PASS'),
    count(*) filter(where requiredness='NOT_APPLICABLE'),
    count(*) filter(where consumer is null
                         or requiredness not in ('REQUIRED','OPTIONAL','NOT_APPLICABLE')
                         or (requiredness in ('REQUIRED','OPTIONAL') and decision='')),
    coalesce(jsonb_agg(item order by consumer) filter(where requiredness='REQUIRED' and decision<>'PASS'),'[]'::jsonb)
  into v_required,v_required_fail,v_optional,v_optional_fail,v_na,v_invalid,v_failures
  from q;

  if v_invalid>0 then
    return jsonb_build_object(
      'schema_version','IG_CONSUMER_REQUIREDNESS_AGGREGATE_V1',
      'status','BLOCKED','decision','BLOCKED','continuation_allowed',false,
      'blocking_code','AGGREGATE_REQUIREDNESS_UNRESOLVED',
      'required_count',v_required,'required_failure_count',v_required_fail,
      'optional_count',v_optional,'optional_failure_count',v_optional_fail,
      'not_applicable_count',v_na,'invalid_count',v_invalid,
      'required_failures',v_failures,'items',v_items
    );
  end if;

  if v_required=0 then
    return jsonb_build_object(
      'schema_version','IG_CONSUMER_REQUIREDNESS_AGGREGATE_V1',
      'status','NOT_REQUIRED','decision','N/A','continuation_allowed',true,
      'blocking_code',null,'required_count',0,'required_failure_count',0,
      'optional_count',v_optional,'optional_failure_count',v_optional_fail,
      'not_applicable_count',v_na,'invalid_count',0,
      'required_failures','[]'::jsonb,'items',v_items
    );
  end if;

  if v_required_fail>0 then
    return jsonb_build_object(
      'schema_version','IG_CONSUMER_REQUIREDNESS_AGGREGATE_V1',
      'status','BLOCKED','decision','BLOCKED','continuation_allowed',false,
      'blocking_code','REQUIRED_CONSUMER_NON_PASS',
      'required_count',v_required,'required_failure_count',v_required_fail,
      'optional_count',v_optional,'optional_failure_count',v_optional_fail,
      'not_applicable_count',v_na,'invalid_count',0,
      'required_failures',v_failures,'items',v_items
    );
  end if;

  return jsonb_build_object(
    'schema_version','IG_CONSUMER_REQUIREDNESS_AGGREGATE_V1',
    'status','READY','decision','PASS','continuation_allowed',true,
    'blocking_code',null,
    'required_count',v_required,'required_failure_count',0,
    'optional_count',v_optional,'optional_failure_count',v_optional_fail,
    'not_applicable_count',v_na,'invalid_count',0,
    'required_failures','[]'::jsonb,'items',v_items
  );
end;
$function$;

comment on function programacion.fn_input_governance_aggregate_requiredness_v1(jsonb)
is 'N-13 aggregate policy: REQUIRED non-PASS blocks; OPTIONAL/N-A do not create a blanket veto. Unknown requiredness fails closed.';

-- Deterministic policy/readback tests. These do not mutate runtime authority.
do $test$
declare
  v jsonb;
begin
  -- VALIDATING must use CURRENTNESS_AUTHORITY dimensions, not terminal lifecycle.
  v:=programacion.fn_input_governance_continuation_currentness_decide_v1(
    'VALIDATING',
    jsonb_build_object(
      'authority','CURRENTNESS_AUTHORITY','source_current',false,
      'dimensions',jsonb_build_object(
        'readiness_contract',jsonb_build_object('current',true),
        'execution_policy',jsonb_build_object('current',true),
        'source_manifest',jsonb_build_object('current',true)
      )
    )
  );
  if coalesce((v->>'continuation_current')::boolean,false) is not true then
    raise exception 'N13_SELFTEST_VALIDATING_CURRENT_FAILED:%',v;
  end if;

  v:=programacion.fn_input_governance_continuation_currentness_decide_v1(
    'VALIDATING',
    jsonb_build_object(
      'authority','CURRENTNESS_AUTHORITY','source_current',false,
      'dimensions',jsonb_build_object(
        'readiness_contract',jsonb_build_object('current',true),
        'execution_policy',jsonb_build_object('current',true),
        'source_manifest',jsonb_build_object('current',false)
      )
    )
  );
  if coalesce((v->>'continuation_current')::boolean,true) is not false then
    raise exception 'N13_SELFTEST_VALIDATING_STALE_FALSE_GREEN:%',v;
  end if;

  v:=programacion.fn_input_governance_continuation_currentness_decide_v1(
    'COMPLETED',jsonb_build_object('authority','CURRENTNESS_AUTHORITY','source_current',false,'dimensions','{}'::jsonb)
  );
  if coalesce((v->>'continuation_current')::boolean,true) is not false then
    raise exception 'N13_SELFTEST_COMPLETED_STALE_FALSE_GREEN:%',v;
  end if;

  -- REQUIRED contradiction may never aggregate PASS.
  v:=programacion.fn_input_governance_aggregate_requiredness_v1(jsonb_build_array(
    jsonb_build_object('consumer','A','requiredness','REQUIRED','decision','PASS'),
    jsonb_build_object('consumer','B','requiredness','REQUIRED','decision','FAIL')
  ));
  if v->>'decision'<>'BLOCKED' or coalesce((v->>'continuation_allowed')::boolean,true) then
    raise exception 'N13_SELFTEST_REQUIRED_FALSE_GREEN:%',v;
  end if;

  -- OPTIONAL failure does not become a blanket veto when REQUIRED consumers pass.
  v:=programacion.fn_input_governance_aggregate_requiredness_v1(jsonb_build_array(
    jsonb_build_object('consumer','A','requiredness','REQUIRED','decision','PASS'),
    jsonb_build_object('consumer','B','requiredness','OPTIONAL','decision','FAIL')
  ));
  if v->>'decision'<>'PASS' or coalesce((v->>'continuation_allowed')::boolean,false) is not true then
    raise exception 'N13_SELFTEST_OPTIONAL_OVERBLOCK:%',v;
  end if;

  -- N/A is excluded from veto semantics.
  v:=programacion.fn_input_governance_aggregate_requiredness_v1(jsonb_build_array(
    jsonb_build_object('consumer','A','requiredness','REQUIRED','decision','PASS'),
    jsonb_build_object('consumer','B','requiredness','NOT_APPLICABLE','decision','FAIL')
  ));
  if v->>'decision'<>'PASS' or coalesce((v->>'continuation_allowed')::boolean,false) is not true then
    raise exception 'N13_SELFTEST_NA_OVERBLOCK:%',v;
  end if;

  -- Unknown requiredness is not silently optional.
  v:=programacion.fn_input_governance_aggregate_requiredness_v1(jsonb_build_array(
    jsonb_build_object('consumer','A','requiredness','REQUIRED','decision','PASS'),
    jsonb_build_object('consumer','B','requiredness','UNKNOWN','decision','FAIL')
  ));
  if v->>'decision'<>'BLOCKED' or v->>'blocking_code'<>'AGGREGATE_REQUIREDNESS_UNRESOLVED' then
    raise exception 'N13_SELFTEST_REQUIREDNESS_UNKNOWN_FALSE_GREEN:%',v;
  end if;
end;
$test$;

commit;
