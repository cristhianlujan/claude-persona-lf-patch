-- Option C canary: no-op migration to prove the Merge Train opens, records and
-- closes its own ACTUALIZACION_DB_LF execution. No schema or data change.
SELECT 1 AS lf_train_execution_canary_v1;
