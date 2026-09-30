-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M0.2
-- Register the 17 currently-unrepresented live IG functions without creating
-- duplicate assets or changing runtime behavior.
--
-- Strategy:
--   * 12 trigger guards extend the existing GUARD set (1 -> 13).
--   * 4 public wrappers extend their existing functional sets.
--   * the L1 source lookup becomes a member of the existing candidate source-inventory asset.
--
-- No new asset, approval, promotion, or runtime binding is created.
-- Five code-derived GUARD_SET dependency relations are added because the expanded
-- guard membership introduces real cross-set calls that were not representable before.

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
  v_relation_count integer := 0;
  v_relation_target_sha text;
  v_missing_edge_count integer := 0;
  v_relation_batch constant uuid := 'e14f1d14-5d36-4f6c-a01e-1a0f10132401'::uuid;
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
         rol_arquitectura='Trigger guards for Input Governance assessments, executions, gap proposals, parameter provenance, NA/stage/semantic coherence, and readiness runs.',
         metadata = metadata || jsonb_build_object(
           'registration_extension','M0.2_REGISTER_17_FUNCTION_GAPS_V1',
           'guard_member_count',13,
           'guard_registration_scope','ALL_LIVE_PROGRAMACION_FN_GUARD_INPUT',
           'm0_3_trigger_evidence','PR1318 / 21 trigger bindings baseline',
           'updated_by_r16_git_first',true,
           'lectura_alcance','13 funciones guard exactas por pg_get_function_identity_arguments; dependencias entre sets verificadas desde pg_proc.prosrc'
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
        '99a1192ddc1cb17420317a159b26127e184eb87d88750ae95f66ff52a41925ba',
        'Curator materialization, rebind, recuration, and public RPC facade wrapper.',
        '8 funciones exactas por pg_get_function_identity_arguments, incluida la fachada public del Curator'
      ),
      (
        'PROGRAMACION_FN_INPUT_GOVERNANCE_EXECUTION_SET',
        'public','fn_input_governance_execute',
        5,
        '2fad0d188cc5011661eb8697e5c5e109e34f049dd0cdb3123e2dc54d98fcbaf5',
        'Runtime execute and worker-spec functions, including the public execution facade.',
        '5 funciones exactas por pg_get_function_identity_arguments, incluida la fachada public de ejecución'
      ),
      (
        'PROGRAMACION_FN_INPUT_GOVERNANCE_REMEDIATION_SET',
        'public','fn_input_governance_safe_autofix_v1',
        2,
        '8c9cf35f768169820ce44998650083954dada340a590d8c7a2a8b4824f3f133b',
        'Safe-autofix remediation implementation and public RPC facade.',
        '2 funciones exactas por pg_get_function_identity_arguments: implementación y fachada public'
      ),
      (
        'PROGRAMACION_FN_INPUT_GOVERNANCE_VALIDATION_SET',
        'public','fn_input_governance_validator_validate_v1',
        7,
        '4532074de481760ec0f801f27b7e2379a873fc4a2b41a9ed878c0dfcc163d729',
        'Validator functions, including public resume-context and validation facade helpers.',
        '7 funciones exactas por pg_get_function_identity_arguments, incluidas las fachadas public del Validator'
      )
    ) x(asset_code,wrapper_schema,wrapper_name,expected_count,expected_sha,role_text,scope_text)
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
           rol_arquitectura=r.role_text,
           metadata = metadata || jsonb_build_object(
             'registration_extension','M0.2_REGISTER_17_FUNCTION_GAPS_V1',
             'public_facade_member',
               r.wrapper_schema||'.'||r.wrapper_name,
             'public_facade_registration','WRAPPER_OF_EXISTING_INTERNAL_FUNCTION_SET',
             'updated_by_r16_git_first',true,
             'lectura_alcance',r.scope_text
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
         rol_arquitectura='Inventario de fuentes de Input Governance L1 con lookup read-only; discovery index only, sin duplicar filas canónicas y pendiente de calificación transversal.',
         metadata = metadata || jsonb_build_object(
           'registration_extension','M0.2_REGISTER_17_FUNCTION_GAPS_V1',
           'lookup_function_registration','MEMBER_OF_EXISTING_CANDIDATE_CAPABILITY',
           'approval_status','NOT_APPROVED',
           'l2_decision_note','decidir en L2 si lo absorbe T-SOURCE',
           'updated_by_r16_git_first',true,
           'lectura_alcance','1 función lookup exacta por pg_get_function_identity_arguments; tabla/vista L1 permanecen discovery-only'
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

  -- The expanded GUARD_SET introduces five real cross-set dependencies.
  -- Derive them from pg_proc.prosrc (function body only) with schema-aware call parsing.
  with member_funcs as (
    select a.codigo_activo asset_code,
           n.nspname schema_name,
           p.proname,
           p.prosrc
    from public.lf_activos a
    cross join lateral jsonb_array_elements_text(a.raw_payload->'members') m(identity)
    join pg_proc p on true
    join pg_namespace n on n.oid=p.pronamespace
      and n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'=m.identity
    where a.archived_at is null
      and a.codigo_activo in (
        'PROGRAMACION_FN_INPUT_GOVERNANCE_GUARD_SET',
        'PROGRAMACION_FN_INPUT_GOVERNANCE_ASSERTION_ENGINE_SET',
        'PROGRAMACION_FN_INPUT_GOVERNANCE_NA_AUTHORITY_SET',
        'PROGRAMACION_FN_INPUT_GOVERNANCE_SECURITY_EXPECTATIONS_SET',
        'PROGRAMACION_FN_INPUT_GOVERNANCE_SEMANTIC_CLASSIFICATION_SET',
        'PROGRAMACION_FN_INPUT_GOVERNANCE_STAGE_AUTHORITY_SET',
        'PROGRAMACION_FN_INPUT_GOVERNANCE_CANONICAL_CONTEXT_SET'
      )
  ),
  calls as (
    select distinct f.asset_code caller_asset,
           f.proname caller_fn,
           nullif(x.m[2],'') call_schema,
           x.m[3] call_name
    from member_funcs f
    cross join lateral regexp_matches(
      f.prosrc,
      '(^|[^A-Za-z0-9_])(?:(public|programacion|lf_ops)\.)?(fn_[A-Za-z0-9_]+)[[:space:]]*\(',
      'g'
    ) x(m)
  ),
  guard_pairs as (
    select distinct c.caller_fn,b.asset_code callee_asset,b.proname callee_fn
    from calls c
    join member_funcs b
      on b.proname=c.call_name
     and (c.call_schema is null or b.schema_name=c.call_schema)
    where c.caller_asset='PROGRAMACION_FN_INPUT_GOVERNANCE_GUARD_SET'
      and b.asset_code<>c.caller_asset
  ),
  missing_edges as (
    select callee_asset,
           count(*) evidence_pairs,
           count(distinct caller_fn) unique_guard_callers
    from guard_pairs gp
    where not exists (
      select 1
      from public.lf_activo_relaciones rel
      where rel.codigo_activo='PROGRAMACION_FN_INPUT_GOVERNANCE_GUARD_SET'
        and rel.relacionado_codigo=gp.callee_asset
        and rel.relacion_tipo='DEPENDE_DE'
    )
    group by callee_asset
  )
  select count(*),
         encode(
           extensions.digest(
             convert_to(jsonb_agg(callee_asset order by callee_asset)::text,'UTF8'),
             'sha256'
           ),
           'hex'
         )
    into v_relation_count,v_relation_target_sha
  from missing_edges;

  if v_relation_count <> 5
     or v_relation_target_sha <> '371e98463f503372e8137dfdde3063250ffdc5129396968919d62d5ef6640d32'
  then
    raise exception 'GUARD_RELATION_PREFLIGHT_DRIFT:count=%,sha=%',
      v_relation_count,v_relation_target_sha;
  end if;

  with member_funcs as (
    select a.codigo_activo asset_code,
           n.nspname schema_name,
           p.proname,
           p.prosrc
    from public.lf_activos a
    cross join lateral jsonb_array_elements_text(a.raw_payload->'members') m(identity)
    join pg_proc p on true
    join pg_namespace n on n.oid=p.pronamespace
      and n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'=m.identity
    where a.archived_at is null
      and a.codigo_activo in (
        'PROGRAMACION_FN_INPUT_GOVERNANCE_GUARD_SET',
        'PROGRAMACION_FN_INPUT_GOVERNANCE_ASSERTION_ENGINE_SET',
        'PROGRAMACION_FN_INPUT_GOVERNANCE_NA_AUTHORITY_SET',
        'PROGRAMACION_FN_INPUT_GOVERNANCE_SECURITY_EXPECTATIONS_SET',
        'PROGRAMACION_FN_INPUT_GOVERNANCE_SEMANTIC_CLASSIFICATION_SET',
        'PROGRAMACION_FN_INPUT_GOVERNANCE_STAGE_AUTHORITY_SET',
        'PROGRAMACION_FN_INPUT_GOVERNANCE_CANONICAL_CONTEXT_SET'
      )
  ),
  calls as (
    select distinct f.asset_code caller_asset,
           f.proname caller_fn,
           nullif(x.m[2],'') call_schema,
           x.m[3] call_name
    from member_funcs f
    cross join lateral regexp_matches(
      f.prosrc,
      '(^|[^A-Za-z0-9_])(?:(public|programacion|lf_ops)\.)?(fn_[A-Za-z0-9_]+)[[:space:]]*\(',
      'g'
    ) x(m)
  ),
  guard_pairs as (
    select distinct c.caller_fn,b.asset_code callee_asset,b.proname callee_fn
    from calls c
    join member_funcs b
      on b.proname=c.call_name
     and (c.call_schema is null or b.schema_name=c.call_schema)
    where c.caller_asset='PROGRAMACION_FN_INPUT_GOVERNANCE_GUARD_SET'
      and b.asset_code<>c.caller_asset
  ),
  missing_edges as (
    select callee_asset,
           count(*) evidence_pairs,
           count(distinct caller_fn) unique_guard_callers
    from guard_pairs gp
    where not exists (
      select 1
      from public.lf_activo_relaciones rel
      where rel.codigo_activo='PROGRAMACION_FN_INPUT_GOVERNANCE_GUARD_SET'
        and rel.relacionado_codigo=gp.callee_asset
        and rel.relacion_tipo='DEPENDE_DE'
    )
    group by callee_asset
  )
  insert into public.lf_activo_relaciones(
    codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
    migration_batch_id,created_by_execution_id,updated_by_execution_id
  )
  select
    'PROGRAMACION_FN_INPUT_GOVERNANCE_GUARD_SET',
    callee_asset,
    'DEPENDE_DE',
    'pg_proc.prosrc schema-aware group edge GUARD_SET -> '||callee_asset||
      '; unique_guard_callers='||unique_guard_callers::text||
      '; evidence_pairs='||evidence_pairs::text,
    'supabase/migrations/20260930225000_lf_ig_register_17_function_gaps_v1.sql',
    v_relation_batch,
    v_exec,
    v_exec
  from missing_edges
  order by callee_asset;

  get diagnostics v_relation_count = row_count;
  if v_relation_count <> 5 then
    raise exception 'GUARD_RELATION_INSERT_COUNT:%',v_relation_count;
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

  -- Postcondition: every code-derived call between registered IG member sets
  -- must have a DEPENDE_DE relation. prosrc excludes CREATE FUNCTION headers;
  -- qualified calls resolve only to the qualified schema.
  with member_funcs as (
    select a.codigo_activo asset_code,
           n.nspname schema_name,
           p.proname,
           p.prosrc
    from public.lf_activos a
    cross join lateral jsonb_array_elements_text(
      case when jsonb_typeof(a.raw_payload->'members')='array'
           then a.raw_payload->'members' else '[]'::jsonb end
    ) m(identity)
    join pg_proc p on true
    join pg_namespace n on n.oid=p.pronamespace
      and n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'=m.identity
    where a.archived_at is null
      and jsonb_typeof(a.raw_payload->'members')='array'
      and (
        a.metadata->>'dominio'='INPUT_GOVERNANCE'
        or a.codigo_activo='PROGRAMACION_INPUT_SOURCE_INVENTORY_L1'
      )
  ),
  calls as (
    select distinct f.asset_code caller_asset,
           nullif(x.m[2],'') call_schema,
           x.m[3] call_name
    from member_funcs f
    cross join lateral regexp_matches(
      f.prosrc,
      '(^|[^A-Za-z0-9_])(?:(public|programacion|lf_ops)\.)?(fn_[A-Za-z0-9_]+)[[:space:]]*\(',
      'g'
    ) x(m)
  ),
  edges as (
    select distinct c.caller_asset,b.asset_code callee_asset
    from calls c
    join member_funcs b
      on b.proname=c.call_name
     and (c.call_schema is null or b.schema_name=c.call_schema)
    where c.caller_asset<>b.asset_code
  )
  select count(*)
    into v_missing_edge_count
  from edges e
  where not exists (
    select 1
    from public.lf_activo_relaciones rel
    where rel.codigo_activo=e.caller_asset
      and rel.relacionado_codigo=e.callee_asset
      and rel.relacion_tipo='DEPENDE_DE'
  );

  if v_missing_edge_count <> 0 then
    raise exception 'IG_CROSS_SET_RELATION_POSTFLIGHT_GAPS:%',v_missing_edge_count;
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
