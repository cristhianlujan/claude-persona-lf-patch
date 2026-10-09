-- M4.8 LOCK_ALL_PATHS
-- M4.2 established one canonical Validator entrypoint. Enforce one advisory
-- transaction lock per run at that dispatcher and close the accidental direct
-- validate_v2 execution surface for application roles.

do $m48_lock$
declare
  v_md5 text;
  v_def text;
  v_new text;
begin
  v_md5:=md5(pg_get_functiondef(
    'programacion.fn_input_governance_validator_validate_v1(bigint,text)'::regprocedure
  ));
  if v_md5 is distinct from 'fa9ee37dfb8f4d955b399979fa3c54e2' then
    raise exception 'M48_LOCK_DISPATCHER_BASE_DRIFT expected=fa9ee37dfb8f4d955b399979fa3c54e2 actual=%',v_md5;
  end if;

  v_def:=pg_get_functiondef(
    'programacion.fn_input_governance_validator_validate_v1(bigint,text)'::regprocedure
  );
  v_new:=replace(
    v_def,
    'pg_catalog.hashtextextended(''IG_VALIDATOR_CHUNK:''||p_run_id::text||'':''||coalesce(p_validator_identity,''''),0)',
    'pg_catalog.hashtextextended(''IG_VALIDATOR_RUN:''||p_run_id::text,0)'
  );

  if v_new=v_def then
    raise exception 'M48_LOCK_DISPATCHER_PATCH_NOT_APPLIED';
  end if;

  execute v_new;
end;
$m48_lock$;

-- Internal strategy function is not an application entrypoint.
revoke all on function programacion.fn_input_governance_validate_v2(bigint,text) from public;
revoke execute on function programacion.fn_input_governance_validate_v2(bigint,text) from anon;
revoke execute on function programacion.fn_input_governance_validate_v2(bigint,text) from authenticated;
revoke execute on function programacion.fn_input_governance_validate_v2(bigint,text) from service_role;
grant execute on function programacion.fn_input_governance_validate_v2(bigint,text) to postgres;

comment on function programacion.fn_input_governance_validator_validate_v1(bigint,text)
is 'M4.8: canonical Validator dispatcher serializes all validation strategies by run_id using IG_VALIDATOR_RUN advisory transaction lock.';

comment on function programacion.fn_input_governance_validate_v2(bigint,text)
is 'Internal Validator strategy. Application-role direct execution is revoked; call through canonical Validator dispatcher so the per-run lock and continuation admission always apply.';

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  coalesce(unit_metadata,'{}'::jsonb),
  '{action_specs_v1}',
  coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)
  || jsonb_build_object(
    'LOCK_ALL_PATHS',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'status','READY',
      'checkpoint_code','LOCK_ALL_PATHS',
      'checkpoint_title','Lock por run en todos los caminos (alineado con lock de M5.1/L1)',
      'action_kind','VERIFY_QUERY_ONCE',
      'recipe_mode','VERIFY_EXACT',
      'precision','EXPLICIT_SINGLE_ENTRYPOINT_PER_RUN_LOCK_READBACK',
      'requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'expected','Canonical Validator entrypoint acquires one transaction-scoped advisory lock keyed only by run_id. Direct application-role execution of validate_v2 is forbidden; service_role reaches validation through the public canonical facade.',
      'verification_queries',jsonb_build_array(
        $q$
with d as (
  select pg_get_functiondef(
    'programacion.fn_input_governance_validator_validate_v1(bigint,text)'::regprocedure
  ) as dispatcher_def,
  pg_get_functiondef(
    'public.fn_input_governance_validator_validate_v1(bigint,text)'::regprocedure
  ) as facade_def
)
select
  position('IG_VALIDATOR_RUN:' in dispatcher_def)>0 as per_run_lock_present,
  position('IG_VALIDATOR_CHUNK:' in dispatcher_def)=0 as identity_scoped_lock_removed,
  position('programacion.fn_input_governance_validator_validate_v1' in facade_def)>0 as public_facade_routes_to_dispatcher,
  has_function_privilege('service_role','public.fn_input_governance_validator_validate_v1(bigint,text)','EXECUTE') as service_role_facade_exec,
  not has_function_privilege('anon','programacion.fn_input_governance_validate_v2(bigint,text)','EXECUTE') as anon_direct_v2_denied,
  not has_function_privilege('authenticated','programacion.fn_input_governance_validate_v2(bigint,text)','EXECUTE') as authenticated_direct_v2_denied,
  not has_function_privilege('service_role','programacion.fn_input_governance_validate_v2(bigint,text)','EXECUTE') as service_role_direct_v2_denied
from d
$q$
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      ),
      'forbidden',jsonb_build_array(
        'LOCK_BY_VALIDATOR_IDENTITY',
        'DIRECT_APPLICATION_EXECUTION_OF_INTERNAL_VALIDATOR_STRATEGY',
        'DUPLICATE_LOCK_IMPLEMENTATIONS_PER_STRATEGY'
      ),
      'contract_correction','SINGLE_ENTRYPOINT_PLUS_RUN_SCOPED_LOCK'
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M4.8';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'INPUT-GOV-VALIDATOR-LOCK-SCOPE-001',
  'INPUT_GOVERNANCE',
  'Validator concurrency lock must be keyed by run, not validator identity',
  'The canonical Validator dispatcher used an advisory lock keyed by run_id plus validator_identity. Two identities could therefore enter the same run concurrently on rebind/bootstrap paths. validate_v2 also remained directly executable by application roles, bypassing dispatcher admission.',
  'Concurrency protection was scoped to an execution identity instead of the governed run, while an internal strategy retained accidental direct EXECUTE authority.',
  'SAME_RUN_CAN_USE_DIFFERENT_LOCK_KEYS_OR_BYPASS_DISPATCHER',
  'Acquire IG_VALIDATOR_RUN:<run_id> at the canonical dispatcher, keep internal strategies behind that entrypoint, and revoke application-role direct EXECUTE from internal validate_v2.',
  'M4.8 requires dispatcher per-run lock, public facade -> dispatcher routing, service_role facade access, and zero anon/authenticated/service_role direct execute on validate_v2.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_input_governance_validator_validate_v1; supabase://public.fn_input_governance_validator_validate_v1; supabase://programacion.fn_input_governance_validate_v2',
  'EXECUTION',
  array['INPUT_VALIDATOR','ENGINEERING_SCHEDULER']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'M4.8 LOCK_ALL_PATHS',
  'supabase://programacion.fn_input_governance_validator_validate_v1'
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
