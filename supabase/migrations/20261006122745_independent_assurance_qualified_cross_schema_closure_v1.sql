create or replace function public.lf_function_dependency_closure_qualified_v1(
  p_root_schema text,
  p_root_name text,
  p_max_depth integer default 8
)
returns text[]
language plpgsql
stable
set search_path to 'pg_catalog','public'
as $fn$
declare
  v_root text;
  v_seen text[];
  v_frontier text[];
  v_next text[];
  v_current text;
  v_schema text;
  v_name text;
  v_source text;
  v_dep text;
  v_depth integer:=0;
begin
  if nullif(btrim(coalesce(p_root_schema,'')),'') is null
     or nullif(btrim(coalesce(p_root_name,'')),'') is null
     or p_max_depth<1 or p_max_depth>16 then
    return null;
  end if;

  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname=p_root_schema and p.proname=p_root_name) <> 1 then
    return null;
  end if;

  v_root:=p_root_schema||'.'||p_root_name;
  v_seen:=array[v_root];
  v_frontier:=array[v_root];

  while cardinality(v_frontier)>0 and v_depth<p_max_depth loop
    v_next:='{}'::text[];

    foreach v_current in array v_frontier loop
      v_schema:=split_part(v_current,'.',1);
      v_name:=split_part(v_current,'.',2);

      select string_agg(lower(p.prosrc),E'\n')
        into v_source
      from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
      where n.nspname=v_schema and p.proname=v_name;

      if v_source is null then
        continue;
      end if;

      for v_dep in
        select distinct n.nspname||'.'||p.proname
        from pg_proc p
        join pg_namespace n on n.oid=p.pronamespace
        where n.nspname not like 'pg_%'
          and n.nspname<>'information_schema'
          and (
            position(lower(n.nspname)||'.'||lower(p.proname)||'(' in v_source)>0
            or (
              n.nspname=v_schema
              and position(lower(p.proname)||'(' in v_source)>0
            )
          )
        order by 1
      loop
        if not v_dep=any(v_seen) then
          v_seen:=array_append(v_seen,v_dep);
          v_next:=array_append(v_next,v_dep);
        end if;
      end loop;
    end loop;

    v_frontier:=v_next;
    v_depth:=v_depth+1;
  end loop;

  return array(
    select x
    from unnest(v_seen) x
    where x<>v_root
    order by x
  );
end
$fn$;

create or replace function public.lf_independent_assurance_measure_v1(
  p_dependency_schema text,
  p_producer_root text,
  p_reviewer_root text,
  p_max_depth integer default 8,
  p_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
set search_path to 'pg_catalog','public','extensions'
as $fn$
declare
  v_producer_deps text[] := '{}'::text[];
  v_reviewer_deps text[] := '{}'::text[];
  v_shared text[] := '{}'::text[];
  v_exceptions text[] := '{}'::text[];
  v_unknown_exceptions text[] := '{}'::text[];
  v_unresolved text[] := '{}'::text[];
  v_producer_data text[] := '{}'::text[];
  v_reviewer_data text[] := '{}'::text[];
  v_shared_data text[] := '{}'::text[];
  v_dependency_state text;
  v_data_state text := 'UNPROVEN';
  v_author_state text := 'UNPROVEN';
  v_overall_state text;
  v_producer_author text;
  v_reviewer_author text;
  v_dependency_digest text;
  v_reviewer_digest text;
  v_cross_schema boolean;
  v_producer_schema text;
  v_producer_name text;
  v_reviewer_schema text;
  v_reviewer_name text;
begin
  if nullif(btrim(coalesce(p_dependency_schema,'')),'') is null
     or nullif(btrim(coalesce(p_producer_root,'')),'') is null
     or nullif(btrim(coalesce(p_reviewer_root,'')),'') is null
     or p_max_depth < 1 or p_max_depth > 16
     or p_context is null or jsonb_typeof(p_context) <> 'object' then
    return jsonb_build_object(
      'schema_version','LF_INDEPENDENT_ASSURANCE_MEASURE_V1',
      'state','BLOCKED','code','MEASURE_INPUT_INVALID'
    );
  end if;

  v_cross_schema :=
    position('.' in p_producer_root)>0
    or position('.' in p_reviewer_root)>0;

  if v_cross_schema then
    if p_producer_root !~ '^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*$'
       or p_reviewer_root !~ '^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*$' then
      return jsonb_build_object(
        'schema_version','LF_INDEPENDENT_ASSURANCE_MEASURE_V1',
        'state','BLOCKED','code','QUALIFIED_ROOTS_BOTH_REQUIRED'
      );
    end if;

    v_producer_schema:=split_part(p_producer_root,'.',1);
    v_producer_name:=split_part(p_producer_root,'.',2);
    v_reviewer_schema:=split_part(p_reviewer_root,'.',1);
    v_reviewer_name:=split_part(p_reviewer_root,'.',2);

    v_producer_deps:=public.lf_function_dependency_closure_qualified_v1(
      v_producer_schema,v_producer_name,p_max_depth
    );
    v_reviewer_deps:=public.lf_function_dependency_closure_qualified_v1(
      v_reviewer_schema,v_reviewer_name,p_max_depth
    );

    if v_producer_deps is null or v_reviewer_deps is null then
      return jsonb_build_object(
        'schema_version','LF_INDEPENDENT_ASSURANCE_MEASURE_V1',
        'state','BLOCKED','code','ROOT_FUNCTION_NOT_UNIQUE_OR_MISSING',
        'producer_root',p_producer_root,'reviewer_root',p_reviewer_root
      );
    end if;
  else
    if not exists (select 1 from pg_namespace where nspname=p_dependency_schema) then
      return jsonb_build_object(
        'schema_version','LF_INDEPENDENT_ASSURANCE_MEASURE_V1',
        'state','BLOCKED','code','DEPENDENCY_SCHEMA_NOT_FOUND',
        'dependency_schema',p_dependency_schema
      );
    end if;

    if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname=p_dependency_schema and p.proname=p_producer_root) <> 1
       or (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname=p_dependency_schema and p.proname=p_reviewer_root) <> 1 then
      return jsonb_build_object(
        'schema_version','LF_INDEPENDENT_ASSURANCE_MEASURE_V1',
        'state','BLOCKED','code','ROOT_FUNCTION_NOT_UNIQUE_OR_MISSING',
        'producer_root',p_producer_root,'reviewer_root',p_reviewer_root
      );
    end if;

    with recursive
    funcs as (
      select p.proname collate "C" as proname, lower(p.prosrc) collate "C" as src
      from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
      where n.nspname=p_dependency_schema
    ),
    roots(root_name) as (
      values (p_producer_root::text collate "C"), (p_reviewer_root::text collate "C")
    ),
    walk(root_name,fn_name,depth,path) as (
      select r.root_name,r.root_name,0,array[r.root_name]::text[] from roots r
      union all
      select w.root_name,d.proname,w.depth+1,w.path||d.proname
      from walk w
      join funcs s on s.proname=w.fn_name
      join funcs d on position(lower(d.proname)||'(' in s.src)>0
      where w.depth<p_max_depth and not d.proname=any(w.path)
    )
    select
      coalesce(array_agg(distinct fn_name order by fn_name)
        filter (where root_name=p_producer_root and depth>0),'{}'::text[]),
      coalesce(array_agg(distinct fn_name order by fn_name)
        filter (where root_name=p_reviewer_root and depth>0),'{}'::text[])
    into v_producer_deps,v_reviewer_deps
    from walk;
  end if;

  if p_context ? 'adjudicated_dependency_exceptions'
     and jsonb_typeof(p_context->'adjudicated_dependency_exceptions') <> 'array' then
    return jsonb_build_object('schema_version','LF_INDEPENDENT_ASSURANCE_MEASURE_V1','state','BLOCKED','code','EXCEPTIONS_NOT_ARRAY');
  end if;
  if p_context ? 'producer_data_refs' and jsonb_typeof(p_context->'producer_data_refs') <> 'array' then
    return jsonb_build_object('schema_version','LF_INDEPENDENT_ASSURANCE_MEASURE_V1','state','BLOCKED','code','PRODUCER_DATA_REFS_NOT_ARRAY');
  end if;
  if p_context ? 'reviewer_data_refs' and jsonb_typeof(p_context->'reviewer_data_refs') <> 'array' then
    return jsonb_build_object('schema_version','LF_INDEPENDENT_ASSURANCE_MEASURE_V1','state','BLOCKED','code','REVIEWER_DATA_REFS_NOT_ARRAY');
  end if;

  select coalesce(array_agg(x order by x),'{}'::text[])
    into v_shared
  from (
    select unnest(v_producer_deps) x
    intersect
    select unnest(v_reviewer_deps) x
  ) q;

  if p_context ? 'adjudicated_dependency_exceptions' then
    select coalesce(array_agg(distinct v order by v),'{}'::text[])
      into v_exceptions
    from jsonb_array_elements_text(p_context->'adjudicated_dependency_exceptions') t(v);
  end if;

  select coalesce(array_agg(x order by x),'{}'::text[])
    into v_unknown_exceptions
  from (
    select unnest(v_exceptions) x
    except
    select unnest(v_shared) x
  ) q;

  if cardinality(v_unknown_exceptions)>0 then
    return jsonb_build_object(
      'schema_version','LF_INDEPENDENT_ASSURANCE_MEASURE_V1',
      'state','BLOCKED','code','UNBOUND_ADJUDICATED_EXCEPTION',
      'unknown_exceptions',to_jsonb(v_unknown_exceptions)
    );
  end if;

  select coalesce(array_agg(x order by x),'{}'::text[])
    into v_unresolved
  from (
    select unnest(v_shared) x
    except
    select unnest(v_exceptions) x
  ) q;

  v_dependency_state := case when cardinality(v_unresolved)=0 then 'INDEPENDENT' else 'NOT_INDEPENDENT' end;

  if p_context ? 'producer_data_refs' and p_context ? 'reviewer_data_refs' then
    select coalesce(array_agg(distinct v order by v),'{}'::text[])
      into v_producer_data from jsonb_array_elements_text(p_context->'producer_data_refs') t(v);
    select coalesce(array_agg(distinct v order by v),'{}'::text[])
      into v_reviewer_data from jsonb_array_elements_text(p_context->'reviewer_data_refs') t(v);
    select coalesce(array_agg(x order by x),'{}'::text[])
      into v_shared_data
    from (
      select unnest(v_producer_data) x
      intersect
      select unnest(v_reviewer_data) x
    ) q;
    v_data_state := case when cardinality(v_shared_data)=0 then 'INDEPENDENT' else 'NOT_INDEPENDENT' end;
  end if;

  v_producer_author := nullif(btrim(coalesce(p_context->>'producer_author_ref','')),'');
  v_reviewer_author := nullif(btrim(coalesce(p_context->>'reviewer_author_ref','')),'');
  if v_producer_author is not null and v_reviewer_author is not null then
    v_author_state := case when v_producer_author is distinct from v_reviewer_author then 'INDEPENDENT' else 'NOT_INDEPENDENT' end;
  end if;

  if 'NOT_INDEPENDENT'=any(array[v_dependency_state,v_data_state,v_author_state]) then
    v_overall_state := 'NOT_INDEPENDENT';
  elsif v_dependency_state='INDEPENDENT' and v_data_state='INDEPENDENT' and v_author_state='INDEPENDENT' then
    v_overall_state := 'INDEPENDENT';
  else
    v_overall_state := 'UNPROVEN';
  end if;

  v_dependency_digest := encode(extensions.digest(convert_to(to_jsonb(v_producer_deps)::text,'UTF8'),'sha256'),'hex');
  v_reviewer_digest := encode(extensions.digest(convert_to(to_jsonb(v_reviewer_deps)::text,'UTF8'),'sha256'),'hex');

  return jsonb_build_object(
    'schema_version','LF_INDEPENDENT_ASSURANCE_MEASURE_V1',
    'state',v_overall_state,
    'method',case when v_cross_schema then 'PG_PROC_STATIC_CLOSURE_QUALIFIED_V1' else 'PG_PROC_STATIC_CLOSURE_V1' end,
    'limitations',case when v_cross_schema
      then jsonb_build_array('NO_DYNAMIC_SQL','NO_EDGE_RUNTIME_CALL_GRAPH','UNQUALIFIED_CROSS_SCHEMA_SEARCH_PATH_CALLS_NOT_RESOLVED')
      else jsonb_build_array('NO_DYNAMIC_SQL','NO_EDGE_RUNTIME_CALL_GRAPH','FUNCTION_NAME_MATCH_WITHIN_DECLARED_SCHEMA')
    end,
    'dependency_schema',case when v_cross_schema then 'QUALIFIED_ROOTS' else p_dependency_schema end,
    'max_depth',p_max_depth,
    'producer_root',p_producer_root,
    'reviewer_root',p_reviewer_root,
    'dependency_dimension',jsonb_build_object(
      'state',v_dependency_state,
      'producer_dependency_count',cardinality(v_producer_deps),
      'reviewer_dependency_count',cardinality(v_reviewer_deps),
      'shared_dependency_count',cardinality(v_shared),
      'unresolved_shared_dependency_count',cardinality(v_unresolved),
      'adjudicated_exception_count',cardinality(v_exceptions),
      'producer_dependency_digest',v_dependency_digest,
      'reviewer_dependency_digest',v_reviewer_digest,
      'shared_dependencies',to_jsonb(v_shared),
      'unresolved_shared_dependencies',to_jsonb(v_unresolved),
      'adjudicated_dependency_exceptions',to_jsonb(v_exceptions)
    ),
    'data_dimension',jsonb_build_object(
      'state',v_data_state,'shared_data_refs',to_jsonb(v_shared_data)
    ),
    'author_dimension',jsonb_build_object(
      'state',v_author_state,
      'producer_author_ref',v_producer_author,
      'reviewer_author_ref',v_reviewer_author
    ),
    'criterion','INDEPENDENT only when dependency overlap after adjudicated exceptions is zero AND data sources are disjoint AND producer/reviewer author identities are distinct; any proven shared dimension => NOT_INDEPENDENT; missing data/author evidence => UNPROVEN unless another dimension is already NOT_INDEPENDENT'
  );
end
$fn$;