-- PR #93 / LOTE-E.7 dependency preflight. SELECT-only.
-- Execute before PR93_LOTE_E5_FINAL_INTEGRITY_READBACK.sql.

with dependencies as (
  select
    pg_catalog.to_regprocedure(
      'extensions.digest(pg_catalog.bytea,pg_catalog.text)'
    ) is not null as primary_digest_available,
    pg_catalog.to_regprocedure(
      'pg_catalog.sha256(pg_catalog.bytea)'
    ) is not null as core_sha256_available,
    pg_catalog.to_regprocedure('private.fn_bind_gate_writer_nonce_v7()')
      is not null as binder_available,
    pg_catalog.to_regrole('lf_governance_owner_v3') is not null
      as governance_owner_available,
    pg_catalog.to_regclass('private.lf_gate_test_runs_v3') is not null
      as gate_table_available
)
select pg_catalog.jsonb_build_object(
  'primary_digest_available',dependencies.primary_digest_available,
  'core_sha256_available',dependencies.core_sha256_available,
  'binder_available',dependencies.binder_available,
  'governance_owner_available',dependencies.governance_owner_available,
  'gate_table_available',dependencies.gate_table_available,
  'all_present',(
    dependencies.primary_digest_available
    and dependencies.core_sha256_available
    and dependencies.binder_available
    and dependencies.governance_owner_available
    and dependencies.gate_table_available
  )
) as pr93_lote_e7_dependency_preflight
from dependencies;
