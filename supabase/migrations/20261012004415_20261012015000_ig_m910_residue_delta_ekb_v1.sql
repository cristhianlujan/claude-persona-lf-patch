-- M9.10 followup: residue-by-delta, include assessments, and record verified contract lessons in EKB.
-- Contract-only; leaves canary, release pointer, and checkpoint states unchanged.
DO $m910_residue$
DECLARE v_work bigint; v_meta jsonb; v_spec jsonb; v_queries jsonb;
BEGIN
 SELECT work_item_id,unit_metadata INTO v_work,v_meta FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.10' FOR UPDATE;
 IF v_work IS NULL OR v_meta#>>'{cohort_expansion_governance_v1,transversal_governance_change}'
    IS DISTINCT FROM 'NOT_APPLICABLE_REUSE_EXISTING_GATES' THEN
    RAISE EXCEPTION 'M910_REVISED_CONTRACT_NOT_CURRENT'; END IF;
 IF (select status from programacion.engineering_work_items where id=v_work) IS DISTINCT FROM 'IN_PROGRESS'
 THEN RAISE EXCEPTION 'M910_WORK_STATE_DRIFT'; END IF;
 v_queries:=jsonb_build_array(
  'select count(*) as historical_runs from programacion.input_readiness_runs',
  'select count(*) as historical_assessments from programacion.input_family_assessments a join programacion.input_readiness_runs r on r.id=a.run_id',
  'select capability_code,binding_state,count(*) as historical_bindings from public.lf_capability_binding group by capability_code,binding_state',
  'select capability_code,version,manifest_sha256 from public.lf_capability_version_registry where capability_code=''INPUT_GOVERNANCE'' order by version');
 v_spec:=v_meta#>'{action_specs_v1,RESIDUE_NEGATIVE}';
 IF v_spec->>'status' IS DISTINCT FROM 'READY' THEN RAISE EXCEPTION 'M910_NEGATIVE_PRESTATE_DRIFT'; END IF;
 v_spec:=v_spec||jsonb_build_object('expected',
   'Compare prestate/poststate of candidate-only runs, input_family_assessments keyed by run_id, bindings, and registry versions. Exact candidate delta must equal 0; existing historical data can be nonzero.',
   'verification_queries',v_queries,
   'residue_policy_v1',jsonb_build_object(
      'scope','CANDIDATE_ONLY','comparison','PRESTATE_EQUALS_POSTSTATE',
      'run_join_key','programacion.input_family_assessments.run_id',
      'no_global_rowcount_zero_expectation',true,'no_runtime_activation',true));
 v_spec:=jsonb_set(v_spec,'{test_execution_contract,declared_queries}',v_queries,true);
 v_spec:=jsonb_set(v_spec,'{test_execution_contract,declared_objects}',
  jsonb_build_array('programacion.input_readiness_runs','programacion.input_family_assessments','public.lf_capability_binding','public.lf_capability_version_registry'),true);
 v_spec:=jsonb_set(v_spec,'{test_execution_contract,checkpoint_title_context}',
  to_jsonb('Negativo: delta de residuos del candidato=0 frente a baseline capturado en la misma prueba'::text),true);
 v_spec:=jsonb_set(v_spec,'{target,declared_objects}',
  jsonb_build_array('programacion.input_readiness_runs','programacion.input_family_assessments','public.lf_capability_binding','public.lf_capability_version_registry'),true);
 v_meta:=jsonb_set(v_meta,'{action_specs_v1,RESIDUE_NEGATIVE}',v_spec,true);
 v_meta:=jsonb_set(v_meta,'{source_pack_v1,checkpoint_inputs,RESIDUE_NEGATIVE,inputs,queries}',v_queries,true);
 v_meta:=jsonb_set(v_meta,'{source_pack_v1,checkpoint_inputs,RESIDUE_NEGATIVE,inputs,db_objects}',
  jsonb_build_array('programacion.input_readiness_runs','programacion.input_family_assessments','public.lf_capability_binding','public.lf_capability_version_registry'),true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_meta
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.10';
 UPDATE programacion.engineering_work_checkpoints SET title='Negativo: delta de residuos del candidato igual a cero'
 WHERE work_item_id=v_work AND checkpoint_code='RESIDUE_NEGATIVE'
 AND title='Negativo: query de residuos (filas/bindings del candidato) debe devolver 0';
 IF NOT FOUND THEN RAISE EXCEPTION 'M910_RESIDUE_TITLE_DRIFT'; END IF;
END $m910_residue$;
DO $ekb$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM public.lf_error_knowledge
 WHERE codigo IN ('IG-M910-CONTRACT-AUTHORITY-DRIFT-001','IG-M910-RESIDUE-BASELINE-001');
 IF n<>0 THEN RAISE EXCEPTION 'M910_EKB_PRESTATE_ALREADY_EXISTS'; END IF;
 INSERT INTO public.lf_error_knowledge
  (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
   severidad,frecuencia,lote_origen,pr,estado,evidencia,lifecycle_phase,
   consumer_role,root_cause_family,detectability,source_context,source_ref)
 VALUES
 ('IG-M910-CONTRACT-AUTHORITY-DRIFT-001','GOVERNANCE','M9.10 heredaba CAPABILITY_CUTOVER ausente y SADM-PP desactivado',
 'Contrato COHORT_BY_COHORT estaba en BLOCK_CAPABILITY_CUTOVER_NOT_REGISTERED aunque existe INPUT_GOVERNANCE versionado; el simulacro de rollback citaba CAPABILITY_CUTOVER y SOURCE_PACK consultaba SADM-PP.',
 'Copia de autoridad nominal y fuentes externas en contrato IG sin reconciliar con registry CURRENT ni estado de workstream.',
 'STALE_CUTOVER_ALIAS_AND_DISABLED_POST_PASE_SOURCE',
 'Reutilizar current/version_registry/promote y effective_dependencies; reparar action spec, checkpoint, source_pack y test contract como un lote; conservar WAIT_DEPENDENCIES hasta M9.9 DONE, sin nuevo motor ni ejecución de cutover.',
 'PR #2257 SQL exacto Git BEGIN/ROLLBACK PASS: compilador READY, bootstrap WAIT_DEPENDENCIES, cuatro pendientes, SADM=0, CAPABILITY_CUTOVER target=0, 0 residuos; aplicada en LF_SUPABASE_SANDBOX.',
 'HIGH',1,'IG_CURATOR_VALIDATOR_REFACTOR_V2','2257','VERIFICADO',
 'github://cristhianlujan/claude-persona-lf-patch/pull/2257; migration 20261012011000_ig_m910_versioned_cohort_contract_v1; PAULO-150 IN_PROGRESS 15%; prerequisite PAULO-093 IN_PROGRESS',
 'CONSTRUCTION',ARRAY['ENGINEERING_EXECUTOR','GOVERNANCE']::text[],
 'R2_NO_VE','PROCESS_DEPENDENT','M9.10 contract repair without expansion','programacion.engineering_plan_units M9.10'),
 ('IG-M910-RESIDUE-BASELINE-001','ENGINEERING_VALIDATION','Contador histórico no prueba residuo cero del candidato',
 'El checkpoint RESIDUE_NEGATIVE requería 0 filas en consultas agregadas aunque input_readiness_runs contiene historia real. Además omitía input_family_assessments asociadas a run_id.',
 'Se confundió cero residuos de una transacción reversible con ausencia absoluta de datos históricos y se omitió una entidad dependiente.',
 'GLOBAL_ROWCOUNT_ZERO_INSTEAD_OF_CANDIDATE_DELTA_ZERO',
 'Congelar baseline prestate, ejecutar prueba reversible, comparar delta de registros candidato y versiones con baseline, exigir delta=0 por runs, assessments, bindings y registry. No borrar ni modificar datos históricos para pasar.',
 'Contrato y title M9.10 alineados; requerir prueba de regresión con datos históricos no vacíos y rollback sin residuo antes del DONE del checkpoint.',
 'HIGH',1,'IG_CURATOR_VALIDATOR_REFACTOR_V2','2257','ACTIVO',
 'supabase://programacion.input_readiness_runs; programacion.input_family_assessments; github://cristhianlujan/claude-persona-lf-patch/pull/2257',
 'VALIDATION',ARRAY['ENGINEERING_EXECUTOR','VALIDATOR']::text[],
 'R2_NO_VE','PROCESS_DEPENDENT','M9.10 residual check contract repair','programacion.engineering_plan_units M9.10 RESIDUE_NEGATIVE');
 IF (select count(*) from public.lf_error_knowledge where codigo in
 ('IG-M910-CONTRACT-AUTHORITY-DRIFT-001','IG-M910-RESIDUE-BASELINE-001'))<>2
 THEN RAISE EXCEPTION 'M910_EKB_INSERT_READBACK_FAILED'; END IF;
END $ekb$;
