-- PE10_C5: ONE dynamic Updater v0.2; remove the assistant-introduced
-- LIMITED vs FULL_EXPERT product approval split. No production activation here.
-- This migration changes ONLY PE10_C5 declared contract/queries/criteria.
-- C3 historical non-admission is preserved, C4 drain preserved, C6/C7 untouched.
-- Actual method qualification and safety verification remain mandatory.
-- Train: test new contract under rolled-back subtransaction, replay, readback.
BEGIN;
DO $pe10$
DECLARE
  v_plan constant text:='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
  v_actor constant text:='EXEC-PE10-C5-SINGLE-DYNAMIC-CONTRACT-20261016-V3';
  v_event_code constant text:='PE10_C5.SINGLE_DYNAMIC_UPDATER_V02_CONTRACT.V3';
  v_work bigint;v_old jsonb;v_new jsonb;v_contract jsonb;v_spec jsonb;v_source jsonb;
  v_old_criteria jsonb;v_new_criteria jsonb;v_query text;v_state text;
  v_event_payload jsonb;v_event_id bigint;v_admissions integer;v_pairs integer;v_methods integer;
BEGIN
 SELECT u.work_item_id,u.unit_metadata INTO v_work,v_old
 FROM programacion.engineering_plan_units u
 WHERE u.plan_code=v_plan AND u.unit_code='PE10' AND u.disposition='ASSIGNED' FOR UPDATE;
 IF v_work IS NULL THEN RAISE EXCEPTION 'PE10_C5_V3_UNIT_NOT_FOUND'; END IF;
 SELECT w.acceptance_criteria INTO v_old_criteria
 FROM programacion.engineering_work_items w WHERE w.id=v_work FOR UPDATE;
 SELECT c.status INTO v_state FROM programacion.engineering_work_checkpoints c
 WHERE c.work_item_id=v_work AND c.checkpoint_code='PE10_C5' FOR UPDATE;
 IF v_state<>'PENDING' OR v_old_criteria IS NULL
 OR v_old#>>'{pe10_c5_scope_qualification_contract_v2,schema}'
 IS DISTINCT FROM 'PE10_C5_SCOPE_BOUND_ADMISSION_CONTRACT_V2'
 OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c
     WHERE c.work_item_id=v_work AND c.checkpoint_code IN ('PE10_C3','PE10_C4') AND c.status='DONE')<>2
 OR (SELECT count(*) FROM public.lf_operation_registry
     WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND version='v0.1'
       AND status='PRODUCCION_CONTROLADA')<>1
 THEN RAISE EXCEPTION 'PE10_C5_V3_PREIMAGE_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_eventos e WHERE e.entidad_codigo=v_event_code)
 OR EXISTS(SELECT 1 FROM public.lf_eventos e
     WHERE e.evento_tipo='PROFILE_EVOLUTION_CUTOVER_ADMITTED'
       AND e.entidad_codigo='ACTUALIZACION_PERFIL_LF')
 THEN RAISE EXCEPTION 'PE10_C5_V3_ADMISSION_OR_REPLAY_CONFLICT'; END IF;
 IF (SELECT count(*) FROM private.lf_event_type_contracts_v2 e
 WHERE e.event_type='ARTIFACT_RECONCILED' AND e.active
 AND e.contract_mode='OPERATIONAL')<>1
 THEN RAISE EXCEPTION 'PE10_C5_V3_AUDIT_EVENT_NOT_GOVERNED'; END IF;
 v_contract:=v_old#>'{checkpoint_contracts,PE10_C5}';
 v_spec:=v_old#>'{action_specs_v1,PE10_C5}';
 v_source:=v_old#>'{source_pack_v2,checkpoint_inputs,PE10_C5}';
 IF v_contract IS NULL OR v_spec IS NULL OR v_source IS NULL OR
 v_spec->>'action_kind' IS DISTINCT FROM 'READBACK_ONCE'
 OR v_contract->>'validator_code' IS DISTINCT FROM 'PROFILE_EVOLUTION_CUTOVER_GATE_V1'
 OR v_spec#>>'{scope_qualification_policy,mode}'
 IS DISTINCT FROM 'TWO_DISJOINT_SCOPES_NO_AUTO_ACTIVATION'
 THEN RAISE EXCEPTION 'PE10_C5_V3_EXPECTED_V2_SPLIT_NOT_PRESENT'; END IF;

 v_query:=$single_query$
WITH frozen AS (
  SELECT subject_sha256 FROM private.lf_evidence_ledger_v1
  WHERE receipt_id='37db027e-ad58-4cbb-b4dc-01b7568f6ac2'::uuid
  AND subject_type='PROFILE_EVOLUTION_CUTOVER'
  AND subject_ref='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
  AND verification_state='VERIFIED'
), benchmarks AS (
 SELECT c.assertion_receipt_sha256 c2_sha,b.assertion_receipt_sha256 c2b_sha
 FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id AND c.checkpoint_code='PE10_C2'
 JOIN programacion.engineering_work_checkpoints b ON b.work_item_id=u.work_item_id AND b.checkpoint_code='PE10_C2B'
 WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND u.unit_code='PE10'
 AND c.status='DONE' AND b.status='DONE'
 AND c.assertion_receipt->>'result'='PASS' AND b.assertion_receipt->>'result'='PASS'
 AND c.assertion_receipt#>>'{observed,benchmark_scope}'='DECISION_POLICY_AND_COMPOSITION'
 AND b.assertion_receipt#>>'{observed,benchmark_scope}'='FULL_PROFILE_EVOLUTION_BEHAVIOR'
 AND (c.assertion_receipt#>>'{observed,case_count}')::int>=24
 AND (b.assertion_receipt#>>'{observed,case_count}')::int>=21
 AND (c.assertion_receipt#>>'{observed,critical_regressions}')::int=0
 AND (b.assertion_receipt#>>'{observed,critical_regressions}')::int=0
), current_methods AS (
 SELECT v.manifest->'qualified_method_portfolio' portfolio,
        v.manifest#>>'{usage,allow_runtime_execution}' permission
 FROM public.lf_capability_current cur
 JOIN public.lf_capability_version_registry v
 ON v.capability_code=cur.capability_code AND v.version=cur.version
 WHERE cur.capability_code='METHOD_PACK_REGISTRY' AND v.release_state='RELEASED'
), qualified_methods AS (
 SELECT count(*)::int n
 FROM current_methods m CROSS JOIN LATERAL jsonb_array_elements(
 CASE WHEN jsonb_typeof(m.portfolio)='array' THEN m.portfolio ELSE '[]'::jsonb END
 ) item
 WHERE item->>'qualification_state'='QUALIFIED'
 AND EXISTS (SELECT 1 FROM private.lf_evidence_ledger_v1 l
 JOIN private.lf_evidence_resolver_registry_v1 r ON r.resolver_id=l.resolver_id
 WHERE l.subject_type='METHOD_QUALIFICATION'
 AND l.subject_ref=item->>'method_id'||'@'||(item->>'exact_version')
 AND l.provider_ref=item->>'benchmark_receipt_ref'
 AND l.verification_state='VERIFIED' AND r.active
 AND r.trust_level='TRUSTED_PROVIDER_BOUND')
), admitted AS (
 SELECT ev.id FROM public.lf_eventos ev
 CROSS JOIN frozen s CROSS JOIN benchmarks b
 JOIN public.lf_policy_versions p ON
  p.policy_code='POL-PROFILE-UPDATE-PASS'
  AND p.policy_version='v1.4-evolved-routing-candidate' AND p.status='CANDIDATE'
 WHERE ev.evento_tipo='PROFILE_EVOLUTION_CUTOVER_ADMITTED'
 AND ev.entidad_tipo='OPERACION' AND ev.entidad_codigo='ACTUALIZACION_PERFIL_LF'
 AND ev.payload->>'status'='ADMIT_CUTOVER'
 AND ev.payload->>'target'='SINGLE_DYNAMIC_PROFILE_UPDATER_V02'
 AND ev.payload->>'frozen_subject_sha256'=s.subject_sha256
 AND ev.payload->>'benchmark_c2_sha256'=b.c2_sha
 AND ev.payload->>'benchmark_c2b_sha256'=b.c2b_sha
 AND ev.payload->>'candidate_policy_sha256'=p.policy_sha
 AND (SELECT n FROM qualified_methods)=8
 AND EXISTS (SELECT 1 FROM private.lf_evidence_ledger_v1 safe
 WHERE safe.receipt_id::text=ev.payload->>'safe_change_admission_ref'
 AND safe.capability_code='SAFE_CHANGE_ADMISSION'
 AND safe.subject_ref='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
 AND safe.subject_sha256=s.subject_sha256
 AND safe.verification_state='VERIFIED'
 AND safe.receipt_payload->>'execution_permission'='DOWNSTREAM_EXECUTION_ELIGIBLE')
 AND nullif(ev.payload->>'operational_selection_evidence_ref','') IS NOT NULL
 AND ev.payload->>'method_execution_verified'='true'
)
SELECT CASE WHEN EXISTS(SELECT 1 FROM admitted) THEN 1 ELSE 0 END admissible_events,
       (SELECT count(*)::int FROM benchmarks) benchmark_pairs,
       (SELECT n FROM qualified_methods) qualified_methods
$single_query$;
 EXECUTE v_query INTO v_admissions,v_pairs,v_methods;
 IF v_admissions<>0 OR v_pairs<>1 OR v_methods<>0
 THEN RAISE EXCEPTION 'PE10_C5_V3_BASELINE_NOT_FAIL_CLOSED:%,%,%',
    v_admissions,v_pairs,v_methods; END IF;

 v_contract:=v_contract || jsonb_build_object(
 'pass_when','ONE dynamic Updater v0.2 admission: source-bound prior measured uplift, qualified method execution for all candidate methods, verified safe-change admission, and exact operational selection evidence; no separate LIMITED or FULL_EXPERT versions',
 'failure_code','SINGLE_DYNAMIC_V02_ADMISSION_NOT_VERIFIED',
 'resolver_policy','REUSE_EXISTING_C2_C2B_C6_EVIDENCE_NO_NEW_SELECTOR_CAMPAIGN',
 'validation_input',jsonb_build_object('source','VERIFIED_SINGLE_DYNAMIC_ADMISSION','queries',jsonb_build_array(v_query)));
 v_spec:=v_spec || jsonb_build_object(
 'verification_queries',jsonb_build_array(v_query),
 'scope_qualification_policy',jsonb_build_object('mode','SINGLE_DYNAMIC_UPDATER_V02',
   'method_selection','PER_REQUEST_EVIDENCE_AND_BUDGET',
   'method_execution','ONLY_WITH_VERIFIED_QUALIFICATION_AND_EXECUTION_RECEIPTS',
   'production_activation','SEPARATE_AFTER_C6_C7_READBACK'),
 'validator_contract',(v_spec->'validator_contract') || jsonb_build_object(
 'pass_when','ONE exact qualified v0.2 dynamic admission with real method receipts and verified safe-change source',
 'failure_code','SINGLE_DYNAMIC_V02_ADMISSION_NOT_VERIFIED',
 'validation_input',jsonb_build_object('mode','SINGLE_DYNAMIC_OPERATIONAL_READBACK')),
 'forbidden',(v_spec->'forbidden') || jsonb_build_array(
 'TREAT_SELECTION_FIXTURES_AS_METHOD_EXECUTION',
 'BYPASS_METHOD_QUALIFICATION',
 'ASSUME_C3_INDEPENDENT_ASSURANCE_PASS'));
 v_source:=jsonb_set(v_source,'{inputs,queries}',jsonb_build_array(v_query),false);
 v_new:=jsonb_set(v_old,'{checkpoint_contracts,PE10_C5}',v_contract,false);
 v_new:=jsonb_set(v_new,'{action_specs_v1,PE10_C5}',v_spec,false);
 v_new:=jsonb_set(v_new,'{source_pack_v2,checkpoint_inputs,PE10_C5}',v_source,false);
 v_new:=jsonb_set(v_new,'{pe10_c5_single_dynamic_updater_v3}',
 jsonb_build_object('schema','PE10_C5_SINGLE_DYNAMIC_UPDATER_V3',
 'target_operation_version','v0.2','one_updater',true,'method_selection_per_request',true,
 'supersedes_approval_split','PE10_C5_SCOPE_BOUND_ADMISSION_CONTRACT_V2',
 'c3_nonadmission_preserved',true,'c6_c7_contracts_unchanged',true,
 'no_production_activation',true),true);
 IF v_new#>'{action_specs_v1,PE10_C6}' IS DISTINCT FROM v_old#>'{action_specs_v1,PE10_C6}'
 OR v_new#>'{action_specs_v1,PE10_C7}' IS DISTINCT FROM v_old#>'{action_specs_v1,PE10_C7}'
 OR v_new#>'{checkpoint_contracts,PE10_C6}' IS DISTINCT FROM v_old#>'{checkpoint_contracts,PE10_C6}'
 OR v_new#>'{checkpoint_contracts,PE10_C7}' IS DISTINCT FROM v_old#>'{checkpoint_contracts,PE10_C7}'
 THEN RAISE EXCEPTION 'PE10_C5_V3_CROSS_CHECKPOINT_DRIFT'; END IF;
 SELECT jsonb_agg(CASE WHEN value LIKE 'PE10_C5:%'
 THEN to_jsonb('PE10_C5: single dynamic v0.2 selected per request; qualified-method operational evidence and exact safe-change admission required, with no limited/expert variants'::text)
 ELSE to_jsonb(value) END ORDER BY ordinality)
 INTO v_new_criteria FROM jsonb_array_elements_text(v_old_criteria)
 WITH ORDINALITY a(value,ordinality);
 IF v_new_criteria IS NULL OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements_text(v_new_criteria) a
 WHERE a.value LIKE 'PE10_C5:%') THEN
 RAISE EXCEPTION 'PE10_C5_V3_CRITERIA_NOT_RECONCILED'; END IF;
 v_event_payload:=jsonb_build_object(
 'evidence_schema_version','operational-event/v2','execution_id',v_actor,
 'producer','PE10_C5_CONTRACT_REPAIR','occurred_at',clock_timestamp(),
 'purpose','Replace two approval scopes with one dynamic v0.2 without claiming execution success',
 'plan_code',v_plan,'checkpoint_code','PE10_C5',
 'single_dynamic_version','v0.2',
 'qualified_method_count',v_methods,'measured_benchmark_pairs',v_pairs,
 'admissible_events',v_admissions,
 'acceptance_declared',false,'cutover_admitted',false,'production_activation',false);
 IF private.fn_lf_event_acceptance_signal_v2('ARTIFACT_RECONCILED',
 v_event_code,'Single v0.2 dynamic admission contract; no cutover',v_event_payload) IS NOT NULL
 THEN RAISE EXCEPTION 'PE10_C5_V3_FALSE_ADMISSION_SIGNAL'; END IF;

 -- First execute exactly the source update + event in a rollback subtransaction.
 BEGIN
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_new
 WHERE work_item_id=v_work AND unit_metadata=v_old;
 IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C5_V3_DRY_METADATA_CAS'; END IF;
 UPDATE programacion.engineering_work_items SET acceptance_criteria=v_new_criteria
 WHERE id=v_work AND acceptance_criteria=v_old_criteria;
 IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C5_V3_DRY_CRITERIA_CAS'; END IF;
 INSERT INTO public.lf_eventos(evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,created_by_execution_id,payload)
 VALUES ('ARTIFACT_RECONCILED','PROGRAM_PLAN',v_event_code,
 'Single v0.2 dynamic admission contract; no cutover','INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_event_payload)
 RETURNING id INTO v_event_id;
 IF (SELECT unit_metadata#>>'{pe10_c5_single_dynamic_updater_v3,schema}'
 FROM programacion.engineering_plan_units WHERE work_item_id=v_work)
 IS DISTINCT FROM 'PE10_C5_SINGLE_DYNAMIC_UPDATER_V3'
 THEN RAISE EXCEPTION 'PE10_C5_V3_DRY_READBACK_FAIL'; END IF;
 RAISE EXCEPTION 'PE10_C5_V3_EXPECTED_ROLLBACK';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
 IF SQLERRM<>'PE10_C5_V3_EXPECTED_ROLLBACK' THEN RAISE; END IF;
 END;
 IF (SELECT unit_metadata FROM programacion.engineering_plan_units
 WHERE work_item_id=v_work) IS DISTINCT FROM v_old
 OR EXISTS(SELECT 1 FROM public.lf_eventos WHERE entidad_codigo=v_event_code)
 THEN RAISE EXCEPTION 'PE10_C5_V3_ROLLBACK_RESIDUE'; END IF;

 -- Durable exact replay after proof.
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_new
 WHERE work_item_id=v_work AND unit_metadata=v_old;
 IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C5_V3_FINAL_METADATA_CAS'; END IF;
 UPDATE programacion.engineering_work_items SET acceptance_criteria=v_new_criteria
 WHERE id=v_work AND acceptance_criteria=v_old_criteria;
 IF NOT FOUND THEN RAISE EXCEPTION 'PE10_C5_V3_FINAL_CRITERIA_CAS'; END IF;
 INSERT INTO public.lf_eventos(evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,created_by_execution_id,payload)
 VALUES ('ARTIFACT_RECONCILED','PROGRAM_PLAN',v_event_code,
 'Single v0.2 dynamic admission contract; no cutover','INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_event_payload)
 RETURNING id INTO v_event_id;
 EXECUTE v_query INTO v_admissions,v_pairs,v_methods;
 IF v_admissions<>0 OR v_pairs<>1 OR v_methods<>0
 OR (SELECT count(*) FROM public.lf_eventos WHERE id=v_event_id AND
 payload->>'cutover_admitted'='false')<>1
 OR (SELECT status FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=v_work AND checkpoint_code='PE10_C5')<>'PENDING'
 OR (SELECT count(*) FROM public.lf_operation_registry WHERE
 operation_code='ACTUALIZACION_PERFIL_LF' AND version='v0.1')<>1
 THEN RAISE EXCEPTION 'PE10_C5_V3_DURABLE_READBACK_FAILED'; END IF;
END $pe10$;
COMMIT;