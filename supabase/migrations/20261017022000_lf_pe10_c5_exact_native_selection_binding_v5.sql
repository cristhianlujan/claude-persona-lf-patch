-- PE10_C5 v5: close cross-run selection/RAW reference gap in v4 consumer.
-- No C5/C6 closure, no event-contract registration, no engine qualification or activation.
BEGIN;
DO $pe10_c5_v5$
DECLARE
 v_plan constant text:='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
 v_actor constant text:='EXEC-PE10C5-SELECTION-BINDING-20261017-V5';
 v_audit constant text:='PE10_C5.NATIVE_SELECTION_SOURCE_BOUND.V5';
 v_rollback constant text:='PE10_C5.NATIVE_SELECTION_ROLLBACK_PROBE.V5';
 v_work bigint; v_old jsonb; v_new jsonb; v_contract jsonb;v_spec jsonb;v_pack jsonb;
 v_old_criteria jsonb;v_new_criteria jsonb;v_query text;v_next_query text;
 v_native_needle text; v_external_needle text;v_event_payload jsonb;
 v_admit int;v_pairs int;v_candidates int;v_event bigint;
BEGIN
 SELECT work_item_id,unit_metadata INTO STRICT v_work,v_old
 FROM programacion.engineering_plan_units
 WHERE plan_code=v_plan AND unit_code='PE10' AND disposition='ASSIGNED' FOR UPDATE;
 SELECT acceptance_criteria INTO STRICT v_old_criteria
 FROM programacion.engineering_work_items WHERE id=v_work FOR UPDATE;
 IF v_old#>>'{pe10_c5_typed_native_admission_v4,schema}' IS DISTINCT FROM
 'PE10_C5_TYPED_NATIVE_ADMISSION_V4'
 OR (SELECT status FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=v_work AND checkpoint_code='PE10_C5')<>'PENDING'
 OR (SELECT status FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=v_work AND checkpoint_code='PE10_C6')<>'PENDING'
 OR (SELECT version FROM public.lf_operation_registry
 WHERE operation_code='ACTUALIZACION_PERFIL_LF')<>'v0.1'
 OR EXISTS(SELECT 1 FROM public.lf_eventos WHERE entidad_codigo IN(v_audit,v_rollback))
 OR EXISTS(SELECT 1 FROM public.lf_eventos WHERE
 evento_tipo='PROFILE_EVOLUTION_CUTOVER_ADMITTED'
 AND entidad_codigo='ACTUALIZACION_PERFIL_LF')
 THEN RAISE EXCEPTION 'PE10_C5_V5_PRESTATE_DRIFT'; END IF;
 v_contract:=v_old#>'{checkpoint_contracts,PE10_C5}';
 v_spec:=v_old#>'{action_specs_v1,PE10_C5}';
 v_pack:=v_old#>'{source_pack_v2,checkpoint_inputs,PE10_C5}';
 v_query:=v_spec#>>'{verification_queries,0}';
 IF v_spec#>>'{scope_qualification_policy,mode}' IS DISTINCT FROM 'SINGLE_DYNAMIC_UPDATER_V02'
 OR v_query IS DISTINCT FROM v_contract#>>'{validation_input,queries,0}'
 OR v_query IS DISTINCT FROM v_pack#>>'{inputs,queries,0}'
 THEN RAISE EXCEPTION 'PE10_C5_V5_CONSUMER_PREIMAGE_DRIFT'; END IF;
 v_native_needle:='AND raw.receipt_payload->>''source_manifest_sha256''=c.p->>''native_source_manifest_sha256''';
 v_external_needle:='c.p->>''executor_mode''=''METHOD_PACK_EXECUTOR''';
 IF position(v_native_needle in v_query)=0
 OR position(v_external_needle in v_query)=0
 OR position('raw.receipt_payload->''selected_method_ids''=c.p->''selected_method_ids''' in v_query)>0
 THEN RAISE EXCEPTION 'PE10_C5_V5_ANCHOR_DRIFT_OR_REPLAY'; END IF;
 v_next_query:=replace(v_query,v_native_needle,v_native_needle||E'\n'||
 '      AND c.p->>''operational_selection_evidence_ref''=c.p->>''native_source_receipt_ref'''||E'\n'||
 '      AND raw.receipt_payload->''selected_method_ids''=c.p->''selected_method_ids'''||E'\n'||
 '      AND raw.receipt_payload->>''profile_slug''=c.p->>''profile_slug'''||E'\n'||
 '      AND raw.receipt_payload->>''run_id''=c.p->>''native_run_id'''||E'\n'||
 '      AND raw.receipt_payload->>''native_conversation_scope''=''EXISTING_CONVERSATION_ONLY'''||E'\n'||
 '      AND raw.receipt_payload->>''api_invocation''=''false'''||E'\n'||
 '      AND raw.receipt_payload->>''session_creation''=''false'''||E'\n'||
 '      AND raw.receipt_payload->>''cutover_eligible''=''false'''||E'\n'||
 '      AND raw.receipt_payload->>''method_execution_certified''=''false''');
 v_next_query:=replace(v_next_query,v_external_needle,v_external_needle||E'\n'||
 '  AND c.p->>''operational_selection_evidence_ref'' IN ('||
 'SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(c.p->''method_execution_receipt_refs'')=''array'' '||
 'THEN c.p->''method_execution_receipt_refs'' ELSE ''[]''::jsonb END))');
 IF v_next_query=v_query
 OR position('raw.receipt_payload->''selected_method_ids''=c.p->''selected_method_ids''' in v_next_query)=0
 OR position('operational_selection_evidence_ref'' IN (' in v_next_query)=0
 THEN RAISE EXCEPTION 'PE10_C5_V5_NO_EFFECT'; END IF;
 v_contract:=jsonb_set(v_contract,'{validation_input,queries}',
  jsonb_build_array(v_next_query),false);
 v_contract:=v_contract||jsonb_build_object(
 'resolver_policy','SOURCE_BOUND_EXACT_NATIVE_METHOD_SELECTION_OR_VERIFIED_SELECTED_ENGINE_EXECUTION',
 'pass_when','One dynamic v0.2, verified SAFE_CHANGE_ADMISSION, and exact reviewer or selected external method execution evidence. Native operational selection receipt MUST equal its verified raw SOURCE_SNAPSHOT and selected IDs MUST equal raw selected IDs.');
 v_spec:=jsonb_set(v_spec,'{verification_queries}',jsonb_build_array(v_next_query),false);
 v_spec:=v_spec||jsonb_build_object(
 'scope_qualification_policy',(v_spec->'scope_qualification_policy')||
 jsonb_build_object('native_selection_binding','RAW_RECEIPT_AND_EXACT_METHOD_IDS',
 'external_selection_binding','VERIFIED_SELECTED_EXECUTION_RECEIPT'),
 'forbidden',(v_spec->'forbidden')||
 jsonb_build_array('NATIVE_SELECTION_TEXT_ONLY_REF','CROSS_RUN_METHOD_IDS','EXTERNAL_SELECTION_TEXT_ONLY_REF'));
 v_pack:=jsonb_set(v_pack,'{inputs,queries}',jsonb_build_array(v_next_query),false);
 v_new:=jsonb_set(v_old,'{checkpoint_contracts,PE10_C5}',v_contract,false);
 v_new:=jsonb_set(v_new,'{action_specs_v1,PE10_C5}',v_spec,false);
 v_new:=jsonb_set(v_new,'{source_pack_v2,checkpoint_inputs,PE10_C5}',v_pack,false);
 v_new:=jsonb_set(v_new,'{pe10_c5_native_selection_binding_v5}',jsonb_build_object(
 'schema','PE10_C5_NATIVE_SELECTION_BINDING_V5',
 'one_updater',true,'selected_methods_match_verified_raw',true,
 'native_selection_ref_must_match_source_receipt',true,
 'external_selection_ref_must_match_verified_execution',true,
 'no_cutover',true,'no_production_activation',true),true);
 IF v_new#>'{action_specs_v1,PE10_C6}' IS DISTINCT FROM v_old#>'{action_specs_v1,PE10_C6}'
 OR v_new#>'{action_specs_v1,PE10_C7}' IS DISTINCT FROM v_old#>'{action_specs_v1,PE10_C7}'
 OR v_new#>'{checkpoint_contracts,PE10_C6}' IS DISTINCT FROM v_old#>'{checkpoint_contracts,PE10_C6}'
 OR v_new#>'{checkpoint_contracts,PE10_C7}' IS DISTINCT FROM v_old#>'{checkpoint_contracts,PE10_C7}'
 THEN RAISE EXCEPTION 'PE10_C5_V5_CROSS_CHECKPOINT_DRIFT'; END IF;
 SELECT jsonb_agg(CASE WHEN x.value LIKE 'PE10_C5:%'
 THEN to_jsonb('PE10_C5: single dynamic v0.2, selected methods must match the exact source-bound GPT/Claude Native RAW and its verified selection ref, or verified per-selected external pack execution; real independent review plus SAFE_CHANGE_ADMISSION, no activation.'::text)
 ELSE to_jsonb(x.value) END ORDER BY x.ordinality) INTO v_new_criteria
 FROM jsonb_array_elements_text(v_old_criteria) WITH ORDINALITY x(value,ordinality);
 IF v_new_criteria IS NULL THEN RAISE EXCEPTION 'PE10_C5_V5_CRITERIA_MISSING'; END IF;
 EXECUTE v_next_query INTO v_admit,v_pairs,v_candidates;
 IF v_admit<>0 OR v_pairs<>1 OR v_candidates<>0
 THEN RAISE EXCEPTION 'PE10_C5_V5_BASELINE_NOT_FAIL_CLOSED:%,%,%',v_admit,v_pairs,v_candidates; END IF;
 IF (programacion.fn_engineering_execution_packet_from_spec_v1(
 v_plan,'PE10','PE10_C5',v_spec,v_pack))->>'status' IS DISTINCT FROM 'READY'
 THEN RAISE EXCEPTION 'PE10_C5_V5_PACKET_INVALID'; END IF;
 v_event_payload:=jsonb_build_object(
 'evidence_schema_version','operational-event/v2','execution_id',v_actor,
 'producer','PE10_C5_CONTRACT_REPAIR','purpose',
 'Enforce verified native RAW selection and exact method IDs before admission',
 'occurred_at',clock_timestamp(),'acceptance_declared',false,
 'plan_code',v_plan,'checkpoint_code','PE10_C5','admissible_events',0,
 'original_contract','PE10_C5_TYPED_NATIVE_ADMISSION_V4',
 'new_contract','PE10_C5_NATIVE_SELECTION_BINDING_V5',
 'checkpoint_pass',false,'cutover_admitted',false,'production_activation',false);
 IF private.fn_lf_event_acceptance_signal_v2('ARTIFACT_RECONCILED',v_audit,
 'PE10 C5 exact selection source binding',v_event_payload) IS NOT NULL
 THEN RAISE EXCEPTION 'PE10_C5_V5_AUDIT_FALSE_ACCEPTANCE'; END IF;
 BEGIN
  UPDATE programacion.engineering_plan_units SET unit_metadata=v_new
   WHERE work_item_id=v_work AND unit_metadata=v_old;
  UPDATE programacion.engineering_work_items SET acceptance_criteria=v_new_criteria
   WHERE id=v_work AND acceptance_criteria=v_old_criteria;
  INSERT INTO public.lf_eventos
   (evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,created_by_execution_id,payload)
   VALUES('ARTIFACT_RECONCILED','PROGRAM_PLAN',v_rollback,
    'PE10 C5 V5 expected rollback only','INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_event_payload)
   RETURNING id INTO v_event;
  IF v_event IS NULL THEN RAISE EXCEPTION 'PE10_C5_V5_PROBE_MISSING'; END IF;
  RAISE EXCEPTION 'PE10_C5_V5_EXPECTED_ROLLBACK';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'PE10_C5_V5_EXPECTED_ROLLBACK' THEN RAISE; END IF;
 END;
 IF (SELECT unit_metadata FROM programacion.engineering_plan_units WHERE work_item_id=v_work)
 IS DISTINCT FROM v_old OR EXISTS(SELECT 1 FROM public.lf_eventos WHERE entidad_codigo=v_rollback)
 THEN RAISE EXCEPTION 'PE10_C5_V5_ROLLBACK_RESIDUE'; END IF;
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_new
 WHERE work_item_id=v_work AND unit_metadata=v_old;
 IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C5_V5_SOURCE_CAS'; END IF;
 UPDATE programacion.engineering_work_items SET acceptance_criteria=v_new_criteria
 WHERE id=v_work AND acceptance_criteria=v_old_criteria;
 IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C5_V5_CRITERIA_CAS'; END IF;
 INSERT INTO public.lf_eventos
 (evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,created_by_execution_id,payload)
 VALUES('ARTIFACT_RECONCILED','PROGRAM_PLAN',v_audit,
 'C5 native/external verified source selection binding; no cutover',
 'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_event_payload)
 RETURNING id INTO v_event;
 EXECUTE v_next_query INTO v_admit,v_pairs,v_candidates;
 IF v_admit<>0 OR v_pairs<>1 OR v_candidates<>0
 OR (SELECT status FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=v_work AND checkpoint_code='PE10_C5')<>'PENDING'
 OR (SELECT version FROM public.lf_operation_registry
 WHERE operation_code='ACTUALIZACION_PERFIL_LF')<>'v0.1'
 THEN RAISE EXCEPTION 'PE10_C5_V5_POST_WRITE_READBACK'; END IF;
END $pe10_c5_v5$;
COMMIT;
