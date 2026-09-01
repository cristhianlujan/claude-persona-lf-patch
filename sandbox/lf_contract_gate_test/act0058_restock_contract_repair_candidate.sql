-- SANDBOX / SOURCE-FIRST CANDIDATE ONLY. DO NOT APPLY FROM THIS FILE.
-- Root cause matched to EKB SQL-008 + DB-EVT-001: lf_eventos.severidad accepts INFO|WARN|CRITICAL, not MEDIA.
-- Target is deliberately one exact operation/step; no broad update.
UPDATE public.lf_operation_step_contracts
SET fail_condition = jsonb_set(
      fail_condition,
      '{NO_NEW_URLS,execution_sql}',
      to_jsonb(replace(fail_condition #>> '{NO_NEW_URLS,execution_sql}', '''MEDIA''', '''WARN''')),
      false
    ),
    updated_at = now()
WHERE operation_code = 'ORQUESTACION_PIPELINE_LF'
  AND step_id = 'restock_queue'
  AND step_order = 105
  AND mini_judge_code = 'MINI_JUDGE_ACT0058_RESTOCK'
  AND fail_condition #>> '{NO_NEW_URLS,execution_sql}' LIKE '%''MEDIA''%';

-- Required readback after governed application:
-- 1) exactly one row changed;
-- 2) execution_sql contains severity='WARN';
-- 3) execution_sql contains no severity='MEDIA';
-- 4) no other operation_code/step_id changed;
-- 5) only after this readback may MINI_JUDGE_ACT0058_RESTOCK be materialized/bound.
