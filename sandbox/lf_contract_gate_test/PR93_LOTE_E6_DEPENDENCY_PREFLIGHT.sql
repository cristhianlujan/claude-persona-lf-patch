-- PR #93 / LOTE-E.6 dependency preflight. SELECT-only.
-- Execute before PR93_LOTE_E5_FINAL_INTEGRITY_READBACK.sql.

with dependencies as (
  select
    pg_catalog.to_regprocedure('extensions.digest(bytea,text)') is not null
      as digest_available,
    pg_catalog.to_regprocedure('private.fn_bind_gate_writer_nonce_v7()') is not null
      as binder_available,
    pg_catalog.to_regrole('lf_governance_owner_v3') is not null
      as governance_owner_available,
    pg_catalog.to_regclass('private.lf_gate_test_runs_v3') is not null
      as gate_table_available
)
select pg_catalog.jsonb_build_object(
  'digest_available',dependencies.digest_available,
  'binder_available',dependencies.binder_available,
  'governance_owner_available',dependencies.governance_owner_available,
  'gate_table_available',dependencies.gate_table_available,
  'all_present',(
    dependencies.digest_available
    and dependencies.binder_available
    and dependencies.governance_owner_available
    and dependencies.gate_table_available
  )
) as pr93_lote_e6_dependency_preflight
from dependencies;
