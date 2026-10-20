-- Router: ACT-0001
-- Operation: ACTUALIZACION_DB_LF
-- Scope: enable RLS on 19 LF/custom internal tables currently lacking it.
-- Intent: defense in depth. No FORCE RLS, no DML, no policy widening.
-- RLS-001: policyless internal tables remain deny-by-default unless a legitimate reader requires an explicit policy.

begin;

do $pre$
declare
  v_missing text;
begin
  with targets(schema_name, table_name) as (
    values
      ('programacion','engineering_checkpoint_closure_providers_v1'),
      ('programacion','input_validator_compaction_checkpoint_v1'),
      ('programacion','input_validator_compaction_verification_receipt_v2'),
      ('programacion','programming_checkpoint_bindings'),
      ('programacion','programming_resolution_receipts'),
      ('programacion','programming_resolver_registry'),
      ('programacion','programming_simple_run_units'),
      ('programacion','programming_simple_runs'),
      ('programacion','programming_validation_registry'),
      ('private','lf_db_size_snapshots_v1'),
      ('private','lf_decision_context_asof_v1'),
      ('private','lf_human_decision_receipts_v1'),
      ('private','lf_human_decision_requests_v1'),
      ('private','lf_orchestrator_dispatch_receipts_v1'),
      ('private','lf_post_pase_waivers'),
      ('private','lf_r5e_vacuum_control_v1'),
      ('private','lf_r5e_vacuum_table_receipts_v1'),
      ('inventory','baseline_sync_items'),
      ('inventory','baseline_sync_runs')
  )
  select string_agg(format('%I.%I', t.schema_name, t.table_name), ', ' order by t.schema_name,t.table_name)
    into v_missing
  from targets t
  where to_regclass(format('%I.%I', t.schema_name, t.table_name)) is null;

  if v_missing is not null then
    raise exception 'RLS_HARDENING_TARGET_MISSING:%', v_missing;
  end if;
end
$pre$;

alter table programacion.engineering_checkpoint_closure_providers_v1 enable row level security;
alter table programacion.input_validator_compaction_checkpoint_v1 enable row level security;
alter table programacion.input_validator_compaction_verification_receipt_v2 enable row level security;
alter table programacion.programming_checkpoint_bindings enable row level security;
alter table programacion.programming_resolution_receipts enable row level security;
alter table programacion.programming_resolver_registry enable row level security;
alter table programacion.programming_simple_run_units enable row level security;
alter table programacion.programming_simple_runs enable row level security;
alter table programacion.programming_validation_registry enable row level security;

alter table private.lf_db_size_snapshots_v1 enable row level security;
alter table private.lf_decision_context_asof_v1 enable row level security;
alter table private.lf_human_decision_receipts_v1 enable row level security;
alter table private.lf_human_decision_requests_v1 enable row level security;
alter table private.lf_orchestrator_dispatch_receipts_v1 enable row level security;
alter table private.lf_post_pase_waivers enable row level security;
alter table private.lf_r5e_vacuum_control_v1 enable row level security;
alter table private.lf_r5e_vacuum_table_receipts_v1 enable row level security;

alter table inventory.baseline_sync_items enable row level security;
alter table inventory.baseline_sync_runs enable row level security;

do $post$
declare
  v_failed text;
begin
  with targets(schema_name, table_name) as (
    values
      ('programacion','engineering_checkpoint_closure_providers_v1'),
      ('programacion','input_validator_compaction_checkpoint_v1'),
      ('programacion','input_validator_compaction_verification_receipt_v2'),
      ('programacion','programming_checkpoint_bindings'),
      ('programacion','programming_resolution_receipts'),
      ('programacion','programming_resolver_registry'),
      ('programacion','programming_simple_run_units'),
      ('programacion','programming_simple_runs'),
      ('programacion','programming_validation_registry'),
      ('private','lf_db_size_snapshots_v1'),
      ('private','lf_decision_context_asof_v1'),
      ('private','lf_human_decision_receipts_v1'),
      ('private','lf_human_decision_requests_v1'),
      ('private','lf_orchestrator_dispatch_receipts_v1'),
      ('private','lf_post_pase_waivers'),
      ('private','lf_r5e_vacuum_control_v1'),
      ('private','lf_r5e_vacuum_table_receipts_v1'),
      ('inventory','baseline_sync_items'),
      ('inventory','baseline_sync_runs')
  )
  select string_agg(format('%I.%I', t.schema_name, t.table_name), ', ' order by t.schema_name,t.table_name)
    into v_failed
  from targets t
  join pg_namespace n on n.nspname=t.schema_name
  join pg_class c on c.relnamespace=n.oid
                 and c.relname=t.table_name
                 and c.relkind in ('r','p')
  where not c.relrowsecurity
     or c.relforcerowsecurity;

  if v_failed is not null then
    raise exception 'RLS_HARDENING_POSTCONDITION_FAILED:%', v_failed;
  end if;
end
$post$;

commit;
