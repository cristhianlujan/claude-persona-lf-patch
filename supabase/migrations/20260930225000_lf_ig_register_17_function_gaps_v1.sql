-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M0.2
-- Register the 17 currently-unrepresented live IG functions without creating
-- duplicate assets or changing runtime behavior.
--
-- Strategy:
--   * 12 trigger guards extend the existing GUARD set (1 -> 13).
--   * 4 public wrappers extend their existing functional sets.
--   * the L1 source lookup becomes a member of the existing candidate source-inventory asset.
--
-- No new asset, relation, approval, promotion, or runtime binding is created.

begin;

do $register_17$
declare
  v_exec constant text := 'CHATGPT-IG-CV-M02-REGISTER-17-FUNCTION-GAPS-20260930';
  v_gap_count integer;
  v_gap_sha text;
  v_live_count integer;
  v_members jsonb;
  v_sha text;
  v_n integer;
  v_updated integer := 0;
  r record;
begin
  if (
    select count(*) from supabase_migrations.schema_migrations
    where version='20260930223000'
      and name='ig_cv_r16_git_first_database_governance_v1'
  ) <> 1 then
    raise exception 'R16_GIT_FIRST_GOVERNANCE_NOT_LEDGERED';
  end if;

  with live_ig as (
    select n.nspname schema_name,p.proname,pg_get_function_identity_arguments(p.oid) args,
           n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' identity
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where
      (
        n.nspname='programacion' and (
          p.proname like 'fn_input_governance_%'
          or p.proname like 'fn_input_readiness_%'
          or (p.proname like 'fn_input_%'
              and p.proname not like 'fn_input_governance_%'
              and p.proname not like 'fn_input_readiness_%')
          or p.proname='fn_lf_router_input_governance_resolve_v1'
          or p.proname like 'fn_guard_input_%'
        )
      )
      or (
        n.nspname='public' and p.proname in (
          'fn_input_governance_validator_resume_context_v1',
          'fn_input_governance_execute',
          'fn_input_governance_safe_autofix_v1',
          'fn_input_governance_curator_materialize_v1',
          'fn_input_governance_validator_validate_v1'
        )
      )
  ),
  member_covered as (
    select jsonb_array_elements_text(
      case when jsonb_typeof(raw_payload->'members')='array'
           then raw_payload->'members' else '[]'::jsonb end
    ) identity
    from public.lf_activos
    where archived_at is null
  ),
  covered as (
    select identity from member_covered
    union
    select l.identity
    from live_ig l
    where exists (
      select 1 from public.lf_activos a
      where a.archived_at is null
        and a.raw_payload->>'schema'=l.schema_name
        and a.raw_payload->>'function'=l.proname
    )
  ),
  gaps as (
    select identity from live_ig
    where identity not in (select identity from covered)
  )
  select
    (select count(*) from live_ig),
    count(*),
    encode(
      extensions.digest(
        convert_to(jsonb_agg(identity order by identity)::text,'UTF8'),
        'sha256'
      ),
      'hex'
    )
  into v_live_count,v_gap_count,v_gap_sha
  from gaps;

  if v_live_count <> 113
     or v_gap_count <> 17
     or v_gap_sha <> '6be620fe2dcf02350e4a7f7970281d1556296b20599e202f7c6d578c2a5e4691'
  then
    raise exception 'IG_FUNCTION_GAP_PREFLIGHT_DRIFT:live=%,gaps=%,sha=%',
      v_live_count,v_gap_count,v_gap_sha;
  end if;

  -- 12 additional trigger guards + existing readiness-run guard = 13.
  select
    jsonb_agg(
      n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'
      order by n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)
    ),
    count(*)
  into v_members,v_n
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname like 'fn_guard_input_%';

  v_sha := encode(extensions.digest(convert_to(v_members::text,'UTF8'),'sha256'),'hex');

  if v_n <> 13
     or v_sha <> 'e2e7b9954003bc6547efa5ef1c7df676bbf5aedf77065c53c5db803031d16c7e'
  then
    raise exception 'GUARD_SET_MEMBERS_DRIFT:n=%,sha=%',v_n,v_sha;
  end if;

  update public.lf_activos
     set raw_payload = raw_payload || jsonb_build_object(
           'members',v_members,
           'function_count',v_n,
           'members_sha256',v_sha
         ),
         metadata = metadata || jsonb_build_object(
           'registration_extension','M0.2_REGISTER_17_FUNCTION_GAPS_V1',
           'guard_member_count',13,
           'guard_registration_scope','ALL_LIVE_PROGRAMACION_FN_GUARD_INPUT',
           'm0_3_trigger_evidence','PR1318 / 21 trigger bindings baseline',
           'updated_by_r16_git_first',true
         ),
         updated_at=clock_timestamp(),
         updated_by_execution_id=v_exec
   where codigo_activo='PROGRAMACION_FN_INPUT_GOVERNANCE_GUARD_SET'
     and archived_at is null;

  if not found then raise exception 'GUARD_SET_ASSET_MISSING'; end if;
  v_updated := v_updated + 1;

  -- Four public wrappers extend the already-canonical functional sets.
  for r in
    select * from (values
      (
        'PROGRAMACION_FN_INPUT_GOVERNANCE_CURATION_SET',
        'public','fn_input_governance_curator_materialize_v1',
        8,
        '99a1192ddc1cb17420317a159b26127e184eb87d88750ae95f66ff52a41925ba'
      ),
      (
        'PROGRAMACION_FN_INPUT_GOVERNANCE_EXECUTION_SET',
        'public','fn_input_governance_execute',
        5,
        '2fad0d188cc5011661eb8697e5c5e109e34f049dd0cdb3123e2dc54d98fcbaf5'
      ),
      (
        'PROGRAMACION_FN_INPUT_GOVERNANCE_REMEDIATION_SET',
        'public','fn_input_governance_safe_autofix_v1',
        2,
        '8c9cf35f768169820ce44998650083954dada340a590d8c7a2a8b4824f3f133b'
      ),
      (
        'PROGRAMACION_FN_INPUT_GOVERNANCE_VALIDATION_SET',
        'public','fn_input_governance_validator_validate_v1',
        7,
        '4532074de481760ec0f801f27b7e2379a873fc4a2b41a9ed878c0dfcc163d729'
      )
    ) x(asset_code,wrapper_schema,wrapper_name,expected_count,expected_sha)
  loop
    select
      jsonb_agg(member order by member),
      count(*)
    into v_members,v_n
    from (
      select jsonb_array_elements_text(a.raw_payload->'members') member
      from public.lf_activos a
      where a.codigo_activo=r.asset_code and a.archived_at is null
      union
      select n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'
      from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
      where n.nspname=r.wrapper_schema and p.proname=r.wrapper_name
    ) m;

    v_sha := encode(extensions.digest(convert_to(v_members::text,'UTF8'),'sha256'),'hex');

    if v_n <> r.expected_count or v_sha <> r.expected_sha then
      raise exception 'WRAPPER_SET_DRIFT:% n=% sha=% expected_n=% expected_sha=%',
        r.asset_code,v_n,v_sha,r.expected_count,r.expected_sha;
    end if;

    update public.lf_activos
       set raw_payload = raw_payload || jsonb_build_object(
             'members',v_members,
             'function_count',v_n,
             'members_sha256',v_sha
           ),
           metadata = metadata || jsonb_build_object(
             'registration_extension','M0.2_REGISTER_17_FUNCTION_GAPS_V1',
             'public_facade_member',
               r.wrapper_schema||'.'||r.wrapper_name,
             'public_facade_registration','WRAPPER_OF_EXISTING_INTERNAL_FUNCTION_SET',
             'updated_by_r16_git_first',true
           ),
           updated_at=clock_timestamp(),
           updated_by_execution_id=v_exec
     where codigo_activo=r.asset_code
       and archived_at is null;

    if not found then raise exception 'TARGET_FUNCTION_SET_MISSING:%',r.asset_code; end if;
    v_updated := v_updated + 1;
  end loop;

  -- Register the lookup function as a member of the existing candidate capability.
  select
    jsonb_agg(
      n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'
      order by n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)
    ),
    count(*)
  into v_members,v_n
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname='fn_input_source_inventory_lookup_l1_v1';

  v_sha := encode(extensions.digest(convert_to(v_members::text,'UTF8'),'sha256'),'hex');

  if v_n <> 1
     or v_sha <> '4d1bb266643b9ad1c849a7a6a1dd3e6ac6d89a461616929062f10c79701578ce'
  then
    raise exception 'SOURCE_INVENTORY_LOOKUP_DRIFT:n=%,sha=%',v_n,v_sha;
  end if;

  update public.lf_activos
     set raw_payload = raw_payload || jsonb_build_object(
           'members',v_members,
           'function_count',v_n,
           'members_sha256',v_sha
         ),
         metadata = metadata || jsonb_build_object(
           'registration_extension','M0.2_REGISTER_17_FUNCTION_GAPS_V1',
           'lookup_function_registration','MEMBER_OF_EXISTING_CANDIDATE_CAPABILITY',
           'approval_status','NOT_APPROVED',
           'l2_decision_note','decidir en L2 si lo absorbe T-SOURCE',
           'updated_by_r16_git_first',true
         ),
         updated_at=clock_timestamp(),
         updated_by_execution_id=v_exec
   where codigo_activo='PROGRAMACION_INPUT_SOURCE_INVENTORY_L1'
     and archived_at is null
     and estado_documental='CANDIDATO';

  if not found then raise exception 'SOURCE_INVENTORY_CANDIDATE_ASSET_MISSING_OR_NOT_CANDIDATE'; end if;
  v_updated := v_updated + 1;

  if v_updated <> 6 then
    raise exception 'TARGET_ASSET_UPDATE_COUNT_DRIFT:%',v_updated;
  end if;

  -- Postflight: every live IG function in the M0.2 proper set is now represented.
  with live_ig as (
    select n.nspname schema_name,p.proname,pg_get_function_identity_arguments(p.oid) args,
           n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' identity
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where
      (
        n.nspname='programacion' and (
          p.proname like 'fn_input_governance_%'
          or p.proname like 'fn_input_readiness_%'
          or (p.proname like 'fn_input_%'
              and p.proname not like 'fn_input_governance_%'
              and p.proname not like 'fn_input_readiness_%')
          or p.proname='fn_lf_router_input_governance_resolve_v1'
          or p.proname like 'fn_guard_input_%'
        )
      )
      or (
        n.nspname='public' and p.proname in (
          'fn_input_governance_validator_resume_context_v1',
          'fn_input_governance_execute',
          'fn_input_governance_safe_autofix_v1',
          'fn_input_governance_curator_materialize_v1',
          'fn_input_governance_validator_validate_v1'
        )
      )
  ),
  member_covered as (
    select jsonb_array_elements_text(
      case when jsonb_typeof(raw_payload->'members')='array'
           then raw_payload->'members' else '[]'::jsonb end
    ) identity
    from public.lf_activos
    where archived_at is null
  ),
  covered as (
    select identity from member_covered
    union
    select l.identity
    from live_ig l
    where exists (
      select 1 from public.lf_activos a
      where a.archived_at is null
        and a.raw_payload->>'schema'=l.schema_name
        and a.raw_payload->>'function'=l.proname
    )
  )
  select count(*)
  into v_gap_count
  from live_ig
  where identity not in (select identity from covered);

  if v_gap_count <> 0 then
    raise exception 'IG_FUNCTION_REGISTRY_POSTFLIGHT_GAPS:%',v_gap_count;
  end if;

  -- Candidate status of source inventory must remain unchanged.
  if not exists (
    select 1
    from public.lf_activos
    where codigo_activo='PROGRAMACION_INPUT_SOURCE_INVENTORY_L1'
      and archived_at is null
      and estado_documental='CANDIDATO'
      and estado_operativo='READ_ONLY'
      and runtime_estado='CANDIDATE_READ_ONLY'
      and metadata->>'approval_status'='NOT_APPROVED'
      and metadata->>'l2_decision_note'='decidir en L2 si lo absorbe T-SOURCE'
  ) then
    raise exception 'SOURCE_INVENTORY_CANDIDATE_STATE_CHANGED';
  end if;
end
$register_17$;

commit;
