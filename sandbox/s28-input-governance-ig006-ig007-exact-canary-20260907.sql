-- Strategy 28 / IG-006 + IG-007 exact-version forward canary runner.
-- Run only after 20260907023000 is applied and before mandatory 20260907023100 rollback.
-- Test runs are always enclosed in transactions and rolled back.
\set ON_ERROR_STOP on

-- Session-local helper only; disappears with this psql session.
create temp table s28_ig_exact_canary_session_anchor(x integer);

create or replace function pg_temp.s28_ig_exact_case(p_pantalla_id integer,p_screen_code text)
returns jsonb
language plpgsql
as $case$
declare
  v_cur jsonb;
  v_val jsonb;
  v_run bigint;
  v_parent bigint;
  v_family_count integer;
  v_pass integer;
  v_missing_fp integer;
  v_diff integer;
  v_cur_ms numeric;
  v_val_total numeric:=0;
  v_val_max numeric:=0;
  v_chunk_ms numeric;
  v_calls integer:=0;
  v_status text;
  v_curator_identity text;
  v_validator_identity text;
  t0 timestamptz;
  t1 timestamptz;
begin
  select id into v_parent
  from programacion.input_readiness_runs
  where version_id=19 and pantalla_id=p_pantalla_id and status='COMPLETED'
  order by id desc limit 1;
  if v_parent is null then raise exception 'S28_IG_EXACT_PARENT_MISSING:%',p_screen_code; end if;

  v_curator_identity := 'INPUT_CURATOR:EDGE:input-governance-curator-v1:S28IGEXACT_' || p_pantalla_id::text;
  v_validator_identity := 'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:S28IGEXACT_' || p_pantalla_id::text;

  t0:=clock_timestamp();
  v_cur:=programacion.fn_input_governance_curator_rebind_candidate_v1(
    p_pantalla_id,'MANUAL',v_curator_identity,true
  );
  t1:=clock_timestamp();
  v_cur_ms:=extract(epoch from (t1-t0))*1000;

  if v_cur->>'status'<>'VALIDATOR_RUNTIME_REQUIRED' then
    raise exception 'S28_IG_EXACT_CURATOR_STATUS_FAIL:%:%',p_screen_code,v_cur;
  end if;
  v_run:=(v_cur->>'run_id')::bigint;
  v_family_count:=(v_cur->>'family_count')::integer;
  if v_family_count<>47 then raise exception 'S28_IG_EXACT_CURATOR_CARDINALITY_FAIL:%:%',p_screen_code,v_family_count; end if;
  if v_cur_ms>=30000 then raise exception 'S28_IG_EXACT_CURATOR_30S_GATE_FAIL:%:%ms',p_screen_code,round(v_cur_ms,3); end if;

  select count(*) into v_missing_fp
  from programacion.input_family_assessments
  where run_id=v_run
    and coalesce(curator_evidence->>'bootstrap_classifier_sha256','')='';
  if v_missing_fp<>0 then raise exception 'S28_IG_EXACT_CLASSIFIER_FINGERPRINT_MISSING:%:%',p_screen_code,v_missing_fp; end if;

  select count(*) into v_diff
  from programacion.input_family_assessments c
  join programacion.input_family_assessments p
    on p.run_id=v_parent and p.family_code=c.family_code
  where c.run_id=v_run and jsonb_build_object(
    'severity',c.severity,
    'applicability',c.applicability,
    'coverage_status',c.coverage_status,
    'well_defined_status',c.well_defined_status,
    'story_ready_status',c.story_ready_status,
    'implementation_ready_status',c.implementation_ready_status,
    'qa_ready_status',c.qa_ready_status,
    'production_ready_status',c.production_ready_status,
    'source_refs',c.source_refs,
    'blockers',c.blockers,
    'negative_requirements',c.negative_requirements,
    'test_obligations',c.test_obligations,
    'subject_coverage',c.subject_coverage,
    'threat_coverage',c.threat_coverage,
    'semantic_depth_sha256',c.semantic_depth_sha256
  ) is distinct from jsonb_build_object(
    'severity',p.severity,
    'applicability',p.applicability,
    'coverage_status',p.coverage_status,
    'well_defined_status',p.well_defined_status,
    'story_ready_status',p.story_ready_status,
    'implementation_ready_status',p.implementation_ready_status,
    'qa_ready_status',p.qa_ready_status,
    'production_ready_status',p.production_ready_status,
    'source_refs',p.source_refs,
    'blockers',p.blockers,
    'negative_requirements',p.negative_requirements,
    'test_obligations',p.test_obligations,
    'subject_coverage',p.subject_coverage,
    'threat_coverage',p.threat_coverage,
    'semantic_depth_sha256',p.semantic_depth_sha256
  );
  if v_diff<>0 then raise exception 'S28_IG_EXACT_SEMANTIC_COPY_DIFF:%:%',p_screen_code,v_diff; end if;

  for i in 1..8 loop
    v_calls:=v_calls+1;
    t0:=clock_timestamp();
    v_val:=programacion.fn_input_governance_validator_validate_v1(v_run,v_validator_identity);
    t1:=clock_timestamp();
    v_chunk_ms:=extract(epoch from (t1-t0))*1000;
    v_val_total:=v_val_total+v_chunk_ms;
    v_val_max:=greatest(v_val_max,v_chunk_ms);
    v_status:=v_val->>'status';
    if v_chunk_ms>=30000 then
      raise exception 'S28_IG_EXACT_VALIDATOR_30S_CHUNK_GATE_FAIL:%:call=%:%ms',p_screen_code,v_calls,round(v_chunk_ms,3);
    end if;
    exit when v_status='COMPLETED';
    if v_status<>'VALIDATOR_CONTINUE_REQUIRED' then
      raise exception 'S28_IG_EXACT_VALIDATOR_STATUS_FAIL:%:call=%:%',p_screen_code,v_calls,v_val;
    end if;
  end loop;
  if v_status<>'COMPLETED' then raise exception 'S28_IG_EXACT_VALIDATOR_NOT_COMPLETED:%:%',p_screen_code,v_status; end if;

  select count(*) into v_pass
  from programacion.input_family_assessments
  where run_id=v_run
    and validator_outcome='PASS'
    and validator_identity=v_validator_identity;
  if v_pass<>47 then raise exception 'S28_IG_EXACT_VALIDATOR_47_GATE_FAIL:%:%',p_screen_code,v_pass; end if;
  if v_validator_identity=v_curator_identity then raise exception 'S28_IG_EXACT_VALIDATOR_INDEPENDENCE_FAIL:%',p_screen_code; end if;

  return jsonb_build_object(
    'screen_code',p_screen_code,
    'pantalla_id',p_pantalla_id,
    'parent_run_id',v_parent,
    'candidate_run_id_ephemeral',v_run,
    'curator_ms',round(v_cur_ms,3),
    'validator_total_ms',round(v_val_total,3),
    'validator_max_chunk_ms',round(v_val_max,3),
    'validator_calls',v_calls,
    'validator_pass_count',v_pass,
    'semantic_diff_count',v_diff,
    'missing_classifier_fingerprint_count',v_missing_fp,
    'result','PASS'
  );
end;
$case$;

-- Preflight exact forward state.
do $preflight$
declare
  v_count integer;
  v_guard text;
  v_exec text;
begin
  if not exists(select 1 from supabase_migrations.schema_migrations where version='20260907023000' and name='lf_input_governance_ig006_ig007_exact_canary_forward_v1') then
    raise exception 'S28_IG_EXACT_FORWARD_LEDGER_MISSING';
  end if;
  if exists(select 1 from supabase_migrations.schema_migrations where version='20260907023100') then
    raise exception 'S28_IG_EXACT_ROLLBACK_ALREADY_APPLIED';
  end if;

  select count(*) into v_count from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname in (
    'fn_guard_input_family_assessment_insert_baseline_ig007_v1',
    'fn_input_rebind_assertion_cached_v1',
    'fn_input_v58_build_assertions_cached_v1',
    'fn_input_governance_curator_rebind_candidate_v1'
  );
  if v_count<>4 then raise exception 'S28_IG_EXACT_FORWARD_OBJECT_COUNT:%',v_count; end if;

  select pg_get_functiondef('programacion.fn_guard_input_family_assessment_insert()'::regprocedure),
         pg_get_functiondef('programacion.fn_input_governance_execute(integer,text)'::regprocedure)
    into v_guard,v_exec;
  if position('v_cached_graph is null and v_cached_graph_sha is null' in v_guard)=0 then
    raise exception 'S28_IG_EXACT_GUARD_FALLBACK_MISSING';
  end if;
  if position('fn_input_governance_curator_rebind_candidate_v1' in v_exec)>0 then
    raise exception 'S28_IG_EXACT_LIVE_ENTRYPOINT_SWITCHED';
  end if;
end;
$preflight$;

-- Fallback proof: live Curator does NOT publish the cache. The modified guard must
-- therefore use the original canonical resolver and still create all 47 assessments.
begin;
set local statement_timeout='60s';
do $fallback$
declare
  v jsonb;
  v_run bigint;
  v_count integer;
begin
  perform set_config('lf.input_screen_canonical_graph_v1','',true);
  perform set_config('lf.input_screen_canonical_graph_sha256_v1','',true);
  v:=programacion.fn_input_governance_curator_rebind_v1(
    5,'MANUAL','INPUT_CURATOR:EDGE:input-governance-curator-v1:S28IGEXACT_FALLBACK',true
  );
  if v->>'status'<>'VALIDATOR_RUNTIME_REQUIRED' then
    raise exception 'S28_IG_EXACT_GUARD_FALLBACK_CURATOR_FAIL:%',v;
  end if;
  v_run:=(v->>'run_id')::bigint;
  select count(*) into v_count from programacion.input_family_assessments where run_id=v_run;
  if v_count<>47 then raise exception 'S28_IG_EXACT_GUARD_FALLBACK_CARDINALITY:%',v_count; end if;
  raise notice 'S28_IG_EXACT_GUARD_FALLBACK_PASS run=% families=%',v_run,v_count;
end;
$fallback$;
rollback;

-- GOLD control 1: B2B-CARGA-001. One SQL statement bounded below 120s.
begin;
set local statement_timeout='120s';
select pg_temp.s28_ig_exact_case(43,'B2B-CARGA-001') as s28_ig_exact_result;
rollback;

-- GOLD control 2: HOME_002. One SQL statement bounded below 120s.
begin;
set local statement_timeout='120s';
select pg_temp.s28_ig_exact_case(5,'HOME_002') as s28_ig_exact_result;
rollback;

-- Durable readback: all test identities must have rolled back.
do $post$
declare v_count integer;
begin
  select count(*) into v_count
  from programacion.input_readiness_runs
  where curator_identity like 'INPUT_CURATOR:EDGE:input-governance-curator-v1:S28IGEXACT_%'
     or validator_identity like 'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:S28IGEXACT_%';
  if v_count<>0 then raise exception 'S28_IG_EXACT_TEST_RUN_RESIDUE:%',v_count; end if;
  raise notice 'S28_IG_EXACT_CANARY_PASS durable_test_runs=0';
end;
$post$;
