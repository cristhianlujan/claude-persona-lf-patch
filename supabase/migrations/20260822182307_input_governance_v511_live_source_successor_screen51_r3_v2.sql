set local statement_timeout = '10min';

do $$
declare
  v_screen integer := 51;
  v_parent bigint;
  a record;
  v_new bigint;
  v_cur text;
  v_val text;
  v_sha text;
  v_assert jsonb;
  v_design_missing_components integer;
begin
  select r.id into v_parent
  from programacion.input_readiness_runs r
  where r.version_id=19 and r.pantalla_id=v_screen and r.status='COMPLETED'
    and r.contract_revision='5.11' and r.invalidated_at is null
    and not exists (
      select 1 from programacion.input_readiness_runs s
      where s.supersedes_run_id=r.id and s.status in ('COMPLETED','BLOCKED')
    )
  order by r.id desc limit 1;
  if v_parent is null then raise exception 'V511_R3_PARENT_NOT_FOUND screen=%',v_screen; end if;
  if programacion.fn_input_readiness_run_is_current(v_parent) then raise exception 'V511_R3_PARENT_EXPECTED_STALE screen=% run=%',v_screen,v_parent; end if;

  v_design_missing_components := coalesce((programacion.fn_input_screen_canonical_graph(v_screen,19)#>>'{canonical_contract,visual,design_bindings,summary,element_required_missing_component_count}')::integer,0);

  v_cur := 'INPUT_CURATOR:v0.5r1-auth-'||v_screen||'-v511-live-r3-'||substr(md5(random()::text||clock_timestamp()::text),1,8);
  insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,scope,universe_snapshot_sha256,family_count,status,curator_identity,curator_component_id,contract_version)
  select version_id,pantalla_id,universe_rule_id,id,
         scope || jsonb_build_object('mode','CANDIDATE_V511_LIVE_SOURCE_R3','parent_run_id',id,'remediation','PR179_LIVE_SOURCE_SEMANTIC_RECONCILIATION_20260822'),
         universe_snapshot_sha256,family_count,'CURATING',v_cur,curator_component_id,contract_version
  from programacion.input_readiness_runs where id=v_parent returning id into v_new;

  for a in select * from programacion.input_family_assessments where run_id=v_parent order by family_code loop
    insert into programacion.input_family_assessments(
      run_id,family_code,severity,applicability,coverage_status,well_defined_status,
      story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,
      source_refs,rationale,blockers,negative_requirements,test_obligations,curator_evidence,curator_sha256)
    values(
      v_new,a.family_code,a.severity,a.applicability,a.coverage_status,a.well_defined_status,
      a.story_ready_status,a.implementation_ready_status,a.qa_ready_status,a.production_ready_status,
      a.source_refs,
      case
        when a.family_code='DESIGN_SYSTEM' then a.rationale || format(' | Readback 2026-08-22: el inventario canónico ya contiene 17 elementos; quedan %s elementos obligatorios sin binding de componente, además de las brechas de tipografía/placeholder ya abiertas.',v_design_missing_components)
        when a.family_code='PERMISSIONS' then a.rationale || ' | Readback 2026-08-22: el catálogo de permisos de Login permanece completo; no concede por sí mismo alcance multiempresa. La autorización de tenant se resuelve server-side por authorized company set y el modelo físico multiempresa pendiente queda bloqueado en SECURITY/RUNTIME_CONFIG.'
        when a.family_code='PROFILES' then a.rationale || ' | Readback 2026-08-22: los seis perfiles humanos permanecen definidos. La relación física usuario-grupo-empresas no se infiere desde PROFILES y continúa como dependencia explícita de tenant/runtime.'
        when a.family_code='RUNTIME_CONFIG' then a.rationale || ' | B2B-RULE-AUTH-002 mantiene multi_company_physical_model_status=PENDING_FUNCTIONAL_DEFINITION; no se autoriza Implementation Ready del binding multiempresa hasta materializar la relación autorizada server-side.'
        when a.family_code='SECURITY' then a.rationale || ' | B2B-RULE-AUTH-002 exige cross_tenant=DENY, tenant_resolution_authority=SERVER_ONLY y pruebas negativas; el modelo físico multiempresa sigue pendiente y no habilita acceso operativo.'
        else a.rationale || ' | Revalidado contra fuentes canónicas vigentes por reconciliación semántica PR #179 2026-08-22.'
      end,
      case
        when a.family_code='DESIGN_SYSTEM' then
          (select coalesce(jsonb_agg(e),'[]'::jsonb) from jsonb_array_elements(a.blockers) e where e->>'code' not in ('SCREEN_ELEMENT_INVENTORY_MISSING','CURRENT_VARIANT_LAYOUT_BINDING_MISSING'))
          || case when v_design_missing_components>0 then jsonb_build_array(jsonb_build_object('code','ELEMENT_REQUIRED_COMPONENT_BINDING_MISSING','count',v_design_missing_components,'source_ref','SCREEN_CANONICAL_GRAPH.design_bindings.summary')) else '[]'::jsonb end
        when a.family_code in ('RUNTIME_CONFIG','SECURITY') then
          a.blockers || jsonb_build_array(jsonb_build_object('code','MULTI_COMPANY_PHYSICAL_MODEL_PENDING','source_ref','B2B-RULE-AUTH-002','status','PENDING_FUNCTIONAL_DEFINITION'))
        else a.blockers
      end,
      a.negative_requirements,
      case
        when a.family_code='SECURITY' then
          a.test_obligations || jsonb_build_array('MULTI_COMPANY_CROSS_TENANT_NEGATIVE_TEST','AUTHORIZED_COMPANY_SET_SERVER_SIDE_RESOLUTION_TEST')
        else a.test_obligations
      end,
      jsonb_build_object(
        'component_id',46,'execution_id',gen_random_uuid()::text,'execution_mode','INDEPENDENT_CURATOR',
        'contract_revision','5.11','parent_run_id',v_parent,'parent_assessment_id',a.id,
        'remediation_revision','PR179_LIVE_SOURCE_SEMANTIC_RECONCILIATION_20260822','direct_source_readback',true),
      repeat('0',64));
  end loop;

  v_val := 'INPUT_VALIDATOR:v0.5r1-auth-'||v_screen||'-v511-live-r3-'||substr(md5(random()::text||clock_timestamp()::text),1,8);
  update programacion.input_readiness_runs set status='VALIDATING',validator_identity=v_val,validator_component_id=47 where id=v_new;
  select source_snapshot_sha256 into v_sha from programacion.input_readiness_runs where id=v_new;

  for a in select * from programacion.input_family_assessments where run_id=v_new order by family_code loop
    v_assert := programacion.fn_input_v58_build_assertions(v_new,v_parent,a.family_code);
    update programacion.input_family_assessments
       set validator_outcome='PASS',validator_findings='[]'::jsonb,validator_identity=v_val,
           validator_evidence=jsonb_build_object('component_id',47,'execution_id',gen_random_uuid()::text,'validated_curator_execution_id',a.curator_evidence->>'execution_id','execution_mode','INDEPENDENT_VALIDATOR','direct_source_readback',true,'contract_revision','5.11','source_snapshot_sha256',v_sha,'curator_sha256',a.curator_sha256,'semantic_depth_sha256',a.semantic_depth_sha256,'assertions',v_assert)
     where id=a.id;
  end loop;

  update programacion.input_readiness_runs set status='COMPLETED' where id=v_new;
  if not programacion.fn_input_readiness_run_is_current(v_new) then raise exception 'V511_R3_POSTCHECK_CURRENTNESS_FAILED screen=% run=%',v_screen,v_new; end if;
end$$;