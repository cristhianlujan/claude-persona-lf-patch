-- PR #93 / LOTE-E.6 final integrity addendum. SELECT-only.
-- Closes CA-N77 to CA-N83 without changing the audited 25-vector readback.

with expected_binder as (
  select
    '3927d2b5bc724f10d5f3db09ad204e3212060c30242ccab7b9501869d6396293'::text
      as prosrc_sha256
),
required_dependencies as (
  select
    pg_catalog.to_regprocedure('extensions.digest(bytea,text)') is not null
      as digest_available,
    pg_catalog.to_regprocedure('private.fn_bind_gate_writer_nonce_v7()') is not null
      as binder_available,
    pg_catalog.to_regrole('lf_governance_owner_v3') is not null
      as governance_owner_available
),
binder_definition as (
  select (
    select pg_catalog.encode(
      extensions.digest(pg_catalog.convert_to(p.prosrc,'UTF8'),'sha256'),
      'hex'
    )
    from pg_catalog.pg_proc p
    where p.oid=pg_catalog.to_regprocedure(
      'private.fn_bind_gate_writer_nonce_v7()'
    )
  ) as prosrc_sha256
),
gate_trigger_check as (
  select
    count(*)=1 as present,
    coalesce(pg_catalog.bool_and(t.tgenabled='A'),false) as enabled_always,
    coalesce(pg_catalog.bool_and(
      (t.tgtype & 2)=2
      and (t.tgtype & 4)=4
      and (t.tgtype & 16)=16
    ),false) as before_insert_update,
    coalesce(pg_catalog.bool_and((t.tgtype & 1)=1),false) as for_each_row,
    coalesce(pg_catalog.bool_and(t.tgqual is null),false) as without_when_clause,
    coalesce(pg_catalog.bool_and(
      t.tgattr=''::pg_catalog.int2vector
    ),false) as all_update_columns,
    coalesce(pg_catalog.bool_and(
      t.tgfoid=pg_catalog.to_regprocedure(
        'private.fn_bind_gate_writer_nonce_v7()'
      )
    ),false) as binds_pinned_function,
    coalesce(pg_catalog.bool_and(
      p.proowner=pg_catalog.to_regrole('lf_governance_owner_v3')
    ),false) as function_owner_is_governance,
    min(pg_catalog.pg_get_userbyid(p.proowner)) as function_owner
  from pg_catalog.pg_trigger t
  join pg_catalog.pg_class c on c.oid=t.tgrelid
  join pg_catalog.pg_namespace n on n.oid=c.relnamespace
  join pg_catalog.pg_proc p on p.oid=t.tgfoid
  where n.nspname='private'
    and c.relname='lf_gate_test_runs_v3'
    and t.tgname='trg_05_bind_gate_writer_nonce_v7'
    and not t.tgisinternal
),
table_trigger_inventory as (
  select
    count(*) filter (
      where not t.tgisinternal
        and (t.tgtype & 2)=2
        and (
          (t.tgtype & 4)=4
          or (t.tgtype & 16)=16
        )
    ) as before_insert_update_count,
    coalesce(
      pg_catalog.jsonb_agg(t.tgname order by t.tgname) filter (
        where not t.tgisinternal
          and (t.tgtype & 2)=2
          and (
            (t.tgtype & 4)=4
            or (t.tgtype & 16)=16
          )
      ),
      '[]'::jsonb
    ) as before_insert_update_names
  from pg_catalog.pg_trigger t
  join pg_catalog.pg_class c on c.oid=t.tgrelid
  join pg_catalog.pg_namespace n on n.oid=c.relnamespace
  where n.nspname='private'
    and c.relname='lf_gate_test_runs_v3'
)
select pg_catalog.jsonb_build_object(
  'dependencies',pg_catalog.jsonb_build_object(
    'digest_available',required_dependencies.digest_available,
    'binder_available',required_dependencies.binder_available,
    'governance_owner_available',
      required_dependencies.governance_owner_available,
    'all_present',(
      required_dependencies.digest_available
      and required_dependencies.binder_available
      and required_dependencies.governance_owner_available
    )
  ),
  'binder_definition_digest',pg_catalog.jsonb_build_object(
    'expected',expected_binder.prosrc_sha256,
    'actual',binder_definition.prosrc_sha256,
    'matches',coalesce(
      binder_definition.prosrc_sha256=expected_binder.prosrc_sha256,
      false
    )
  ),
  'gate_trigger',pg_catalog.jsonb_build_object(
    'present',gate_trigger_check.present,
    'enabled_always',gate_trigger_check.enabled_always,
    'before_insert_update',gate_trigger_check.before_insert_update,
    'for_each_row',gate_trigger_check.for_each_row,
    'without_when_clause',gate_trigger_check.without_when_clause,
    'all_update_columns',gate_trigger_check.all_update_columns,
    'binds_pinned_function',gate_trigger_check.binds_pinned_function,
    'function_owner_is_governance',
      gate_trigger_check.function_owner_is_governance,
    'function_owner',gate_trigger_check.function_owner
  ),
  'table_trigger_inventory',pg_catalog.jsonb_build_object(
    'before_insert_update_count',
      table_trigger_inventory.before_insert_update_count,
    'before_insert_update_names',
      table_trigger_inventory.before_insert_update_names,
    'only_expected_before_insert_update',(
      table_trigger_inventory.before_insert_update_count=1
      and table_trigger_inventory.before_insert_update_names
          =pg_catalog.jsonb_build_array('trg_05_bind_gate_writer_nonce_v7')
    )
  ),
  'binder_and_trigger_integrity',(
    required_dependencies.digest_available
    and required_dependencies.binder_available
    and required_dependencies.governance_owner_available
    and coalesce(
      binder_definition.prosrc_sha256=expected_binder.prosrc_sha256,
      false
    )
    and gate_trigger_check.present
    and gate_trigger_check.enabled_always
    and gate_trigger_check.before_insert_update
    and gate_trigger_check.for_each_row
    and gate_trigger_check.without_when_clause
    and gate_trigger_check.all_update_columns
    and gate_trigger_check.binds_pinned_function
    and gate_trigger_check.function_owner_is_governance
    and table_trigger_inventory.before_insert_update_count=1
    and table_trigger_inventory.before_insert_update_names
        =pg_catalog.jsonb_build_array('trg_05_bind_gate_writer_nonce_v7')
  ),
  'required_primary_readback_fields',pg_catalog.jsonb_build_array(
    'definition_checks.binder_preserves_persisted_effects=true',
    'definition_checks.binder_definition_digest.matches=true',
    'definition_checks.binder_mutation_pattern_controls.all_pass=true',
    'gate_trigger.binds_pinned_function=true'
  )
) as pr93_lote_e6_final_integrity_readback
from expected_binder
cross join required_dependencies
cross join binder_definition
cross join gate_trigger_check
cross join table_trigger_inventory;
