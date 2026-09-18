begin;

do $execution_guard$
declare
  v_execution_id constant text := 'EXEC-S30-CONTEXT-ADMISSION-COMPACT-20260918-001';
begin
  if not exists (
    select 1
    from public.lf_operation_execution e
    where e.execution_id=v_execution_id
      and e.operation_code='ACTUALIZACION_DB_LF'
      and e.target_type='MIGRATION'
      and e.target_code='ROUTER_CONTEXT_ADMISSION_COMPACT_V1'
      and e.target_repo='cristhianlujan/claude-persona-lf-patch'
      and e.target_path='supabase/migrations/20260918054000_lf_s30_operation_policy_context_admission_v1.sql'
      and e.status='IN_PROGRESS'
  ) then
    raise exception 'BLOCK_CONTEXT_ADMISSION_GOVERNED_EXECUTION_BINDING:%',v_execution_id;
  end if;
end
$execution_guard$;

-- S30 transversal operation policy + compact context admission v1.
-- Fixes EKB: OPERATION-POLICY-CONTEXT-AMBIGUOUS-NONE-001 and ROUTER-CONTEXT-ADMISSION-INTEGRATION-GAP-001.
--
-- Architecture:
--   OP_OPERATIONAL consumer
--     -> generic transversal policy set (resolved once from canonical asset metadata)
--     -> + explicit operation-specific bindings
--     -> dedup
--     -> one immutable execution snapshot through existing attach/guard functions.
--
-- This migration does NOT create per-operation copies of the transversal bundle,
-- does NOT add a second policy engine, and does NOT add a new policy-mode column.

do $pre$
declare
  v_view_sha text;
  v_generic_count integer;
  v_generic_resolved integer;
  v_unknown_role text[];
begin
  select encode(
    extensions.digest(
      convert_to(pg_get_viewdef('public.v_lf_operation_policy_snapshot'::regclass,true),'UTF8'),
      'sha256'
    ),
    'hex'
  ) into v_view_sha;

  if v_view_sha is distinct from 'c32c20f908ef166e26df339e49467c8ee661db8c6f2264381b40f1fb660bc2f7' then
    raise exception 'BLOCK_POLICY_RESOLVER_PRESTATE_DRIFT expected=% actual=%',
      'c32c20f908ef166e26df339e49467c8ee661db8c6f2264381b40f1fb660bc2f7',
      v_view_sha;
  end if;

  select
    count(*),
    count(*) filter (where v.policy_sha is not null and v.status='ACTIVE')
  into v_generic_count,v_generic_resolved
  from public.lf_activos a
  left join public.lf_policy_versions v
    on v.policy_code=a.codigo_activo
   and v.status='ACTIVE'
  where a.archived_at is null
    and a.tipo_activo='REGLA'
    and a.nivel_control='TRANSVERSAL'
    and coalesce((a.metadata->>'transversal')::boolean,false)
    and coalesce((a.metadata->>'router_required')::boolean,false);

  if v_generic_count<>4 or v_generic_resolved<>v_generic_count then
    raise exception 'BLOCK_POLICY_GENERIC_SET_NOT_RESOLVED expected=4 generic=% resolved=%',
      v_generic_count,v_generic_resolved;
  end if;

  select array_agg(a.codigo_activo order by a.codigo_activo)
  into v_unknown_role
  from public.lf_activos a
  where a.archived_at is null
    and a.tipo_activo='REGLA'
    and a.nivel_control='TRANSVERSAL'
    and coalesce((a.metadata->>'transversal')::boolean,false)
    and coalesce((a.metadata->>'router_required')::boolean,false)
    and coalesce(
      nullif(a.metadata->>'policy_role',''),
      case a.metadata->>'policy_kind'
        when 'OPERATION_LIFECYCLE_POLICY' then 'GOVERNANCE_LIFECYCLE'
        when 'POLICY_CONSUMPTION_POLICY' then 'POLICY_CONSUMPTION'
        when 'SOURCE_RESOLUTION_POLICY' then 'SOURCE_RESOLUTION'
        when 'STATE_MODEL_POLICY' then 'STATE_MODEL'
      end
    ) is null;

  if coalesce(array_length(v_unknown_role,1),0)<>0 then
    raise exception 'BLOCK_POLICY_GENERIC_ROLE_UNRESOLVED:%',v_unknown_role;
  end if;
end
$pre$;

create or replace view public.v_lf_operation_policy_snapshot
with (security_invoker=true)
as
with governed_codes as (
  -- Preserve every currently routable consumer, regardless of lifecycle projection,
  -- and extend coverage to operational internal/child consumers.
  select distinct r.operation_code
  from public.lf_router_action_registry r
  where r.status='ACTIVE'
    and r.operation_code is not null

  union

  select o.operation_code
  from public.lf_operation_registry o
  where o.lifecycle_state_code='OP_OPERATIONAL'
),
governed as (
  select
    g.operation_code,
    case
      when exists (
        select 1
        from public.lf_router_action_registry r
        where r.status='ACTIVE'
          and r.operation_code=g.operation_code
      )
      then array['ROUTER','DIRECT']::text[]
      else array['DIRECT']::text[]
    end as distribution_modes
  from governed_codes g
),
generic_policies as (
  select
    a.codigo_activo as policy_code,
    coalesce(
      nullif(a.metadata->>'policy_role',''),
      case a.metadata->>'policy_kind'
        when 'OPERATION_LIFECYCLE_POLICY' then 'GOVERNANCE_LIFECYCLE'
        when 'POLICY_CONSUMPTION_POLICY' then 'POLICY_CONSUMPTION'
        when 'SOURCE_RESOLUTION_POLICY' then 'SOURCE_RESOLUTION'
        when 'STATE_MODEL_POLICY' then 'STATE_MODEL'
      end
    ) as policy_role
  from public.lf_activos a
  where a.archived_at is null
    and a.tipo_activo='REGLA'
    and a.nivel_control='TRANSVERSAL'
    and coalesce((a.metadata->>'transversal')::boolean,false)
    and coalesce((a.metadata->>'router_required')::boolean,false)
),
expected as (
  -- Operation-specific extension wins identity/role/required metadata.
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

  -- Generic transversal package is inherited by every canonical operational
  -- operation. It is resolved once from metadata; no per-operation copy exists.
  select
    g.operation_code,
    p.policy_role,
    true as required,
    g.distribution_modes,
    p.policy_code,
    null::timestamptz as binding_updated_at,
    1 as precedence
  from governed g
  cross join generic_policies p
),
dedup as (
  select distinct on (e.operation_code,e.policy_code)
    e.operation_code,
    e.policy_role,
    e.required,
    e.policy_code,
    e.binding_updated_at
  from expected e
  order by e.operation_code,e.policy_code,e.precedence
),
modes as (
  select
    e.operation_code,
    e.policy_code,
    array_agg(distinct m.mode order by m.mode) as distribution_modes
  from expected e
  cross join lateral unnest(e.distribution_modes) as m(mode)
  group by e.operation_code,e.policy_code
)
select
  d.operation_code,
  d.policy_role,
  d.required,
  m.distribution_modes,
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
join modes m
  on m.operation_code=d.operation_code
 and m.policy_code=d.policy_code
join public.lf_activos a
  on a.codigo_activo=d.policy_code
left join public.lf_policy_versions v
  on v.policy_code=d.policy_code
 and v.status='ACTIVE';

do $post$
declare
  v_operational integer;
  v_routable integer;
  v_governed integer;
  v_all_generic integer;
  v_uncovered_bad text[];
  v_explicit_copies integer;
  v_duplicates integer;
  v_profile_count integer;
  v_profile_specific integer;
begin
  select count(*)
  into v_operational
  from public.lf_operation_registry
  where lifecycle_state_code='OP_OPERATIONAL';

  select count(distinct operation_code)
  into v_routable
  from public.lf_router_action_registry
  where status='ACTIVE'
    and operation_code is not null;

  with governed_codes as (
    select distinct operation_code
    from public.lf_router_action_registry
    where status='ACTIVE'
      and operation_code is not null
    union
    select operation_code
    from public.lf_operation_registry
    where lifecycle_state_code='OP_OPERATIONAL'
  ),
  per_operation as (
    select
      g.operation_code,
      count(*) filter (
        where p.required
          and p.policy_sha is not null
          and p.policy_code in (
            select a.codigo_activo
            from public.lf_activos a
            where a.archived_at is null
              and a.tipo_activo='REGLA'
              and a.nivel_control='TRANSVERSAL'
              and coalesce((a.metadata->>'transversal')::boolean,false)
              and coalesce((a.metadata->>'router_required')::boolean,false)
          )
      ) as generic_resolved
    from governed_codes g
    left join public.v_lf_operation_policy_snapshot p
      on p.operation_code=g.operation_code
    group by g.operation_code
  )
  select count(*),
         count(*) filter (where generic_resolved=4)
  into v_governed,v_all_generic
  from per_operation;

  if v_operational<>26
     or v_routable<>23
     or v_governed<>33
     or v_all_generic<>v_governed then
    raise exception 'BLOCK_POLICY_GENERIC_GOVERNED_COVERAGE operational=% routable=% governed=% all_generic=%',
      v_operational,v_routable,v_governed,v_all_generic;
  end if;

  select array_agg(x.operation_code order by x.operation_code)
  into v_uncovered_bad
  from (
    select operation_code
    from public.v_lf_operation_policy_snapshot
    where operation_code in (
      'ANALISIS_RIESGO_CONTENIDO_LF',
      'ESCRITURA_BASE_CONOCIMIENTO_LF',
      'EXTRACCION_DOCUMENTOS_REGULATORIOS_LF',
      'EXTRACCION_FUENTES_DIGITALES_LF',
      'EXTRACCION_NOTICIAS_FINANCIERAS_LF',
      'HOMOLOGACION_FUENTES_DIGITALES_LF',
      'ORQUESTACION_PIPELINE_LF',
      'VULNERABILITY_COVERAGE_REPAIR_LF'
    )
    group by operation_code
    having count(*) filter (
      where required
        and binding_updated_at is null
        and policy_sha is not null
    )<>4
  ) x;

  if coalesce(array_length(v_uncovered_bad,1),0)<>0 then
    raise exception 'BLOCK_POLICY_PREVIOUSLY_UNCOVERED_STILL_BAD:%',v_uncovered_bad;
  end if;

  select count(*)
  into v_explicit_copies
  from public.lf_operation_policy_bindings b
  where b.operation_code in (
      'ANALISIS_RIESGO_CONTENIDO_LF',
      'ESCRITURA_BASE_CONOCIMIENTO_LF',
      'EXTRACCION_DOCUMENTOS_REGULATORIOS_LF',
      'EXTRACCION_FUENTES_DIGITALES_LF',
      'EXTRACCION_NOTICIAS_FINANCIERAS_LF',
      'HOMOLOGACION_FUENTES_DIGITALES_LF',
      'ORQUESTACION_PIPELINE_LF',
      'VULNERABILITY_COVERAGE_REPAIR_LF'
    )
    and b.policy_code in (
      select a.codigo_activo
      from public.lf_activos a
      where a.archived_at is null
        and a.tipo_activo='REGLA'
        and a.nivel_control='TRANSVERSAL'
        and coalesce((a.metadata->>'transversal')::boolean,false)
        and coalesce((a.metadata->>'router_required')::boolean,false)
    );

  if v_explicit_copies<>0 then
    raise exception 'BLOCK_POLICY_TRANSVERSAL_COPY_CREATED count=%',v_explicit_copies;
  end if;

  select count(*)
  into v_duplicates
  from (
    select operation_code,policy_code
    from public.v_lf_operation_policy_snapshot
    group by operation_code,policy_code
    having count(*)>1
  ) d;

  if v_duplicates<>0 then
    raise exception 'BLOCK_POLICY_RESOLVER_DUPLICATE_CODES count=%',v_duplicates;
  end if;

  select count(*),
         count(*) filter (where policy_code='POL-PROFILE-UPDATE-PASS')
  into v_profile_count,v_profile_specific
  from public.v_lf_operation_policy_snapshot
  where operation_code='ACTUALIZACION_PERFIL_LF'
    and required
    and policy_sha is not null;

  if v_profile_count<>5 or v_profile_specific<>1 then
    raise exception 'BLOCK_POLICY_SPECIFIC_EXTENSION_REGRESSION profile_count=% specific=%',
      v_profile_count,v_profile_specific;
  end if;
end
$post$;



-- ---------------------------------------------------------------------------
-- Compact context admission: extend the existing policy-consumption authority.
-- No new engine/table. Reuses fn_lf_router_preflight_v1 + existing budget ledger.
-- ---------------------------------------------------------------------------

do $policy_upgrade$
declare
  v_execution_id constant text := 'EXEC-S30-CONTEXT-ADMISSION-COMPACT-20260918-001';
  v_current public.lf_policy_versions%rowtype;
  v_payload jsonb;
  v_sha text;
begin
  select * into v_current
  from public.lf_policy_versions
  where policy_code='POL-LF-POLICY-CONSUMPTION'
    and status='ACTIVE'
  order by effective_at desc
  limit 1
  for update;

  if not found or v_current.policy_version<>'v1.1-transversal-candidate' then
    raise exception 'BLOCK_POLICY_CONSUMPTION_PRESTATE expected=v1.1-transversal-candidate actual=%',
      coalesce(v_current.policy_version,'MISSING');
  end if;

  if exists (
    select 1 from public.lf_policy_versions
    where policy_code='POL-LF-POLICY-CONSUMPTION'
      and policy_version='v1.2-context-admission'
  ) then
    raise exception 'BLOCK_POLICY_CONSUMPTION_V12_ALREADY_EXISTS';
  end if;

  v_payload := v_current.policy_payload || jsonb_build_object(
    'version','v1.2-context-admission',
    'context_compilation',jsonb_build_object(
      'schema_version','lf-context-admission/v1',
      'base_set',jsonb_build_object(
        'set_id','TRANSVERSAL_BASE_SET_V1',
        'capabilities',jsonb_build_array(
          'ACT-0001',
          'CURRENTNESS_AUTHORITY',
          'OPERATION_MATERIALIZATION_GUARD',
          'PRE_EKB_GATE',
          'GATE_CHECK_OBSERVABILITY',
          'EXECUTION_EVENT_READBACK_INDEX'
        )
      ),
      'conditional_sets',jsonb_build_array(
        jsonb_build_object(
          'set_id','WRITE_MUTATION_SET_V1',
          'capabilities',jsonb_build_array(
            'TRANSACTIONAL_EXECUTION_BEGIN',
            'OPERATION_EFFECT_GUARD',
            'EVENT_CONTRACT_GOVERNANCE',
            'TYPED_EVIDENCE_REGISTRY'
          ),
          'applies_when',jsonb_build_object(
            'operation_types',jsonb_build_array(
              'UPDATE_PROTOCOL','UPDATE_CANDIDATE','CREATE_CANDIDATE','CREATION_PROTOCOL',
              'CLOSE_PROTOCOL','CREATE_RELATION','MATERIALIZE_EXPLORATION','CONTROLLED_EXECUTION'
            )
          )
        ),
        jsonb_build_object(
          'set_id','DB_MIGRATION_SET_V1',
          'capabilities',jsonb_build_array(
            'DB_WRITE_TRANSPORT','MIGRATION_SOURCE_PARITY','SCHEMA_FINGERPRINT_GUARD'
          ),
          'applies_when',jsonb_build_object(
            'target_types',jsonb_build_array('DB','MIGRATION','FUNCTION'),
            'operation_families',jsonb_build_array('DATABASE_OPERATIONS')
          )
        ),
        jsonb_build_object(
          'set_id','REPOSITORY_CI_SET_V1',
          'capabilities',jsonb_build_array(
            'CI_FAST_DEEP_LANE_ROUTER','REPOSITORY_GOVERNANCE_BUNDLE','ASSURANCE_COMPLETENESS'
          ),
          'applies_when',jsonb_build_object(
            'target_types',jsonb_build_array(
              'CI_WORKFLOW','GITHUB_GOVERNANCE_BUNDLE','REPOSITORY_GOVERNED_PATHS','SOURCE'
            ),
            'requires_target_repo',true
          )
        ),
        jsonb_build_object(
          'set_id','HIGH_ASSURANCE_SET_V1',
          'capabilities',jsonb_build_array(
            'QUALIFICATION_FRAMEWORK','QUALIFICATION_RECEIPTS',
            'INDEPENDENT_ASSURANCE','EVIDENCE_RESOLVER_REGISTRY'
          ),
          'applies_when',jsonb_build_object(
            'operation_types',jsonb_build_array('INDEPENDENT_REVIEW','REGRESSION_SUITE'),
            'operation_domains',jsonb_build_array('STRATEGY_ASSURANCE','REGRESSION_SUITE'),
            'risk_classes',jsonb_build_array('HIGH','CRITICAL')
          )
        ),
        jsonb_build_object(
          'set_id','STRATEGY_EXECUTION_SET_V1',
          'capabilities',jsonb_build_array('C05_GENERIC_EXECUTION_RELIABILITY'),
          'applies_when',jsonb_build_object(
            'target_types',jsonb_build_array(
              'STRATEGY','STRATEGY_SNAPSHOT','STRATEGY_PORTFOLIO','STRATEGY_PROGRESS'
            ),
            'operation_domains',jsonb_build_array(
              'STRATEGY_LIFECYCLE','STRATEGY_FACTORY','STRATEGY_EXECUTION','STRATEGY_ASSURANCE'
            )
          )
        )
      ),
      'ekb',jsonb_build_object(
        'base_codes',jsonb_build_array('GOV-010'),
        'max_items',12,
        'detail_mode','JIT_BY_CODE',
        'full_entries_to_model',false
      ),
      'budget',jsonb_build_object(
        'soft_limit_tokens',1500,
        'hard_limit_tokens',3000,
        'estimator','UTF8_BYTES_DIV_4'
      ),
      'model_delivery',jsonb_build_object(
        'policy_payloads',false,
        'full_ekb_entries',false,
        'full_readmes',false,
        'jit_only',true
      )
    )
  );

  v_sha:=encode(
    extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),
    'hex'
  );

  update public.lf_policy_versions
  set status='SUPERSEDED',
      superseded_at=clock_timestamp(),
      updated_at=clock_timestamp(),
      updated_by_execution_id=v_execution_id
  where policy_code='POL-LF-POLICY-CONSUMPTION'
    and status='ACTIVE';

  insert into public.lf_policy_versions(
    policy_code,policy_version,policy_payload,policy_sha,status,effective_at,
    source_ref,created_by_execution_id,updated_by_execution_id
  ) values (
    'POL-LF-POLICY-CONSUMPTION',
    'v1.2-context-admission',
    v_payload,
    v_sha,
    'ACTIVE',
    clock_timestamp(),
    'supabase/migrations/20260918054000_lf_s30_operation_policy_context_admission_v1.sql',
    v_execution_id,
    v_execution_id
  );

  update public.lf_activos
  set version='v1.2-context-admission',
      updated_at=clock_timestamp(),
      updated_by_execution_id=v_execution_id
  where codigo_activo='POL-LF-POLICY-CONSUMPTION'
    and archived_at is null;

  if (
    select count(*)
    from public.lf_policy_versions
    where policy_code='POL-LF-POLICY-CONSUMPTION'
      and status='ACTIVE'
      and policy_version='v1.2-context-admission'
      and policy_sha=v_sha
  )<>1 then
    raise exception 'BLOCK_POLICY_CONSUMPTION_V12_READBACK';
  end if;
end
$policy_upgrade$;

create or replace function public.fn_lf_router_preflight_v1(p_execution_id text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_exec public.lf_operation_execution%rowtype;
  v_op public.lf_operation_registry%rowtype;
  v_router jsonb;
  v_cfg jsonb;
  v_set jsonb;
  v_set_codes text[];
  v_required_codes text[] := array[]::text[];
  v_base_ekb_codes text[] := array[]::text[];
  v_applied_sets jsonb := '[]'::jsonb;
  v_capabilities jsonb := '[]'::jsonb;
  v_policies jsonb := '[]'::jsonb;
  v_ekb jsonb := '[]'::jsonb;
  v_ekb_matched integer := 0;
  v_ekb_limit integer := 12;
  v_soft_limit integer := 1500;
  v_hard_limit integer := 3000;
  v_missing text[];
  v_applies boolean;
  v_receipt jsonb;
  v_evento_id bigint;
  v_budget_event_id bigint;
  v_context_bytes bigint;
  v_estimated_tokens bigint;
  v_context_status text;
begin
  if coalesce(btrim(p_execution_id),'')='' then
    raise exception 'BLOCK_CONTEXT_ADMISSION_EXECUTION_ID_REQUIRED';
  end if;

  select * into v_exec
  from public.lf_operation_execution
  where execution_id=p_execution_id;

  if not found then
    raise exception 'BLOCK_CONTEXT_ADMISSION_EXECUTION_NOT_FOUND:%',p_execution_id;
  end if;

  select * into v_op
  from public.lf_operation_registry
  where operation_code=v_exec.operation_code;

  if not found then
    raise exception 'BLOCK_CONTEXT_ADMISSION_OPERATION_NOT_REGISTERED:%',v_exec.operation_code;
  end if;

  select to_jsonb(r) into v_router
  from (
    select codigo_activo,nombre_canonico,estado_documental,estado_operativo,
           nivel_control,runtime_estado,impacto_automatico,version_normalizada,updated_at
    from public.v_lf_fuente_operativa
    where codigo_activo='ACT-0001'
  ) r;

  if v_router is null
     or v_router->>'estado_operativo' is distinct from 'ACTIVO' then
    raise exception 'BLOCK_CONTEXT_ADMISSION_ROUTER_NOT_CURRENT';
  end if;

  select policy_payload->'context_compilation'
  into v_cfg
  from public.lf_policy_versions
  where policy_code='POL-LF-POLICY-CONSUMPTION'
    and status='ACTIVE'
  order by effective_at desc
  limit 1;

  if v_cfg is null
     or v_cfg->>'schema_version' is distinct from 'lf-context-admission/v1' then
    raise exception 'BLOCK_CONTEXT_ADMISSION_POLICY_CONFIG_MISSING';
  end if;

  select coalesce(array_agg(value order by value),array[]::text[])
  into v_required_codes
  from jsonb_array_elements_text(coalesce(v_cfg #> '{base_set,capabilities}','[]'::jsonb)) t(value);

  v_applied_sets:=jsonb_build_array(v_cfg #>> '{base_set,set_id}');

  for v_set in
    select value
    from jsonb_array_elements(coalesce(v_cfg->'conditional_sets','[]'::jsonb))
  loop
    v_applies:=false;

    if exists (
      select 1
      from jsonb_array_elements_text(coalesce(v_set #> '{applies_when,target_types}','[]'::jsonb)) x(value)
      where upper(x.value)=upper(coalesce(v_exec.target_type,''))
    ) then v_applies:=true; end if;

    if exists (
      select 1
      from jsonb_array_elements_text(coalesce(v_set #> '{applies_when,operation_families}','[]'::jsonb)) x(value)
      where upper(x.value)=upper(coalesce(v_op.operation_family,''))
    ) then v_applies:=true; end if;

    if exists (
      select 1
      from jsonb_array_elements_text(coalesce(v_set #> '{applies_when,operation_domains}','[]'::jsonb)) x(value)
      where upper(x.value)=upper(coalesce(v_op.operation_domain,''))
    ) then v_applies:=true; end if;

    if exists (
      select 1
      from jsonb_array_elements_text(coalesce(v_set #> '{applies_when,operation_types}','[]'::jsonb)) x(value)
      where upper(x.value)=upper(coalesce(v_op.operation_type,''))
    ) then v_applies:=true; end if;

    if coalesce((v_set #>> '{applies_when,requires_target_repo}')::boolean,false)
       and nullif(btrim(coalesce(v_exec.target_repo,'')),'') is not null then
      v_applies:=true;
    end if;

    if exists (
      select 1
      from jsonb_array_elements_text(coalesce(v_set #> '{applies_when,risk_classes}','[]'::jsonb)) x(value)
      where upper(x.value)=upper(coalesce(v_exec.manifest->>'risk_class',''))
    ) then v_applies:=true; end if;

    if v_applies then
      select coalesce(array_agg(value order by value),array[]::text[])
      into v_set_codes
      from jsonb_array_elements_text(coalesce(v_set->'capabilities','[]'::jsonb)) t(value);

      v_required_codes:=v_required_codes||v_set_codes;
      v_applied_sets:=v_applied_sets||jsonb_build_array(v_set->>'set_id');
    end if;
  end loop;

  select coalesce(array_agg(distinct x order by x),array[]::text[])
  into v_required_codes
  from unnest(v_required_codes) x;

  select array_agg(req order by req)
  into v_missing
  from unnest(v_required_codes) req
  where not exists (
    select 1
    from public.lf_activos a
    where a.codigo_activo=req
      and a.archived_at is null
      and a.estado_operativo='ACTIVO'
      and a.metadata #>> '{transversal_inventory,inventory_status}' in (
        'ACTIVE_SHARED_ENFORCEMENT','FORMAL_TRANSVERSAL_ACTIVE','ACTIVE_TRANSVERSAL_POLICY'
      )
  );

  if coalesce(array_length(v_missing,1),0)>0 then
    raise exception 'BLOCK_CONTEXT_ADMISSION_REQUIRED_CAPABILITY_NOT_CURRENT:%',v_missing;
  end if;

  v_capabilities:=to_jsonb(v_required_codes);

  select coalesce(jsonb_agg(jsonb_build_object(
           'policy_code',p.policy_code,
           'policy_role',p.policy_role,
           'policy_version',p.policy_version,
           'policy_sha',p.policy_sha,
           'required',p.required
         ) order by p.policy_role,p.policy_code),'[]'::jsonb)
  into v_policies
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=v_exec.operation_code
    and p.required;

  if jsonb_array_length(v_policies)=0
     or exists (
       select 1
       from public.v_lf_operation_policy_snapshot p
       where p.operation_code=v_exec.operation_code
         and p.required
         and p.policy_sha is null
     ) then
    raise exception 'BLOCK_CONTEXT_ADMISSION_POLICY_SNAPSHOT_UNRESOLVED:%',v_exec.operation_code;
  end if;

  select coalesce(array_agg(value order by value),array[]::text[])
  into v_base_ekb_codes
  from jsonb_array_elements_text(coalesce(v_cfg #> '{ekb,base_codes}','[]'::jsonb)) t(value);

  v_ekb_limit:=greatest(1,least(50,coalesce((v_cfg #>> '{ekb,max_items}')::integer,12)));
  v_soft_limit:=greatest(250,coalesce((v_cfg #>> '{budget,soft_limit_tokens}')::integer,1500));
  v_hard_limit:=greatest(v_soft_limit+1,coalesce((v_cfg #>> '{budget,hard_limit_tokens}')::integer,3000));

  select count(*)
  into v_ekb_matched
  from public.lf_error_knowledge k
  where upper(coalesce(k.estado,'')) in ('ACTIVO','ACTIVE','ABIERTO','OPEN')
    and upper(coalesce(k.severidad,'')) in ('ALTA','HIGH','CRITICA','CRITICAL','P0')
    and (
      k.codigo=any(v_base_ekb_codes)
      or v_exec.operation_code=any(coalesce(k.consumer_role,array[]::text[]))
      or exists (
        select 1 from unnest(coalesce(k.consumer_role,array[]::text[])) r(role)
        where upper(r.role)=upper(coalesce(v_exec.target_type,''))
      )
      or exists (
        select 1
        from unnest(v_required_codes) c(code)
        where c.code=any(coalesce(k.consumer_role,array[]::text[]))
      )
    );

  select coalesce(jsonb_agg(x.item order by x.priority,x.ultima_vez desc nulls last,x.codigo),'[]'::jsonb)
  into v_ekb
  from (
    select
      k.codigo,
      k.ultima_vez,
      case
        when k.codigo=any(v_base_ekb_codes) then 0
        when upper(coalesce(k.severidad,'')) in ('CRITICA','CRITICAL','P0') then 1
        else 2
      end as priority,
      jsonb_build_object(
        'codigo',k.codigo,
        'severidad',k.severidad
      ) as item
    from public.lf_error_knowledge k
    where upper(coalesce(k.estado,'')) in ('ACTIVO','ACTIVE','ABIERTO','OPEN')
      and upper(coalesce(k.severidad,'')) in ('ALTA','HIGH','CRITICA','CRITICAL','P0')
      and (
        k.codigo=any(v_base_ekb_codes)
        or v_exec.operation_code=any(coalesce(k.consumer_role,array[]::text[]))
        or exists (
          select 1 from unnest(coalesce(k.consumer_role,array[]::text[])) r(role)
          where upper(r.role)=upper(coalesce(v_exec.target_type,''))
        )
        or exists (
          select 1
          from unnest(v_required_codes) c(code)
          where c.code=any(coalesce(k.consumer_role,array[]::text[]))
        )
      )
    order by priority,k.ultima_vez desc nulls last,k.codigo
    limit v_ekb_limit
  ) x;

  v_receipt:=jsonb_build_object(
    'schema_version','lf-context-admission/v1',
    'status','READY',
    'blocking_code',null,
    'execution_id',v_exec.execution_id,
    'operation_code',v_exec.operation_code,
    'target',jsonb_build_object(
      'target_type',v_exec.target_type,
      'target_code',v_exec.target_code
    ),
    'router_ref',jsonb_build_object(
      'code',v_router->>'codigo_activo',
      'version',v_router->>'version_normalizada'
    ),
    'base_set',v_cfg #>> '{base_set,set_id}',
    'applied_sets',v_applied_sets,
    'required_capabilities',v_capabilities,
    'policy_refs',v_policies,
    'ekb_controles',v_ekb,
    'ekb_controles_count',jsonb_array_length(v_ekb),
    'ekb_matched_count',v_ekb_matched,
    'lazy_detail_required',v_ekb_matched>jsonb_array_length(v_ekb),
    'lazy_refs',jsonb_build_object(
      'policies','supabase://public.v_lf_operation_policy_snapshot/'||v_exec.operation_code,
      'ekb','supabase://public.lf_error_knowledge/{codigo}',
      'capabilities','supabase://public.lf_activos/{codigo_activo}'
    ),
    'delivery',jsonb_build_object(
      'policy_payloads',false,
      'full_ekb_entries',false,
      'full_readmes',false,
      'jit_only',true
    )
  );

  v_context_bytes:=octet_length(v_receipt::text);
  v_estimated_tokens:=(v_context_bytes+3)/4;
  v_context_status:=case
    when v_estimated_tokens>v_hard_limit then 'RED'
    when v_estimated_tokens>v_soft_limit then 'YELLOW'
    else 'GREEN'
  end;

  v_receipt:=v_receipt||jsonb_build_object(
    'context_budget',jsonb_build_object(
      'estimated_tokens',v_estimated_tokens,
      'estimated_bytes',v_context_bytes,
      'status',v_context_status,
      'soft_limit_tokens',v_soft_limit,
      'hard_limit_tokens',v_hard_limit,
      'estimator','UTF8_BYTES_DIV_4'
    )
  );

  if v_context_status='RED' then
    v_receipt:=jsonb_set(v_receipt,'{status}','"BLOCKED"'::jsonb,true);
    v_receipt:=jsonb_set(v_receipt,'{blocking_code}','"BLOCK_CONTEXT_BUDGET_HARD_LIMIT"'::jsonb,true);
  end if;

  insert into public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,origen,created_by_execution_id
  ) values (
    'SESION_INICIO','ACTIVO','ACT-0001',
    'Router preflight compiled a bounded context receipt with JIT references.',
    case when v_context_status='RED' then 'WARN' else 'INFO' end,
    jsonb_build_object(
      'evidence_schema_version','operational-event/v2',
      'execution_id',v_exec.execution_id,
      'producer','fn_lf_router_preflight_v1',
      'purpose','Compile BASE + conditional transversal sets without hydrating full policies/EKB/readmes into model context',
      'acceptance_declared',false,
      'occurred_at',clock_timestamp(),
      'context_receipt',v_receipt
    ),
    'DB_FUNCTION',v_exec.execution_id
  ) returning id into v_evento_id;

  insert into private.lf_context_budget_events_v2(
    execution_id,estimated_tokens,context_status,source,recommendation,evidence_event_id
  ) values (
    v_exec.execution_id,
    v_estimated_tokens,
    v_context_status,
    'ROUTER_CONTEXT_ADMISSION_V1',
    case
      when v_context_status='RED' then 'BLOCK_AND_REDUCE_CONTEXT_OR_USE_JIT'
      when v_context_status='YELLOW' then 'PREFER_JIT_AND_AVOID_ADDITIONAL_PREFETCH'
      else 'WITHIN_COMPACT_CONTEXT_BUDGET'
    end,
    v_evento_id
  ) returning id into v_budget_event_id;

  return v_receipt||jsonb_build_object(
    'evento_id',v_evento_id,
    'context_budget_event_id',v_budget_event_id
  );
end;
$function$;

revoke execute on function public.fn_lf_router_preflight_v1(text) from public,anon,authenticated;
grant execute on function public.fn_lf_router_preflight_v1(text) to service_role;

do $context_post$
declare
  v_policy_count integer;
  v_active_count integer;
begin
  select count(*) into v_active_count
  from public.lf_policy_versions
  where policy_code='POL-LF-POLICY-CONSUMPTION'
    and status='ACTIVE'
    and policy_version='v1.2-context-admission';

  if v_active_count<>1 then
    raise exception 'BLOCK_CONTEXT_ADMISSION_POLICY_ACTIVE_COUNT:%',v_active_count;
  end if;

  select count(*) into v_policy_count
  from public.v_lf_operation_policy_snapshot
  where operation_code='ACTUALIZACION_DB_LF'
    and required
    and policy_sha is not null;

  if v_policy_count<4 then
    raise exception 'BLOCK_CONTEXT_ADMISSION_DB_POLICY_COVERAGE:%',v_policy_count;
  end if;

  if strpos(
      pg_get_functiondef('public.fn_lf_router_preflight_v1(text)'::regprocedure),
      'ROUTER_CONTEXT_ADMISSION_V1'
    )=0
     or strpos(
      pg_get_functiondef('public.fn_lf_router_preflight_v1(text)'::regprocedure),
      'limit v_ekb_limit'
    )=0
     or strpos(
      pg_get_functiondef('public.fn_lf_router_preflight_v1(text)'::regprocedure),
      '''policy_payloads'',false'
    )=0 then
    raise exception 'BLOCK_CONTEXT_ADMISSION_PREFLIGHT_SOURCE_INCOMPLETE';
  end if;
end
$context_post$;


commit;
