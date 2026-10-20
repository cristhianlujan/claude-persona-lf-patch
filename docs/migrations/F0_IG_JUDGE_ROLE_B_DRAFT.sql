-- F0 DRAFT ONLY — DO NOT RUN. Not deployable until transitive RPC and PR SQL restrictions are audited.
-- Restricted reader foundation for future IG judge role B (current judge stays postgres temporarily).
-- NOTE: "read only" would break reversible IG writes; privileges alone cannot sandbox untrusted SQL.
BEGIN;
CREATE ROLE lf_ig_judge LOGIN PASSWORD '<GENERATE_IN_SECRET_MANAGER>'
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT CONNECT ON DATABASE postgres TO lf_ig_judge;
GRANT USAGE ON SCHEMA programacion TO lf_ig_judge;
GRANT SELECT ON TABLE
  programacion.input_readiness_runs,
  programacion.input_family_assessments,
  programacion.input_validator_chunk_timings
TO lf_ig_judge;
ALTER ROLE lf_ig_judge SET statement_timeout = '30s';
ALTER ROLE lf_ig_judge SET lock_timeout = '5s';
COMMIT;

-- Additional grant candidates PENDING EXACT SIGNATURE AND TRANSITIVE BODY REVIEW:
-- EXECUTE on IG judge's execute/curator_materialize/validator_validate functions.
-- DML on per-run IG fixture tables only if proven required, never on migration ledger.
-- DO NOT GRANT CREATE ON SCHEMA, GRANT ALL, broad EXECUTE, or membership in postgres.
-- Must prohibit SECURITY DEFINER PUBLIC escape and dynamic server/network/file functions.
-- This ROLE B draft DOES NOT yet support full judge operation and is NOT the immediate cutover.
-- Rollback plan, only after no callers/objects depend on it:
-- ALTER ROLE lf_ig_judge NOLOGIN;
-- REVOKE SELECT ON TABLE programacion.input_readiness_runs,
--   programacion.input_family_assessments,programacion.input_validator_chunk_timings FROM lf_ig_judge;
-- REVOKE USAGE ON SCHEMA programacion FROM lf_ig_judge;
-- REVOKE CONNECT ON DATABASE postgres FROM lf_ig_judge;
-- DROP ROLE lf_ig_judge;
