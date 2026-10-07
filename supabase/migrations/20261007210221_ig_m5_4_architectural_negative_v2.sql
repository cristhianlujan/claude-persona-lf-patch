-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M5.4 / NEGATIVE_NO_CLASSIFY
-- Reframe the negative check around architectural invariants, not literal probe names.

do $m54$
declare
  v_unit_id bigint;
  v_work_item_id bigint;
  v_title text := 'Negativo arquitectónico: 0 bypass directo a classify_v1/v2; resolvers semánticos solo vía registry/semantic plan; 0 router paralelo';
  v_exit text := 'Curator no ejecuta classify_v1/v2 directamente; cualquier resolver semántico consumido por las funciones declaradas debe estar publicado por INPUT_FAMILY_POLICY_REGISTRY y ejecutarse dentro del boundary M5_4_SEMANTIC_PLAN_V1; no existe router paralelo; el semantic plan conserva autoridad explícita.';
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
funcs as (
  select
    p.proname,
    p.oid::regprocedure::text as f,
    p.prosrc,
    (
      position('fn_input_governance_bootstrap_classify_v1' in lower(p.prosrc))>0
      or position('fn_input_governance_bootstrap_classify_v2' in lower(p.prosrc))>0
      or position('fn_input_governance_bootstrap_classify_v2_cached_v2' in lower(p.prosrc))>0
    ) as direct_classify_bypass,
    (
      position('M5_4_SEMANTIC_PLAN_V1' in p.prosrc)>0
      and position('INPUT_FAMILY_POLICY_REGISTRY' in p.prosrc)>0
    ) as semantic_plan_boundary,
    (
      position('method_router' in lower(p.prosrc))>0
      or position('capability_router' in lower(p.prosrc))>0
      or position('parallel_router' in lower(p.prosrc))>0
    ) as parallel_router_hit
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion'
    and p.proname in (
      'fn_input_governance_curator_materialize_v1',
      'fn_input_governance_curator_rebind_v1',
      'fn_input_governance_bootstrap_materialize_v2',
      'fn_input_governance_recurate_source_stale_v1',
      'fn_input_governance_recurate_v2'
    )
),
refs as (
  select
    f.proname,
    f.f,
    f.direct_classify_bypass,
    f.semantic_plan_boundary,
    f.parallel_router_hit,
    coalesce(
      array_agg(distinct ('programacion.'||m.ref))
        filter (where m.ref is not null),
      array[]::text[]
    ) as resolver_refs
  from funcs f
  left join lateral (
    select x[1] as ref
    from regexp_matches(
      lower(f.prosrc),
      'programacion\.(fn_input_governance_[a-z0-9_]*semantic[a-z0-9_]*v[0-9]+)',
      'g'
    ) x
  ) m on true
  group by
    f.proname,f.f,f.direct_classify_bypass,
    f.semantic_plan_boundary,f.parallel_router_hit
)
select jsonb_build_object(
  'functions',
    coalesce(
      (select jsonb_agg(
         jsonb_build_object(
           'proname',r.proname,
           'f',r.f,
           'direct_classify_bypass',r.direct_classify_bypass,
           'semantic_plan_boundary',r.semantic_plan_boundary,
           'parallel_router_hit',r.parallel_router_hit,
           'resolver_refs',to_jsonb(r.resolver_refs)
         )
         order by r.proname
       ) from refs r),
      '[]'::jsonb
    ),
  'allowed_semantic_resolvers',to_jsonb(a.resolver_names),
  'semantic_plan_authority_bound',
    exists(
      select 1 from refs r
      where r.proname='fn_input_governance_curator_materialize_v1'
        and r.semantic_plan_boundary
    )
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
  v_spec := jsonb_set(v_spec,'{mutation_policy}',to_jsonb('ONLY_DECLARED_TARGETS'::text),true);
  v_spec := jsonb_set(
    v_spec,'{repair_policy}',
    jsonb_build_object(
      'mode','REPAIR_DECLARED_TARGET_THEN_RETEST',
      'max_repairs',1,
      'targets_source','target.declared_objects',
      'second_failure','BLOCK'
    ),true
  );
  v_spec := jsonb_set(
    v_spec,'{expected}',
    to_jsonb('Execute the architectural negative against live function definitions. PASS only when there is no direct classify bypass, every semantic resolver reference is registry-authorized and inside the semantic-plan boundary, semantic-plan authority is bound, and no parallel router is referenced.'::text),
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
           'direct_classify_bypass_count',0,
           'resolver_boundary_violation_count',0,
           'parallel_router_count',0,
           'semantic_authority_bound',true
         ),
         prohibited_output=jsonb_build_object(
           'direct_classify_bypass_count_gt',0,
           'resolver_boundary_violation_count_gt',0,
           'parallel_router_count_gt',0,
           'semantic_authority_bound',false
         ),
         metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
           'criterion_revision','M5_4_ARCHITECTURAL_NEGATIVE_V2',
           'criterion_nature','ARCHITECTURAL_INVARIANT'
         ),
         updated_at=now(),
         updated_by_execution_id='CHATGPT-M5.4-ARCH-NEGATIVE-20261007'
   where test_code='ENG_M5_4_NEGATIVE_NO_CLASSIFY'
     and metadata->>'unit_code'='M5.4'
     and metadata->>'checkpoint_code'='NEGATIVE_NO_CLASSIFY';

  if not exists (
    select 1
    from programacion.engineering_work_checkpoints c
    where c.work_item_id=v_work_item_id
      and c.checkpoint_code='NEGATIVE_NO_CLASSIFY'
      and c.title=v_title
  ) then
    raise exception 'M5_4_NEGATIVE_TITLE_UPDATE_FAILED';
  end if;
end;
$m54$;
