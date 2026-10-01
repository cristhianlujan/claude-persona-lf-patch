-- LF Global Technical Inventory - canonical skill artifact projection v1
-- Extends LF_GLOBAL_TECHNICAL_INVENTORY_V1. No new inventory authority is created.
-- Canonical artifact state remains private.lf_skill_artifacts; inventory is discovery/projection only.

create or replace function inventory.fn_refresh_skill_artifacts_v1()
returns jsonb
language plpgsql
security invoker
set search_path=inventory,public,private,pg_catalog
as $$
declare
  v_start timestamptz := clock_timestamp();
  v_binding_errors jsonb;
  v_projected bigint;
  v_retired bigint;
  v_owner_edges bigint;
  v_materialization_edges bigint;
begin
  -- Fail closed if a canonical skill_code cannot resolve to exactly one active SKILL asset.
  with skills as (
    select distinct s.skill_code
    from private.lf_skill_artifacts s
    where s.is_current
  ), bindings as (
    select
      s.skill_code,
      count(a.id) as asset_count,
      array_agg(a.codigo_activo order by a.codigo_activo)
        filter (where a.codigo_activo is not null) as asset_codes
    from skills s
    left join public.lf_activos a
      on a.archived_at is null
     and a.tipo_activo='SKILL'
     and (
       a.nombre_canonico=s.skill_code
       or a.metadata->>'skill_code'=s.skill_code
       or a.ruta_esperada='skills/'||s.skill_code||'/SKILL.md'
       or a.ruta_esperada='skills/'||s.skill_code||'/'
     )
    group by s.skill_code
  )
  select jsonb_agg(
    jsonb_build_object(
      'skill_code',skill_code,
      'asset_count',asset_count,
      'asset_codes',coalesce(to_jsonb(asset_codes),'[]'::jsonb)
    ) order by skill_code
  )
  into v_binding_errors
  from bindings
  where asset_count<>1;

  if v_binding_errors is not null then
    return jsonb_build_object(
      'status','BLOCKED_SKILL_ASSET_BINDING',
      'binding_errors',v_binding_errors,
      'writes',0,
      'duration_ms',round(extract(epoch from clock_timestamp()-v_start)*1000)
    );
  end if;

  -- Project each current canonical skill artifact as a searchable inventory object.
  insert into inventory.objects(
    object_ref,object_type,object_name,domain,source_system,source_of_truth,status,
    definition_sha256,source_version,metadata,last_seen_at,updated_at,active
  )
  select
    'artifact://skill/'||s.skill_code||'/'||s.artifact_code,
    'SKILL_ARTIFACT',
    s.artifact_code,
    'SKILL',
    'LF_SKILL_ARTIFACTS',
    true,
    s.artifact_status,
    s.content_sha256,
    s.version::text,
    jsonb_build_object(
      'artifact_id',s.id,
      'skill_code',s.skill_code,
      'artifact_code',s.artifact_code,
      'relative_path',s.relative_path,
      'artifact_type',s.artifact_type,
      'classification',s.classification,
      'validation_status',s.validation_status,
      'dependencies',s.dependencies,
      'source_refs',s.source_refs,
      'canonical_relation','private.lf_skill_artifacts',
      'is_current',true
    ),
    now(),now(),true
  from private.lf_skill_artifacts s
  where s.is_current
  on conflict(object_ref) do update set
    object_type=excluded.object_type,
    object_name=excluded.object_name,
    domain=excluded.domain,
    source_system=excluded.source_system,
    source_of_truth=excluded.source_of_truth,
    status=excluded.status,
    definition_sha256=excluded.definition_sha256,
    source_version=excluded.source_version,
    metadata=excluded.metadata,
    last_seen_at=now(),
    active=true,
    updated_at=now();

  get diagnostics v_projected=row_count;

  -- Retire projections whose canonical row is no longer current. Never delete history.
  update inventory.objects o
  set active=false,
      status='SUPERSEDED_OR_NOT_CURRENT',
      updated_at=now()
  where o.active
    and o.source_system='LF_SKILL_ARTIFACTS'
    and o.object_type='SKILL_ARTIFACT'
    and not exists (
      select 1
      from private.lf_skill_artifacts s
      where s.is_current
        and o.object_ref='artifact://skill/'||s.skill_code||'/'||s.artifact_code
    );

  get diagnostics v_retired=row_count;

  -- Rebuild only this projection family's edges. Other dependency sources are untouched.
  update inventory.dependencies
  set active=false,last_verified_at=now()
  where active
    and source_system='LF_SKILL_ARTIFACTS'
    and relation_type in ('OWNS_ARTIFACT','MATERIALIZES_AS');

  -- Asset -> canonical artifact ownership.
  insert into inventory.dependencies(
    dependency_key,source_object_id,target_object_id,target_ref,relation_type,evidence_type,
    evidence,confidence,source_system,metadata,last_verified_at,active
  )
  select
    'SKILL_OWNER|'||asset.object_id||'|'||artifact.object_id,
    asset.object_id,
    artifact.object_id,
    artifact.object_ref,
    'OWNS_ARTIFACT',
    'CANONICAL_REGISTRY_BINDING',
    'private.lf_skill_artifacts current row bound to unique active SKILL asset',
    1.0,
    'LF_SKILL_ARTIFACTS',
    jsonb_build_object(
      'skill_code',s.skill_code,
      'artifact_id',s.id,
      'artifact_code',s.artifact_code,
      'relative_path',s.relative_path
    ),
    now(),true
  from private.lf_skill_artifacts s
  join public.lf_activos a
    on a.archived_at is null
   and a.tipo_activo='SKILL'
   and (
     a.nombre_canonico=s.skill_code
     or a.metadata->>'skill_code'=s.skill_code
     or a.ruta_esperada='skills/'||s.skill_code||'/SKILL.md'
     or a.ruta_esperada='skills/'||s.skill_code||'/'
   )
  join inventory.objects asset
    on asset.object_ref='asset://'||a.codigo_activo
   and asset.active
  join inventory.objects artifact
    on artifact.object_ref='artifact://skill/'||s.skill_code||'/'||s.artifact_code
   and artifact.active
  where s.is_current
  on conflict(dependency_key) do update set
    source_object_id=excluded.source_object_id,
    target_object_id=excluded.target_object_id,
    target_ref=excluded.target_ref,
    relation_type=excluded.relation_type,
    evidence_type=excluded.evidence_type,
    evidence=excluded.evidence,
    confidence=excluded.confidence,
    source_system=excluded.source_system,
    metadata=excluded.metadata,
    last_verified_at=now(),
    active=true;

  get diagnostics v_owner_edges=row_count;

  -- Canonical artifact -> repository materialization. Repository objects are snapshots,
  -- therefore they remain non-authoritative even when the canonical artifact points to them.
  insert into inventory.dependencies(
    dependency_key,source_object_id,target_object_id,target_ref,relation_type,evidence_type,
    evidence,confidence,source_system,metadata,last_verified_at,active
  )
  select
    'SKILL_MATERIALIZATION|'||artifact.object_id||'|'||md5(repo_ref.repo_object_ref),
    artifact.object_id,
    repo_object.object_id,
    repo_ref.repo_object_ref,
    'MATERIALIZES_AS',
    case when nullif(s.source_refs->>'repo_path','') is not null
      then 'CANONICAL_ARTIFACT_REPO_PATH'
      else 'DETERMINISTIC_SKILL_PATH'
    end,
    repo_ref.repo_object_ref,
    case when nullif(s.source_refs->>'repo_path','') is not null then 1.0 else 0.95 end,
    'LF_SKILL_ARTIFACTS',
    jsonb_build_object(
      'skill_code',s.skill_code,
      'artifact_id',s.id,
      'artifact_code',s.artifact_code,
      'relative_path',s.relative_path,
      'repo_object_present',repo_object.object_id is not null
    ),
    now(),true
  from private.lf_skill_artifacts s
  join inventory.objects artifact
    on artifact.object_ref='artifact://skill/'||s.skill_code||'/'||s.artifact_code
   and artifact.active
  cross join lateral (
    select 'repo://'||coalesce(
      nullif(s.source_refs->>'repo_path',''),
      'skills/'||s.skill_code||'/'||s.relative_path
    ) as repo_object_ref
  ) repo_ref
  left join inventory.objects repo_object
    on repo_object.object_ref=repo_ref.repo_object_ref
   and repo_object.active
  where s.is_current
  on conflict(dependency_key) do update set
    source_object_id=excluded.source_object_id,
    target_object_id=excluded.target_object_id,
    target_ref=excluded.target_ref,
    relation_type=excluded.relation_type,
    evidence_type=excluded.evidence_type,
    evidence=excluded.evidence,
    confidence=excluded.confidence,
    source_system=excluded.source_system,
    metadata=excluded.metadata,
    last_verified_at=now(),
    active=true;

  get diagnostics v_materialization_edges=row_count;

  return jsonb_build_object(
    'status','COMPLETED',
    'projected_current_artifacts',(select count(*) from inventory.objects where active and source_system='LF_SKILL_ARTIFACTS' and object_type='SKILL_ARTIFACT'),
    'canonical_current_artifacts',(select count(*) from private.lf_skill_artifacts where is_current),
    'retired_projections',v_retired,
    'owner_edges',(select count(*) from inventory.dependencies where active and source_system='LF_SKILL_ARTIFACTS' and relation_type='OWNS_ARTIFACT'),
    'materialization_edges',(select count(*) from inventory.dependencies where active and source_system='LF_SKILL_ARTIFACTS' and relation_type='MATERIALIZES_AS'),
    'materialization_targets_missing',(select count(*) from inventory.dependencies where active and source_system='LF_SKILL_ARTIFACTS' and relation_type='MATERIALIZES_AS' and target_object_id is null),
    'duration_ms',round(extract(epoch from clock_timestamp()-v_start)*1000)
  );
end;
$$;

comment on function inventory.fn_refresh_skill_artifacts_v1() is
'Projects current private.lf_skill_artifacts rows into the global discovery inventory and binds each canonical artifact to its owning SKILL asset and repository materialization. Does not change canonical artifact state.';

-- Extend the existing staged finalizer; do not create a parallel scheduler or inventory engine.
create or replace function inventory.fn_finalize_refresh_v1()
returns jsonb
language plpgsql
security invoker
set search_path=inventory,pg_catalog
as $$
declare
  v_start timestamptz:=clock_timestamp();
  v_reg jsonb;
  v_skill_artifacts jsonb;
  v_tags jsonb;
  v_indexed bigint;
begin
  v_reg := inventory.fn_refresh_registries_v1();
  v_skill_artifacts := inventory.fn_refresh_skill_artifacts_v1();

  if coalesce(v_skill_artifacts->>'status','') <> 'COMPLETED' then
    raise exception using
      errcode='P0001',
      message='GLOBAL_INVENTORY_SKILL_ARTIFACT_PROJECTION_BLOCKED',
      detail=v_skill_artifacts::text;
  end if;

  v_tags := inventory.fn_refresh_tags_v1();
  v_indexed := inventory.fn_refresh_search_index_v1();

  insert into inventory.snapshots(
    snapshot_code,source_system,scope,started_at,completed_at,status,
    object_count,dependency_count,metadata
  )
  values(
    'LF_AUTO_REFRESH_'||to_char(v_start at time zone 'UTC','YYYYMMDDHH24MISSMS'),
    'INVENTORY_STAGED_REFRESH_V1','DATABASE_AND_REGISTRIES',
    v_start,clock_timestamp(),'COMPLETED',
    (select count(*) from inventory.objects where active),
    (select count(*) from inventory.dependencies where active),
    jsonb_build_object(
      'registries',v_reg,
      'skill_artifacts',v_skill_artifacts,
      'tags',v_tags,
      'search_index_objects',v_indexed,
      'pg_catalog_drift',(select count(*) from inventory.v_pg_catalog_drift_v1),
      'external_repo_sync_included',false,
      'edge_runtime_sync_included',false
    )
  );

  return jsonb_build_object(
    'status','COMPLETED',
    'objects',(select count(*) from inventory.objects where active),
    'dependencies',(select count(*) from inventory.dependencies where active),
    'skill_artifacts',v_skill_artifacts,
    'search_index_objects',v_indexed,
    'pg_catalog_drift',(select count(*) from inventory.v_pg_catalog_drift_v1),
    'duration_ms',round(extract(epoch from clock_timestamp()-v_start)*1000)
  );
end;
$$;
