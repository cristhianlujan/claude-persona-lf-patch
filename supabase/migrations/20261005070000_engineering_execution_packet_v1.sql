create or replace function programacion.fn_engineering_execution_packet_from_spec_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_action_spec jsonb,
  p_execution_input jsonb
)
returns jsonb
language sql
immutable
set search_path to 'programacion','public','pg_catalog'
as $$
with x as materialized (
  select
    coalesce(p_action_spec->>'status','') spec_status,
    coalesce(p_action_spec->>'action_kind','') action_kind,
    lower(coalesce(p_action_spec->>'checkpoint_title','')) title_l,
    coalesce((p_action_spec->>'requires_material_execution')::boolean,false) declared_material,
    coalesce(p_action_spec#>'{target,declared_objects}','[]'::jsonb) objects,
    coalesce(p_action_spec#>'{target,declared_artifacts}','[]'::jsonb) artifacts,
    coalesce(p_action_spec->'verification_queries','[]'::jsonb) verification_queries
), f as materialized (
  select x.*,
    (declared_material
      and title_l ~ '^(conteo|readback|verificar|comprobar|observar|listar|inspeccionar)'
      and title_l !~ '(crear|insertar|actualizar|eliminar|materializar|implementar|construir|emitir|registrar|migraci)') read_only_reclass,
    (jsonb_array_length(objects)>0 or jsonb_array_length(artifacts)>0) has_target,
    (jsonb_array_length(verification_queries)>0) has_verification,
    exists(
      select 1 from jsonb_array_elements(artifacts) a
      where coalesce(a->>'path','') like '%:supabase/migrations/%'
        and coalesce((a->>'verified')::boolean,false)=false
    ) has_migration_output,
    exists(
      select 1 from jsonb_array_elements(artifacts) a
      where coalesce((a->>'verified')::boolean,false)=false
    ) has_unverified_artifact,
    (title_l ~ '(migraci|git-first)') expects_migration
  from x
), d as materialized (
  select *,
    (declared_material and not read_only_reclass) effective_material,
    case
      when spec_status<>'READY' then 'BLOCK_ACTION_SPEC'
      when not (declared_material and not read_only_reclass) then 'READY'
      when not has_target then 'BLOCK_SPEC_INCOMPLETE'
      when not has_verification then 'BLOCK_SPEC_INCOMPLETE'
      when expects_migration and not has_migration_output then 'BLOCK_SPEC_INCOMPLETE'
      when not has_unverified_artifact then 'BLOCK_SPEC_INCOMPLETE'
      else 'READY'
    end packet_status
  from f
)
select jsonb_build_object(
  'schema_version','ENGINEERING_EXECUTION_PACKET_V1',
  'status',packet_status,
  'plan_code',p_plan_code,
  'unit_code',p_unit_code,
  'checkpoint_code',p_checkpoint_code,
  'requires_material_execution',effective_material,
  'effective_action_kind',case when read_only_reclass then 'READBACK_ONCE' else action_kind end,
  'block_reasons',
      (case when effective_material and not has_target then jsonb_build_array('MISSING_DECLARED_TARGET') else '[]'::jsonb end)
    || (case when effective_material and not has_verification then jsonb_build_array('MISSING_VERIFICATION') else '[]'::jsonb end)
    || (case when effective_material and expects_migration and not has_migration_output then jsonb_build_array('MISSING_OUTPUT_MIGRATION_ARTIFACT') else '[]'::jsonb end)
    || (case when effective_material and has_target and has_verification and not has_unverified_artifact then jsonb_build_array('MISSING_EXECUTABLE_ARTIFACT_OR_OPERATION') else '[]'::jsonb end),
  'connector_plan',case
    when packet_status<>'READY' then '[]'::jsonb
    when not effective_material then jsonb_build_array(
      jsonb_build_object('seq',1,'provider','SUPABASE','operation','EXECUTE_SQL_READONLY','queries',verification_queries),
      jsonb_build_object('seq',2,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
    )
    when has_migration_output then jsonb_build_array(
      jsonb_build_object('seq',1,'provider','GITHUB','operation','CREATE_DECLARED_MIGRATION_ARTIFACT','targets',artifacts),
      jsonb_build_object('seq',2,'provider','GITHUB','operation','OPEN_AND_MERGE_SCOPED_PR'),
      jsonb_build_object('seq',3,'provider','SUPABASE','operation','APPLY_DECLARED_MIGRATION'),
      jsonb_build_object('seq',4,'provider','SUPABASE','operation','EXECUTE_SQL_READBACK','queries',verification_queries),
      jsonb_build_object('seq',5,'provider','SUPABASE','operation','CHECKPOINT_TRANSITION')
    )
    else '[]'::jsonb
  end,
  'retry_policy',jsonb_build_object(
    'restart_checkpoint',false,
    'retry_same_failed_operation_only',true,
    'max_immediate_retries',1,
    'on_rate_limit','RETRY_SAME_OPERATION_ONLY',
    'on_safety_block','REDUCE_TO_EXACT_SINGLE_OPERATION_OR_STOP'
  ),
  'tool_failure_protocol',jsonb_build_object(
    'record_phase','CONNECTOR_BLOCKED',
    'record_on_next_success_if_provider_unavailable',true,
    'do_not_rebootstrap_before_retry',true
  ),
  'mutation_policy',case when effective_material then 'ONLY_DECLARED_TARGETS' else 'NO_DOMAIN_MUTATION' end,
  'execution_input',p_execution_input
)
from d;
$$;
