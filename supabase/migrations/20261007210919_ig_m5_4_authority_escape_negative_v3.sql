-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M5.4 / NEGATIVE_NO_CLASSIFY V3
-- Architectural negative: prevent legacy authority escape, not internal seed implementation.

do $m54$
declare
  v_unit_id bigint;
  v_work_item_id bigint;
  v_title text := 'Negativo arquitectónico: ningún resultado legacy puede escapar del Core; writers internos no ejecutables; resolvers semánticos gobernados; 0 router paralelo';
  v_exit text := 'Los strategy writers pueden usar clasificación legacy solo como semilla interna si no son ejecutables por roles runtime ni tienen callers runtime no autorizados; toda assessment materializada debe pasar por fn_input_deterministic_assess en el Curator central antes de convertirse en salida autoritativa; resolvers semánticos permanecen centralizados/gobernados por INPUT_FAMILY_POLICY_REGISTRY; no existe router paralelo.';
  v_query text := $q$
with current_reg as (
  select c.especificacion
  from programacion.contratos c
  where c.version_id=public.fn_lf_version_compatibility_current_version_id_v1(
          'PROGRAMACION_CONTRACT','INPUT_FAMILY_POLICY_REGISTRY',null
        )
    and c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
    and c.estado='defined'
    and c.fail_closed
  order by c.id desc
  limit 1
),
allowed as (
  select coalesce(
           array_agg(distinct split_part(r.value->>'function','(',1))
             filter (where nullif(r.value->>'function','') is not null),
           array[]::text[]
         ) as resolver_names
  from current_reg c
  cross join lateral jsonb_each(c.especificacion->'families') fam
  cross join lateral jsonb_array_elements(fam.value->'semantic_resolvers') r
),
central as (
  select
    p.oid,
    p.proname,
    p.oid::regprocedure::text as f,
    p.prosrc,
    (position('fn_input_deterministic_assess' in p.prosrc)>0) as core_normalization_present,
    (
      position('for v_core_assessment in' in p.prosrc)>0
      and position('update programacion.input_family_assessments' in lower(p.prosrc))>0
    ) as normalizes_all_materialized_assessments,
    (
      position('M5_4_SEMANTIC_PLAN_V1' in p.prosrc)>0
      and position('INPUT_FAMILY_POLICY_REGISTRY' in p.prosrc)>0
    ) as semantic_plan_authority_bound,
    (
      position('method_router' in lower(p.prosrc))>0
      or position('capability_router' in lower(p.prosrc))>0
      or position('parallel_router' in lower(p.prosrc))>0
    ) as parallel_router_hit
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname='fn_input_governance_curator_materialize_v1'
),
writers0 as (
  select
    p.oid,
    p.proname,
    p.oid::regprocedure::text as f,
    p.prosrc,
    (
      position('fn_input_governance_bootstrap_classify_v1' in lower(p.prosrc))>0
      or position('fn_input_governance_bootstrap_classify_v2' in lower(p.prosrc))>0
      or position('fn_input_governance_bootstrap_classify_v2_cached_v2' in lower(p.prosrc))>0
    ) as legacy_classify_seed,
    (
      has_function_privilege('anon',p.oid,'EXECUTE')
      or has_function_privilege('authenticated',p.oid,'EXECUTE')
      or has_function_privilege('service_role',p.oid,'EXECUTE')
    ) as external_runtime_execute,
    (
      position('method_router' in lower(p.prosrc))>0
      or position('capability_router' in lower(p.prosrc))>0
      or position('parallel_router' in lower(p.prosrc))>0
    ) as parallel_router_hit
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname in (
      'fn_input_governance_bootstrap_materialize_v2',
      'fn_input_governance_curator_rebind_v1',
      'fn_input_governance_recurate_source_stale_v1',
      'fn_input_governance_recurate_v2'
    )
),
writers as (
  select
    w.proname,
    w.f,
    w.legacy_classify_seed,
    w.external_runtime_execute,
    w.parallel_router_hit,
    coalesce((
      select jsonb_agg(c.oid::regprocedure::text order by c.oid::regprocedure::text)
      from pg_proc c
      join pg_namespace cn on cn.oid=c.pronamespace
      where cn.nspname='programacion'
        and c.oid<>w.oid
        and c.prosrc like '%'||w.proname||'%'
        and c.proname<>'fn_input_governance_curator_materialize_v1'
        and c.proname not in (
          'fn_input_governance_bootstrap_materialize_v2',
          'fn_input_governance_curator_rebind_v1',
          'fn_input_governance_recurate_source_stale_v1',
          'fn_input_governance_recurate_v2'
        )
        and c.proname not like 'fn_engineering_%'
    ),'[]'::jsonb) as unauthorized_runtime_callers,
    coalesce((
      select jsonb_agg(distinct ('programacion.'||x[1]))
      from regexp_matches(
        lower(w.prosrc),
        'programacion\.(fn_input_governance_[a-z0-9_]*semantic[a-z0-9_]*v[0-9]+)',
        'g'
      ) x
    ),'[]'::jsonb) as resolver_refs
  from writers0 w
)
select jsonb_build_object(
  'central',
    (select jsonb_build_object(
       'proname',c.proname,
       'f',c.f,
       'core_normalization_present',c.core_normalization_present,
       'normalizes_all_materialized_assessments',c.normalizes_all_materialized_assessments,
       'semantic_plan_authority_bound',c.semantic_plan_authority_bound,
       'parallel_router_hit',c.parallel_router_hit
     ) from central c),
  'writers',
    coalesce((select jsonb_agg(to_jsonb(w) order by w.proname) from writers w),'[]'::jsonb),
  'allowed_semantic_resolvers',to_jsonb(a.resolver_names)
)
from allowed a
$q$;
  v_spec jsonb;
  v_sp jsonb;
begin
  select pu.id,pu.work_item_id
    into v_unit_id,v_work_item_id
  from programacion.engineering_plan_units pu
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and pu.unit_code='M5.4'
    and pu.disposition='ASSIGNED';

  if v_unit_id is null then
    raise exception 'M5_4_PLAN_UNIT_NOT_FOUND';
  end if;

  update programacion.engineering_work_checkpoints
     set title=v_title
   where work_item_id=v_work_item_id
     and checkpoint_code='NEGATIVE_NO_CLASSIFY';

  select unit_metadata#>'{action_specs_v1,NEGATIVE_NO_CLASSIFY}',
         unit_metadata#>'{source_pack_v1,checkpoint_inputs,NEGATIVE_NO_CLASSIFY}'
    into v_spec,v_sp
  from programacion.engineering_plan_units
  where id=v_unit_id;

  if jsonb_typeof(v_spec) is distinct from 'object'
     or jsonb_typeof(v_sp) is distinct from 'object' then
    raise exception 'M5_4_NEGATIVE_CONTRACT_MISSING';
  end if;

  v_spec := jsonb_set(v_spec,'{checkpoint_title}',to_jsonb(v_title),true);
  v_spec := jsonb_set(v_spec,'{verification_queries}',jsonb_build_array(v_query),true);
  v_spec := jsonb_set(v_spec,'{mutation_policy}',to_jsonb('TEST_ARTIFACT_ONLY'::text),true);
  v_spec := jsonb_set(v_spec,'{repair_policy}',jsonb_build_object('mode','NONE'),true);
  v_spec := jsonb_set(
    v_spec,'{expected}',
    to_jsonb('Execute the architectural negative against live authority boundaries. PASS when internal legacy seeds cannot escape as runtime authority, the central Curator normalizes every materialized assessment through deterministic_assess, semantic resolution remains registry-governed, and no parallel router exists.'::text),
    true
  );
  v_spec := jsonb_set(v_spec,'{test_execution_contract,declared_queries}',jsonb_build_array(v_query),true);
  v_spec := jsonb_set(v_spec,'{test_execution_contract,canonical_exit_criterion}',to_jsonb(v_exit),true);
  v_spec := jsonb_set(v_spec,'{test_execution_contract,checkpoint_title_context}',to_jsonb(v_title),true);

  v_sp := jsonb_set(v_sp,'{inputs,queries}',jsonb_build_array(v_query),true);

  update programacion.engineering_plan_units
     set unit_metadata =
       jsonb_set(
         jsonb_set(
           coalesce(unit_metadata,'{}'::jsonb),
           '{action_specs_v1,NEGATIVE_NO_CLASSIFY}',v_spec,true
         ),
         '{source_pack_v1,checkpoint_inputs,NEGATIVE_NO_CLASSIFY}',v_sp,true
       )
   where id=v_unit_id;

  update public.lf_test_suite_cases
     set title=v_title,
         expected_output=jsonb_build_object(
           'test_passed',true,
           'test_exit_code',0,
           'runtime_exposed_writer_count',0,
           'unauthorized_runtime_caller_count',0,
           'parallel_router_count',0,
           'semantic_authority_bound',true
         ),
         prohibited_output=jsonb_build_object(
           'runtime_exposed_writer_count_gt',0,
           'unauthorized_runtime_caller_count_gt',0,
           'parallel_router_count_gt',0,
           'semantic_authority_bound',false,
           'core_normalization_missing',true
         ),
         metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
           'criterion_revision','M5_4_AUTHORITY_ESCAPE_NEGATIVE_V3',
           'criterion_nature','ARCHITECTURAL_AUTHORITY_BOUNDARY'
         ),
         updated_at=now(),
         updated_by_execution_id='CHATGPT-M5.4-AUTHORITY-NEGATIVE-20261007'
   where test_code='ENG_M5_4_NEGATIVE_NO_CLASSIFY'
     and metadata->>'unit_code'='M5.4'
     and metadata->>'checkpoint_code'='NEGATIVE_NO_CLASSIFY';
end;
$m54$;
