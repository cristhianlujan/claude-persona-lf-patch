create or replace function programacion.fn_engineering_checkpoint_action_spec_v2(p_plan_code text,p_unit_code text,p_checkpoint_code text default null::text)
returns jsonb
language sql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
with s as materialized (
  select programacion.fn_engineering_checkpoint_action_spec_v1(p_plan_code,p_unit_code,p_checkpoint_code) as spec
)
select case
  when spec is null then null
  when spec->>'action_kind'='MATERIALIZE_DECLARED_DELIVERABLE' then
    spec || jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V2',
      'precision','COMPILED_MATERIAL_HANDLER',
      'requires_material_execution',true,
      'material_contract',jsonb_build_object(
        'scope','CURRENT_CHECKPOINT_ONLY',
        'heartbeat_required',true,
        'verification_mode',case
          when jsonb_array_length(coalesce(spec->'verification_queries','[]'::jsonb))>0 then 'DECLARED_QUERY_READBACK'
          when jsonb_array_length(coalesce(spec#>'{target,declared_artifacts}','[]'::jsonb))>0 then 'ARTIFACT_AND_TARGET_READBACK'
          else 'DECLARED_TARGET_READBACK'
        end,
        'design_boundary','ONLY_CURRENT_CHECKPOINT_DELIVERABLE',
        'persist_on_pass','programacion.fn_engineering_checkpoint_transition_v1'
      )
    )
  else spec || jsonb_build_object('schema_version','ENGINEERING_ACTION_SPEC_V2')
end
from s;
$function$;

create or replace function programacion.fn_engineering_checkpoint_action_spec_v3(p_plan_code text,p_unit_code text,p_checkpoint_code text default null::text)
returns jsonb
language sql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
with s as materialized (
  select programacion.fn_engineering_checkpoint_action_spec_v2(p_plan_code,p_unit_code,p_checkpoint_code) spec
), x as materialized (
  select spec,
         lower(coalesce(spec->>'checkpoint_title','')) title_l,
         coalesce(spec->>'checkpoint_code','') checkpoint_code,
         coalesce((spec->>'requires_material_execution')::boolean,false) is_material
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
  ) then
    spec || jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'precision','COMPILED_READ_ONLY_GUARD',
      'action_kind','READBACK_ONCE',
      'recipe_mode','READBACK_EXACT',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'action_steps',jsonb_build_array('READ_DECLARED_AUTHORITY_ONCE','ASSERT_EXACT_STATE','PERSIST_CHECKPOINT_ONLY','USE_RETURNED_BOOTSTRAP'),
      'forbidden',coalesce(spec->'forbidden','[]'::jsonb) || jsonb_build_array('MUTATE_DEPENDENCY_GRAPH','CREATE_UNDECLARED_SHARED_ABSTRACTION')
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
      'forbidden',coalesce(spec->'forbidden','[]'::jsonb) || jsonb_build_array('CREATE_UNDECLARED_SHARED_ABSTRACTION','MUTATE_UNDECLARED_TARGET')
    )
end
from x;
$function$;
