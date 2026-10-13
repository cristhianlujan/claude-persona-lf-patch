-- LF_MIGRATION_RECONCILIATION_SOURCE_V1
-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY
-- owner_binding_required=true
-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF
-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER
-- source_authority=supabase_migrations.schema_migrations
-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-BATCH2-20261013-001
-- source_version=20261011021429
-- source_name=t_remed_function_comments_v1
do $c$
declare r record; v_old text; v_new text; v_purpose text; v_effects text;
begin
  for r in
    select p.oid, p.proname, p.provolatile, pg_get_function_identity_arguments(p.oid) idargs,
           pg_get_function_arguments(p.oid) args, pg_get_function_result(p.oid) res,
           d.description old
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    left join pg_description d on d.objoid=p.oid and d.classoid='pg_proc'::regclass and d.objsubid=0
    where n.nspname='programacion' and p.proname like 'fn\_t\_remed\_%' and p.prokind='f'
  loop
    v_old := r.old;
    if v_old like 'LF_METADATA_V1%' then continue; end if;
    v_purpose := coalesce(nullif(btrim(v_old),''), 'SIN DESCRIPCION PREVIA (funcion heredada, sin documentar; candidata a retiro o a documentarse por su autor)');
    v_effects := case r.provolatile when 'v' then 'puede escribir (VOLATILE); revisar su PURPOSE antes de llamarla' else 'solo lectura (STABLE/IMMUTABLE), no modifica datos' end;
    v_new := 'LF_METADATA_V1 | PURPOSE: '||v_purpose
          ||' INPUTS: '||case when r.args='' then 'ninguno' else r.args end
          ||'. OUTPUT: '||r.res
          ||'. EFFECTS: '||v_effects
          ||'. FAMILY: T-REMED (cierre de brechas de Input Governance; ver docs/t-remed/README.md)'
          ||'. USAGE: select * from programacion.'||r.proname||'('||case when r.args='' then '' else '...' end||');';
    execute format('comment on function programacion.%I(%s) is %L', r.proname, r.idargs, v_new);
  end loop;
end
$c$;
