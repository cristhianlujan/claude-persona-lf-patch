do $$
declare
  v_prev programacion.agent_tasks%rowtype;
  v_f public.lf_functional_versions%rowtype;
  v_task_id bigint;
  v_dc_prev programacion.agent_task_delivery_contracts%rowtype;
  v_dc_id bigint;
  v_ac text[];
  v_inv text[];
  v_neg text[];
  v_all text[];
begin
  select * into v_f
  from public.lf_functional_versions
  where artifact_code='HU-HMO-001' and version_no=2 and status='SEALED'
  order by id desc limit 1;
  if v_f.id is null then raise exception 'PRODUCT_QUALITY_FUNCTIONAL_V2_MISSING'; end if;

  select * into v_prev
  from programacion.agent_tasks
  where task_code='HU-HMO-001' and task_version=2 and definition_status='SEALED'
  order by id desc limit 1;
  if v_prev.id is null then raise exception 'PRODUCT_QUALITY_TASK_V2_MISSING'; end if;

  select id into v_task_id
  from programacion.agent_tasks
  where task_code='HU-HMO-001' and task_version=3
  order by id desc limit 1;

  if v_task_id is null then
    insert into programacion.agent_tasks(
      task_code,task_version,functional_version_id,supersedes_task_id,objective,
      acceptance_refs,invariant_refs,negative_refs,
      context_path_patterns,write_path_patterns,protected_path_patterns,files_expected,
      platform_refs,interface_refs,unknown_refs,
      max_attempts,max_patch_bytes,max_changed_files,max_context_bytes,
      allow_deletions,definition_status,task_sha256,sealed_at
    ) values (
      'HU-HMO-001',3,v_f.id,v_prev.id,v_prev.objective,
      array['AC-HMO-001-001','AC-HMO-001-002','AC-HMO-001-003','AC-HMO-001-004','AC-HMO-001-005','AC-HMO-001-006']::text[],
      v_prev.invariant_refs,v_prev.negative_refs,
      v_prev.context_path_patterns,v_prev.write_path_patterns,v_prev.protected_path_patterns,
      array['src/app/hmo-state.mjs','src/app/hmo-state.mutation.test.mjs','src/app/hmo-state.test.mjs','src/app/multi-offer-home.tsx','src/app/page.tsx']::text[],
      v_prev.platform_refs,v_prev.interface_refs,'{}'::text[],
      null,null,null,null,false,'DRAFT',null,null
    ) returning id into v_task_id;
    update programacion.agent_tasks set definition_status='SEALED' where id=v_task_id and definition_status='DRAFT';
  end if;

  if not exists(
    select 1 from programacion.agent_tasks
    where id=v_task_id and functional_version_id=v_f.id and task_version=3 and definition_status='SEALED'
      and acceptance_refs=array['AC-HMO-001-001','AC-HMO-001-002','AC-HMO-001-003','AC-HMO-001-004','AC-HMO-001-005','AC-HMO-001-006']::text[]
      and files_expected=array['src/app/hmo-state.mjs','src/app/hmo-state.mutation.test.mjs','src/app/hmo-state.test.mjs','src/app/multi-offer-home.tsx','src/app/page.tsx']::text[]
  ) then raise exception 'PRODUCT_QUALITY_TASK_V3_DRIFT'; end if;

  select * into v_dc_prev
  from programacion.agent_task_delivery_contracts
  where task_id=v_prev.id and status='SEALED'
  order by id desc limit 1;
  if v_dc_prev.id is null then raise exception 'PRODUCT_QUALITY_DELIVERY_V2_MISSING'; end if;

  select id into v_dc_id
  from programacion.agent_task_delivery_contracts
  where task_id=v_task_id
  order by id desc limit 1;

  v_ac:=programacion.fn_p0_json_codes(v_f.acceptance_criteria,'AC');
  v_inv:=programacion.fn_p0_json_codes(v_f.invariants,'INV');
  v_neg:=programacion.fn_p0_json_codes(v_f.negative_controls,'NEG');
  v_all:=coalesce(v_ac,'{}'::text[])||coalesce(v_inv,'{}'::text[])||coalesce(v_neg,'{}'::text[]);

  if v_dc_id is null then
    insert into programacion.agent_task_delivery_contracts(
      task_id,schema_version,expected_change,in_scope,out_of_scope,must_not_change,
      positive_cases,edge_cases,regression_cases,dependency_resolution,
      required_tests,required_evidence,blocked_if,semantic_ambiguities,
      generated_from_functional_sha256,generated_from_task_sha256,status,contract_sha256,sealed_at
    )
    select
      v_task_id,3,
      v_dc_prev.expected_change,
      v_dc_prev.in_scope,
      v_dc_prev.out_of_scope,
      v_dc_prev.must_not_change,
      v_dc_prev.positive_cases,
      v_dc_prev.edge_cases,
      v_dc_prev.regression_cases,
      v_dc_prev.dependency_resolution,
      jsonb_build_array(
        jsonb_build_object('test_ref','VISIBLE:build','purpose','Demostrar que el cambio compila en el proyecto exacto.','covers_refs',to_jsonb(v_f.source_rule_codes)),
        jsonb_build_object('test_ref','VISIBLE:lint','purpose','Detectar defectos estáticos en el cambio.','covers_refs',to_jsonb(v_f.source_rule_codes)),
        jsonb_build_object('test_ref','SEMANTIC:HMO-001','purpose','Ejecutar los comportamientos observables de los seis criterios de aceptación.','covers_refs',to_jsonb(v_ac)),
        jsonb_build_object('test_ref','MUTATION:HMO-001','purpose','Mutar cada comportamiento material y demostrar que el evaluador produce FAIL.','covers_refs',to_jsonb(v_all))
      ),
      jsonb_build_array(
        jsonb_build_object('evidence_type','EXACT_HEAD_TEST_RECEIPTS','source_ref','github-actions://hmo-product-quality','covers_refs',to_jsonb(v_all)),
        jsonb_build_object('evidence_type','SEMANTIC_MUTATION_RECEIPT','source_ref','quality://mutation-hmo-001','covers_refs',to_jsonb(v_all))
      ),
      jsonb_build_array(
        jsonb_build_object('code','BLOCK-SEMANTIC-TESTS','condition','Los tests semánticos y mutation tests requeridos no existen o no demuestran comportamiento; build/lint y búsqueda de palabras no son suficientes.')
      ),
      '[]'::jsonb,
      v_f.content_sha256,
      (select task_sha256 from programacion.agent_tasks where id=v_task_id),
      'DRAFT',null,null
    returning id into v_dc_id;
    update programacion.agent_task_delivery_contracts set status='SEALED' where id=v_dc_id and status='DRAFT';
  end if;

  if not exists(
    select 1 from programacion.agent_task_delivery_contracts
    where id=v_dc_id and task_id=v_task_id and schema_version=3 and status='SEALED'
  ) then raise exception 'PRODUCT_QUALITY_DELIVERY_V3_DRIFT'; end if;
end $$;
