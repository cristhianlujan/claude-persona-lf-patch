do $$
declare
  v_ddl text;
  v_old text := $old$    'counts',v_counts,
    'family_statuses',v_family_statuses,$old$;
  v_new text := $new$    'counts',v_counts,
    'stage_gate_summary',programacion.fn_input_stage_gate_summary(p_run_id),
    'family_statuses',v_family_statuses,$new$;
begin
  select pg_get_functiondef(p.oid) into v_ddl
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_input_context_manifest';
  if v_ddl is null or position(v_old in v_ddl)=0 then
    raise exception 'INPUT_CONTEXT_MANIFEST_STAGE_SUMMARY_PATCH_TARGET_NOT_FOUND';
  end if;
  execute replace(v_ddl,v_old,v_new);
end;
$$;

update programacion.contratos c
set especificacion = c.especificacion || jsonb_build_object(
  'stage_gate_summary','programacion.fn_input_stage_gate_summary',
  'includes',case
    when c.especificacion->'includes' ? 'STAGE_GATE_SUMMARY' then c.especificacion->'includes'
    else (c.especificacion->'includes') || jsonb_build_array('STAGE_GATE_SUMMARY')
  end
)
from programacion.versiones_agente v
where c.version_id=v.id
  and v.version_codigo='v0.5-input-readiness-api-contract-sufficiency-r1-stage-gates-candidate'
  and c.contrato_codigo='INPUT_CONTEXT_MANIFEST_CONTRACT';

create or replace function programacion.fn_input_governance_module_health(
  p_version_id bigint,
  p_module_code text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops
as $$
declare
  v_version record;
  v_contract record;
  v_screen_count integer := 0;
  v_healthy integer := 0;
  v_rows jsonb := '[]'::jsonb;
  v_downstream_contract_count integer := 0;
  v_payload jsonb;
begin
  select v.id,v.version_codigo,v.estado,a.agente_codigo,a.estado agent_state
    into v_version
  from programacion.versiones_agente v
  join programacion.agentes a on a.id=v.agente_id
  where v.id=p_version_id;
  if not found or v_version.agente_codigo<>'INPUT_GOVERNANCE_AGENT' then
    raise exception 'INPUT_GOVERNANCE_MODULE_HEALTH_INVALID_VERSION:%',p_version_id;
  end if;

  select c.id,c.especificacion->>'contract_revision' contract_revision,
         jsonb_array_length(c.especificacion->'negative_tests') negative_test_count,
         c.fail_closed,c.estado
    into v_contract
  from programacion.contratos c
  where c.version_id=p_version_id and c.contrato_codigo='INPUT_READINESS_CONTRACT';
  if not found then raise exception 'INPUT_GOVERNANCE_MODULE_HEALTH_CONTRACT_MISSING:%',p_version_id; end if;

  select count(*) into v_downstream_contract_count
  from programacion.contratos c
  where c.version_id=p_version_id
    and c.contrato_codigo in ('INPUT_CONTEXT_MANIFEST_CONTRACT','INPUT_FRESHNESS_DELTA_CONTRACT','INPUT_RETRIEVAL_HANDLE_CONTRACT');

  with screens as (
    select p.id,p.codigo,p.nombre,p.activa
    from lf_ops.pantallas p
    where p.module_code=p_module_code and p.activa=true
  ), runs as (
    select s.*,
           r.id run_id,r.status run_status,r.version_id,r.validator_identity,r.source_snapshot_sha256,
           case when r.id is null then false else programacion.fn_input_readiness_run_is_current(r.id) end run_current
    from screens s
    left join lateral (
      select rr.* from programacion.input_readiness_runs rr
      where rr.pantalla_id=s.id and rr.version_id=p_version_id
      order by rr.id desc limit 1
    ) r on true
  ), checks as (
    select r.*,
           coalesce((select count(*) from programacion.input_family_assessments a where a.run_id=r.run_id),0) family_count,
           coalesce((select count(*) from programacion.input_family_assessments a where a.run_id=r.run_id and a.validator_outcome='PASS'),0) validator_pass_count,
           coalesce((select count(*) from programacion.input_family_assessments a where a.run_id=r.run_id and a.applicability='APPLICABLE' and 'NOT_APPLICABLE'=any(array[a.coverage_status,a.well_defined_status,a.story_ready_status,a.implementation_ready_status,a.qa_ready_status,a.production_ready_status])),0) applicability_invariant_violations,
           coalesce((select count(*) from programacion.input_family_assessments a where a.run_id=r.run_id and a.applicability='NOT_APPLICABLE' and exists(select 1 from unnest(array[a.coverage_status,a.well_defined_status,a.story_ready_status,a.implementation_ready_status,a.qa_ready_status,a.production_ready_status]) st where st<>'NOT_APPLICABLE')),0) na_invariant_violations,
           case when r.run_id is null then null else (programacion.fn_input_stage_gate_summary(r.run_id)->>'hierarchy_violation_count')::integer end hierarchy_violations
    from runs r
  ), shaped as (
    select *,
      (run_id is not null and run_status='COMPLETED' and run_current and family_count=47 and validator_pass_count=47
       and applicability_invariant_violations=0 and na_invariant_violations=0 and coalesce(hierarchy_violations,0)=0) healthy
    from checks
  )
  select count(*),count(*) filter(where healthy),
         coalesce(jsonb_agg(jsonb_build_object(
           'pantalla_id',id,'screen_code',codigo,'name',nombre,
           'run_id',run_id,'run_status',run_status,'run_current',run_current,
           'family_count',family_count,'validator_pass_count',validator_pass_count,
           'applicability_invariant_violations',applicability_invariant_violations,
           'na_invariant_violations',na_invariant_violations,
           'hierarchy_violations',hierarchy_violations,
           'healthy',healthy
         ) order by id),'[]'::jsonb)
  into v_screen_count,v_healthy,v_rows
  from shaped;

  v_payload:=jsonb_build_object(
    'health_contract','INPUT_GOVERNANCE_MODULE_HEALTH_V1',
    'version',jsonb_build_object(
      'version_id',p_version_id,'version_code',v_version.version_codigo,'version_state',v_version.estado,
      'agent_code',v_version.agente_codigo,'agent_state',v_version.agent_state
    ),
    'readiness_contract',jsonb_build_object(
      'contract_id',v_contract.id,'contract_revision',v_contract.contract_revision,
      'negative_test_count',v_contract.negative_test_count,'fail_closed',v_contract.fail_closed,'state',v_contract.estado
    ),
    'module_code',p_module_code,
    'screen_count',v_screen_count,
    'healthy_screen_count',v_healthy,
    'downstream_contract_count',v_downstream_contract_count,
    'required_downstream_contract_count',3,
    'screens',v_rows,
    'health_pass',v_screen_count>0 and v_healthy=v_screen_count and v_downstream_contract_count=3,
    'promotion_authorized',false,
    'note','Health validates governance mechanics and current evidence; it does not erase functional/readiness blockers or authorize promotion.'
  );
  return v_payload || jsonb_build_object('health_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;
$$;

revoke all on function programacion.fn_input_governance_module_health(bigint,text) from public;

insert into programacion.contratos(
  version_id,contrato_codigo,tipo,nombre,descripcion,productor_componente_id,consumidor_componente_id,
  especificacion,fail_closed,estado
)
select v.id,
       'INPUT_GOVERNANCE_MODULE_HEALTH_CONTRACT',
       'HEALTH_GATE',
       'Input Governance module health gate',
       'Gate mecánico para comprobar cobertura 47/47, Validator PASS, current snapshot e invariantes por pantalla sin confundir health del agente con readiness funcional ni promoción.',
       (select c.id from programacion.componentes c where c.version_id=v.id and c.componente_codigo='INPUT_VALIDATOR'),
       null,
       jsonb_build_object(
         'schema_version',1,'contract_revision','1.0','health_contract','INPUT_GOVERNANCE_MODULE_HEALTH_V1',
         'requires',jsonb_build_array('47_FAMILIES_PER_ACTIVE_SCREEN','47_VALIDATOR_PASS','CURRENT_RUN','APPLICABILITY_INVARIANTS','STAGE_HIERARCHY','3_DOWNSTREAM_INTERFACE_CONTRACTS'),
         'does_not_require',jsonb_build_array('ALL_FAMILIES_READY','NO_FUNCTIONAL_BLOCKERS','PRODUCTION_READY'),
         'promotion_authorized',false,'fail_closed',true
       ),
       true,'defined'
from programacion.versiones_agente v
where v.version_codigo='v0.5-input-readiness-api-contract-sufficiency-r1-stage-gates-candidate'
  and not exists(select 1 from programacion.contratos x where x.version_id=v.id and x.contrato_codigo='INPUT_GOVERNANCE_MODULE_HEALTH_CONTRACT');