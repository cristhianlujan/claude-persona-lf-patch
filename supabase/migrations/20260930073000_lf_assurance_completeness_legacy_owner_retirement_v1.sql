begin;

-- Assurance post-cutover cleanup.
-- Removes the legacy umbrella capability from generic repository-CI context
-- and retires its inventory ownership without deleting historical lineage.
-- No Assurance subject binding, runtime, deployment or production activation.

do $execution_guard$
declare
  v_execution_id constant text := 'EXEC-ASSURANCE-COMPLETENESS-RETIRE-20260930-001';
begin
  if not exists (
    select 1
    from public.lf_operation_execution e
    where e.execution_id = v_execution_id
      and e.operation_code = 'ACTUALIZACION_DB_LF'
      and e.target_type = 'MIGRATION'
      and e.target_code = 'ASSURANCE_COMPLETENESS_LEGACY_OWNER_RETIREMENT_V1'
      and e.target_repo = 'cristhianlujan/claude-persona-lf-patch'
      and e.target_path = 'supabase/migrations/20260930073000_lf_assurance_completeness_legacy_owner_retirement_v1.sql'
      and e.status = 'IN_PROGRESS'
  ) then
    raise exception 'BLOCK_ASSURANCE_COMPLETENESS_RETIREMENT_GOVERNED_EXECUTION:%', v_execution_id;
  end if;
end
$execution_guard$;

do $cutover$
declare
  v_execution_id constant text := 'EXEC-ASSURANCE-COMPLETENESS-RETIRE-20260930-001';
  v_current public.lf_policy_versions%rowtype;
  v_payload jsonb;
  v_sets jsonb;
  v_occurrences integer;
  v_repo_set_count integer;
  v_active_bindings integer;
  v_explicit_policy_bindings integer;
  v_sha text;
begin
  select * into v_current
  from public.lf_policy_versions
  where policy_code = 'POL-LF-POLICY-CONSUMPTION'
    and status = 'ACTIVE'
  order by effective_at desc
  limit 1
  for update;

  if not found
     or v_current.policy_version <> 'v1.2-context-admission'
     or v_current.policy_sha <> '9cbea9e36403439303312cd2e1d207c4506356624d224374cbe87220329fcbd5' then
    raise exception 'BLOCK_ASSURANCE_COMPLETENESS_POLICY_PRESTATE version=% sha=%',
      coalesce(v_current.policy_version,'MISSING'), coalesce(v_current.policy_sha,'MISSING');
  end if;

  if not exists (
    select 1
    from public.lf_activos a
    where a.id = 128
      and a.codigo_activo = 'ASSURANCE_COMPLETENESS'
      and a.nombre_canonico = 'TRANSVERSAL_ASSURANCE_COMPLETENESS'
      and a.tipo_activo = 'CAPABILITY'
      and a.estado_documental = 'VIGENTE'
      and a.estado_operativo = 'ACTIVO'
      and a.archived_at is null
      and a.metadata #>> '{transversal_inventory,inventory_status}' = 'ACTIVE_SHARED_ENFORCEMENT'
  ) then
    raise exception 'BLOCK_ASSURANCE_COMPLETENESS_ASSET_PRESTATE';
  end if;

  select count(*) into v_explicit_policy_bindings
  from public.lf_operation_policy_bindings b
  where b.policy_code = 'ASSURANCE_COMPLETENESS'
    and b.binding_status = 'ACTIVE';

  if v_explicit_policy_bindings <> 0 then
    raise exception 'BLOCK_ASSURANCE_COMPLETENESS_EXPLICIT_BINDINGS count=%', v_explicit_policy_bindings;
  end if;

  select count(*) into v_active_bindings
  from public.lf_assurance_subject_bindings
  where status = 'ACTIVE';

  if v_active_bindings <> 0 then
    raise exception 'BLOCK_ASSURANCE_COMPLETENESS_RETIREMENT_ASSURANCE_ACTIVE_BINDINGS count=%', v_active_bindings;
  end if;

  v_payload := v_current.policy_payload;

  select count(*) into v_repo_set_count
  from jsonb_array_elements(v_payload #> '{context_compilation,conditional_sets}') s(elem)
  where s.elem->>'set_id' = 'REPOSITORY_CI_SET_V1';

  select count(*) into v_occurrences
  from jsonb_array_elements(v_payload #> '{context_compilation,conditional_sets}') s(elem)
  cross join lateral jsonb_array_elements_text(coalesce(s.elem->'capabilities','[]'::jsonb)) c(value)
  where s.elem->>'set_id' = 'REPOSITORY_CI_SET_V1'
    and c.value = 'ASSURANCE_COMPLETENESS';

  if v_repo_set_count <> 1 or v_occurrences <> 1 then
    raise exception 'BLOCK_ASSURANCE_COMPLETENESS_CONTEXT_PRESTATE repo_sets=% occurrences=%',
      v_repo_set_count, v_occurrences;
  end if;

  select jsonb_agg(
           case
             when s.elem->>'set_id' = 'REPOSITORY_CI_SET_V1' then
               jsonb_set(
                 s.elem,
                 '{capabilities}',
                 coalesce(
                   (
                     select jsonb_agg(to_jsonb(c.value) order by c.ord)
                     from jsonb_array_elements_text(coalesce(s.elem->'capabilities','[]'::jsonb))
                          with ordinality c(value,ord)
                     where c.value <> 'ASSURANCE_COMPLETENESS'
                   ),
                   '[]'::jsonb
                 ),
                 true
               )
             else s.elem
           end
           order by s.ord
         )
  into v_sets
  from jsonb_array_elements(v_payload #> '{context_compilation,conditional_sets}')
       with ordinality s(elem,ord);

  v_payload := jsonb_set(v_payload, '{context_compilation,conditional_sets}', v_sets, true);
  v_payload := jsonb_set(v_payload, '{version}', to_jsonb('v1.3-assurance-cutover'::text), true);

  if (v_payload #> '{context_compilation}')::text like '%ASSURANCE_COMPLETENESS%' then
    raise exception 'BLOCK_ASSURANCE_COMPLETENESS_CONTEXT_POSTSTATE';
  end if;

  if not (
    (v_payload #> '{context_compilation,conditional_sets}')::text like '%CI_FAST_DEEP_LANE_ROUTER%'
    and (v_payload #> '{context_compilation,conditional_sets}')::text like '%REPOSITORY_GOVERNANCE_BUNDLE%'
  ) then
    raise exception 'BLOCK_ASSURANCE_COMPLETENESS_REPOSITORY_SET_COLLATERAL_DRIFT';
  end if;

  v_sha := encode(
    extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),
    'hex'
  );

  update public.lf_policy_versions
  set status = 'SUPERSEDED',
      superseded_at = clock_timestamp(),
      updated_at = clock_timestamp(),
      updated_by_execution_id = v_execution_id
  where policy_code = 'POL-LF-POLICY-CONSUMPTION'
    and policy_version = 'v1.2-context-admission'
    and status = 'ACTIVE';

  if not found then
    raise exception 'BLOCK_ASSURANCE_COMPLETENESS_POLICY_SUPERSEDE_FAILED';
  end if;

  insert into public.lf_policy_versions(
    policy_code, policy_version, policy_payload, policy_sha, status, effective_at,
    source_ref, created_by_execution_id, updated_by_execution_id
  ) values (
    'POL-LF-POLICY-CONSUMPTION',
    'v1.3-assurance-cutover',
    v_payload,
    v_sha,
    'ACTIVE',
    clock_timestamp(),
    'supabase/migrations/20260930073000_lf_assurance_completeness_legacy_owner_retirement_v1.sql',
    v_execution_id,
    v_execution_id
  );

  update public.lf_activos
  set estado_documental = 'LEGACY',
      estado_operativo = 'READ_ONLY',
      metadata = jsonb_set(
        coalesce(metadata,'{}'::jsonb),
        '{transversal_inventory,inventory_status}',
        to_jsonb('RETIRED_LEGACY_LINEAGE'::text),
        true
      ) || jsonb_build_object(
        'assurance_cutover_retirement', jsonb_build_object(
          'retired_by_execution_id', v_execution_id,
          'retired_at', to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
          'reason', 'UMBRELLA_OWNER_DECOMPOSED',
          'replacement_capabilities', jsonb_build_array(
            'OPERATION_TEST_COVERAGE',
            'TEST_COVERAGE_DEBT_GUARD',
            'ASSURANCE_EVALUATOR'
          ),
          'legacy_function_new_consumer_allowed', false
        )
      ),
      updated_by_execution_id = v_execution_id,
      updated_at = clock_timestamp()
  where id = 128
    and codigo_activo = 'ASSURANCE_COMPLETENESS'
    and archived_at is null;

  if not found then
    raise exception 'BLOCK_ASSURANCE_COMPLETENESS_ASSET_RETIREMENT_FAILED';
  end if;
end
$cutover$;

do $readback$
declare
  v_active_policy integer;
  v_legacy_policy integer;
  v_context_occurrences integer;
  v_active_bindings integer;
begin
  select count(*) into v_active_policy
  from public.lf_policy_versions
  where policy_code = 'POL-LF-POLICY-CONSUMPTION'
    and policy_version = 'v1.3-assurance-cutover'
    and status = 'ACTIVE'
    and (policy_payload #> '{context_compilation}')::text not like '%ASSURANCE_COMPLETENESS%';

  select count(*) into v_legacy_policy
  from public.lf_policy_versions
  where policy_code = 'POL-LF-POLICY-CONSUMPTION'
    and policy_version = 'v1.2-context-admission'
    and status = 'SUPERSEDED';

  select count(*) into v_context_occurrences
  from public.lf_policy_versions p
  cross join lateral jsonb_array_elements(p.policy_payload #> '{context_compilation,conditional_sets}') s(elem)
  cross join lateral jsonb_array_elements_text(coalesce(s.elem->'capabilities','[]'::jsonb)) c(value)
  where p.policy_code = 'POL-LF-POLICY-CONSUMPTION'
    and p.status = 'ACTIVE'
    and c.value = 'ASSURANCE_COMPLETENESS';

  select count(*) into v_active_bindings
  from public.lf_assurance_subject_bindings
  where status = 'ACTIVE';

  if v_active_policy <> 1 or v_legacy_policy <> 1 or v_context_occurrences <> 0 then
    raise exception 'BLOCK_ASSURANCE_COMPLETENESS_POLICY_READBACK active=% legacy=% context_occurrences=%',
      v_active_policy, v_legacy_policy, v_context_occurrences;
  end if;

  if not exists (
    select 1 from public.lf_activos a
    where a.id = 128
      and a.codigo_activo = 'ASSURANCE_COMPLETENESS'
      and a.estado_documental = 'LEGACY'
      and a.estado_operativo = 'READ_ONLY'
      and a.metadata #>> '{transversal_inventory,inventory_status}' = 'RETIRED_LEGACY_LINEAGE'
      and a.metadata #>> '{assurance_cutover_retirement,reason}' = 'UMBRELLA_OWNER_DECOMPOSED'
      and coalesce((a.metadata #>> '{assurance_cutover_retirement,legacy_function_new_consumer_allowed}')::boolean,true) = false
  ) then
    raise exception 'BLOCK_ASSURANCE_COMPLETENESS_ASSET_READBACK';
  end if;

  if v_active_bindings <> 0 then
    raise exception 'BLOCK_ASSURANCE_COMPLETENESS_BINDING_READBACK count=%', v_active_bindings;
  end if;
end
$readback$;

commit;
