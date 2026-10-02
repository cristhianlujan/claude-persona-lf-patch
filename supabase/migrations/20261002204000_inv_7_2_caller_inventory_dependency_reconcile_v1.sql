-- INV-7.2 — lf-profiles-governance-caller-v1 inventory/dependency reconciliation.
-- Git-first / EXACT_VERSION_SOURCE_FIRST.
-- Frozen source: main 0c3df451674a0c003b7b6f4eaeac649d2b84023b.
-- Runtime readback: deployed bundle _18, runtime SHA-256
-- 022f49c56d4a715023959a10e2b0ad602331de27ce142185f073e6e0e1d31936.
--
-- Deliberate omission / INV-9.5:
-- repo://.github/workflows/lf-input-governance-recurate-dispatch.yml is present
-- in GitHub main but has no baseline row in inventory.objects at authoring time.
-- Therefore wrapper -> reusable is NOT created here. Do not insert that repo object
-- manually. If the baseline appears before apply, this migration blocks and must
-- be regenerated so the dependency can be represented from a valid baseline.
--
-- This migration does NOT mutate inventory currentness and does NOT invoke
-- inventory.fn_apply_external_currentness_observation_v1.

do $inv_7_2_preflight$
declare
  v_entry_contract jsonb;
  v_entry_sha text;
  v_bad integer;
begin
  select metadata->'entry_contract'
    into v_entry_contract
  from public.lf_activos
  where id=226
    and codigo_activo='EDGE_FN_LF_PROFILES_GOVERNANCE_CALLER_V1'
    and archived_at is null
    and estado_operativo in ('ACTIVO','APROBADO','READ_ONLY');

  if not found then
    raise exception 'INV_7_2_LF_ACTIVO_226_NOT_ACTIVE';
  end if;

  v_entry_sha := encode(digest(v_entry_contract::text,'sha256'),'hex');
  if v_entry_sha <> '19fb5d15b533fcab6a1fc46a23d442f29a015201648fed41ff65f4d7180d81b0' then
    raise exception 'INV_7_2_ENTRY_CONTRACT_PRECONDITION_FAILED expected=% actual=%',
      '19fb5d15b533fcab6a1fc46a23d442f29a015201648fed41ff65f4d7180d81b0',
      coalesce(v_entry_sha,'NULL');
  end if;

  select count(*) into v_bad
  from (
    values
      (5775::bigint,'edge://lf-profiles-governance-caller-v1'::text),
      (5773::bigint,'edge://input-governance-agent-v1'::text),
      (5744::bigint,'edge://run-creacion-perfil-lf'::text),
      (72931::bigint,'dbfunc://public.lf_input_gov_recuration_allowlist_v1()'::text),
      (54690::bigint,'repo://.github/workflows/lf-input-governance-recurate.yml'::text)
  ) expected(object_id,object_ref)
  left join inventory.objects o
    on o.object_id=expected.object_id
   and o.object_ref=expected.object_ref
   and o.active
  where o.object_id is null;

  if v_bad <> 0 then
    raise exception 'INV_7_2_TARGET_OBJECT_PRECONDITION_FAILED count=%',v_bad;
  end if;

  if exists (
    select 1
    from inventory.objects
    where object_ref='repo://.github/workflows/lf-input-governance-recurate-dispatch.yml'
      and active
  ) then
    raise exception 'INV_7_2_WRAPPER_BASELINE_STATE_CHANGED_REAUTHOR_REQUIRED';
  end if;

  select count(*) into v_bad
  from inventory.dependencies
  where active
    and relation_type='CALLS'
    and (
      (dependency_key='GITHUB_CALLS|5775|5773'
       and source_object_id=5775 and target_object_id=5773
       and target_ref='edge://input-governance-agent-v1')
      or
      (dependency_key='GITHUB_CALLS|5775|5744'
       and source_object_id=5775 and target_object_id=5744
       and target_ref='edge://run-creacion-perfil-lf')
    );

  if v_bad <> 2 then
    raise exception 'INV_7_2_EXISTING_CALLS_PRECONDITION_FAILED expected=2 actual=%',v_bad;
  end if;

  if exists (
    select 1
    from inventory.dependencies
    where dependency_key='GITHUB_CALLS|5775|72931'
      and (
        source_object_id<>5775
        or target_object_id<>72931
        or target_ref<>'dbfunc://public.lf_input_gov_recuration_allowlist_v1()'
        or relation_type<>'CALLS'
      )
  ) then
    raise exception 'INV_7_2_DB_FUNC_DEPENDENCY_KEY_CONFLICT';
  end if;

  update public.lf_activos
  set version='v8',
      raw_payload=
        coalesce(raw_payload,'{}'::jsonb)
        || jsonb_build_object(
          'deployed_version',18,
          'runtime_sha256','022f49c56d4a715023959a10e2b0ad602331de27ce142185f073e6e0e1d31936',
          'merge_commit_sha','fe7e91ef2553b2604349a16010d49eed759dbf20',
          'index_blob','c77e2759640b9465eb11e0a10d00b8d102332253',
          'caller_blob','e21da4660dd9fd3ab24b6abf9f03da98f58a67fe'
        ),
      metadata=
        jsonb_set(
          jsonb_set(
            jsonb_set(
              jsonb_set(
                coalesce(metadata,'{}'::jsonb),
                '{riesgos}',
                to_jsonb('Caller fail-closed: las rutas requieren configuración LF_CALLER_* válida. La recuración está limitada por identidad OIDC exacta y allowlist gobernada por RPC public.lf_input_gov_recuration_allowlist_v1 / regla 661. verify_jwt=false es intencional: la autenticación OIDC se valida dentro del caller.'::text),
                true
              ),
              '{auth_real}',
              to_jsonb('GitHub Actions OIDC validado en código: issuer/JWKS/RS256, repository y repository_id exactos; identidad legacy preservada; reusable push/workflow_call y workflow_dispatch exactos sobre main; scope INPUT_GOVERNANCE_RECURATION_ONLY.'::text),
              true
            ),
            '{lectura_fecha}',
            to_jsonb('2026-10-02'::text),
            true
          ),
          '{entry_contract}',
          v_entry_contract,
          true
        ),
      updated_at=clock_timestamp()
  where id=226
    and codigo_activo='EDGE_FN_LF_PROFILES_GOVERNANCE_CALLER_V1'
    and archived_at is null;

  if not found then
    raise exception 'INV_7_2_LF_ACTIVO_226_UPDATE_MISSING';
  end if;

  select encode(digest((metadata->'entry_contract')::text,'sha256'),'hex')
    into v_entry_sha
  from public.lf_activos
  where id=226;

  if v_entry_sha <> '19fb5d15b533fcab6a1fc46a23d442f29a015201648fed41ff65f4d7180d81b0' then
    raise exception 'INV_7_2_ENTRY_CONTRACT_CHANGED_AFTER_ASSET_UPDATE actual=%',
      coalesce(v_entry_sha,'NULL');
  end if;
end
$inv_7_2_preflight$;

-- Refresh the two existing runtime CALLS from the real implementation file.
update inventory.dependencies
set evidence_type='GITHUB_TYPESCRIPT_CALL_RUNTIME',
    evidence='callRuntime("input-governance-agent-v1", ...)',
    source_system='GITHUB_MAIN_STATIC_ANALYSIS',
    metadata=
      coalesce(metadata,'{}'::jsonb)
      || jsonb_build_object(
        'unit','INV-7.2',
        'observed_main_sha','0c3df451674a0c003b7b6f4eaeac649d2b84023b',
        'source_path','supabase/functions/lf-profiles-governance-caller-v1/caller.ts',
        'source_blob','e21da4660dd9fd3ab24b6abf9f03da98f58a67fe',
        'source_code_object_ref','repo://supabase/functions/lf-profiles-governance-caller-v1/caller.ts'
      ),
    last_verified_at=clock_timestamp(),
    active=true
where dependency_key='GITHUB_CALLS|5775|5773'
  and source_object_id=5775
  and target_object_id=5773
  and relation_type='CALLS';

update inventory.dependencies
set evidence_type='GITHUB_TYPESCRIPT_CALL_RUNTIME',
    evidence='callRuntime("run-creacion-perfil-lf", ...)',
    source_system='GITHUB_MAIN_STATIC_ANALYSIS',
    metadata=
      coalesce(metadata,'{}'::jsonb)
      || jsonb_build_object(
        'unit','INV-7.2',
        'observed_main_sha','0c3df451674a0c003b7b6f4eaeac649d2b84023b',
        'source_path','supabase/functions/lf-profiles-governance-caller-v1/caller.ts',
        'source_blob','e21da4660dd9fd3ab24b6abf9f03da98f58a67fe',
        'source_code_object_ref','repo://supabase/functions/lf-profiles-governance-caller-v1/caller.ts'
      ),
    last_verified_at=clock_timestamp(),
    active=true
where dependency_key='GITHUB_CALLS|5775|5744'
  and source_object_id=5775
  and target_object_id=5744
  and relation_type='CALLS';

-- New caller -> allowlist DB function CALLS edge.
-- evidence_type intentionally reuses the existing inventory vocabulary.
insert into inventory.dependencies(
  source_object_id,target_object_id,target_ref,relation_type,
  evidence_type,evidence,confidence,source_system,metadata,
  first_seen_at,last_verified_at,active,dependency_key
)
values(
  5775,72931,'dbfunc://public.lf_input_gov_recuration_allowlist_v1()','CALLS',
  'GITHUB_TYPESCRIPT_CALL_RUNTIME',
  'POST /rest/v1/rpc/lf_input_gov_recuration_allowlist_v1',
  1.0000,'GITHUB_MAIN_STATIC_ANALYSIS',
  jsonb_build_object(
    'unit','INV-7.2',
    'observed_main_sha','0c3df451674a0c003b7b6f4eaeac649d2b84023b',
    'source_path','supabase/functions/lf-profiles-governance-caller-v1/caller.ts',
    'source_blob','e21da4660dd9fd3ab24b6abf9f03da98f58a67fe',
    'source_code_object_ref','repo://supabase/functions/lf-profiles-governance-caller-v1/caller.ts'
  ),
  clock_timestamp(),clock_timestamp(),true,'GITHUB_CALLS|5775|72931'
)
on conflict (dependency_key) do update
set source_object_id=excluded.source_object_id,
    target_object_id=excluded.target_object_id,
    target_ref=excluded.target_ref,
    relation_type=excluded.relation_type,
    evidence_type=excluded.evidence_type,
    evidence=excluded.evidence,
    confidence=excluded.confidence,
    source_system=excluded.source_system,
    metadata=excluded.metadata,
    last_verified_at=excluded.last_verified_at,
    active=true;

do $inv_7_2_readback$
declare
  v_count integer;
  v_entry_sha text;
  v_asset_ok boolean;
begin
  select
    version='v8'
    and raw_payload->>'deployed_version'='18'
    and raw_payload->>'runtime_sha256'='022f49c56d4a715023959a10e2b0ad602331de27ce142185f073e6e0e1d31936'
    and raw_payload->>'merge_commit_sha'='fe7e91ef2553b2604349a16010d49eed759dbf20'
    and raw_payload->>'index_blob'='c77e2759640b9465eb11e0a10d00b8d102332253'
    and raw_payload->>'caller_blob'='e21da4660dd9fd3ab24b6abf9f03da98f58a67fe',
    encode(digest((metadata->'entry_contract')::text,'sha256'),'hex')
  into v_asset_ok,v_entry_sha
  from public.lf_activos
  where id=226
    and archived_at is null;

  if coalesce(v_asset_ok,false) is not true then
    raise exception 'INV_7_2_ASSET_READBACK_FAILED';
  end if;

  if v_entry_sha <> '19fb5d15b533fcab6a1fc46a23d442f29a015201648fed41ff65f4d7180d81b0' then
    raise exception 'INV_7_2_ENTRY_CONTRACT_READBACK_FAILED actual=%',coalesce(v_entry_sha,'NULL');
  end if;

  select count(*) into v_count
  from inventory.dependencies
  where dependency_key in ('GITHUB_CALLS|5775|5773','GITHUB_CALLS|5775|5744')
    and active
    and relation_type='CALLS'
    and metadata->>'source_path'='supabase/functions/lf-profiles-governance-caller-v1/caller.ts'
    and metadata->>'source_blob'='e21da4660dd9fd3ab24b6abf9f03da98f58a67fe';

  if v_count <> 2 then
    raise exception 'INV_7_2_REFRESHED_CALLS_READBACK_FAILED expected=2 actual=%',v_count;
  end if;

  select count(*) into v_count
  from inventory.dependencies
  where dependency_key='GITHUB_CALLS|5775|72931'
    and source_object_id=5775
    and target_object_id=72931
    and target_ref='dbfunc://public.lf_input_gov_recuration_allowlist_v1()'
    and relation_type='CALLS'
    and active;

  if v_count <> 1 then
    raise exception 'INV_7_2_DB_FUNC_CALL_READBACK_FAILED expected=1 actual=%',v_count;
  end if;

  select count(*) into v_count
  from inventory.fn_dependencies_v1(
    'edge://lf-profiles-governance-caller-v1',
    'BOTH',
    4
  ) d
  where d.direction='OUT'
    and d.relation_type='CALLS'
    and d.target_ref='dbfunc://public.lf_input_gov_recuration_allowlist_v1()';

  if v_count <> 1 then
    raise exception 'INV_7_2_FN_DEPENDENCIES_READBACK_FAILED expected=1 actual=%',v_count;
  end if;
end
$inv_7_2_readback$;
