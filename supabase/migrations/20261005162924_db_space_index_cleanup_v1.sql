-- DB-SPACE / PR-IDX-1 — INDEX CLEANUP v1
-- Prepared only. Do not apply without owner approval.
-- Regular DROP INDEX is intentional: this change is kept in one versioned migration,
-- and DROP INDEX CONCURRENTLY cannot run inside a transaction block.
-- Every index below is preflighted to ensure it does not back or serve a constraint.

do $siblings$
declare
  v_pair record;
  v_drop regclass;
  v_keep regclass;
  v_drop_idx pg_index%rowtype;
  v_keep_idx pg_index%rowtype;
  v_drop_relam oid;
  v_keep_relam oid;
begin
  for v_pair in
    select *
    from (values
      ('public.uq_lf_operation_execution_steps_execution_order','public.lf_operation_execution_steps_pkey'),
      ('public.uq_lf_operation_steps_operation_step','public.lf_operation_steps_operation_code_step_id_key'),
      ('public.uq_lf_operation_steps_operation_order','public.lf_operation_steps_pkey'),
      ('public.uq_lf_operation_judges_operation_judge','public.lf_operation_judges_pkey'),
      ('lf_ops.idx_rp_pantalla','lf_ops.idx_reglas_pantallas_screen'),
      ('lf_ops.ux_perfiles_permisos_numeric','lf_ops.perfiles_permisos_pkey_numeric'),
      ('lf_ops.idx_campos_pant_pant','lf_ops.idx_campos_pantallas_screen'),
      ('lf_ops.ux_user_number','lf_ops.empresa_usuarios_user_number_uk'),
      ('lf_ops.ux_usuarios_perfiles_numeric','lf_ops.empresa_usuarios_perfiles_pkey_numeric'),
      ('lf_ops.ux_usuarios_permisos_numeric','lf_ops.empresa_usuarios_permisos_pkey_numeric'),
      ('lf_ops.ux_company_number','lf_ops.empresas_company_number_uk'),
      ('lf_ops.ux_trace_number','lf_ops.errores_ocurrencias_trace_number_uk'),
      ('lf_ops.ux_transiciones_numeric','lf_ops.estados_transiciones_pkey_numeric'),
      ('lf_ops.ux_menu_permisos_numeric','lf_ops.menu_items_permisos_pkey_numeric'),
      ('lf_ops.ux_alert_numeric','lf_ops.observabilidad_alertas_pkey_numeric'),
      ('lf_ops.ux_variant_numeric','lf_ops.pantalla_variantes_pkey_numeric'),
      ('lf_ops.ux_pantallas_perfiles_numeric','lf_ops.pantallas_perfiles_pkey_numeric'),
      ('lf_ops.ux_pantallas_permisos_numeric','lf_ops.pantallas_permisos_pkey_numeric'),
      ('lf_ops.ux_approval_number','lf_ops.aprobaciones_registros_approval_number_uk'),
      ('lf_ops.idx_audit_events_load','lf_ops.idx_auditoria_load_time'),
      ('lf_ops.ux_audit_number','lf_ops.auditoria_eventos_audit_number_uk'),
      ('lf_ops.ux_file_number','lf_ops.cargas_archivos_file_number_uk'),
      ('lf_ops.ux_load_number','lf_ops.cargas_lotes_load_number_uk'),
      ('lf_design.ux_icon_catalog_numeric','lf_design.icon_catalog_pkey_numeric'),
      ('lf_design.ux_visual_decisions_numeric','lf_design.visual_decisions_pkey_numeric')
    ) as p(drop_name,keep_name)
  loop
    v_drop := to_regclass(v_pair.drop_name);
    v_keep := to_regclass(v_pair.keep_name);

    if v_drop is null or v_keep is null then
      raise exception 'PR_IDX_1_SIBLING_MISSING:%=>%',v_pair.drop_name,v_pair.keep_name;
    end if;

    select * into v_drop_idx from pg_index where indexrelid=v_drop;
    select * into v_keep_idx from pg_index where indexrelid=v_keep;
    select relam into v_drop_relam from pg_class where oid=v_drop;
    select relam into v_keep_relam from pg_class where oid=v_keep;

    if not coalesce(v_keep_idx.indisvalid,false)
       or not coalesce(v_keep_idx.indisready,false)
       or v_drop_idx.indkey is distinct from v_keep_idx.indkey
       or v_drop_idx.indclass is distinct from v_keep_idx.indclass
       or v_drop_idx.indoption is distinct from v_keep_idx.indoption
       or v_drop_idx.indcollation is distinct from v_keep_idx.indcollation
       or v_drop_idx.indpred is distinct from v_keep_idx.indpred
       or v_drop_idx.indexprs is distinct from v_keep_idx.indexprs
       or v_drop_idx.indisunique is distinct from v_keep_idx.indisunique
       or v_drop_idx.indnkeyatts is distinct from v_keep_idx.indnkeyatts
       or v_drop_idx.indnatts is distinct from v_keep_idx.indnatts
       or v_drop_relam is distinct from v_keep_relam then
      raise exception 'PR_IDX_1_SIBLING_NOT_EQUIVALENT:%=>%',v_pair.drop_name,v_pair.keep_name;
    end if;
  end loop;
end;
$siblings$;

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
