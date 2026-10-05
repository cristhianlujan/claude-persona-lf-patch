create or replace function programacion.fn_engineering_checkpoint_action_spec_v3(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text default null::text
)
returns jsonb
language sql
stable
set search_path to 'programacion','public','pg_catalog'
as $$
with s as materialized (
  select programacion.fn_engineering_checkpoint_action_spec_v2(p_plan_code,p_unit_code,p_checkpoint_code) spec
), x as materialized (
  select spec,
         lower(coalesce(spec->>'checkpoint_title','')) title_l,
         coalesce(spec->>'checkpoint_code','') checkpoint_code,
         coalesce((spec->>'requires_material_execution')::boolean,false) is_material,
         coalesce(jsonb_array_length(spec#>'{target,declared_artifacts}'),0) artifact_count,
         coalesce(jsonb_array_length(spec->'verification_queries'),0) verification_count
  from s
)
select case
  when spec is null then null
  when (
    (checkpoint_code='DEPENDENCY_WIRING' and title_l like '%hallazgo%')
    or (
      coalesce(spec->>'recipe_mode','')='EXECUTE_DECLARED_DELIVERABLE'
      and title_l ~ '^(verificar|comprobar|readback|observar)'
      and title_l !~ '(crear|insertar|actualizar|eliminar|materializar|implementar|construir|registrar dependencia)'
    )
    or (
      coalesce(spec->>'action_kind','')='MATERIALIZE_DECLARED_DELIVERABLE'
      and artifact_count=0
      and verification_count>0
      and title_l ~ '^(verificar|confirmar|recalcular|conteo|cobertura observada|precondici[oó]n|prerequisit|identificar|0 callers|suite .*verde|evidencia .*exist|aud-[0-9]+ cerrado|consumir .*en vez|elegibilidad le[ií]da|presupuesto .*consumido|hechos espec[ií]ficos jit)'
      and title_l !~ '(crear|insertar|actualizar|eliminar|materializar|implementar|construir|emitir|registrar|migraci)'
    )
  ) then
    spec || jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'precision','COMPILED_READ_ONLY_GUARD',
      'action_kind','READBACK_ONCE',
      'recipe_mode','READBACK_EXACT',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'action_steps',jsonb_build_array(
        'READ_DECLARED_AUTHORITY_ONCE',
        'ASSERT_EXACT_STATE',
        'PERSIST_CHECKPOINT_ONLY',
        'USE_RETURNED_BOOTSTRAP'
      ),
      'forbidden',coalesce(spec->'forbidden','[]'::jsonb) || jsonb_build_array(
        'MUTATE_DEPENDENCY_GRAPH',
        'CREATE_UNDECLARED_SHARED_ABSTRACTION'
      )
    ) - 'material_contract'
  else
    spec || jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'mutation_policy',case when is_material then 'ONLY_DECLARED_TARGETS' else 'NO_DOMAIN_MUTATION' end,
      'scope_guard',jsonb_build_object(
        'new_shared_or_transversal_abstraction','FORBIDDEN_UNLESS_EXPLICITLY_DECLARED',
        'dependency_graph_mutation','FORBIDDEN_UNLESS_EXPLICITLY_DECLARED',
        'cross_checkpoint_design','FORBIDDEN'
      ),
      'forbidden',coalesce(spec->'forbidden','[]'::jsonb) || jsonb_build_array(
        'CREATE_UNDECLARED_SHARED_ABSTRACTION',
        'MUTATE_UNDECLARED_TARGET'
      )
    )
end
from x;
$$;

update public.lf_error_knowledge
set prevencion='Use ENGINEERING_UNIT_BOOTSTRAP_V3 with ACTION_SPEC_V3. Explicit verification/recompute/readback checkpoints with only declared queries and no output artifact are classified READBACK_ONCE and must not be materialized. Material checkpoints may touch only declared targets.',
    validacion='PASS when explicit readback/recompute checkpoints such as M2.10 EXIT_RECOMPUTE compile to READBACK_ONCE/READY while true material work such as M3.5 remains material and incomplete material specs remain blocked.',
    source_ref='supabase://programacion.fn_engineering_checkpoint_action_spec_v3'
where codigo='ENGINEERING-ACTION-SPEC-CONTRACT-001';