-- AUD-1 UNIVERSE FREEZE V1
-- Read-only. Bound to:
-- main_sha=dafe10a6a730d63bc59ce036360f214cd6fd8d96
-- schema_fp=56c2af889d3f6a4781b1ac74ba7da5bb
--
-- Produces database universe denominators only. Repository universe is emitted by aud01_repo_universe_v1.py.
select jsonb_build_object(
  'freeze',jsonb_build_object(
    'schema_column_count',(
      select count(*) from information_schema.columns
      where table_schema in ('public','private')
    ),
    'schema_fp',(
      select md5(string_agg(
        table_schema||'.'||table_name||'.'||column_name||':'||data_type,
        '|' order by table_schema,table_name,ordinal_position
      ))
      from information_schema.columns
      where table_schema in ('public','private')
    )
  ),
  'assets',jsonb_build_object(
    'total',(select count(*) from public.lf_activos),
    'non_archived',(select count(*) from public.lf_activos where archived_at is null),
    'by_type',(
      select jsonb_object_agg(tipo_activo,n)
      from (
        select tipo_activo,count(*) n
        from public.lf_activos
        where archived_at is null
        group by tipo_activo
      ) s
    )
  ),
  'operations',jsonb_build_object(
    'registry',(select count(*) from public.lf_operation_registry),
    'operational',(select count(*) from public.lf_operation_registry where lifecycle_state_code='OP_OPERATIONAL'),
    'steps',(select count(*) from public.lf_operation_steps),
    'active_steps',(select count(*) from public.lf_operation_steps where active),
    'step_contracts',(select count(*) from public.lf_operation_step_contracts),
    'judge_bindings',(select count(*) from public.lf_operation_step_judge_bindings),
    'policy_bindings',(select count(*) from public.lf_operation_policy_bindings)
  ),
  'strategy_programming',jsonb_build_object(
    'strategy_snapshots_non_archived',(select count(*) from public.lf_strategy_snapshots where archived_at is null),
    'programacion_tables',(select count(*) from information_schema.tables where table_schema='programacion' and table_type='BASE TABLE'),
    'programacion_views',(select count(*) from information_schema.views where table_schema='programacion'),
    'programacion_functions',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='programacion' and p.prokind='f'),
    'task_dependencies',(select count(*) from programacion.task_dependencies)
  ),
  'capabilities',jsonb_build_object(
    'operational_view',(select count(*) from public.v_lf_fuente_operativa where tipo_activo='CAPABILITY'),
    'registry',(select count(*) from public.lf_capability_registry),
    'bindings',(select count(*) from public.lf_capability_binding)
  ),
  'knowledge',jsonb_build_object(
    'ekb',(select count(*) from public.lf_error_knowledge),
    'prevention_rules',(select count(*) from public.lf_prevention_rules),
    'best_practices',(select count(*) from public.lf_best_practices),
    'decision_log',(select count(*) from public.lf_decision_log)
  ),
  'assurance',jsonb_build_object(
    'claims',(select count(*) from public.lf_assurance_claim_catalog),
    'obligations',(select count(*) from public.lf_assurance_obligation_catalog),
    'defeaters',(select count(*) from public.lf_assurance_defeater_catalog),
    'subject_bindings',(select count(*) from public.lf_assurance_subject_bindings),
    'evaluations',(select count(*) from public.lf_assurance_evaluations)
  ),
  'database_objects',jsonb_build_object(
    'public_private_tables',(select count(*) from information_schema.tables where table_schema in ('public','private') and table_type='BASE TABLE'),
    'public_private_views',(select count(*) from information_schema.views where table_schema in ('public','private')),
    'public_private_functions',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.prokind='f'),
    'public_private_procedures',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.prokind='p')
  ),
  'operational_view',jsonb_build_object(
    'rows',(select count(*) from public.v_lf_fuente_operativa),
    'duplicate_codes',(
      select count(*) from (
        select codigo_activo from public.v_lf_fuente_operativa
        group by codigo_activo having count(*)>1
      ) d
    ),
    'version_cleanup_required',(select count(*) from public.v_lf_fuente_operativa where requiere_limpieza_version),
    'missing_owner',(select count(*) from public.v_lf_fuente_operativa where nullif(btrim(coalesce(owner_name,'')),'') is null),
    'missing_url',(select count(*) from public.v_lf_fuente_operativa where nullif(btrim(coalesce(url,'')),'') is null)
  )
) as aud01_database_universe;
