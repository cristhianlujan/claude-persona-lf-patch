-- DRAFT ONLY. Never run on LF_SUPABASE_SANDBOX without authorization.
-- Admission direct SELECT evidence: lf_independent_change_admission_carrier_v1.py:325-363
-- Parity direct SELECT evidence: run_migration_source_parity_flow_v1.py:331-343
-- m93 readback: full_pipeline_shadow_runner.py:108-132, 248-279
-- NOTE: excluded dynamic EXECUTE on public.get_lf_repository_governance_bundle_v4()
-- until SECURITY DEFINER/volatility/body and grants are examined.
BEGIN;
CREATE ROLE lf_ci_readonly LOGIN PASSWORD '<CREATE_NEW_RANDOM_SECRET>'
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT CONNECT ON DATABASE postgres TO lf_ci_readonly;
GRANT USAGE ON SCHEMA public, programacion, supabase_migrations TO lf_ci_readonly;
GRANT SELECT ON TABLE
  supabase_migrations.schema_migrations,
  public.lf_operation_execution,
  public.lf_operation_execution_steps,
  public.v_lf_operation_execution_judge,
  programacion.v_input_governance_representative_cohort_v1,
  programacion.input_readiness_runs,
  programacion.input_family_assessments,
  programacion.input_validator_chunk_timings
TO lf_ci_readonly;
ALTER ROLE lf_ci_readonly SET default_transaction_read_only = on;
ALTER ROLE lf_ci_readonly SET statement_timeout = '30s';
ALTER ROLE lf_ci_readonly SET lock_timeout = '5s';
COMMIT;
-- Do not grant EXECUTE before inspecting function bodies and transitive calls.
-- Public routine EXECUTE may be inherited via PUBLIC; audit/revoke as needed,
-- and ensure no ownership, membership or SECURITY DEFINER escalation exists.

-- CHECKS (connect with USER=lf_ci_readonly.mhwmirqcgxxukpctffuv via pooler):
-- SELECT current_user, current_setting('default_transaction_read_only');
-- SELECT count(*) FROM supabase_migrations.schema_migrations;
-- SELECT has_table_privilege(current_user,'supabase_migrations.schema_migrations','INSERT');
-- SELECT has_table_privilege(current_user,'supabase_migrations.schema_migrations','UPDATE');
-- SELECT has_table_privilege(current_user,'supabase_migrations.schema_migrations','DELETE');
-- SELECT has_schema_privilege(current_user,'public','CREATE');
-- Expect all has_* writes false. NO live write probe without authorization.
-- Pooler port 5432 (session) / 6543 (transaction); verify account availability.

-- RECOVERY / REVOCATION (only after dep checks, NOT automatic):
-- REVOKE SELECT ON TABLE supabase_migrations.schema_migrations,
--   public.lf_operation_execution,public.lf_operation_execution_steps,
--   public.v_lf_operation_execution_judge,
--   programacion.v_input_governance_representative_cohort_v1,
--   programacion.input_readiness_runs,programacion.input_family_assessments,
--   programacion.input_validator_chunk_timings FROM lf_ci_readonly;
-- REVOKE USAGE ON SCHEMA public,programacion,supabase_migrations FROM lf_ci_readonly;
-- REVOKE CONNECT ON DATABASE postgres FROM lf_ci_readonly;
-- ALTER ROLE lf_ci_readonly NOLOGIN;
-- DROP ROLE lf_ci_readonly; -- only when no dependencies remain
