insert into programacion.versiones_agente(agente_id,version_codigo,objetivo,estado,supersedes_version_id,notas)
select agente_id,
       'v0.5-input-readiness-api-contract-sufficiency-r1-stage-gates-candidate',
       objetivo || ' Añade jerarquía determinística Story→Implementation→QA→Production y resumen de gates.',
       'candidate',id,
       'CANDIDATE_V5_5_2026-08-18: readiness stage hierarchy is enforced by DB guard. No promotion.'
from programacion.versiones_agente
where id=18
  and not exists(select 1 from programacion.versiones_agente where version_codigo='v0.5-input-readiness-api-contract-sufficiency-r1-stage-gates-candidate');

insert into programacion.componentes(version_id,componente_codigo,tipo,nombre,responsabilidad,orden_ejecucion,independencia_requerida,configuracion,estado)
select nv.id,c.componente_codigo,c.tipo,c.nombre,c.responsabilidad,c.orden_ejecucion,c.independencia_requerida,
       c.configuracion || jsonb_build_object('readiness_stage_hierarchy','STORY_IMPL_QA_PROD_V1','deterministic_gate_summary','REQUIRED'),c.estado
from programacion.componentes c
join programacion.versiones_agente nv on nv.version_codigo='v0.5-input-readiness-api-contract-sufficiency-r1-stage-gates-candidate'
where c.version_id=18
  and not exists(select 1 from programacion.componentes x where x.version_id=nv.id and x.componente_codigo=c.componente_codigo);

insert into programacion.contratos(version_id,contrato_codigo,tipo,nombre,descripcion,productor_componente_id,consumidor_componente_id,especificacion,fail_closed,estado)
select nv.id,c.contrato_codigo,c.tipo,c.nombre,
       c.descripcion || ' V5.5 añade jerarquía determinística entre etapas readiness.',
       (select nc.id from programacion.componentes nc where nc.version_id=nv.id and nc.componente_codigo='INPUT_VALIDATOR'),
       null,
       jsonb_set(c.especificacion,'{contract_revision}','"5.5"'::jsonb,true)
       || jsonb_build_object(
          'readiness_stage_hierarchy',jsonb_build_object(
             'implementation_ready_requires_story_ready',true,
             'qa_ready_requires_implementation_ready',true,
             'production_ready_requires_qa_ready',true,
             'coverage_and_well_defined_not_forced_monotonic',true
          ),
          'deterministic_stage_summary','programacion.fn_input_stage_gate_summary',
          'negative_tests',(c.especificacion->'negative_tests') || jsonb_build_array(
             'IMPLEMENTATION_READY_WHILE_STORY_NOT_READY',
             'QA_READY_WHILE_IMPLEMENTATION_NOT_READY',
             'PRODUCTION_READY_WHILE_QA_NOT_READY'
          ),
          'audit_remediation',(c.especificacion->'audit_remediation') || jsonb_build_array('AUD-IGA-012_READINESS_STAGE_HIERARCHY')
       ),
       c.fail_closed,c.estado
from programacion.contratos c
join programacion.versiones_agente nv on nv.version_codigo='v0.5-input-readiness-api-contract-sufficiency-r1-stage-gates-candidate'
where c.id=33
  and not exists(select 1 from programacion.contratos x where x.version_id=nv.id and x.contrato_codigo=c.contrato_codigo);

-- Carry downstream interface contracts forward without changing their source-of-truth role.
insert into programacion.contratos(version_id,contrato_codigo,tipo,nombre,descripcion,productor_componente_id,consumidor_componente_id,especificacion,fail_closed,estado)
select nv.id,c.contrato_codigo,c.tipo,c.nombre,c.descripcion,
       (select nc.id from programacion.componentes nc where nc.version_id=nv.id and nc.componente_codigo='INPUT_VALIDATOR'),
       c.consumidor_componente_id,c.especificacion,c.fail_closed,c.estado
from programacion.contratos c
join programacion.versiones_agente nv on nv.version_codigo='v0.5-input-readiness-api-contract-sufficiency-r1-stage-gates-candidate'
where c.version_id=18
  and c.contrato_codigo in ('INPUT_CONTEXT_MANIFEST_CONTRACT','INPUT_FRESHNESS_DELTA_CONTRACT','INPUT_RETRIEVAL_HANDLE_CONTRACT')
  and not exists(select 1 from programacion.contratos x where x.version_id=nv.id and x.contrato_codigo=c.contrato_codigo);

create or replace function programacion.fn_guard_input_family_assessment_insert()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, programacion, lf_ops
as $$
declare
  v_status text;
  v_contract_version integer;
  v_pantalla_id integer;
  v_version_id bigint;
  v_version_code text;
  v_families jsonb;
  v_payload jsonb;
  v_ref jsonb;
  v_mode text;
  v_states text[];
begin
  select r.status,r.contract_version,r.pantalla_id,r.version_id,v.version_codigo,q.valor_config->'families'
    into v_status,v_contract_version,v_pantalla_id,v_version_id,v_version_code,v_families
  from programacion.input_readiness_runs r
  join programacion.versiones_agente v on v.id=r.version_id
  join lf_ops.reglas q on q.id=r.universe_rule_id
  where r.id=new.run_id;
  if v_status is null then raise exception 'INPUT_READINESS_RUN_NOT_FOUND'; end if;
  if v_contract_version not in (3,4) then raise exception 'LEGACY_INPUT_READINESS_RUN_NOT_WRITABLE'; end if;
  if v_status<>'CURATING' then raise exception 'CURATOR_INSERT_CLOSED_FOR_RUN_STATUS_%',v_status; end if;
  if jsonb_typeof(v_families)<>'array' or not (v_families ? new.family_code) then raise exception 'FAMILY_NOT_IN_CANONICAL_UNIVERSE:%',new.family_code; end if;
  if jsonb_typeof(new.source_refs)<>'array' or jsonb_array_length(new.source_refs)=0 then raise exception 'SOURCE_REFS_REQUIRED:%',new.family_code; end if;
  for v_ref in select value from jsonb_array_elements(new.source_refs) loop
    perform programacion.fn_input_resolve_source_ref(v_ref,v_pantalla_id,v_version_id);
  end loop;

  v_states:=array[new.coverage_status,new.well_defined_status,new.story_ready_status,new.implementation_ready_status,new.qa_ready_status,new.production_ready_status];
  if new.applicability='APPLICABLE' and 'NOT_APPLICABLE'=any(v_states) then
    raise exception 'APPLICABLE_FAMILY_CANNOT_HAVE_NOT_APPLICABLE_READINESS:%',new.family_code;
  end if;
  if new.applicability='NOT_APPLICABLE' and exists(select 1 from unnest(v_states) s where s<>'NOT_APPLICABLE') then
    raise exception 'NOT_APPLICABLE_FAMILY_REQUIRES_ALL_NOT_APPLICABLE_READINESS:%',new.family_code;
  end if;
  if new.applicability='UNRESOLVED' and new.story_ready_status='READY' then
    raise exception 'UNRESOLVED_APPLICABILITY_CANNOT_BE_STORY_READY:%',new.family_code;
  end if;

  if v_version_code like 'v0.5-input-readiness-api-contract-sufficiency-r1-stage-gates%' and new.applicability='APPLICABLE' then
    if new.implementation_ready_status='READY' and new.story_ready_status<>'READY' then
      raise exception 'IMPLEMENTATION_READY_REQUIRES_STORY_READY:%',new.family_code;
    end if;
    if new.qa_ready_status='READY' and new.implementation_ready_status<>'READY' then
      raise exception 'QA_READY_REQUIRES_IMPLEMENTATION_READY:%',new.family_code;
    end if;
    if new.production_ready_status='READY' and new.qa_ready_status<>'READY' then
      raise exception 'PRODUCTION_READY_REQUIRES_QA_READY:%',new.family_code;
    end if;
  end if;

  if new.validator_outcome<>'PENDING' or new.validator_identity is not null or new.validator_sha256 is not null
     or new.validator_assessed_at is not null or new.validator_findings<>'[]'::jsonb or new.validator_evidence<>'{}'::jsonb then
    raise exception 'CURATOR_CANNOT_PREVALIDATE:%',new.family_code;
  end if;
  v_mode:=case when v_contract_version=4 then 'DB_MANIFEST_V4' else 'DB_MANIFEST_V3' end;
  new.freshness:=jsonb_build_object('mode',v_mode,'status','PENDING_RUN_SNAPSHOT');
  v_payload:=jsonb_build_object('run_id',new.run_id,'family_code',new.family_code,'severity',new.severity,'applicability',new.applicability,
    'coverage_status',new.coverage_status,'well_defined_status',new.well_defined_status,'story_ready_status',new.story_ready_status,
    'implementation_ready_status',new.implementation_ready_status,'qa_ready_status',new.qa_ready_status,'production_ready_status',new.production_ready_status,
    'source_refs',new.source_refs,'rationale',new.rationale,'blockers',new.blockers,'negative_requirements',new.negative_requirements,
    'test_obligations',new.test_obligations,'freshness',new.freshness,'curator_evidence',new.curator_evidence);
  new.curator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload);
  return new;
end;
$$;

create or replace function programacion.fn_input_stage_gate_summary(p_run_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, programacion
as $$
declare
  v_run programacion.input_readiness_runs%rowtype;
  v_summary jsonb;
  v_violations jsonb;
begin
  select * into v_run from programacion.input_readiness_runs where id=p_run_id;
  if not found then raise exception 'INPUT_STAGE_GATE_RUN_NOT_FOUND:%',p_run_id; end if;

  select jsonb_build_object(
    'families_total',count(*),
    'validator_pass',count(*) filter(where validator_outcome='PASS'),
    'applicable',count(*) filter(where applicability='APPLICABLE'),
    'not_applicable',count(*) filter(where applicability='NOT_APPLICABLE'),
    'unresolved',count(*) filter(where applicability='UNRESOLVED'),
    'applicable_p0_story_open',count(*) filter(where applicability='APPLICABLE' and severity='P0' and story_ready_status<>'READY'),
    'story_stage_open',count(*) filter(where applicability='UNRESOLVED' or (applicability='APPLICABLE' and story_ready_status<>'READY')),
    'implementation_stage_open',count(*) filter(where applicability='UNRESOLVED' or (applicability='APPLICABLE' and implementation_ready_status<>'READY')),
    'qa_stage_open',count(*) filter(where applicability='UNRESOLVED' or (applicability='APPLICABLE' and qa_ready_status<>'READY')),
    'production_stage_open',count(*) filter(where applicability='UNRESOLVED' or (applicability='APPLICABLE' and production_ready_status<>'READY'))
  ) into v_summary
  from programacion.input_family_assessments where run_id=p_run_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'family_code',family_code,
    'story',story_ready_status,
    'implementation',implementation_ready_status,
    'qa',qa_ready_status,
    'production',production_ready_status,
    'code',case
      when implementation_ready_status='READY' and story_ready_status<>'READY' then 'IMPLEMENTATION_READY_WHILE_STORY_NOT_READY'
      when qa_ready_status='READY' and implementation_ready_status<>'READY' then 'QA_READY_WHILE_IMPLEMENTATION_NOT_READY'
      when production_ready_status='READY' and qa_ready_status<>'READY' then 'PRODUCTION_READY_WHILE_QA_NOT_READY'
    end
  ) order by family_code),'[]'::jsonb) into v_violations
  from programacion.input_family_assessments
  where run_id=p_run_id and applicability='APPLICABLE'
    and ((implementation_ready_status='READY' and story_ready_status<>'READY')
      or (qa_ready_status='READY' and implementation_ready_status<>'READY')
      or (production_ready_status='READY' and qa_ready_status<>'READY'));

  return jsonb_build_object(
    'stage_gate_contract','INPUT_STAGE_GATE_SUMMARY_V1',
    'run_id',p_run_id,
    'run_status',v_run.status,
    'run_current',case when v_run.status='COMPLETED' then programacion.fn_input_readiness_run_is_current(p_run_id) else false end,
    'summary',v_summary,
    'canonical_story_gate_pass',coalesce((v_summary->>'applicable_p0_story_open')::integer,0)=0,
    'full_story_stage_closed',coalesce((v_summary->>'story_stage_open')::integer,0)=0,
    'full_implementation_stage_closed',coalesce((v_summary->>'implementation_stage_open')::integer,0)=0,
    'full_qa_stage_closed',coalesce((v_summary->>'qa_stage_open')::integer,0)=0,
    'full_production_stage_closed',coalesce((v_summary->>'production_stage_open')::integer,0)=0,
    'hierarchy_violation_count',jsonb_array_length(v_violations),
    'hierarchy_violations',v_violations
  );
end;
$$;

revoke all on function programacion.fn_input_stage_gate_summary(bigint) from public;