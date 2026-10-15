-- Router read-only access + DB_WRITE_TRANSPORT v2.1.0.
-- 1) Lets read-only agents resolve the Router (ACT-0001): EXECUTE on
--    lf_router_resolve_v1 for supabase_read_only_user. The function is STABLE
--    and not SECURITY DEFINER, so it runs with the caller's read-only rights.
-- 2) Registers DB_WRITE_TRANSPORT 2.1.0 (code merged in PR #2347, main 3e57646e5f65247a7962223b1adecd24e8e2e991):
--    Train checklist, read-only denial rule, execution request, prevention rules.
-- Requires EXEC-DB-ROUTER-RO-TRANSPORT-V21-20261012-001 (ACTUALIZACION_DB_LF, IN_PROGRESS).
begin;

do $pre$
begin
  if not exists (
    select 1 from public.lf_operation_execution
    where execution_id = 'EXEC-DB-ROUTER-RO-TRANSPORT-V21-20261012-001'
      and operation_code = 'ACTUALIZACION_DB_LF' and status = 'IN_PROGRESS'
  ) then
    raise exception 'LF_ROUTER_RO_V21_EXECUTION_MISSING';
  end if;
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'lf_router_resolve_v1'
      and pg_get_function_identity_arguments(p.oid) = 'p_request_text text, p_target_hint text, p_action_hint text, p_asset_type_hint text, p_distribution_mode text'
      and p.provolatile = 's' and not p.prosecdef
  ) then
    raise exception 'LF_ROUTER_RO_V21_ROUTER_NOT_STABLE_INVOKER';
  end if;
  if (select version from public.lf_capability_current where capability_code = 'DB_WRITE_TRANSPORT') <> '2.0.0' then
    raise exception 'LF_ROUTER_RO_V21_UNEXPECTED_CURRENT';
  end if;
  if (select count(*) from transversal.prevention_rules
      where activa is true and regla_codigo in ('PRV-CI-009','PRV-DB-GIT-FIRST-PERSISTENT-OBJECT-001',
        'PRV-SQL-001','PRV-SQL-007','PRV-SQL-012','PRV-RTE-006')) <> 6 then
    raise exception 'LF_ROUTER_RO_V21_PREVENTION_RULES_MISSING';
  end if;
end $pre$;

grant execute on function public.lf_router_resolve_v1(text, text, text, text, text) to supabase_read_only_user;

with base as (
  select manifest from public.lf_capability_version_registry
  where capability_code = 'DB_WRITE_TRANSPORT' and version = '2.0.0'
), m as (
  select jsonb_set(jsonb_set(jsonb_set(jsonb_set(
           manifest || jsonb_build_object('version', '2.1.0'),
           '{agent_route}',
           (manifest->'agent_route') || jsonb_build_object(
             'router_passage', jsonb_build_array('ROUTER_OPERATION_FROM_LF_ROUTER_RESOLVE_V1', 'ACTUALIZACION_DB_LF_EXECUTION_ID'),
             'router_resolve_function', 'public.lf_router_resolve_v1',
             'router_resolve_readonly', true,
             'steps', jsonb_build_array('ONE_MIGRATION_FILE','ONE_MIGRATION_PER_PR','NAME_PER_POL_LF_MIGRATION_NAMING',
                                        'VERSION_IS_ASSIGNED_OR_REASSIGNED_BY_TRAIN','OPEN_PR_NOT_DRAFT',
                                        'REQUIRED_CHECKS_GREEN_ON_EXACT_HEAD','ONE_TRAIN_AT_A_TIME',
                                        'LABEL_READY_TO_MERGE','MERGE_TRAIN_APPLIES_AND_MERGES','LEDGER_AND_MAIN_READBACK'),
             'on_denied', 'READ_ONLY_OR_PERMISSION_DENIAL_IS_INTENTIONAL_DO_NOT_SEEK_ANOTHER_ROUTE_USE_MERGE_TRAIN',
             'execution_request', 'IF_NO_EXECUTION_STATE_EXACT_TARGET_IN_PR_AND_REQUEST_IT_FROM_OWNER;TRAIN_MANAGED_EXECUTION_WHEN_ENABLED',
             'prevention_rules', jsonb_build_array('PRV-CI-009','PRV-DB-GIT-FIRST-PERSISTENT-OBJECT-001',
                                                   'PRV-SQL-001','PRV-SQL-007','PRV-SQL-012','PRV-RTE-006'),
             'train_rejections', jsonb_build_array('FAIL_TRAIN_DRAFT_PR','FAIL_UNCLASSIFIED_MIGRATION_PRE_APPLY'))),
           '{usage,agent_cli}',
           to_jsonb('python sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py --target-type <TYPE> [--migration-path <path>] --router-operation ACTUALIZACION_DB_LF | --router-execution-id EXEC-...'::text)),
           '{currentness,authority_ref}', to_jsonb('github://cristhianlujan/claude-persona-lf-patch@3e57646e5f65247a7962223b1adecd24e8e2e991'::text)),
           '{compatibility,breaking_change_from}', to_jsonb('1.0.0'::text)) as manifest
  from base
)
insert into public.lf_capability_version_registry (
  capability_code, version, version_major, version_minor, version_patch,
  release_state, supersedes_version, manifest, manifest_sha256,
  source_ref, docs_ref, validator_ref, created_by_execution_id
)
select 'DB_WRITE_TRANSPORT', '2.1.0', 2, 1, 0, 'RELEASED', '2.0.0', manifest, repeat('0', 64),
  'github://cristhianlujan/claude-persona-lf-patch@3e57646e5f65247a7962223b1adecd24e8e2e991/sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py',
  'github://cristhianlujan/claude-persona-lf-patch@3e57646e5f65247a7962223b1adecd24e8e2e991/sandbox/lf_contract_gate_test/db_write_transport/README.md',
  'github://cristhianlujan/claude-persona-lf-patch@3e57646e5f65247a7962223b1adecd24e8e2e991/sandbox/lf_contract_gate_test/db_write_transport/lf_db_write_transport.py#self_test',
  'EXEC-DB-ROUTER-RO-TRANSPORT-V21-20261012-001'
from m;

update public.lf_capability_current
set version = '2.1.0',
    manifest_sha256 = (select manifest_sha256 from public.lf_capability_version_registry
                       where capability_code = 'DB_WRITE_TRANSPORT' and version = '2.1.0'),
    previous_version = '2.0.0',
    promoted_at = clock_timestamp(),
    promoted_by_execution_id = 'EXEC-DB-ROUTER-RO-TRANSPORT-V21-20261012-001',
    promotion_reason = 'Train checklist, read-only denial rule, execution request, prevention rules; Router readable by read-only agents (PR #2347, owner-approved)'
where capability_code = 'DB_WRITE_TRANSPORT' and version = '2.0.0';

do $post$
declare v_sha text;
begin
  if not has_function_privilege('supabase_read_only_user',
       'public.lf_router_resolve_v1(text,text,text,text,text)', 'EXECUTE') then
    raise exception 'LF_ROUTER_RO_V21_GRANT_MISSING';
  end if;
  if has_function_privilege('anon', 'public.lf_router_resolve_v1(text,text,text,text,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.lf_router_resolve_v1(text,text,text,text,text)', 'EXECUTE') then
    raise exception 'LF_ROUTER_RO_V21_ROUTER_EXPOSED_TO_CLIENT_ROLES';
  end if;
  select manifest_sha256 into v_sha from public.lf_capability_version_registry
  where capability_code = 'DB_WRITE_TRANSPORT' and version = '2.1.0';
  if (select count(*) from public.v_lf_capability_entry_guard_v1
      where capability_code = 'DB_WRITE_TRANSPORT' and current_version = '2.1.0'
        and current_manifest_sha256 = v_sha and entry_guard_state = 'GUARDED') <> 1 then
    raise exception 'LF_ROUTER_RO_V21_NOT_CURRENT';
  end if;
  if (select manifest->'agent_route'->>'on_denied' from public.lf_capability_version_registry
      where capability_code = 'DB_WRITE_TRANSPORT' and version = '2.1.0') is null
     or (select manifest->'compatibility'->>'direct_mode' from public.lf_capability_version_registry
      where capability_code = 'DB_WRITE_TRANSPORT' and version = '2.1.0') <> 'RETIRED' then
    raise exception 'LF_ROUTER_RO_V21_MANIFEST_INVALID';
  end if;
end $post$;

commit;
