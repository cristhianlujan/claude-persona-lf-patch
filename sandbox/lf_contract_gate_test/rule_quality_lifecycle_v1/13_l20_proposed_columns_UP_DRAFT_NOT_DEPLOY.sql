-- LOTE 20 - PROPOSAL ONLY / NOT AUTHORIZED FOR LIVE DEPLOY.
-- Actual LF/SALY schemas inspected via read-only SELECT 2026-11-12.
-- Run ONLY against a disposable PG18 replica/fixture, through CI tests.
-- Does NOT implement production synchronization or authorizations.
-- Review the actual source owners, triggers, policies, consumers, and migration
-- naming/merge train BEFORE any potential real migration.
ALTER TABLE lf_ops.reglas
  ADD COLUMN reviewed_at timestamptz,
  ADD COLUMN next_review_at timestamptz,
  ADD COLUMN successor_rule_code text,
  ADD COLUMN effective_to timestamptz;

-- SALY.estado is a separate validation state (VALIDADO), NOT a lifecycle enum.
-- A distinct lifecycle_state is needed to distinguish expired vs superseded;
-- vigente=false alone cannot distinguish these two meanings.
ALTER TABLE saly.reglas
  ADD COLUMN reviewed_at timestamptz,
  ADD COLUMN next_review_at timestamptz,
  ADD COLUMN successor_rule_code text,
  ADD COLUMN effective_to timestamptz,
  ADD COLUMN lifecycle_state text;
