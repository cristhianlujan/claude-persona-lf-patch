-- PROFILE_OPERATION_COMMON_RECORDER_V1
-- MIGRATION SOURCE CANDIDATE / NOT APPLIED
-- Canonical source: skills/profile_creator/contracts/profile_operation_common_recorder_v1.sql
-- Q3: durable BLOCKED evidence after truthful execution+step+binding identity resolution.
-- Missing required evidence is represented with explicit null placeholders in BLOCKED snapshots only;
-- evidence audits MUST require non-null values and MUST NOT use key-presence alone as proof.

\ir ../../skills/profile_creator/contracts/profile_operation_common_recorder_v1.sql

-- IMPORTANT: this migration source is intentionally not applied by this commit.
-- Before live materialization, expand this file to inline the canonical function body because
-- Supabase remote migration execution does not resolve repository-relative psql \\ir includes.
-- Keeping this source candidate fail-closed prevents accidental partial deployment.
