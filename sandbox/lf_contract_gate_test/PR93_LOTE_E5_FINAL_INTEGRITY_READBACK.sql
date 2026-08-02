-- PR #93 / LOTE-E.5 final integrity addendum. SELECT-only.
-- This addendum closes CA-N74 without changing the already audited 25-vector readback.

with expected_binder as (
  select
    '3927d2b5bc724f10d5f3db09ad204e3212060c30242ccab7b9501869d6396293'::text
      as prosrc_sha256
),
binder_definition as (
  select (
    select encode(
      extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),
      'hex'
    )
    from pg_proc p
    where p.oid=to_regprocedure('private.fn_bind_gate_writer_nonce_v7()')
  ) as prosrc_sha256
),
gate_trigger_check as (
  select
    count(*)=1 as present,
    coalesce(bool_and(t.tgenabled='A'),false) as enabled_always,
    coalesce(bool_and(
      (t.tgtype & 2)=2
      and (t.tgtype & 4)=4
      and (t.tgtype & 16)=16
    ),false) as before_insert_update,
    coalesce(bool_and(
      t.tgfoid=to_regprocedure('private.fn_bind_gate_writer_nonce_v7()')
    ),false) as binds_pinned_function,
    min(pg_get_userbyid(p.proowner)) as function_owner
  from pg_trigger t
  join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  join pg_proc p on p.oid=t.tgfoid
  where n.nspname='private'
    and c.relname='lf_gate_test_runs_v3'
    and t.tgname='trg_05_bind_gate_writer_nonce_v7'
    and not t.tgisinternal
)
select jsonb_build_object(
  'binder_definition_digest',jsonb_build_object(
    'expected',expected_binder.prosrc_sha256,
    'actual',binder_definition.prosrc_sha256,
    'matches',coalesce(
      binder_definition.prosrc_sha256=expected_binder.prosrc_sha256,
      false
    )
  ),
  'gate_trigger',jsonb_build_object(
    'present',gate_trigger_check.present,
    'enabled_always',gate_trigger_check.enabled_always,
    'before_insert_update',gate_trigger_check.before_insert_update,
    'binds_pinned_function',gate_trigger_check.binds_pinned_function,
    'function_owner',gate_trigger_check.function_owner
  ),
  'binder_and_trigger_integrity',(
    coalesce(
      binder_definition.prosrc_sha256=expected_binder.prosrc_sha256,
      false
    )
    and gate_trigger_check.present
    and gate_trigger_check.enabled_always
    and gate_trigger_check.before_insert_update
    and gate_trigger_check.binds_pinned_function
  ),
  'required_primary_readback_fields',jsonb_build_array(
    'definition_checks.binder_preserves_persisted_effects=true',
    'definition_checks.binder_definition_digest.matches=true',
    'definition_checks.binder_mutation_pattern_controls.all_pass=true',
    'gate_trigger.binds_pinned_function=true'
  )
) as pr93_lote_e5_final_integrity_readback
from expected_binder
cross join binder_definition
cross join gate_trigger_check;
