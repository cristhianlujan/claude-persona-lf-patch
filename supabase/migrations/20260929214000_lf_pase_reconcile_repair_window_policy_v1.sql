-- Documentation-only migration marker for PASE repair-window reconciliation policy.
-- No DDL/DML: canonical database state is unchanged.
-- The active Edge reconciler and Pooler fallback must consume
-- pase_repair_window_required_checks_empty during PASE_REPAIR_WINDOW.
select 1;
