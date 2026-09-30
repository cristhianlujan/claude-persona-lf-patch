
-- LF Global Technical Inventory - Wiring/bootstrap v1

-- External inventory policy:
-- Repository snapshots and Supabase Edge Runtime state are intentionally NOT hardcoded
-- into database migrations. They are time/environment-specific evidence and must be
-- synchronized by an authorized external sync process after migration application.
-- This keeps Git-first migrations reproducible across DEV/QA/PROD.


insert into inventory.tags(tag_code,tag_type,description) values
('PAYMENTS','DOMAIN','Payments, Niubiz and collection-related technical objects'),
('PROFILE','DOMAIN','Profile creation/update/runtime technical objects'),
('ROUTER','CAPABILITY','Routing and entrypoint technical objects'),
('PLAN','CAPABILITY','Engineering plan and planning technical objects'),
('ASSURANCE','CAPABILITY','Assurance, qualification and review technical objects'),
('PASE','CAPABILITY','Pase / controlled promotion technical objects'),
('AWS_INFRA','DOMAIN','AWS, Terraform and infrastructure technical objects'),
('GLOBAL_INVENTORY','DISCOVERY','LF global technical inventory capability'),
('DEPENDENCY_GRAPH','DISCOVERY','Technical dependency graph capability'),
('TECHNICAL_CATALOG','DISCOVERY','Technical object catalog capability')
on conflict(tag_code) do nothing;

insert into public.lf_activos(
  codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,
  estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
  accion_migracion,version,ruta_esperada,url,owner_name,rol_arquitectura,
  source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,
  migration_batch_id,raw_payload,metadata,created_by_execution_id,updated_by_execution_id
)
values(
  'LF_GLOBAL_TECHNICAL_INVENTORY_V1',
  'LF Global Technical Inventory v1',
  'CAPABILITY','TECHNICAL_INVENTORY',
  'CANDIDATO','READ_ONLY','CONTROLADO','CANDIDATE_READ_ONLY','BLOQUEADO',
  'REGISTER_GLOBAL_TECHNICAL_INVENTORY','v1',null,
  'supabase://inventory/global',
  'LF_GOVERNANCE',
  'Global discovery catalog and dependency graph for LF technical objects. Reusable by Input Governance, PLAN, audit and future processes; does not duplicate canonical business rows.',
  'SUPABASE_DIRECT_CONTROLLED_ENTRY','LF_GLOBAL_TECHNICAL_INVENTORY',
  'GLOBAL_INVENTORY_20260930',1,
  md5('LF_GLOBAL_TECHNICAL_INVENTORY_V1_20260930')::uuid,
  jsonb_build_object(
    'objects_table','inventory.objects',
    'dependencies_table','inventory.dependencies',
    'lookup','inventory.fn_lookup_v2(text,text[],integer)',
    'dependency_lookup','inventory.fn_dependencies_v1(text,text,integer)',
    'impact_lookup','inventory.fn_impact_analysis_v1(text,integer,numeric)',
    'drift_view','inventory.v_pg_catalog_drift_v1',
    'search_index','inventory.search_index'
  ),
  jsonb_build_object(
    'dominio','GLOBAL_TECHNICAL_INVENTORY',
    'inventory_status','CANDIDATE_PENDING_QUALIFICATION',
    'no_duplicate_engine',true,
    'canonical_rows_duplicated',false,
    'discovery_scope','ALL_LF_CUSTOM_SCHEMAS_PLUS_REPO_AND_GOVERNANCE_REGISTRIES',
    'consumers',jsonb_build_array('INPUT_GOVERNANCE','PLAN','AUDIT','FUTURE_PROCESSES'),
    'aliases',jsonb_build_array('inventario tecnico','global inventory','technical inventory','dependency graph','catalogo tecnico'),
    'source_of_truth','inventory schema for discovery; original objects remain canonical',
    'external_refresh_semantics','DB_AND_REGISTRIES_AUTOMATIC; REPO_AND_EDGE_RUNTIME_EXTERNAL_SYNC'
  ),
  'LF_GLOBAL_TECHNICAL_INVENTORY_V1',
  'LF_GLOBAL_TECHNICAL_INVENTORY_V1'
)
on conflict(codigo_activo) do update set
  nombre_canonico=excluded.nombre_canonico,
  tipo_activo=excluded.tipo_activo,
  subtipo_activo=excluded.subtipo_activo,
  estado_documental=excluded.estado_documental,
  estado_operativo=excluded.estado_operativo,
  version=excluded.version,
  url=excluded.url,
  owner_name=excluded.owner_name,
  rol_arquitectura=excluded.rol_arquitectura,
  raw_payload=excluded.raw_payload,
  metadata=excluded.metadata,
  updated_at=now(),
  updated_by_execution_id=excluded.updated_by_execution_id;

do $$
begin
  if to_regclass('programacion.input_source_inventory_l1') is not null then
    execute 'comment on table programacion.input_source_inventory_l1 is ''Compatibility/pilot discovery index created for Input Governance L1. Superseded for global discovery by inventory.objects + inventory.fn_lookup_v2; canonical business rows remain in original source tables.''';
  end if;
end $$;

update public.lf_activos
set metadata=jsonb_set(
  coalesce(metadata,'{}'::jsonb),
  '{global_inventory}',
  jsonb_build_object(
    'schema','inventory',
    'objects','inventory.objects',
    'dependencies','inventory.dependencies',
    'lookup','inventory.fn_lookup_v2(text,text[],integer)',
    'dependency_lookup','inventory.fn_dependencies_v1(text,text,integer)',
    'impact_lookup','inventory.fn_impact_analysis_v1(text,integer,numeric)',
    'semantics','GLOBAL_DISCOVERY_GRAPH',
    'canonical_rows_duplicated',false,
    'l1_pilot_status','SUPERSEDED_BY_GLOBAL_INVENTORY'
  ),
  true
),
updated_at=now(),
updated_by_execution_id='LF_GLOBAL_TECHNICAL_INVENTORY_V1'
where codigo_activo in (
  'EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
  'PROGRAMACION_FN_INPUT_GOVERNANCE_CANONICAL_CONTEXT_SET'
)
and archived_at is null;

-- Initial DB/registry bootstrap. External repo and Edge runtime syncs remain separate sources.
select inventory.fn_refresh_catalog_v2();
select inventory.fn_refresh_db_details_v2();
select inventory.fn_refresh_dependencies_exact_v1();
select inventory.fn_refresh_registries_v1();
select inventory.fn_finalize_refresh_v1();

-- Tags are recalculated by inventory.fn_finalize_refresh_v1() on every staged refresh.


-- Staged pg_cron maintenance avoids a single long-running refresh.
do $$
declare r record;
begin
  if to_regnamespace('cron') is not null then
    for r in
      select jobid from cron.job
      where jobname in (
        'lf-global-inventory-catalog-v2',
        'lf-global-inventory-details-v2',
        'lf-global-inventory-exact-deps-v1',
        'lf-global-inventory-static-incremental-v1',
        'lf-global-inventory-finalize-v1',
        'lf-global-inventory-refresh-v1'
      )
    loop
      perform cron.unschedule(r.jobid);
    end loop;

    perform cron.schedule(
      'lf-global-inventory-catalog-v2',
      '17 */6 * * *',
      'select inventory.fn_refresh_catalog_v2();'
    );
    perform cron.schedule(
      'lf-global-inventory-details-v2',
      '22 */6 * * *',
      'select inventory.fn_refresh_db_details_v2();'
    );
    perform cron.schedule(
      'lf-global-inventory-exact-deps-v1',
      '27 */6 * * *',
      'select inventory.fn_refresh_dependencies_exact_v1();'
    );
    perform cron.schedule(
      'lf-global-inventory-static-incremental-v1',
      '32 */6 * * *',
      'select inventory.fn_refresh_static_incremental_v1();'
    );
    perform cron.schedule(
      'lf-global-inventory-finalize-v1',
      '37 */6 * * *',
      'select inventory.fn_finalize_refresh_v1();'
    );
  end if;
end $$;
