-- SANDBOX / SOURCE-FIRST CANDIDATE ONLY. DO NOT APPLY FROM THIS FILE.
-- EKB preflight: DB-001, DB-EVT-001, SQL-008, GOV-010.
-- Exact scope: two currently unjudgeable ACT-0058 steps only.

UPDATE public.lf_operation_step_contracts
SET pass_condition = jsonb_build_object(
      'execution_id','PRESENT',
      'operation_code','ORQUESTACION_PIPELINE_LF',
      'status','IN_PROGRESS',
      'started_at','PRESENT'
    ),
    block_condition = jsonb_build_array('execution_id_missing','operation_code_mismatch','status_not_in_progress','started_at_missing'),
    required_evidence_keys = jsonb_build_array('execution_id','operation_code','status','started_at'),
    updated_at = now()
WHERE operation_code='ORQUESTACION_PIPELINE_LF'
  AND step_id='init_execution'
  AND step_order=5
  AND mini_judge_code='MINI_JUDGE_ACT0058_INIT_EXECUTION'
  AND pass_condition='{}'::jsonb
  AND required_evidence_keys='[]'::jsonb;

UPDATE public.lf_operation_step_contracts
SET required_evidence_keys = jsonb_build_array('urls_insertadas','queue_ids','dedup_count','event_id_if_no_new_urls'),
    fail_condition = jsonb_set(
      fail_condition,
      '{NO_NEW_URLS,execution_sql}',
      to_jsonb(replace(fail_condition #>> '{NO_NEW_URLS,execution_sql}', '''MEDIA''', '''WARN''')),
      false
    ),
    updated_at = now()
WHERE operation_code='ORQUESTACION_PIPELINE_LF'
  AND step_id='restock_queue'
  AND step_order=105
  AND mini_judge_code='MINI_JUDGE_ACT0058_RESTOCK'
  AND required_evidence_keys='[]'::jsonb
  AND fail_condition #>> '{NO_NEW_URLS,execution_sql}' LIKE '%''MEDIA''%';

-- Governed apply readback must prove exactly two target rows changed and no other scope changed.
-- Do not create/bind the two judges before contract readback is PASS.
