-- Prior art para N-9 (juez de flujo IG). Dry-run transaccional antes/después de un candidato de runtime.
-- Uso: verificación independiente del PR #1386 (evento 19780). Detectó la regresión del guard de M8.1.
-- Todo termina en RAISE EXCEPTION 'DRYRUN_OK ...' (ROLLBACK total). Reemplazar el bloque de migración por el candidato.
do $p0$ begin
  perform set_config('lf.old_v2', pg_get_functiondef('programacion.fn_input_governance_validate_v2(bigint,text)'::regprocedure), true);
  perform set_config('lf.old_v1', pg_get_functiondef('programacion.fn_input_governance_validator_validate_v1(bigint,text)'::regprocedure), true);
end $p0$;
do $gfix$
declare d text; n text;
begin
  d := pg_get_functiondef('programacion.fn_guard_input_readiness_run()'::regprocedure);
  perform set_config('lf.guard_md5_before', md5(d), true);
  n := replace(d, $q$(to_jsonb(new)-'invalidated_at'-'invalidated_reason'-'invalidated_by_run_id')=(to_jsonb(old)-'invalidated_at'-'invalidated_reason'-'invalidated_by_run_id')$q$,
                  $q$(to_jsonb(new)-'invalidated_at'-'invalidated_reason'-'invalidated_by_run_id'-'curator_duration_ms'-'validator_duration_ms')=(to_jsonb(old)-'invalidated_at'-'invalidated_reason'-'invalidated_by_run_id'-'curator_duration_ms'-'validator_duration_ms')$q$);
  if n = d then raise exception 'GUARD_FIX_ANCHOR_NOT_FOUND'; end if;
  execute n;
end $gfix$;
do $phase_a$
declare v_cur text := 'INPUT_CURATOR:EDGE:input-governance-curator-v1:'||gen_random_uuid();
 v_val text := 'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:'||replace(gen_random_uuid()::text,'-','');
 m jsonb; r jsonb; v_run bigint; pg_exception_context_txt text; st text[] := '{}'; i int; t0 timestamptz; t1 timestamptz; t2 timestamptz; cap jsonb; err text;
begin
  begin
    t0 := clock_timestamp();
    m := programacion.fn_input_governance_execute(1, 'STORY_CREATOR');
    if m->>'status' <> 'CURATOR_RUNTIME_REQUIRED' then raise exception 'DISPATCH_UNEXPECTED:%', left(m::text,300); end if;
    m := programacion.fn_input_governance_curator_materialize_v1(1, 'STORY_CREATOR', v_cur);
    t1 := clock_timestamp();
    v_run := coalesce((m->>'run_id')::bigint, (m->>'latest_run_id')::bigint);
    if m->>'status' <> 'VALIDATOR_RUNTIME_REQUIRED' or v_run is null then raise exception 'CURATOR_UNEXPECTED:%', left(m::text,300); end if;
    for i in 1..8 loop
      r := programacion.fn_input_governance_validator_validate_v1(v_run, v_val);
      st := st || (r->>'status');
      exit when r->>'status' in ('COMPLETED','NOOP_COMPLETED');
    end loop;
    -- retry/idempotencia: llamada repetida sobre run ya COMPLETED
    st := st || (programacion.fn_input_governance_validator_validate_v1(v_run, v_val)->>'status');
    t2 := clock_timestamp();
    cap := jsonb_build_object(
      'statuses', to_jsonb(st),
      'final', (r - 'run_id' - 'validator_identity' - 'output_sha256' - 'proposal_validation'),
      'proposal_validation_keys', (select jsonb_agg(k order by k) from jsonb_object_keys(coalesce(r->'proposal_validation','{}'::jsonb)) k),
      'assess_digest', (select md5(string_agg(family_code||'|'||validator_outcome||'|'||coalesce(validator_findings::text,'')||'|'||coalesce(validator_evidence->>'bootstrap_classifier_sha256','')||'|'||md5(coalesce((validator_evidence->'assertions')::text,'')), ',' order by family_code)) from programacion.input_family_assessments where run_id=v_run),
      'pass', (select count(*) from programacion.input_family_assessments where run_id=v_run and validator_outcome='PASS'),
      'run_status', (select status from programacion.input_readiness_runs where id=v_run),
      'timing_rows', (select count(*) from programacion.input_validator_chunk_timings where run_id=v_run),
      'timing_routes', (select jsonb_agg(distinct route) from programacion.input_validator_chunk_timings where run_id=v_run),
      'timing_detail', (select jsonb_build_object('rows_with_subphases', count(*) filter (where (to_jsonb(t)->>'classification_ms') is not null),
                                'sum_duration_ms', sum(duration_ms),
                                'sum_subphases_ms', sum(coalesce((to_jsonb(t)->>'classification_ms')::bigint,0)+coalesce((to_jsonb(t)->>'assertions_ms')::bigint,0)+coalesce((to_jsonb(t)->>'ekb_ms')::bigint,0)+coalesce((to_jsonb(t)->>'gap_proposals_ms')::bigint,0)+coalesce((to_jsonb(t)->>'db_write_ms')::bigint,0)),
                                'families_processed', sum(coalesce((to_jsonb(t)->>'families_processed')::int,0)),
                                'chunks', jsonb_agg(jsonb_build_object('n',chunk_no,'ms',duration_ms,'cls',to_jsonb(t)->>'classification_ms','asr',to_jsonb(t)->>'assertions_ms','ekb',to_jsonb(t)->>'ekb_ms','gap',to_jsonb(t)->>'gap_proposals_ms','wr',to_jsonb(t)->>'db_write_ms','wait',to_jsonb(t)->>'wait_resume_ms','fam',to_jsonb(t)->>'families_processed','st',result_status) order by chunk_no))
                         from programacion.input_validator_chunk_timings t where run_id=v_run),
      'curator_s', round(extract(epoch from t1-t0)::numeric,2), 'validator_s', round(extract(epoch from t2-t1)::numeric,2));
    raise exception 'ROLLBACK_PHASE';
  exception when others then
    err := sqlerrm; get stacked diagnostics pg_exception_context_txt = pg_exception_context;
    if err <> 'ROLLBACK_PHASE' then cap := jsonb_build_object('error', err, 'ctx', left(coalesce(m::text,''),120), 'statuses_before_error', to_jsonb(st), 'last_r', left(coalesce(r::text,''),300), 'err_ctx', left(coalesce(pg_exception_context_txt,''),600)); end if;
  end;
  perform set_config('lf.phase_a', cap::text, true);
end $phase_a$;

-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · L2 · N-7 / PAULO-172
-- Complete the N-7 timing model with subphase timings and inter-chunk wait.

alter table programacion.input_validator_chunk_timings
  add column if not exists classification_ms bigint,
  add column if not exists assertions_ms bigint,
  add column if not exists ekb_ms bigint,
  add column if not exists gap_proposals_ms bigint,
  add column if not exists db_write_ms bigint,
  add column if not exists wait_resume_ms bigint,
  add column if not exists families_processed integer;

do $baseline$
declare
  v_validate text:=pg_get_functiondef('programacion.fn_input_governance_validate_v2(bigint,text)'::regprocedure);
  v_wrapper text:=pg_get_functiondef('programacion.fn_input_governance_validator_validate_v1(bigint,text)'::regprocedure);
begin
  if md5(v_validate)<>'8310ddf54aae169d7fbe9da2fa44a186' then raise exception 'N7_VALIDATE_V2_BASELINE_DRIFT:%',md5(v_validate); end if;
  if md5(v_wrapper)<>'2f913ac8ef46e4177b5aa758700c0605' then raise exception 'N7_WRAPPER_BASELINE_DRIFT:%',md5(v_wrapper); end if;
end;
$baseline$;

create or replace function programacion.fn_input_governance_validate_v2(p_run_id bigint,p_validator_identity text)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,programacion
as $function$
declare
  v_status text; v_pantalla_id integer; v_family_count integer; v_curator_identity text;
  v_existing_validator text; v_contract_revision text; v_validator_component bigint; v_source_sha text; v_pass integer; v_pending integer;
  v_pre jsonb; v_assertions jsonb; v_expected jsonb; v_exec_id text:=gen_random_uuid()::text;
  v_payload jsonb; v_result jsonb; v_prop jsonb; a record; v_pending_before integer;
  v_started timestamptz:=clock_timestamp(); v_completed timestamptz; v_phase_started timestamptz; v_prev_completed timestamptz;
  v_classification_ms bigint:=0; v_assertions_ms bigint:=0; v_ekb_ms bigint:=0; v_gap_ms bigint:=0; v_db_write_ms bigint:=0;
  v_wait_ms bigint:=0; v_chunk_no integer; v_families_processed integer:=0;
begin
  if p_validator_identity !~ '^INPUT_VALIDATOR:EDGE:input-governance-validator-v1:[A-Za-z0-9_-]{6,128}$' then raise exception 'INPUT_GOVERNANCE_VALIDATOR_RUNTIME_IDENTITY_INVALID'; end if;
  perform pg_advisory_xact_lock(hashtextextended('input_governance_validator_v2:'||p_run_id::text,0));
  select status,pantalla_id,family_count,curator_identity,validator_identity,contract_revision
    into v_status,v_pantalla_id,v_family_count,v_curator_identity,v_existing_validator,v_contract_revision
  from programacion.input_readiness_runs
  where id=p_run_id and version_id=19 and scope->>'analysis_revision'='INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX';
  if v_status is null then raise exception 'INPUT_REMEDIATION_VALIDATOR_RUN_NOT_FOUND:%',p_run_id; end if;
  if v_status='COMPLETED' then return jsonb_build_object('status','NOOP_COMPLETED','run_id',p_run_id,'promotion_authorized',false,'production_authorized',false); end if;
  if p_validator_identity=v_curator_identity then raise exception 'VALIDATOR_IDENTITY_NOT_INDEPENDENT'; end if;

  v_phase_started:=clock_timestamp();
  v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_VALIDATOR',v_pantalla_id,p_run_id);
  v_ekb_ms:=round(extract(epoch from(clock_timestamp()-v_phase_started))*1000)::bigint;
  if not coalesce((v_pre->>'pass')::boolean,false) then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_VALIDATOR'; end if;

  select id into v_validator_component from programacion.componentes where version_id=19 and componente_codigo='INPUT_VALIDATOR';
  if v_validator_component is null then raise exception 'INPUT_REMEDIATION_VALIDATOR_COMPONENT_UNRESOLVED'; end if;
  if v_status='CURATING' then
    if (select count(*) from programacion.input_family_assessments where run_id=p_run_id)<>v_family_count then raise exception 'CURATOR_UNIVERSE_INCOMPLETE'; end if;
    v_phase_started:=clock_timestamp();
    update programacion.input_readiness_runs set status='VALIDATING',validator_identity=p_validator_identity,validator_component_id=v_validator_component where id=p_run_id;
    v_db_write_ms:=v_db_write_ms+round(extract(epoch from(clock_timestamp()-v_phase_started))*1000)::bigint;
  elsif v_status='VALIDATING' then
    if v_existing_validator is distinct from p_validator_identity then raise exception 'VALIDATOR_IDENTITY_MISMATCH'; end if;
  else raise exception 'INPUT_REMEDIATION_VALIDATOR_INVALID_RUN_STATUS:%',v_status; end if;

  select source_snapshot_sha256,contract_revision into v_source_sha,v_contract_revision from programacion.input_readiness_runs where id=p_run_id;
  select count(*) into v_pending_before from programacion.input_family_assessments where run_id=p_run_id and validator_outcome='PENDING';

  for a in
    select * from programacion.input_family_assessments
    where run_id=p_run_id and validator_outcome='PENDING'
    order by family_code
    limit 10
  loop
    v_phase_started:=clock_timestamp();
    v_expected:=programacion.fn_input_governance_bootstrap_classify_v2(v_pantalla_id,a.family_code,19);
    v_classification_ms:=v_classification_ms+round(extract(epoch from(clock_timestamp()-v_phase_started))*1000)::bigint;
    if a.curator_evidence->>'bootstrap_classifier_sha256' is distinct from v_expected->>'classifier_sha256'
       or a.severity is distinct from v_expected->>'severity'
       or a.applicability is distinct from v_expected->>'applicability'
       or a.coverage_status is distinct from v_expected->>'coverage_status'
       or a.well_defined_status is distinct from v_expected->>'well_defined_status'
       or a.story_ready_status is distinct from v_expected->>'story_ready_status'
       or a.implementation_ready_status is distinct from v_expected->>'implementation_ready_status'
       or a.qa_ready_status is distinct from v_expected->>'qa_ready_status'
       or a.production_ready_status is distinct from v_expected->>'production_ready_status'
       or a.source_refs is distinct from v_expected->'source_refs'
       or a.blockers is distinct from v_expected->'blockers'
    then raise exception 'INPUT_REMEDIATION_VALIDATOR_CLASSIFIER_MISMATCH:%',a.family_code; end if;

    v_phase_started:=clock_timestamp();
    v_assertions:=programacion.fn_input_governance_bootstrap_assertions_v1(p_run_id,a.family_code);
    v_assertions_ms:=v_assertions_ms+round(extract(epoch from(clock_timestamp()-v_phase_started))*1000)::bigint;
    if jsonb_array_length(v_assertions)=0 then raise exception 'INPUT_REMEDIATION_VALIDATOR_ASSERTIONS_EMPTY:%',a.family_code; end if;

    v_phase_started:=clock_timestamp();
    update programacion.input_family_assessments
    set validator_outcome='PASS',validator_findings='[]'::jsonb,
        validator_evidence=jsonb_build_object('component_id',v_validator_component,'execution_id',v_exec_id,'validated_curator_execution_id',a.curator_evidence->>'execution_id','execution_mode','INDEPENDENT_VALIDATOR','runtime','SUPABASE_EDGE_FUNCTION:input-governance-validator-v1','direct_source_readback',true,'contract_revision',v_contract_revision,'source_snapshot_sha256',v_source_sha,'curator_sha256',a.curator_sha256,'semantic_depth_sha256',a.semantic_depth_sha256,'bootstrap_classifier_sha256',v_expected->>'classifier_sha256','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','assertions',v_assertions),
        validator_identity=p_validator_identity,validator_assessed_at=now()
    where id=a.id;
    v_db_write_ms:=v_db_write_ms+round(extract(epoch from(clock_timestamp()-v_phase_started))*1000)::bigint;
    v_families_processed:=v_families_processed+1;
  end loop;

  select count(*) into v_pass from programacion.input_family_assessments where run_id=p_run_id and validator_outcome='PASS' and validator_identity=p_validator_identity;
  select count(*) into v_pending from programacion.input_family_assessments where run_id=p_run_id and validator_outcome='PENDING';
  if v_pass<v_family_count then
    if v_pending=0 then raise exception 'INPUT_REMEDIATION_VALIDATOR_CARDINALITY_STALLED expected=% pass=%',v_family_count,v_pass; end if;
    v_result:=jsonb_build_object('status','VALIDATOR_CONTINUE_REQUIRED','run_id',p_run_id,'pantalla_id',v_pantalla_id,'family_count',v_family_count,'validator_pass_count',v_pass,'pending_count',v_pending,'validator_identity',p_validator_identity,'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','promotion_authorized',false,'production_authorized',false);
  elsif v_pending_before>0 then
    v_result:=jsonb_build_object('status','VALIDATOR_CONTINUE_REQUIRED','run_id',p_run_id,'pantalla_id',v_pantalla_id,'family_count',v_family_count,'validator_pass_count',v_pass,'pending_count',v_pending,'validator_identity',p_validator_identity,'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','next_phase','PROPOSAL_VALIDATION','promotion_authorized',false,'production_authorized',false);
  else
    v_phase_started:=clock_timestamp();
    v_prop:=programacion.fn_input_governance_validate_gap_proposals_v1(p_run_id,p_validator_identity);
    v_gap_ms:=round(extract(epoch from(clock_timestamp()-v_phase_started))*1000)::bigint;
    v_phase_started:=clock_timestamp();
    update programacion.input_readiness_runs set status='COMPLETED',validator_completed_at=now() where id=p_run_id;
    v_db_write_ms:=v_db_write_ms+round(extract(epoch from(clock_timestamp()-v_phase_started))*1000)::bigint;
    v_payload:=jsonb_build_object('status','COMPLETED','run_id',p_run_id,'pantalla_id',v_pantalla_id,'family_count',v_family_count,'validator_pass_count',v_pass,'validator_identity',p_validator_identity,'required_role','DISPATCHER_FINALIZE','analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','proposal_validation',v_prop,'promotion_authorized',false,'production_authorized',false);
    v_result:=v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
  end if;

  v_completed:=clock_timestamp();
  select coalesce(max(chunk_no),0)+1,max(completed_at) into v_chunk_no,v_prev_completed
  from programacion.input_validator_chunk_timings where run_id=p_run_id and validator_identity=p_validator_identity;
  if v_prev_completed is not null then v_wait_ms:=greatest(0,round(extract(epoch from(v_started-v_prev_completed))*1000)::bigint); end if;
  insert into programacion.input_validator_chunk_timings(
    run_id,validator_identity,chunk_no,route,started_at,completed_at,duration_ms,result_status,
    validator_pass_count,family_count,pending_count,classification_ms,assertions_ms,ekb_ms,gap_proposals_ms,db_write_ms,wait_resume_ms,families_processed
  ) values(
    p_run_id,p_validator_identity,v_chunk_no,'VALIDATE_V2',v_started,v_completed,
    round(extract(epoch from(v_completed-v_started))*1000)::bigint,v_result->>'status',v_pass,v_family_count,v_pending,
    v_classification_ms,v_assertions_ms,v_ekb_ms,v_gap_ms,v_db_write_ms,v_wait_ms,v_families_processed
  );
  return v_result;
end;
$function$;

create or replace function programacion.fn_input_governance_validator_validate_v1(p_run_id bigint,p_validator_identity text)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,programacion
as $function$
declare
  v_analysis text; v_bootstrap boolean; v_result jsonb; v_started timestamptz:=clock_timestamp(); v_completed timestamptz; v_route text; v_chunk_no integer;
begin
  perform pg_advisory_xact_lock(pg_catalog.hashtextextended('IG_VALIDATOR_CHUNK:'||p_run_id::text||':'||coalesce(p_validator_identity,''),0));
  select scope->>'analysis_revision',supersedes_run_id is null and scope->>'mode'='GOVERNED_CANONICAL_BOOTSTRAP_V1' into v_analysis,v_bootstrap from programacion.input_readiness_runs where id=p_run_id and version_id=19;
  if v_analysis='INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX' then return programacion.fn_input_governance_validate_v2(p_run_id,p_validator_identity); end if;
  if coalesce(v_bootstrap,false) then v_route:='BOOTSTRAP_VALIDATE_V1'; v_result:=programacion.fn_input_governance_bootstrap_validate_v1(p_run_id,p_validator_identity);
  else v_route:='VALIDATOR_REBIND_V1'; v_result:=programacion.fn_input_governance_validator_rebind_v1(p_run_id,p_validator_identity); end if;
  v_completed:=clock_timestamp();
  select coalesce(max(chunk_no),0)+1 into v_chunk_no from programacion.input_validator_chunk_timings where run_id=p_run_id and validator_identity=p_validator_identity;
  insert into programacion.input_validator_chunk_timings(run_id,validator_identity,chunk_no,route,started_at,completed_at,duration_ms,result_status,validator_pass_count,family_count,pending_count)
  values(p_run_id,p_validator_identity,v_chunk_no,v_route,v_started,v_completed,round(extract(epoch from(v_completed-v_started))*1000)::bigint,v_result->>'status',nullif(v_result->>'validator_pass_count','')::integer,nullif(v_result->>'family_count','')::integer,nullif(v_result->>'pending_count','')::integer);
  return v_result;
end;
$function$;

comment on function programacion.fn_input_governance_validate_v2(bigint,text) is
  'N-7: validator semantics unchanged; persists classification/assertion/EKB/gap-proposal/write/wait timing for each VALIDATE_V2 chunk.';
comment on function programacion.fn_input_governance_validator_validate_v1(bigint,text) is
  'N-7: existing dispatcher; VALIDATE_V2 persists its own detailed chunk timing, bootstrap/rebind keep generic per-call timing.';

do $phase_b$
declare v_cur text := 'INPUT_CURATOR:EDGE:input-governance-curator-v1:'||gen_random_uuid();
 v_val text := 'INPUT_VALIDATOR:EDGE:input-governance-validator-v1:'||replace(gen_random_uuid()::text,'-','');
 m jsonb; r jsonb; v_run bigint; pg_exception_context_txt text; st text[] := '{}'; i int; t0 timestamptz; t1 timestamptz; t2 timestamptz; cap jsonb; err text;
begin
  begin
    t0 := clock_timestamp();
    m := programacion.fn_input_governance_execute(1, 'STORY_CREATOR');
    if m->>'status' <> 'CURATOR_RUNTIME_REQUIRED' then raise exception 'DISPATCH_UNEXPECTED:%', left(m::text,300); end if;
    m := programacion.fn_input_governance_curator_materialize_v1(1, 'STORY_CREATOR', v_cur);
    t1 := clock_timestamp();
    v_run := coalesce((m->>'run_id')::bigint, (m->>'latest_run_id')::bigint);
    if m->>'status' <> 'VALIDATOR_RUNTIME_REQUIRED' or v_run is null then raise exception 'CURATOR_UNEXPECTED:%', left(m::text,300); end if;
    for i in 1..8 loop
      r := programacion.fn_input_governance_validator_validate_v1(v_run, v_val);
      st := st || (r->>'status');
      exit when r->>'status' in ('COMPLETED','NOOP_COMPLETED');
    end loop;
    -- retry/idempotencia: llamada repetida sobre run ya COMPLETED
    st := st || (programacion.fn_input_governance_validator_validate_v1(v_run, v_val)->>'status');
    t2 := clock_timestamp();
    cap := jsonb_build_object(
      'statuses', to_jsonb(st),
      'final', (r - 'run_id' - 'validator_identity' - 'output_sha256' - 'proposal_validation'),
      'proposal_validation_keys', (select jsonb_agg(k order by k) from jsonb_object_keys(coalesce(r->'proposal_validation','{}'::jsonb)) k),
      'assess_digest', (select md5(string_agg(family_code||'|'||validator_outcome||'|'||coalesce(validator_findings::text,'')||'|'||coalesce(validator_evidence->>'bootstrap_classifier_sha256','')||'|'||md5(coalesce((validator_evidence->'assertions')::text,'')), ',' order by family_code)) from programacion.input_family_assessments where run_id=v_run),
      'pass', (select count(*) from programacion.input_family_assessments where run_id=v_run and validator_outcome='PASS'),
      'run_status', (select status from programacion.input_readiness_runs where id=v_run),
      'timing_rows', (select count(*) from programacion.input_validator_chunk_timings where run_id=v_run),
      'timing_routes', (select jsonb_agg(distinct route) from programacion.input_validator_chunk_timings where run_id=v_run),
      'timing_detail', (select jsonb_build_object('rows_with_subphases', count(*) filter (where (to_jsonb(t)->>'classification_ms') is not null),
                                'sum_duration_ms', sum(duration_ms),
                                'sum_subphases_ms', sum(coalesce((to_jsonb(t)->>'classification_ms')::bigint,0)+coalesce((to_jsonb(t)->>'assertions_ms')::bigint,0)+coalesce((to_jsonb(t)->>'ekb_ms')::bigint,0)+coalesce((to_jsonb(t)->>'gap_proposals_ms')::bigint,0)+coalesce((to_jsonb(t)->>'db_write_ms')::bigint,0)),
                                'families_processed', sum(coalesce((to_jsonb(t)->>'families_processed')::int,0)),
                                'chunks', jsonb_agg(jsonb_build_object('n',chunk_no,'ms',duration_ms,'cls',to_jsonb(t)->>'classification_ms','asr',to_jsonb(t)->>'assertions_ms','ekb',to_jsonb(t)->>'ekb_ms','gap',to_jsonb(t)->>'gap_proposals_ms','wr',to_jsonb(t)->>'db_write_ms','wait',to_jsonb(t)->>'wait_resume_ms','fam',to_jsonb(t)->>'families_processed','st',result_status) order by chunk_no))
                         from programacion.input_validator_chunk_timings t where run_id=v_run),
      'curator_s', round(extract(epoch from t1-t0)::numeric,2), 'validator_s', round(extract(epoch from t2-t1)::numeric,2));
    raise exception 'ROLLBACK_PHASE';
  exception when others then
    err := sqlerrm; get stacked diagnostics pg_exception_context_txt = pg_exception_context;
    if err <> 'ROLLBACK_PHASE' then cap := jsonb_build_object('error', err, 'ctx', left(coalesce(m::text,''),120), 'statuses_before_error', to_jsonb(st), 'last_r', left(coalesce(r::text,''),300), 'err_ctx', left(coalesce(pg_exception_context_txt,''),600)); end if;
  end;
  perform set_config('lf.phase_b', cap::text, true);
end $phase_b$;

do $cmp$
declare a jsonb := current_setting('lf.phase_a')::jsonb; b jsonb := current_setting('lf.phase_b')::jsonb; res jsonb; md2 text; md1 text; cols int;
begin
  -- rollback: restaurar definiciones previas exactas y verificar hash
  execute current_setting('lf.old_v2');
  execute current_setting('lf.old_v1');
  md2 := md5(pg_get_functiondef('programacion.fn_input_governance_validate_v2(bigint,text)'::regprocedure));
  md1 := md5(pg_get_functiondef('programacion.fn_input_governance_validator_validate_v1(bigint,text)'::regprocedure));
  res := jsonb_build_object(
    'same_statuses', a->'statuses' = b->'statuses', 'same_final', a->'final' = b->'final', 'same_prop_keys', a->'proposal_validation_keys' = b->'proposal_validation_keys',
    'same_assess', a->>'assess_digest' = b->>'assess_digest', 'pass_a', a->'pass', 'pass_b', b->'pass', 'run_status_a', a->'run_status', 'run_status_b', b->'run_status',
    'statuses_a', a->'statuses', 'statuses_b', b->'statuses', 'timing_rows_a', a->'timing_rows', 'timing_rows_b', b->'timing_rows', 'routes_b', b->'timing_routes',
    'detail_b', b->'timing_detail', 'validator_s_a', a->'validator_s', 'validator_s_b', b->'validator_s', 'curator_s_a', a->'curator_s', 'curator_s_b', b->'curator_s',
    'rollback_md5_v2_ok', md2='8310ddf54aae169d7fbe9da2fa44a186', 'rollback_md5_v1_ok', md1='2f913ac8ef46e4177b5aa758700c0605', 'guard_md5_before', current_setting('lf.guard_md5_before'), 'err_a', a->'error', 'err_b', b->'error', 'ctx_a', a->'ctx', 'st_err_a', a->'statuses_before_error', 'last_r_a', a->'last_r', 'err_ctx_a', a->'err_ctx', 'st_err_b', b->'statuses_before_error', 'err_ctx_b', b->'err_ctx');
  raise exception 'DRYRUN_OK %', res;
end $cmp$;
