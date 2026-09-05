-- LF transversal policy inheritance root fix v1.
-- Exact production source staged in Main before migration-ledger materialization.
-- This file contains no transaction wrapper and no migration-ledger INSERT.

-- 1. Materialize/verify exact candidate policy versions.
do $policy_candidates$
declare
  r record;
  v_computed text;
  v_existing_sha text;
begin
  for r in
    select * from (values
      (
        'POL-LF-POLICY-CONSUMPTION'::text,
        'v1.1-transversal-candidate'::text,
        $json${"rules":["RESOLVE_TRANSVERSAL_AND_OPERATION_POLICIES_ONCE","DISTRIBUTE_MINIMUM_REQUIRED_FIELDS","DO_NOT_LOAD_FULL_POLICY_DOCUMENTS_WHEN_SNAPSHOT_SUFFICES","POLICY_SHA_REQUIRED_FOR_READBACK","EXPLICIT_OPERATION_POLICY_EXTENDS_NOT_DUPLICATES_TRANSVERSAL"],"scope":"TRANSVERSAL_LF_GOVERNANCE","version":"v1.1-transversal-candidate","delivery":"COMPACT_RUNTIME_CAPSULE","authority":"SUPABASE","policy_kind":"POLICY_CONSUMPTION_POLICY","snapshot_view":"public.v_lf_operation_policy_snapshot","inheritance_model":"TRANSVERSAL_PLUS_OPERATION_SPECIFIC_ONCE","resolution_source":"public.v_lf_operation_policy_snapshot","adapter_second_llm_call":false,"required_runtime_fields":["operation_code","policy_code","policy_version","policy_sha","policy_payload"],"max_policy_payload_chars":1800,"single_resolution_per_operation":true}$json$::jsonb,
        'e5eb786e14a4b735e271a81b702a0a775e0bf39ba174d333531a82a0858b5553'::text
      ),
      (
        'POL-LF-SOURCE-RESOLUTION'::text,
        'v1.2-transversal-candidate'::text,
        $json${"rules":["CANONICAL_ID_BEFORE_FREE_SEARCH","REGISTERED_ALIAS_ONLY","SOURCE_OF_TRUTH_BEFORE_REPOSITORY_CONTENT","NO_SIMILARITY_BASED_AUTHORITY_INFERENCE","CLASSIFY_SOURCE_FAMILY_BEFORE_HYDRATION","CONTROLLED_FALLBACK_REQUIRES_EVIDENCE"],"scope":"TRANSVERSAL_LF_GOVERNANCE","version":"v1.2-transversal-candidate","authority":"SUPABASE","policy_kind":"SOURCE_RESOLUTION_POLICY","resolution_order":["ACT-0001","public.v_lf_fuente_operativa","CANONICAL_ID","REGISTERED_ALIAS","CANONICAL_BINDING","SOURCE_ARTIFACT","CONTROLLED_FALLBACK"],"family_strategies":{"MIGRATION":{"flow":["SUPABASE_LEDGER_VERSION_NAME_STATE","EXACT_GITHUB_MIGRATION_PATH_PR_HEAD","CANONICAL_PARITY_VALIDATOR","BROADER_SEARCH_IF_UNRESOLVED","ZIP_LAST_RESORT_ONLY"],"rules":["SUPABASE_FIRST_MIGRATIONS","NO_ZIP_MIGRATIONS"],"zip_exception_required_fields":["zip_reason","files_needed","direct_routes_attempted","why_direct_failed"]},"EXISTING_ARTIFACT":{"modes":["EVALUATE_EXISTING","REMEDIATE_EXISTING"],"required":["source_artifact_ref","source_image_sha256","source_dimensions"],"on_missing":"FAIL_CLOSED","downstream_authorized":false,"remediate_additional_required":["authorized_delta","target_component_id","visual_evidence","acceptance_criteria"]}}}$json$::jsonb,
        '459d9ec975d5955d63619876e13abf2f0975a978e38cfff0aa5eed2d68295ae0'::text
      ),
      (
        'POL-LF-STATE-MODEL'::text,
        'v1.1-transversal-candidate'::text,
        $json${"rules":["NEVER_INFER_PERMISSION_FROM_SINGLE_STATE_DIMENSION","NORMALIZE_ALIAS_BEFORE_LLM_CONSUMPTION","UNKNOWN_OR_EMPTY_STATE_BLOCKS_ACTION","RUNTIME_PERMISSION_REQUIRES_COMBINED_STATE_EVALUATION"],"scope":"TRANSVERSAL_LF_GOVERNANCE","version":"v1.1-transversal-candidate","authority":"SUPABASE","dimensions":{"runtime_estado":["NO_APLICA","NO_HABILITADO","CANDIDATE_READ_ONLY","SANDBOX_READ_ONLY","PRODUCCION_CONTROLADA_READ_ONLY","APROBADO_PRODUCCION_CONTROLADA_READ_ONLY","APROBADO_PRODUCCION_CONTROLADA","RUNTIME_OPERATIVO"],"estado_operativo":["ACTIVO","READ_ONLY","APROBADO","BLOQUEADO","ELIMINADO"],"estado_documental":["CANDIDATO","EN_REVISION","VIGENTE","APROBADO","NO_VALIDADO","LEGACY","ELIMINADO"],"impacto_automatico":["BLOQUEADO","REQUIERE_APROBACION","CONTROLADO","PERMITIDO_CONTROLADO"]},"application":"ALL_ROUTER_GOVERNED_ASSET_AND_OPERATION_STATE_DECISIONS","policy_kind":"STATE_MODEL_POLICY","source_view":"public.v_lf_fuente_operativa","alias_source":"public.cat_estado_normalizacion_lf","inheritance_model":"TRANSVERSAL_ONCE"}$json$::jsonb,
        'f451bb4d2b17cdac48c4dddb250108b2874a9d036edcfb9d2f7fa540416332aa'::text
      )
    ) as x(policy_code,policy_version,policy_payload,expected_sha)
  loop
    v_computed := encode(digest(r.policy_payload::text,'sha256'),'hex');
    if v_computed <> r.expected_sha then
      raise exception 'POLICY_SOURCE_SHA_MISMATCH code=% version=% expected=% computed=%',
        r.policy_code,r.policy_version,r.expected_sha,v_computed;
    end if;

    select policy_sha into v_existing_sha
    from public.lf_policy_versions
    where policy_code=r.policy_code and policy_version=r.policy_version;

    if found then
      if v_existing_sha <> r.expected_sha then
        raise exception 'POLICY_EXISTING_SHA_MISMATCH code=% version=% expected=% existing=%',
          r.policy_code,r.policy_version,r.expected_sha,v_existing_sha;
      end if;
    else
      insert into public.lf_policy_versions(
        policy_code,policy_version,policy_payload,policy_sha,status,effective_at,
        source_ref,created_by_execution_id
      ) values (
        r.policy_code,r.policy_version,r.policy_payload,r.expected_sha,'CANDIDATE',now(),
        'supabase/migrations/20260905013230_lf_policy_transversal_inheritance_rootfix_v1.sql',
        'GPT-GOV-POLICY-TRANSVERSAL-PROMOTION-20260905-001'
      );
    end if;
  end loop;
end;
$policy_candidates$;

-- 2. Graduate the mother policy assets and keep master/payload version coherent.
update public.lf_activos
set metadata = (coalesce(metadata,'{}'::jsonb) - 'pilot_operation')
               || jsonb_build_object('pilot',false,'transversal',true,'router_required',true),
    raw_payload = case codigo_activo
      when 'POL-LF-POLICY-CONSUMPTION' then (
        select policy_payload from public.lf_policy_versions
        where policy_code='POL-LF-POLICY-CONSUMPTION'
          and policy_version='v1.1-transversal-candidate'
      )
      when 'POL-LF-SOURCE-RESOLUTION' then (
        select policy_payload from public.lf_policy_versions
        where policy_code='POL-LF-SOURCE-RESOLUTION'
          and policy_version='v1.2-transversal-candidate'
      )
      when 'POL-LF-STATE-MODEL' then (
        select policy_payload from public.lf_policy_versions
        where policy_code='POL-LF-STATE-MODEL'
          and policy_version='v1.1-transversal-candidate'
      )
      else raw_payload
    end,
    version = case codigo_activo
      when 'POL-LF-POLICY-CONSUMPTION' then 'v1.1-transversal-candidate'
      when 'POL-LF-SOURCE-RESOLUTION' then 'v1.2-transversal-candidate'
      when 'POL-LF-STATE-MODEL' then 'v1.1-transversal-candidate'
      else version
    end,
    ultima_revision=now(),
    updated_at=now(),
    updated_by_execution_id='GPT-GOV-POLICY-TRANSVERSAL-PROMOTION-20260905-001'
where codigo_activo in (
  'POL-LF-OPERATION-LIFECYCLE',
  'POL-LF-POLICY-CONSUMPTION',
  'POL-LF-SOURCE-RESOLUTION',
  'POL-LF-STATE-MODEL'
);

update public.lf_policy_versions
set status='CANDIDATE', superseded_at=now(), updated_at=now(),
    updated_by_execution_id='GPT-GOV-POLICY-TRANSVERSAL-PROMOTION-20260905-001'
where status='ACTIVE'
  and policy_code in (
    'POL-LF-POLICY-CONSUMPTION',
    'POL-LF-SOURCE-RESOLUTION',
    'POL-LF-STATE-MODEL'
  );

update public.lf_policy_versions
set status='ACTIVE', effective_at=now(), superseded_at=null,
    source_ref='supabase/migrations/20260905013230_lf_policy_transversal_inheritance_rootfix_v1.sql',
    updated_by_execution_id='GPT-GOV-POLICY-TRANSVERSAL-PROMOTION-20260905-001',
    updated_at=now()
where (policy_code='POL-LF-POLICY-CONSUMPTION' and policy_version='v1.1-transversal-candidate')
   or (policy_code='POL-LF-SOURCE-RESOLUTION' and policy_version='v1.2-transversal-candidate')
   or (policy_code='POL-LF-STATE-MODEL' and policy_version='v1.1-transversal-candidate');

-- 3. Canonical projection: explicit operation binding wins; transversal fills missing codes.
create or replace view public.v_lf_operation_policy_snapshot
with (security_invoker=true)
as
with routable as (
  select distinct operation_code
  from public.lf_router_action_registry
  where status='ACTIVE' and operation_code is not null
), expected as (
  select
    b.operation_code,
    b.policy_role,
    b.required,
    b.distribution_modes,
    b.policy_code,
    b.updated_at as binding_updated_at,
    0 as precedence
  from public.lf_operation_policy_bindings b
  where b.binding_status='ACTIVE'

  union all

  select
    r.operation_code,
    case a.metadata->>'policy_kind'
      when 'OPERATION_LIFECYCLE_POLICY' then 'GOVERNANCE_LIFECYCLE'
      when 'POLICY_CONSUMPTION_POLICY' then 'POLICY_CONSUMPTION'
      when 'SOURCE_RESOLUTION_POLICY' then 'SOURCE_RESOLUTION'
      when 'STATE_MODEL_POLICY' then 'STATE_MODEL'
    end as policy_role,
    true as required,
    array['ROUTER']::text[] as distribution_modes,
    a.codigo_activo as policy_code,
    null::timestamptz as binding_updated_at,
    1 as precedence
  from routable r
  cross join public.lf_activos a
  where a.archived_at is null
    and a.tipo_activo='REGLA'
    and a.nivel_control='TRANSVERSAL'
    and coalesce((a.metadata->>'transversal')::boolean,false)
    and coalesce((a.metadata->>'router_required')::boolean,false)
    and a.metadata->>'policy_kind' in (
      'OPERATION_LIFECYCLE_POLICY',
      'POLICY_CONSUMPTION_POLICY',
      'SOURCE_RESOLUTION_POLICY',
      'STATE_MODEL_POLICY'
    )
), dedup as (
  select distinct on (operation_code,policy_code)
    operation_code,policy_role,required,distribution_modes,policy_code,binding_updated_at
  from expected
  order by operation_code,policy_code,precedence
)
select
  d.operation_code,
  d.policy_role,
  d.required,
  d.distribution_modes,
  d.policy_code,
  a.nombre_canonico as policy_name,
  a.tipo_activo,
  a.subtipo_activo,
  v.policy_version,
  v.policy_sha,
  v.policy_payload,
  v.effective_at,
  v.source_ref,
  d.binding_updated_at,
  v.updated_at as policy_updated_at
from dedup d
join public.lf_activos a on a.codigo_activo=d.policy_code
left join public.lf_policy_versions v
  on v.policy_code=d.policy_code
 and v.status='ACTIVE';

-- 4. ACT-0001 required/resolved accounting consumes the same canonical projection.
do $router_patch$
declare
  v_def text;
  v_old_required text := $old_required$  select count(*) filter (where b.required) into v_required_policy_count
  from public.lf_operation_policy_bindings b
  where b.operation_code=v_operation.operation_code and b.binding_status='ACTIVE'
    and (p_distribution_mode is null or p_distribution_mode=any(b.distribution_modes));$old_required$;
  v_new_required text := $new_required$  select count(*) filter (where p.required) into v_required_policy_count
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=v_operation.operation_code
    and (p_distribution_mode is null or p_distribution_mode=any(p.distribution_modes));$new_required$;
  v_old_resolved text := $old_resolved$  select count(*) into v_resolved_policy_count
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=v_operation.operation_code and p.required
    and (p_distribution_mode is null or p_distribution_mode=any(p.distribution_modes));$old_resolved$;
  v_new_resolved text := $new_resolved$  select count(*) filter (where p.required and p.policy_sha is not null) into v_resolved_policy_count
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=v_operation.operation_code
    and (p_distribution_mode is null or p_distribution_mode=any(p.distribution_modes));$new_resolved$;
begin
  select pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)
  into v_def;

  if length(v_def)-length(replace(v_def,v_old_required,'')) <> length(v_old_required) then
    raise exception 'ROUTER_REQUIRED_POLICY_BLOCK_NOT_EXACTLY_ONCE';
  end if;
  if length(v_def)-length(replace(v_def,v_old_resolved,'')) <> length(v_old_resolved) then
    raise exception 'ROUTER_RESOLVED_POLICY_BLOCK_NOT_EXACTLY_ONCE';
  end if;

  v_def := replace(v_def,v_old_required,v_new_required);
  v_def := replace(v_def,v_old_resolved,v_new_resolved);
  execute v_def;
end;
$router_patch$;

-- 5. Execution snapshot: explicit bindings keep full payload; inherited mothers are compact.
create or replace function public.lf_attach_operation_policy_snapshot_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_required_count integer := 0;
  v_resolved_required_count integer := 0;
  v_snapshots jsonb;
begin
  select
    count(*) filter (where p.required),
    count(*) filter (where p.required and p.policy_sha is not null)
  into v_required_count,v_resolved_required_count
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=new.operation_code;

  if v_required_count > v_resolved_required_count then
    raise exception 'BLOCK_OPERATION_POLICY_MISSING operation=% required=% resolved=%',
      new.operation_code,v_required_count,v_resolved_required_count;
  end if;

  select jsonb_object_agg(
    p.policy_role,
    case
      when p.binding_updated_at is null then
        jsonb_build_object(
          'policy_code',p.policy_code,
          'policy_version',p.policy_version,
          'policy_sha',p.policy_sha,
          'effective_at',p.effective_at
        )
      else
        jsonb_build_object(
          'policy_code',p.policy_code,
          'policy_version',p.policy_version,
          'policy_sha',p.policy_sha,
          'policy_payload',p.policy_payload,
          'distribution_modes',to_jsonb(p.distribution_modes),
          'effective_at',p.effective_at,
          'source_ref',p.source_ref
        )
    end
  )
  into v_snapshots
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=new.operation_code
    and p.policy_sha is not null;

  if v_snapshots is not null then
    new.manifest := coalesce(new.manifest,'{}'::jsonb) || jsonb_build_object(
      'operation_policy_snapshots',v_snapshots,
      'operation_policy_snapshot_at',now(),
      'operation_policy_source','SUPABASE'
    );
  end if;

  return new;
end;
$$;

revoke all on function public.lf_attach_operation_policy_snapshot_v1() from public,anon,authenticated;

-- 6. Snapshot guard consumes the same expected/resolved set and remains fail-closed.
create or replace function public.lf_operation_policy_snapshot_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_required_count integer := 0;
  v_resolved_required_count integer := 0;
  v_enforcement_at timestamptz;
  r record;
  v_current_sha text;
begin
  select
    count(*) filter (where p.required),
    count(*) filter (where p.required and p.policy_sha is not null),
    min(p.effective_at) filter (where p.required and p.policy_sha is not null)
  into v_required_count,v_resolved_required_count,v_enforcement_at
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=new.operation_code;

  if v_required_count > v_resolved_required_count then
    raise exception 'BLOCK_OPERATION_POLICY_MISSING operation=% required=% resolved=%',
      new.operation_code,v_required_count,v_resolved_required_count;
  end if;

  if old.manifest ? 'operation_policy_snapshots'
     and (old.manifest->'operation_policy_snapshots') is distinct from (new.manifest->'operation_policy_snapshots') then
    raise exception 'BLOCK_POLICY_SNAPSHOT_IMMUTABLE execution=% operation=%',
      new.execution_id,new.operation_code;
  end if;

  if new.status is distinct from old.status and v_required_count > 0 then
    if not (new.manifest ? 'operation_policy_snapshots') then
      if v_enforcement_at is not null and old.started_at < v_enforcement_at then
        return new;
      end if;
      raise exception 'BLOCK_OPERATION_POLICY_MISSING execution=% operation=%',
        new.execution_id,new.operation_code;
    end if;

    for r in
      select key as policy_role,value as snapshot
      from jsonb_each(new.manifest->'operation_policy_snapshots')
    loop
      select p.policy_sha into v_current_sha
      from public.v_lf_operation_policy_snapshot p
      where p.operation_code=new.operation_code
        and p.policy_role=r.policy_role
        and p.policy_sha is not null
      limit 1;

      if v_current_sha is null then
        raise exception 'BLOCK_OPERATION_POLICY_MISSING execution=% role=%',
          new.execution_id,r.policy_role;
      end if;

      if v_current_sha <> (r.snapshot->>'policy_sha') then
        raise exception 'BLOCK_STALE_OPERATION_POLICY execution=% role=% snapshot_sha=% current_sha=%',
          new.execution_id,r.policy_role,r.snapshot->>'policy_sha',v_current_sha;
      end if;
    end loop;
  end if;

  return new;
end;
$$;

revoke all on function public.lf_operation_policy_snapshot_guard_v1() from public,anon,authenticated;

-- 7. Positive production assertions. Negative fail-closed cases were proven in rollback canaries.
do $assertions$
declare
  v_router_ops integer;
  v_all_four integer;
  v_duplicate_codes integer;
  v_role_collisions integer;
  v_max_ref_chars integer;
  v_db jsonb;
  v_profile jsonb;
  v_profile_exec jsonb;
  v_card jsonb;
  v_db_snapshot_bytes integer;
  v_security_invoker boolean;
  v_exposed_grants integer;
  v_version_drift integer;
begin
  with q as (
    select operation_code,
           count(*) filter (where policy_code in (
             'POL-LF-OPERATION-LIFECYCLE','POL-LF-POLICY-CONSUMPTION',
             'POL-LF-SOURCE-RESOLUTION','POL-LF-STATE-MODEL')) as global_count,
           count(*)-count(distinct policy_code) as dups,
           length(jsonb_agg(jsonb_build_array(policy_code,policy_version,policy_sha)
                    order by policy_role,policy_code)::text) as ref_chars
    from public.v_lf_operation_policy_snapshot
    where 'ROUTER'=any(distribution_modes)
      and operation_code in (
        select distinct operation_code from public.lf_router_action_registry
        where status='ACTIVE' and operation_code is not null
      )
    group by operation_code
  )
  select count(*),count(*) filter(where global_count=4),coalesce(sum(dups),0),max(ref_chars)
  into v_router_ops,v_all_four,v_duplicate_codes,v_max_ref_chars
  from q;

  select count(*) into v_role_collisions
  from (
    select operation_code,policy_role
    from public.v_lf_operation_policy_snapshot
    where operation_code in (
      select distinct operation_code from public.lf_router_action_registry
      where status='ACTIVE' and operation_code is not null
    )
    group by operation_code,policy_role
    having count(*)>1
  ) x;

  if v_router_ops<>12 or v_all_four<>12 or v_duplicate_codes<>0 or v_role_collisions<>0 then
    raise exception 'TRANSVERSAL_POLICY_COVERAGE_ASSERTION_FAILED router_ops=% all_four=% duplicate_codes=% role_collisions=%',
      v_router_ops,v_all_four,v_duplicate_codes,v_role_collisions;
  end if;
  if v_max_ref_chars>650 then
    raise exception 'TRANSVERSAL_POLICY_ROUTER_REFS_TOO_LARGE chars=%',v_max_ref_chars;
  end if;

  v_db := public.lf_router_resolve_v1('Actualizar DB governed','','UPDATE','DB','ROUTER');
  v_profile := public.lf_router_resolve_v1('Actualizar perfil quality pack','PERFIL-QUALITY-PACK','PROFILE_UPDATE','PERFIL','ROUTER');
  v_profile_exec := public.lf_router_resolve_v1('Ejecutar perfil quality pack','PERFIL-QUALITY-PACK','PROFILE_EXECUTION','PERFIL','ROUTER');
  v_card := public.lf_router_resolve_v1('Crear card canary transversal','','CARD_CREATE','CARD','ROUTER');

  if v_db->>'status'<>'READY_TO_EXECUTE' or (v_db->>'required_policy_count')::int<>4 or (v_db->>'resolved_policy_count')::int<>4 then
    raise exception 'ROUTER_DB_POLICY_ASSERTION_FAILED %',v_db;
  end if;
  if v_card->>'status'<>'READY_TO_EXECUTE' or (v_card->>'required_policy_count')::int<>4 or (v_card->>'resolved_policy_count')::int<>4 then
    raise exception 'ROUTER_CARD_POLICY_ASSERTION_FAILED %',v_card;
  end if;
  if v_profile->>'status'<>'READY_TO_EXECUTE' or (v_profile->>'required_policy_count')::int<>5 or (v_profile->>'resolved_policy_count')::int<>5 then
    raise exception 'ROUTER_PROFILE_UPDATE_POLICY_ASSERTION_FAILED %',v_profile;
  end if;
  if v_profile_exec->>'status'<>'READY_TO_EXECUTE' or (v_profile_exec->>'required_policy_count')::int<>5 or (v_profile_exec->>'resolved_policy_count')::int<>5 then
    raise exception 'ROUTER_PROFILE_EXECUTION_POLICY_ASSERTION_FAILED %',v_profile_exec;
  end if;

  if not exists (
    select 1 from public.lf_policy_versions
    where policy_code='POL-LF-SOURCE-RESOLUTION' and status='ACTIVE'
      and policy_payload#>'{family_strategies,MIGRATION,rules}' @> '["SUPABASE_FIRST_MIGRATIONS","NO_ZIP_MIGRATIONS"]'::jsonb
  ) then
    raise exception 'SOURCE_RESOLUTION_MIGRATION_RULES_MISSING';
  end if;

  select pg_column_size(jsonb_object_agg(
    p.policy_role,
    jsonb_build_object('policy_code',p.policy_code,'policy_version',p.policy_version,'policy_sha',p.policy_sha,'effective_at',p.effective_at)
  )) into v_db_snapshot_bytes
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code='ACTUALIZACION_DB_LF' and p.binding_updated_at is null and p.policy_sha is not null;
  if v_db_snapshot_bytes>1050 then
    raise exception 'INHERITED_POLICY_SNAPSHOT_TOO_LARGE bytes=%',v_db_snapshot_bytes;
  end if;

  select coalesce('security_invoker=true'=any(c.reloptions),false)
  into v_security_invoker
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname='v_lf_operation_policy_snapshot';
  if not v_security_invoker then
    raise exception 'POLICY_SNAPSHOT_VIEW_SECURITY_INVOKER_MISSING';
  end if;

  select count(*) into v_exposed_grants
  from information_schema.role_table_grants
  where table_schema='public' and table_name='v_lf_operation_policy_snapshot'
    and grantee in ('anon','authenticated');
  if v_exposed_grants<>0 then
    raise exception 'POLICY_SNAPSHOT_VIEW_UNEXPECTED_PUBLIC_GRANTS count=%',v_exposed_grants;
  end if;

  select count(*) into v_version_drift
  from public.lf_activos a
  join public.lf_policy_versions p on p.policy_code=a.codigo_activo and p.status='ACTIVE'
  where a.codigo_activo in ('POL-LF-POLICY-CONSUMPTION','POL-LF-SOURCE-RESOLUTION','POL-LF-STATE-MODEL')
    and (a.version is distinct from p.policy_version or a.raw_payload->>'version' is distinct from p.policy_version);
  if v_version_drift<>0 then
    raise exception 'POLICY_MASTER_VERSION_DRIFT count=%',v_version_drift;
  end if;
end;
$assertions$;
