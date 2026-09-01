do $judges$
declare
  v_execution_id text:=nullif(current_setting('app.lf_execution_id',true),'');
  v_existing integer;
  v_missing integer;
begin
  if v_execution_id is null then raise exception 'ACT0058_JUDGE_CANDIDATE_EXECUTION_ID_REQUIRED'; end if;
  if not exists (
    select 1 from public.lf_operation_execution
    where execution_id=v_execution_id
      and operation_code='ORQUESTACION_PIPELINE_LF'
      and status='IN_PROGRESS'
  ) then raise exception 'ACT0058_JUDGE_CANDIDATE_EXECUTION_INVALID:%',v_execution_id; end if;

  select count(*) into v_existing
  from public.lf_operation_judges
  where operation_code='ORQUESTACION_PIPELINE_LF' and status='ACTIVE_ENFORCEMENT';
  if v_existing<>4 then raise exception 'ACT0058_ACTIVE_JUDGE_BASELINE_DRIFT:%',v_existing; end if;

  select count(*) into v_missing
  from (values
    ('MINI_JUDGE_ACT0058_INIT_EXECUTION'),('MINI_JUDGE_ACT0058_INIT'),('MINI_JUDGE_ACT0058_SCOPE'),
    ('MINI_JUDGE_ACT0058_CAPTURA'),('MINI_JUDGE_ACT0058_HOMOLOG'),('MINI_JUDGE_ACT0058_ANALISIS'),
    ('MINI_JUDGE_ACT0058_KB_WRITE'),('MINI_JUDGE_ACT0058_COMPLETED'),('MINI_JUDGE_ACT0058_RESTOCK'),('MINI_JUDGE_ACT0058_RETRY')
  ) x(judge_code)
  where not exists (
    select 1 from public.lf_operation_judges j
    where j.operation_code='ORQUESTACION_PIPELINE_LF' and j.judge_code=x.judge_code
  );
  if v_missing<>10 then raise exception 'ACT0058_MISSING_JUDGE_BASELINE_DRIFT:%',v_missing; end if;

  insert into public.lf_operation_judges
    (operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,created_by_execution_id,updated_by_execution_id)
  values
    ('ORQUESTACION_PIPELINE_LF','MINI_JUDGE_ACT0058_INIT_EXECUTION','supabase://public/lf_operation_step_contracts/ORQUESTACION_PIPELINE_LF/init_execution',null,'["operation_execution_exists","operation_code_matches","status_in_progress"]','["execution_missing","operation_code_mismatch","status_not_in_progress"]','["EXECUTION_INITIALIZED","BLOCKED"]','CANDIDATO_READ_ONLY',v_execution_id,v_execution_id),
    ('ORQUESTACION_PIPELINE_LF','MINI_JUDGE_ACT0058_INIT','supabase://public/lf_operation_step_contracts/ORQUESTACION_PIPELINE_LF/init_run',null,'["pipeline_run_created","source_url_nonempty","dedup_24h_clear","stage_current_captura"]','["source_url_empty","completed_duplicate_within_24h","pipeline_run_missing"]','["RUN_INITIALIZED","DEDUP_BLOCKED","BLOCKED"]','CANDIDATO_READ_ONLY',v_execution_id,v_execution_id),
    ('ORQUESTACION_PIPELINE_LF','MINI_JUDGE_ACT0058_SCOPE','supabase://public/lf_operation_step_contracts/ORQUESTACION_PIPELINE_LF/scope_filter',null,'["source_domain_allowed"]','["source_domain_out_of_scope"]','["SCOPE_ALLOWED","OUT_OF_SCOPE"]','CANDIDATO_READ_ONLY',v_execution_id,v_execution_id),
    ('ORQUESTACION_PIPELINE_LF','MINI_JUDGE_ACT0058_CAPTURA','supabase://public/lf_operation_step_contracts/ORQUESTACION_PIPELINE_LF/stage_captura',null,'["capture_run_id_present","capture_status_completed"]','["capture_run_id_missing","capture_status_not_completed"]','["CAPTURE_COMPLETED","CAPTURE_BLOCKED"]','CANDIDATO_READ_ONLY',v_execution_id,v_execution_id),
    ('ORQUESTACION_PIPELINE_LF','MINI_JUDGE_ACT0058_HOMOLOG','supabase://public/lf_operation_step_contracts/ORQUESTACION_PIPELINE_LF/stage_homolog',null,'["homolog_record_id_present","homolog_status_aprobado"]','["homolog_record_id_missing","homolog_status_rejected_or_null"]','["HOMOLOG_APPROVED","HOMOLOG_BLOCKED"]','CANDIDATO_READ_ONLY',v_execution_id,v_execution_id),
    ('ORQUESTACION_PIPELINE_LF','MINI_JUDGE_ACT0058_ANALISIS','supabase://public/lf_operation_step_contracts/ORQUESTACION_PIPELINE_LF/stage_analisis',null,'["decision_id_present","consumer_gate_passed_true"]','["decision_id_missing","consumer_gate_not_passed"]','["ANALYSIS_ALLOWED","ANALYSIS_BLOCKED"]','CANDIDATO_READ_ONLY',v_execution_id,v_execution_id),
    ('ORQUESTACION_PIPELINE_LF','MINI_JUDGE_ACT0058_KB_WRITE','supabase://public/lf_operation_step_contracts/ORQUESTACION_PIPELINE_LF/stage_kb_write',null,'["kb_id_present","consumer_gate_passed_true","hitl_triggered_false"]','["consumer_gate_not_passed","hitl_triggered_true","kb_id_missing"]','["KB_WRITE_CONFIRMED","KB_WRITE_BLOCKED"]','CANDIDATO_READ_ONLY',v_execution_id,v_execution_id),
    ('ORQUESTACION_PIPELINE_LF','MINI_JUDGE_ACT0058_COMPLETED','supabase://public/lf_operation_step_contracts/ORQUESTACION_PIPELINE_LF/completed',null,'["stage_completed","closing_event_present"]','["pipeline_update_failed","closing_event_missing"]','["COMPLETED_CONFIRMED","COMPLETION_BLOCKED"]','CANDIDATO_READ_ONLY',v_execution_id,v_execution_id),
    ('ORQUESTACION_PIPELINE_LF','MINI_JUDGE_ACT0058_RESTOCK','supabase://public/lf_operation_step_contracts/ORQUESTACION_PIPELINE_LF/restock_queue',null,'["restock_attempt_recorded","dedup_performed"]','["restock_attempt_missing","dedup_not_performed"]','["RESTOCK_COMPLETED","RESTOCK_NOOP_WARN","RESTOCK_BLOCKED"]','CANDIDATO_READ_ONLY',v_execution_id,v_execution_id),
    ('ORQUESTACION_PIPELINE_LF','MINI_JUDGE_ACT0058_RETRY','supabase://public/lf_operation_step_contracts/ORQUESTACION_PIPELINE_LF/failed_retry',null,'["retry_count_lt_3_and_next_action_retry","retry_count_gte_3_and_next_action_failed_continue_next_url"]','["retry_count_gte_3_and_next_action_retry"]','["RETRY_ALLOWED","RETRY_TERMINAL_FAILED","RETRY_BLOCKED"]','CANDIDATO_READ_ONLY',v_execution_id,v_execution_id);

  if (select count(*) from public.lf_operation_judges where operation_code='ORQUESTACION_PIPELINE_LF' and status='CANDIDATO_READ_ONLY')<>10 then
    raise exception 'ACT0058_CANDIDATE_JUDGE_CARDINALITY_FAILED';
  end if;
  if exists (
    select 1 from public.lf_operation_step_judge_bindings b
    where b.operation_code='ORQUESTACION_PIPELINE_LF' and b.judge_code in (
      'MINI_JUDGE_ACT0058_INIT_EXECUTION','MINI_JUDGE_ACT0058_INIT','MINI_JUDGE_ACT0058_SCOPE','MINI_JUDGE_ACT0058_CAPTURA',
      'MINI_JUDGE_ACT0058_HOMOLOG','MINI_JUDGE_ACT0058_ANALISIS','MINI_JUDGE_ACT0058_KB_WRITE','MINI_JUDGE_ACT0058_COMPLETED',
      'MINI_JUDGE_ACT0058_RESTOCK','MINI_JUDGE_ACT0058_RETRY'
    )
  ) then raise exception 'ACT0058_CANDIDATE_MUST_NOT_BIND_ACTIVE'; end if;
end
$judges$;
