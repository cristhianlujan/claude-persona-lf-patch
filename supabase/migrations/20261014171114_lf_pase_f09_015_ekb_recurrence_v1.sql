select public.lf_write_pipeline_ekb_v1(
  p_operation_code => 'ACTUALIZACION_DB_LF',
  p_error => jsonb_build_object(
    'codigo', 'IG-M9-3-DESIGN-SQL-ERROR-HIDDEN-001',
    'evidencia', $evidence$
Occurrence A — run 38564499676, event 20902, execution EXEC-DB-TRAIN-PR2617-20261014123227-R38564499676: the step "Apply exact version and ledger readback" ended as APPLY_FAILED_BEFORE_LEDGER_EFFECT. The persisted Train receipt has neither SQLSTATE nor the original database message.

Occurrence B — run 38599831560, PR #2632 first attempt, execution EXEC-DB-TRAIN-PR2632-20261014163600-R38599831560: the Train receipt reported EXACT_APPLY_FALLBACK_FAILED without SQLSTATE. Postgres logs at 2026-10-14 16:39:21 UTC show SQLSTATE 23514 from private.fn_enforce_lf_event_type_contract_v2: "operational-event/v2 envelope invalid or declares acceptance: PLAN_SNAPSHOT_DETALLADO". The exact database error was available only in Postgres logs, not in the Train receipt.
$evidence$,
    'source_context', 'IG_CURATOR_VALIDATOR_REFACTOR_V2 M9.3 / PASE-ATOM-F09-015 Fase C / 2026-10-14',
    'source_ref', 'github://cristhianlujan/claude-persona-lf-patch/actions/runs/38564499676; github://cristhianlujan/claude-persona-lf-patch/actions/runs/38599831560',
    'lote_origen', 'IG_M9_3',
    'pr', '2632'
  ),
  p_execution_id => 'EXEC-DB-TRAIN-PR2617-20261014123227-R38564499676'
);
