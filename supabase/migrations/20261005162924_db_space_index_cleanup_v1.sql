-- DB-SPACE / PR-IDX-1 — INDEX CLEANUP v1
-- Prepared only. Do not apply without owner approval.
-- Regular DROP INDEX is intentional: this change is kept in one versioned migration,
-- and DROP INDEX CONCURRENTLY cannot run inside a transaction block.
-- Every index below is preflighted to ensure it does not back or serve a constraint.

do $pre$
declare
  v_index regclass;
  v_name text;
begin
  foreach v_name in array array[
    'public.uq_lf_operation_execution_steps_execution_order',
    'public.uq_lf_operation_steps_operation_step',
    'public.uq_lf_operation_steps_operation_order',
    'public.uq_lf_operation_judges_operation_judge',
    'lf_ops.idx_rp_pantalla',
    'lf_ops.ux_perfiles_permisos_numeric',
    'lf_ops.idx_campos_pant_pant',
    'lf_ops.ux_user_number',
    'lf_ops.ux_usuarios_perfiles_numeric',
    'lf_ops.ux_usuarios_permisos_numeric',
    'lf_ops.ux_company_number',
    'lf_ops.ux_trace_number',
    'lf_ops.ux_transiciones_numeric',
    'lf_ops.ux_menu_permisos_numeric',
    'lf_ops.ux_alert_numeric',
    'lf_ops.ux_variant_numeric',
    'lf_ops.ux_pantallas_perfiles_numeric',
    'lf_ops.ux_pantallas_permisos_numeric',
    'lf_ops.ux_approval_number',
    'lf_ops.idx_audit_events_load',
    'lf_ops.ux_audit_number',
    'lf_ops.ux_file_number',
    'lf_ops.ux_load_number',
    'lf_design.ux_icon_catalog_numeric',
    'lf_design.ux_visual_decisions_numeric',
    'public.idx_lf_strategy_snapshots_payload',
    'public.idx_lf_strategy_snapshots_metadata',
    'public.ix_lf_backlog_errores_metadata_gin'
  ]
  loop
    v_index := to_regclass(v_name);
    if v_index is null then
      raise exception 'PR_IDX_1_INDEX_MISSING:%',v_name;
    end if;

    if exists (
      select 1 from pg_constraint c where c.conindid=v_index
    ) then
      raise exception 'PR_IDX_1_INDEX_BACKS_CONSTRAINT:%',v_name;
    end if;

    if exists (
      select 1
      from pg_depend d
      join pg_constraint c
        on c.oid=d.objid
       and d.classid='pg_constraint'::regclass
      where d.refobjid=v_index
    ) then
      raise exception 'PR_IDX_1_CONSTRAINT_DEPENDS_ON_INDEX:%',v_name;
    end if;
  end loop;
end;
$pre$;

-- Exact duplicates: preserve the sibling that backs a constraint or the canonical-named sibling.
drop index if exists public.uq_lf_operation_execution_steps_execution_order;
drop index if exists public.uq_lf_operation_steps_operation_step;
drop index if exists public.uq_lf_operation_steps_operation_order;
drop index if exists public.uq_lf_operation_judges_operation_judge;

drop index if exists lf_ops.idx_rp_pantalla;
drop index if exists lf_ops.ux_perfiles_permisos_numeric;
drop index if exists lf_ops.idx_campos_pant_pant;
drop index if exists lf_ops.ux_user_number;
drop index if exists lf_ops.ux_usuarios_perfiles_numeric;
drop index if exists lf_ops.ux_usuarios_permisos_numeric;
drop index if exists lf_ops.ux_company_number;
drop index if exists lf_ops.ux_trace_number;
drop index if exists lf_ops.ux_transiciones_numeric;
drop index if exists lf_ops.ux_menu_permisos_numeric;
drop index if exists lf_ops.ux_alert_numeric;
drop index if exists lf_ops.ux_variant_numeric;
drop index if exists lf_ops.ux_pantallas_perfiles_numeric;
drop index if exists lf_ops.ux_pantallas_permisos_numeric;
drop index if exists lf_ops.ux_approval_number;
drop index if exists lf_ops.idx_audit_events_load;
drop index if exists lf_ops.ux_audit_number;
drop index if exists lf_ops.ux_file_number;
drop index if exists lf_ops.ux_load_number;

drop index if exists lf_design.ux_icon_catalog_numeric;
drop index if exists lf_design.ux_visual_decisions_numeric;

-- GINs with no demonstrated code consumer on current main/live DB.
drop index if exists public.idx_lf_strategy_snapshots_payload;
drop index if exists public.idx_lf_strategy_snapshots_metadata;
drop index if exists public.ix_lf_backlog_errores_metadata_gin;
