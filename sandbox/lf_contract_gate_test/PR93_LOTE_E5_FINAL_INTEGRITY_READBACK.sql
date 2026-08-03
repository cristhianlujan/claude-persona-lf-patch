-- PR #93 / LOTE-E.7 final integrity addendum. SELECT-only.
-- Closes CA-N84 to CA-N88 without changing the audited 25-vector readback.

with expected_binder as (
  select
    '3927d2b5bc724f10d5f3db09ad204e3212060c30242ccab7b9501869d6396293'::pg_catalog.text
      as prosrc_sha256
),
required_dependencies as (
  select
    pg_catalog.to_regprocedure(
      'extensions.digest(pg_catalog.bytea,pg_catalog.text)'
    ) is not null
      as primary_digest_available,
    pg_catalog.to_regprocedure('pg_catalog.sha256(pg_catalog.bytea)') is not null
      as core_sha256_available,
    pg_catalog.to_regprocedure('private.fn_bind_gate_writer_nonce_v7()') is not null
      as binder_available,
    pg_catalog.to_regrole('lf_governance_owner_v3') is not null
      as governance_owner_available,
    pg_catalog.to_regclass('private.lf_gate_test_runs_v3') is not null
      as gate_table_available
),
binder_definition as (
  select (
    select pg_catalog.encode(
      pg_catalog.sha256(pg_catalog.convert_to(p.prosrc,'UTF8')),
      'hex'
    )
    from pg_catalog.pg_proc p
    where p.oid OPERATOR(pg_catalog.=) pg_catalog.to_regprocedure(
      'private.fn_bind_gate_writer_nonce_v7()'
    )
  ) as prosrc_sha256
),
gate_table_state as (
  select
    pg_catalog.count(*) OPERATOR(pg_catalog.=) 1::pg_catalog.int8
      as present,
    coalesce(pg_catalog.bool_and(
      c.relkind OPERATOR(pg_catalog.=) 'r'::pg_catalog."char"
    ),false) as ordinary_table,
    coalesce(pg_catalog.bool_and(not c.relhasrules),false) as without_rules,
    coalesce(pg_catalog.bool_and(not c.relispartition),false) as not_partition,
    coalesce(pg_catalog.bool_and(not exists(
      select 1
      from pg_catalog.pg_inherits i
      where i.inhrelid OPERATOR(pg_catalog.=) c.oid
         or i.inhparent OPERATOR(pg_catalog.=) c.oid
    )),false) as without_inheritance
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n
    on n.oid OPERATOR(pg_catalog.=) c.relnamespace
  where n.nspname OPERATOR(pg_catalog.=) 'private'::pg_catalog.name
    and c.relname OPERATOR(pg_catalog.=) 'lf_gate_test_runs_v3'::pg_catalog.name
),
gate_trigger_check as (
  select
    pg_catalog.count(*) OPERATOR(pg_catalog.=) 1::pg_catalog.int8 as present,
    coalesce(pg_catalog.bool_and(
      t.tgenabled OPERATOR(pg_catalog.=) 'A'::pg_catalog."char"
    ),false) as enabled_always,
    coalesce(pg_catalog.bool_and(
      (t.tgtype OPERATOR(pg_catalog.&) 2::pg_catalog.int2)
        OPERATOR(pg_catalog.=) 2::pg_catalog.int2
      and (t.tgtype OPERATOR(pg_catalog.&) 4::pg_catalog.int2)
        OPERATOR(pg_catalog.=) 4::pg_catalog.int2
      and (t.tgtype OPERATOR(pg_catalog.&) 16::pg_catalog.int2)
        OPERATOR(pg_catalog.=) 16::pg_catalog.int2
    ),false) as before_insert_update,
    coalesce(pg_catalog.bool_and(
      (t.tgtype OPERATOR(pg_catalog.&) 1::pg_catalog.int2)
        OPERATOR(pg_catalog.=) 1::pg_catalog.int2
    ),false) as for_each_row,
    coalesce(pg_catalog.bool_and(t.tgqual is null),false) as without_when_clause,
    coalesce(pg_catalog.bool_and(
      t.tgattr OPERATOR(pg_catalog.=) ''::pg_catalog.int2vector
    ),false) as all_update_columns,
    coalesce(pg_catalog.bool_and(
      t.tgfoid OPERATOR(pg_catalog.=) pg_catalog.to_regprocedure(
        'private.fn_bind_gate_writer_nonce_v7()'
      )
    ),false) as binds_pinned_function,
    coalesce(pg_catalog.bool_and(
      p.proowner OPERATOR(pg_catalog.=)
        pg_catalog.to_regrole('lf_governance_owner_v3')
    ),false) as function_owner_is_governance,
    pg_catalog.min(pg_catalog.pg_get_userbyid(p.proowner)) as function_owner
  from pg_catalog.pg_trigger t
  join pg_catalog.pg_class c
    on c.oid OPERATOR(pg_catalog.=) t.tgrelid
  join pg_catalog.pg_namespace n
    on n.oid OPERATOR(pg_catalog.=) c.relnamespace
  join pg_catalog.pg_proc p
    on p.oid OPERATOR(pg_catalog.=) t.tgfoid
  where n.nspname OPERATOR(pg_catalog.=) 'private'::pg_catalog.name
    and c.relname OPERATOR(pg_catalog.=) 'lf_gate_test_runs_v3'::pg_catalog.name
    and t.tgname OPERATOR(pg_catalog.=)
      'trg_05_bind_gate_writer_nonce_v7'::pg_catalog.name
    and not t.tgisinternal
),
table_trigger_inventory as (
  select
    pg_catalog.count(*) filter (
      where not t.tgisinternal
        and (t.tgtype OPERATOR(pg_catalog.&) 2::pg_catalog.int2)
          OPERATOR(pg_catalog.=) 2::pg_catalog.int2
        and (
          (t.tgtype OPERATOR(pg_catalog.&) 4::pg_catalog.int2)
            OPERATOR(pg_catalog.=) 4::pg_catalog.int2
          or (t.tgtype OPERATOR(pg_catalog.&) 16::pg_catalog.int2)
            OPERATOR(pg_catalog.=) 16::pg_catalog.int2
        )
    ) as before_insert_update_count,
    coalesce(
      pg_catalog.jsonb_agg(t.tgname order by t.tgname) filter (
        where not t.tgisinternal
          and (t.tgtype OPERATOR(pg_catalog.&) 2::pg_catalog.int2)
            OPERATOR(pg_catalog.=) 2::pg_catalog.int2
          and (
            (t.tgtype OPERATOR(pg_catalog.&) 4::pg_catalog.int2)
              OPERATOR(pg_catalog.=) 4::pg_catalog.int2
            or (t.tgtype OPERATOR(pg_catalog.&) 16::pg_catalog.int2)
              OPERATOR(pg_catalog.=) 16::pg_catalog.int2
          )
      ),
      '[]'::pg_catalog.jsonb
    ) as before_insert_update_names
  from pg_catalog.pg_trigger t
  join pg_catalog.pg_class c
    on c.oid OPERATOR(pg_catalog.=) t.tgrelid
  join pg_catalog.pg_namespace n
    on n.oid OPERATOR(pg_catalog.=) c.relnamespace
  where n.nspname OPERATOR(pg_catalog.=) 'private'::pg_catalog.name
    and c.relname OPERATOR(pg_catalog.=) 'lf_gate_test_runs_v3'::pg_catalog.name
)
select pg_catalog.jsonb_build_object(
  'dependencies',pg_catalog.jsonb_build_object(
    'primary_digest_available',required_dependencies.primary_digest_available,
    'core_sha256_available',required_dependencies.core_sha256_available,
    'binder_available',required_dependencies.binder_available,
    'governance_owner_available',
      required_dependencies.governance_owner_available,
    'gate_table_available',required_dependencies.gate_table_available,
    'all_present',(
      required_dependencies.primary_digest_available
      and required_dependencies.core_sha256_available
      and required_dependencies.binder_available
      and required_dependencies.governance_owner_available
      and required_dependencies.gate_table_available
    )
  ),
  'binder_definition_digest',pg_catalog.jsonb_build_object(
    'expected',expected_binder.prosrc_sha256,
    'actual',binder_definition.prosrc_sha256,
    'matches',coalesce(
      binder_definition.prosrc_sha256
        OPERATOR(pg_catalog.=) expected_binder.prosrc_sha256,
      false
    )
  ),
  'gate_table',pg_catalog.jsonb_build_object(
    'present',gate_table_state.present,
    'ordinary_table',gate_table_state.ordinary_table,
    'without_rules',gate_table_state.without_rules,
    'not_partition',gate_table_state.not_partition,
    'without_inheritance',gate_table_state.without_inheritance
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
      table_trigger_inventory.before_insert_update_count
        OPERATOR(pg_catalog.=) 1::pg_catalog.int8
      and table_trigger_inventory.before_insert_update_names
        OPERATOR(pg_catalog.=) pg_catalog.jsonb_build_array(
          'trg_05_bind_gate_writer_nonce_v7'
        )
    )
  ),
  'binder_and_trigger_integrity',(
    required_dependencies.primary_digest_available
    and required_dependencies.core_sha256_available
    and required_dependencies.binder_available
    and required_dependencies.governance_owner_available
    and required_dependencies.gate_table_available
    and coalesce(
      binder_definition.prosrc_sha256
        OPERATOR(pg_catalog.=) expected_binder.prosrc_sha256,
      false
    )
    and gate_table_state.present
    and gate_table_state.ordinary_table
    and gate_table_state.without_rules
    and gate_table_state.not_partition
    and gate_table_state.without_inheritance
    and gate_trigger_check.present
    and gate_trigger_check.enabled_always
    and gate_trigger_check.before_insert_update
    and gate_trigger_check.for_each_row
    and gate_trigger_check.without_when_clause
    and gate_trigger_check.all_update_columns
    and gate_trigger_check.binds_pinned_function
    and gate_trigger_check.function_owner_is_governance
    and table_trigger_inventory.before_insert_update_count
      OPERATOR(pg_catalog.=) 1::pg_catalog.int8
    and table_trigger_inventory.before_insert_update_names
      OPERATOR(pg_catalog.=) pg_catalog.jsonb_build_array(
        'trg_05_bind_gate_writer_nonce_v7'
      )
  ),
  'required_primary_readback_fields',pg_catalog.jsonb_build_array(
    'definition_checks.binder_preserves_persisted_effects=true',
    'definition_checks.binder_definition_digest.matches=true',
    'definition_checks.binder_mutation_pattern_controls.all_pass=true',
    'gate_trigger.binds_pinned_function=true'
  )
) as pr93_lote_e7_final_integrity_readback
from expected_binder
cross join required_dependencies
cross join binder_definition
cross join gate_table_state
cross join gate_trigger_check
cross join table_trigger_inventory;
