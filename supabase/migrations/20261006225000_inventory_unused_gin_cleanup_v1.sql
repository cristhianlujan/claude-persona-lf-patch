-- Inventory GIN cleanup — audited unused indexes only.

do $pre$
declare
  v record;
  v_expected text;
begin
  for v in
    select c.relname index_name,
           pg_get_indexdef(c.oid) indexdef,
           coalesce(s.idx_scan,0) idx_scan
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    left join pg_stat_user_indexes s on s.indexrelid=c.oid
    where n.nspname='inventory'
      and c.relname in (
        'inventory_objects_metadata_gin',
        'inventory_search_tags_gin',
        'inventory_search_columns_gin'
      )
  loop
    v_expected:=case v.index_name
      when 'inventory_objects_metadata_gin'
        then 'CREATE INDEX inventory_objects_metadata_gin ON inventory.objects USING gin (metadata)'
      when 'inventory_search_tags_gin'
        then 'CREATE INDEX inventory_search_tags_gin ON inventory.search_index USING gin (tags_lc)'
      when 'inventory_search_columns_gin'
        then 'CREATE INDEX inventory_search_columns_gin ON inventory.search_index USING gin (column_names_lc)'
    end;

    if v.indexdef is distinct from v_expected then
      raise exception 'INVENTORY_GIN_DEFINITION_DRIFT index=% expected=% actual=%',
        v.index_name,v_expected,v.indexdef;
    end if;

    if v.idx_scan<>0 then
      raise exception 'INVENTORY_GIN_RUNTIME_USE_DETECTED index=% idx_scan=%',
        v.index_name,v.idx_scan;
    end if;
  end loop;

  if (
    select count(*)
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='inventory'
      and c.relname in (
        'inventory_objects_metadata_gin',
        'inventory_search_tags_gin',
        'inventory_search_columns_gin'
      )
  )<>3 then
    raise exception 'INVENTORY_GIN_INDEX_SET_INCOMPLETE';
  end if;
end;
$pre$;

drop index inventory.inventory_objects_metadata_gin;
drop index inventory.inventory_search_tags_gin;
drop index inventory.inventory_search_columns_gin;

do $post$
begin
  if to_regclass('inventory.inventory_objects_metadata_gin') is not null
     or to_regclass('inventory.inventory_search_tags_gin') is not null
     or to_regclass('inventory.inventory_search_columns_gin') is not null then
    raise exception 'INVENTORY_GIN_DROP_POSTCHECK_FAILED';
  end if;

  if to_regclass('inventory.inventory_search_document_gin') is null then
    raise exception 'INVENTORY_SEARCH_DOCUMENT_GIN_MUST_REMAIN';
  end if;
end;
$post$;
