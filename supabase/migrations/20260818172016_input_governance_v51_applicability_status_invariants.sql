insert into programacion.versiones_agente(agente_id,version_codigo,objetivo,estado,supersedes_version_id,notas)
select v.agente_id,
       'v0.3-input-readiness-semantic-bindings-r1-candidate',
       v.objetivo || ' Añade invariantes determinísticos entre applicability y estados readiness.',
       'candidate',v.id,
       'CANDIDATE_V5_1_2026-08-18: impide APPLICABLE con NOT_APPLICABLE y NOT_APPLICABLE con estados no-NA. No promotion.'
from programacion.versiones_agente v
where v.id=14
  and not exists(select 1 from programacion.versiones_agente where version_codigo='v0.3-input-readiness-semantic-bindings-r1-candidate');

insert into programacion.componentes(version_id,componente_codigo,tipo,nombre,responsabilidad,orden_ejecucion,independencia_requerida,configuracion,estado)
select nv.id,c.componente_codigo,c.tipo,c.nombre,c.responsabilidad,c.orden_ejecucion,c.independencia_requerida,
       c.configuracion || jsonb_build_object('applicability_status_invariants','V5_1'),c.estado
from programacion.componentes c
join programacion.versiones_agente nv on nv.version_codigo='v0.3-input-readiness-semantic-bindings-r1-candidate'
where c.version_id=14
  and not exists(select 1 from programacion.componentes x where x.version_id=nv.id and x.componente_codigo=c.componente_codigo);

insert into programacion.contratos(version_id,contrato_codigo,tipo,nombre,descripcion,productor_componente_id,consumidor_componente_id,especificacion,fail_closed,estado)
select nv.id,c.contrato_codigo,c.tipo,c.nombre,
       c.descripcion || ' V5.1 añade consistencia determinística applicability↔readiness.',
       (select nc.id from programacion.componentes nc where nc.version_id=nv.id and nc.componente_codigo='INPUT_VALIDATOR'),
       null,
       jsonb_set(c.especificacion,'{contract_revision}','"5.1"'::jsonb,true)
       || jsonb_build_object(
          'applicability_status_invariants',jsonb_build_object(
             'APPLICABLE','NO_READINESS_STATUS_MAY_BE_NOT_APPLICABLE',
             'NOT_APPLICABLE','ALL_READINESS_STATUSES_MUST_BE_NOT_APPLICABLE',
             'UNRESOLVED','STORY_READY_MUST_NOT_BE_READY'
          ),
          'negative_tests',(c.especificacion->'negative_tests') || jsonb_build_array('APPLICABLE_WITH_NOT_APPLICABLE_STATUS','NOT_APPLICABLE_WITH_NON_NA_STATUS'),
          'audit_remediation',(c.especificacion->'audit_remediation') || jsonb_build_array('AUD-IGA-008_APPLICABILITY_STATUS_CONSISTENCY')
       ),
       c.fail_closed,c.estado
from programacion.contratos c
join programacion.versiones_agente nv on nv.version_codigo='v0.3-input-readiness-semantic-bindings-r1-candidate'
where c.id=29
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
  v_families jsonb;
  v_payload jsonb;
  v_ref jsonb;
  v_mode text;
  v_states text[];
begin
  select r.status,r.contract_version,r.pantalla_id,r.version_id,q.valor_config->'families'
    into v_status,v_contract_version,v_pantalla_id,v_version_id,v_families
  from programacion.input_readiness_runs r join lf_ops.reglas q on q.id=r.universe_rule_id where r.id=new.run_id;
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

revoke all on function programacion.fn_guard_input_family_assessment_insert() from public;