-- ENGINEERING artifact role separation v1.
-- Evidence/source artifacts must never become WRITE_GIT targets by mere presence.
-- Only explicit mutation_artifacts (or legacy items explicitly role=MUTATION_TARGET)
-- are writable repository targets.

create or replace function programacion.fn_engineering_action_spec_artifact_roles_v1(
  p_spec jsonb
)
returns jsonb
language plpgsql
immutable
set search_path to 'pg_catalog'
as $function$
declare
  v_spec jsonb := coalesce(p_spec,'{}'::jsonb);
  v_target jsonb := coalesce(v_spec->'target','{}'::jsonb);
  v_declared jsonb := coalesce(v_target->'declared_artifacts','[]'::jsonb);
  v_evidence jsonb := coalesce(v_target->'evidence_artifacts',v_declared,'[]'::jsonb);
  v_mutation jsonb := coalesce(v_target->'mutation_artifacts','[]'::jsonb);
  v_legacy_mutation jsonb := '[]'::jsonb;
  v_item jsonb;
begin
  if jsonb_typeof(v_declared)='array' then
    for v_item in select value from jsonb_array_elements(v_declared)
    loop
      if upper(coalesce(v_item->>'role',''))='MUTATION_TARGET' then
        v_legacy_mutation:=v_legacy_mutation||jsonb_build_array(v_item);
      end if;
    end loop;
  end if;

  if jsonb_typeof(v_mutation)<>'array' then
    v_mutation:='[]'::jsonb;
  end if;
  v_mutation:=v_mutation||v_legacy_mutation;

  v_target:=v_target
    || jsonb_build_object(
      'evidence_artifacts',v_evidence,
      'mutation_artifacts',v_mutation,
      -- Compatibility surface consumed by the legacy packet compiler.
      -- It now receives only actual mutation targets.
      'declared_artifacts',v_mutation
    );

  v_spec:=jsonb_set(v_spec,'{target}',v_target,true);

  return v_spec || jsonb_build_object(
    'artifact_role_contract',jsonb_build_object(
      'schema_version','ENGINEERING_ARTIFACT_ROLE_CONTRACT_V1',
      'legacy_declared_artifacts_role','EVIDENCE_ONLY_UNLESS_EXPLICIT_MUTATION_ROLE',
      'evidence_artifact_write_authority',false,
      'mutation_artifact_write_authority','EXPLICIT_ONLY',
      'evidence_artifact_count',
        case when jsonb_typeof(v_evidence)='array' then jsonb_array_length(v_evidence) else 0 end,
      'mutation_artifact_count',jsonb_array_length(v_mutation)
    )
  );
end;
$function$;

comment on function programacion.fn_engineering_action_spec_artifact_roles_v1(jsonb)
is 'Separates evidence artifacts from mutation artifacts. Legacy declared_artifacts are evidence-only unless an item explicitly declares role=MUTATION_TARGET.';

create or replace function programacion.fn_engineering_action_spec_apply_git_migration_guard_v1(
  p_spec jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_spec jsonb := coalesce(p_spec,'{}'::jsonb);
  v_title text := lower(coalesce(v_spec->>'checkpoint_title',''));
  v_material boolean := coalesce((v_spec->>'requires_material_execution')::boolean,false);
  v_expects_migration boolean := false;
  v_has_migration boolean := false;
  v_mutation_artifacts jsonb;
begin
  if coalesce(v_spec->>'status','')<>'READY' then
    return v_spec;
  end if;

  v_expects_migration :=
    v_material
    and (
      coalesce(v_spec->>'recipe_mode','') in ('GIT_FIRST_MIGRATION','GIT_FIRST_OR_VERSIONED_CONTRACT')
      or (
        v_title ~ '(migraci|git-first)'
        and v_title !~ '(fuera de|sin|excepto|salvo) (las |los )?migraci'
      )
    );

  if not v_expects_migration then
    return v_spec;
  end if;

  v_mutation_artifacts :=
    programacion.fn_engineering_action_spec_artifact_roles_v1(v_spec)
    #>'{target,mutation_artifacts}';

  select exists(
    select 1
    from jsonb_array_elements(coalesce(v_mutation_artifacts,'[]'::jsonb)) a(item)
    where coalesce(a.item->>'path','') like '%:supabase/migrations/%'
       or coalesce(a.item->>'path','') like '%/supabase/migrations/%'
  ) into v_has_migration;

  if v_has_migration then
    return v_spec;
  end if;

  return v_spec || jsonb_build_object(
    'status','BLOCK_GIT_MIGRATION_ARTIFACT_NOT_AUTHORED',
    'precision','EXPLICIT_GIT_FIRST_MIGRATION_OUTPUT_REQUIRED',
    'migration_guard',jsonb_build_object(
      'expected_output','supabase/migrations/<version>_<name>.sql',
      'declared_migration_artifact_present',false,
      'mutation_artifact_required',true,
      'evidence_artifacts_do_not_satisfy_output',true,
      'docs_or_auxiliary_artifacts_do_not_satisfy_output',true
    ),
    'forbidden',
      coalesce(v_spec->'forbidden','[]'::jsonb)
      || jsonb_build_array(
        'ACTION_SPEC_READY_WITHOUT_REQUIRED_MIGRATION_OUTPUT',
        'TREAT_DOC_AS_MIGRATION_OUTPUT',
        'TREAT_EVIDENCE_ARTIFACT_AS_MUTATION_TARGET'
      )
  );
end;
$function$;

create or replace function programacion.fn_engineering_execution_packet_from_spec_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_action_spec jsonb,
  p_execution_input jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_packet jsonb;
  v_budget int;
  v_spec jsonb := programacion.fn_engineering_action_spec_artifact_roles_v1(
    coalesce(p_action_spec,'{}'::jsonb)
  );
  v_material boolean := coalesce((p_action_spec->>'requires_material_execution')::boolean,false);
  v_kind text := coalesce(p_action_spec->>'action_kind','');
  v_title text := coalesce(p_action_spec->>'checkpoint_title','');
begin
  if v_material
     and v_kind not in ('READBACK_ONCE','OBSERVE_ONCE','DECISION_GATE','TERMINAL_RECONCILE') then
    v_spec := jsonb_set(
      v_spec,
      '{checkpoint_title}',
      to_jsonb('execute material: ' || v_title),
      true
    );
  end if;

  v_packet:=programacion.fn_engineering_execution_packet_from_spec_core_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,v_spec,p_execution_input
  );

  v_packet:=programacion.fn_engineering_execution_packet_apply_transversal_adapter_v1(
    v_packet,p_plan_code,p_unit_code,p_checkpoint_code,p_action_spec
  );

  v_packet:=programacion.fn_engineering_packet_apply_test_contract_guard_v1(
    v_packet,p_action_spec
  );

  v_budget:=nullif(p_action_spec#>>'{read_budget,checkpoint_queries_max}','')::int;

  if v_budget is null then
    select nullif(
      coalesce(
        pu.unit_metadata#>>'{source_fast_path_v2,read_budget,checkpoint_queries_max}',
        pu.unit_metadata#>>'{source_fast_path_v1,preferred_queries_max}'
      ),''
    )::int
    into v_budget
    from programacion.engineering_plan_units pu
    where pu.plan_code=p_plan_code
      and pu.unit_code=p_unit_code;
  end if;

  v_packet:=programacion.fn_engineering_packet_apply_read_budget_v1(
    v_packet,v_budget
  );

  v_packet:=programacion.fn_engineering_packet_apply_governed_merge_v1(v_packet);

  return v_packet || jsonb_build_object(
    'artifact_role_contract',v_spec->'artifact_role_contract',
    'evidence_artifacts',v_spec#>'{target,evidence_artifacts}',
    'mutation_artifacts',v_spec#>'{target,mutation_artifacts}',
    'readonly_policy',jsonb_build_object(
      'scope','EXPLICIT_READ_ACTIONS_ONLY',
      'materiality_authority','ACTION_SPEC_REQUIRES_MATERIAL_EXECUTION',
      'title_based_materiality_downgrade','FORBIDDEN',
      'material_actions_allowed',jsonb_build_array('WRITE_DB','WRITE_GIT','RUN_TEST')
    )
  );
end;
$function$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-EVIDENCE-ARTIFACT-MUTATION-TARGET-SEPARATION-001',
  'ENGINEERING_ORCHESTRATION',
  'Evidence artifacts must not become repository mutation targets by presence',
  'The legacy execution packet compiler treated any declared_artifacts entry on a material checkpoint as WRITE_GIT authority. Source-pack evidence such as a governance document could therefore be projected as a write target.',
  'Artifact provenance/evidence and mutation authority shared one field and the packet compiler inferred write intent from artifact presence.',
  'EVIDENCE_ARTIFACT_PROMOTED_TO_WRITE_TARGET',
  'Keep evidence_artifacts and mutation_artifacts separate. Legacy declared_artifacts are evidence-only unless explicitly marked role=MUTATION_TARGET. WRITE_GIT may receive only explicit mutation_artifacts; Git-first migration guards accept only an explicit mutation migration output.',
  'ENGINEERING_ARTIFACT_ROLE_CONTRACT_V1: packet compiler normalizes artifacts before legacy compilation; evidence artifacts carry zero write authority; explicit mutation artifacts remain writable; migration guard ignores docs/evidence.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_action_spec_artifact_roles_v1; supabase://programacion.fn_engineering_execution_packet_from_spec_v1; supabase://programacion.fn_engineering_action_spec_apply_git_migration_guard_v1',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','PROGRAMMING_AGENT']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'Execution packet artifact role separation',
  'supabase://programacion.fn_engineering_execution_packet_from_spec_v1'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  ultima_vez=now(),
  updated_at=now();
