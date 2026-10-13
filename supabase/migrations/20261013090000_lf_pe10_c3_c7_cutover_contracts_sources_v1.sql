-- PE10 C3-C7: one scoped macrolot reconciling checkpoint contract, exact input, governance.
-- No cutover, v0.2 activation, state mutation of legacy executions or invented assurance.
BEGIN;
DO $pe$
DECLARE
 v_meta jsonb;
 v_work bigint;
 v_cp text;
 v_q text;
 v_spec jsonb;
 v_contract jsonb;
 v_pack jsonb;
 v_packet jsonb;
 v_result jsonb;
 v_contract_note text;
 v_validator text;
 v_codes constant text[] := ARRAY['PE10_C4','PE10_C5','PE10_C6','PE10_C7'];
 v_q4 constant text := $q4$select count(*) filter(where status='IN_PROGRESS' and manifest->>'contract_code'='CONTRACT-ACTUALIZACION-PERFIL-LF-v0.1')::int as open_explicit_v01, count(*) filter(where status='IN_PROGRESS' and nullif(manifest->>'contract_code','') is null)::int as open_unclassified, count(*) filter(where status='IN_PROGRESS')::int as open_total from public.lf_operation_execution where operation_code='ACTUALIZACION_PERFIL_LF'$q4$;
 v_q5 constant text := $q5$select count(*)::int as admissible_events from public.lf_eventos where evento_tipo='PROFILE_EVOLUTION_CUTOVER_ADMITTED' and entidad_tipo='OPERACION' and entidad_codigo='ACTUALIZACION_PERFIL_LF' and payload->>'status'='ADMIT_CUTOVER' and nullif(payload->>'benchmark_ref','') is not null and nullif(payload->>'safe_change_admission_ref','') is not null and nullif(payload->>'independent_assurance_ref','') is not null and payload->>'independent_assurance'='PASS'$q5$;
 v_q6 constant text := $q6$select (select status from programacion.engineering_work_checkpoints c join programacion.engineering_plan_units u on u.work_item_id=c.work_item_id where u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' and u.unit_code='PE10' and c.checkpoint_code='PE10_C3') as assurance_status,(select count(*)::int from public.lf_eventos where evento_tipo='PROFILE_EVOLUTION_CUTOVER_ADMITTED' and entidad_codigo='ACTUALIZACION_PERFIL_LF' and payload->>'status'='ADMIT_CUTOVER') as admitted_event_count,(select count(*)::int from public.lf_operation_execution where operation_code='ACTUALIZACION_PERFIL_LF' and status='IN_PROGRESS') as open_execution_count,(select count(*)::int from public.lf_operation_registry where operation_code='ACTUALIZACION_PERFIL_LF' and version='v0.2') as staged_registry_count$q6$;
 v_q7 constant text := $q7$select (select count(*)::int from public.lf_operation_registry where operation_code='ACTUALIZACION_PERFIL_LF' and version='v0.2') registry_v02,(select count(*)::int from public.lf_operation_contracts where operation_code='ACTUALIZACION_PERFIL_LF' and contract_code='CONTRACT-ACTUALIZACION-PERFIL-LF-v0.2') contract_v02,(select count(*)::int from public.lf_policy_versions where policy_code='POL-PROFILE-UPDATE-PASS' and status='CANDIDATE' and policy_payload#>>'{cutover,target_operation_version}'='v0.2') matching_policy_v02,(select count(*)::int from public.lf_policy_versions where policy_code='POL-PROFILE-UPDATE-PASS' and status='ACTIVE') active_policy_count$q7$;
BEGIN
 SELECT work_item_id,unit_metadata INTO STRICT v_work,v_meta
 FROM programacion.engineering_plan_units
 WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
   AND unit_code='PE10' FOR UPDATE;

 IF v_meta#>>'{action_specs_v1,PE10_C3,canonical_receipt_kind}' IS DISTINCT FROM 'INDEPENDENT_REVIEW_RECEIPT'
   OR v_meta#>>'{action_specs_v1,PE10_C3,admission_receipt_rule}' IS DISTINCT FROM 'ONLY_EXACT_CURRENT_INDEPENDENT_AUDIT_VERDICT_MAY_SATISFY_ASSERTION'
   OR v_meta#>>'{source_pack_v2,checkpoint_inputs,PE10_C3,review_request,review_next_step}' IS DISTINCT FROM 'semantic_review'
   OR coalesce(v_meta#>>'{phase_separation_v1,independent_cutover_assurance,owner}','') <> 'SUPER_ADMIN'
   OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND checkpoint_code='PE10_C3' AND status='IN_PROGRESS')<>1
   OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work AND checkpoint_code=ANY(v_codes) AND status='PENDING')<>4
 THEN RAISE EXCEPTION 'PE10_C3_C7_PRESTATE_DRIFT'; END IF;

 -- Last obsolete literal in C3; do not change proof or close the checkpoint.
 v_meta:=jsonb_set(v_meta,'{action_specs_v1,PE10_C3,admission_receipt_rule}',
      to_jsonb('ONLY_EXACT_CURRENT_INDEPENDENT_REVIEW_RECEIPT_MAY_SATISFY_ASSERTION'::text),false);
 v_meta:=jsonb_set(v_meta,'{checkpoint_contracts,PE10_C3}',
      (v_meta#>'{checkpoint_contracts,PE10_C3}') ||
       jsonb_build_object('pass_when','Exact completed canonical six-step INDEPENDENT_REVIEW_RECEIPT and REVIEW_DECISION VERIFIED, real independent semantic PASS, dependency/data/author independence',
          'failure_code','PE10_C3_CANONICAL_INDEPENDENT_REVIEW_RECEIPT_MISSING',
          'validation_input',jsonb_build_object('canonical_receipt_kind','INDEPENDENT_REVIEW_RECEIPT',
             'subject_ref','PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10')),false);

 FOREACH v_cp IN ARRAY v_codes LOOP
   IF v_meta#>ARRAY['source_pack_v2','checkpoint_inputs',v_cp] IS NOT NULL
     OR v_meta#>>ARRAY['action_specs_v1',v_cp,'action_kind'] IS DISTINCT FROM 'READBACK_ONCE'
     OR v_meta#>>ARRAY['action_specs_v1',v_cp,'status'] IS DISTINCT FROM 'READY'
   THEN RAISE EXCEPTION 'PE10_CUTOVER_INPUT_PRESTATE_DRIFT:%',v_cp; END IF;

   v_q:=case v_cp when 'PE10_C4' then v_q4 when 'PE10_C5' then v_q5
     when 'PE10_C6' then v_q6 else v_q7 end;
   v_validator:=case when v_cp='PE10_C7' then 'SUPABASE_CATALOG_ASSERT_V1'
     else 'PROFILE_EVOLUTION_CUTOVER_GATE_V1' end;
   v_contract_note:=case v_cp
     when 'PE10_C4' then 'Only zero open v0.1 AND zero unclassified updater executions; classify and govern lifecycle separately; do not bulk close'
     when 'PE10_C5' then 'Only source-backed PROFILE_EVOLUTION_CUTOVER_ADMITTED event with verified benchmark, safe-change and independent assurance refs'
     when 'PE10_C6' then 'Real bounded transactional test: exact candidate SQL, BEGIN, positive gate, negative gate, ROLLBACK, no mutation and machine-verifiable receipt'
     else 'Exact v0.2 registry AND contract AND matching candidate policy authority, with no automatic activation' end;

   v_spec:=v_meta#>ARRAY['action_specs_v1',v_cp];
   v_contract:=v_meta#>ARRAY['checkpoint_contracts',v_cp];
   v_spec:=v_spec||jsonb_build_object(
     'status','READY','verification_queries',jsonb_build_array(v_q),
     'validator_contract',(v_spec->'validator_contract')||
       jsonb_build_object('pass_when',v_contract_note,
         'resolver_policy','RECONCILE_EXACT_CANONICAL_READBACK_NO_SYNTHETIC_PASS'),
     'pre_activation_scope','PE10_CUTOVER_QUALIFICATION_ONLY',
     'required_gates',case v_cp when 'PE10_C4' then jsonb_build_array('PE10_C3')
        when 'PE10_C5' then jsonb_build_array('PE10_C3','PE10_C4')
        when 'PE10_C6' then jsonb_build_array('PE10_C3','PE10_C4','PE10_C5')
        else jsonb_build_array('PE10_C3','PE10_C4','PE10_C5','PE10_C6') end,
     'forbidden',jsonb_build_array('AUTO_ACTIVATE_V02','AUTO_CLOSE_LEGACY_EXECUTIONS',
        'TREAT_FIRST_EVOLUTION_AS_CUTOVER_PASS','REUSE_UNSCOPED_RECEIPTS'));
   v_contract:=v_contract||jsonb_build_object('pass_when',v_contract_note,
       'validation_input',jsonb_build_object('source','EXACT_DECLARED_READBACK',
          'queries',jsonb_build_array(v_q)));

   v_pack:=jsonb_build_object(
      'checkpoint_code',v_cp,
      'execution_kind',case when v_cp='PE10_C6' then 'BOUNDED_CHECKPOINT_TEST' else 'READBACK_ONCE' end,
      'validator_code',v_validator,
      'expected_result','FAIL_CLOSED_UNTIL_GATES_WITH_FRESH_EVIDENCE',
      'inputs',jsonb_build_object('queries',jsonb_build_array(v_q),
        'db_objects',case v_cp
           when 'PE10_C4' then jsonb_build_array('public.lf_operation_execution')
           when 'PE10_C5' then jsonb_build_array('public.lf_eventos')
           when 'PE10_C6' then jsonb_build_array('public.lf_eventos','programacion.engineering_work_checkpoints','public.lf_operation_execution','public.lf_operation_registry')
           else jsonb_build_array('public.lf_operation_registry','public.lf_operation_contracts','public.lf_policy_versions') end,
        'events','[]'::jsonb,'artifacts','[]'::jsonb,'assets','[]'::jsonb));

   IF v_cp='PE10_C6' THEN
      v_spec:=v_spec || jsonb_build_object(
        'action_kind','RUN_TEST','contract_family','BOUNDED_CHECKPOINT_TEST',
        'requires_material_execution',true,
        'test_execution_contract',jsonb_build_object(
          'test_code','PE10_C6_TRANSACTIONAL_DRY_RUN_V1',
          'test_path','cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/pe10_c6_transactional_dry_run_v1.py',
          'canonical_exit_criterion',v_contract_note,
          'declared_queries',jsonb_build_array(v_q),
          'declared_objects',v_pack#>'{inputs,db_objects}',
          'negative_required',true,
          'transaction_mode','BEGIN_TEST_AND_ROLLBACK',
          'positive_gate_must_pass',true,
          'negative_gate_must_reject',true,
          'existing_production_migration_not_directly_applied',true),
        'assertion_contract',jsonb_build_object(
          'mode','EXPLICIT_PASS_WHEN_SUBSET',
          'pass_when',jsonb_build_object('status','PASS',
            'transaction_rolled_back',true,'positive_gate_tested',true,
            'negative_gate_tested',true,'runtime_activated',false)));
      v_pack:=v_pack||jsonb_build_object('material_test_result','NOT_EXECUTED',
        'runner_authoring_requires_qualified_candidate',true);
   ELSE
      v_spec:=v_spec||jsonb_build_object('action_kind','READBACK_ONCE',
          'recipe_mode','READBACK_EXACT','requires_material_execution',false,
          'assertion_contract',jsonb_build_object('mode','EXPLICIT_PASS_WHEN_SUBSET',
            'pass_when',case v_cp
            when 'PE10_C4' then jsonb_build_object('open_explicit_v01',0,'open_unclassified',0,'open_total',0)
            when 'PE10_C5' then jsonb_build_object('admissible_events',1)
            else jsonb_build_object('registry_v02',1,'contract_v02',1,'matching_policy_v02',1,'active_policy_count',1) end));
   END IF;
   -- Check exact source+spec compilation using the same in-memory payload, not a stale bootstrap.
   v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
     'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1','PE10',v_cp,v_spec,v_pack);
   IF v_packet->>'status' IS DISTINCT FROM 'READY'
      THEN RAISE EXCEPTION 'PE10_CUTOVER_PACKET_NOT_READY:%:%',v_cp,v_packet->'block_reasons'; END IF;

   v_meta:=jsonb_set(v_meta,ARRAY['action_specs_v1',v_cp],v_spec,false);
   v_meta:=jsonb_set(v_meta,ARRAY['checkpoint_contracts',v_cp],v_contract,false);
   v_meta:=jsonb_set(v_meta,ARRAY['source_pack_v2','checkpoint_inputs',v_cp],v_pack,true);
 END LOOP;

 v_meta:=jsonb_set(v_meta,'{phase_separation_v1,cutover_checkpoints_v1}',
   jsonb_build_object(
     'authority','SUPER_ADMIN',
     'c3','AWAITING_REAL_SEMANTIC_INDEPENDENT_REVIEW',
     'c4','25_OPEN_OBSERVED_19_V01_6_UNCLASSIFIED_REQUIRE_FRESH_READBACK',
     'c5','ADMISSION_EVENT_NOT_PUBLISHED',
     'c6','BOUNDED_TRANSACTIONAL_TEST_NOT_EXECUTED',
     'c7','V02_AUTHORITY_NOT_PUBLISHED',
     'cutover_activated',false,
     'automatic_execution_lifecycle_updates_allowed',false,
     'phase_one_accepted_not_equivalent_to_v02_admission',true),true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=v_meta
 WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND unit_code='PE10';
 IF NOT FOUND THEN RAISE EXCEPTION 'PE10_MACROLOT_METADATA_WRITE_MISSING'; END IF;

 UPDATE programacion.engineering_work_items w
  SET acceptance_criteria=(SELECT jsonb_agg(
    CASE WHEN x.value LIKE 'PE10_C4:%'
      THEN to_jsonb('PE10_C4: 0 open v0.1 AND 0 unclassified updater executions; preserve lifecycle history and close only with per-execution evidence'::text)
    WHEN x.value LIKE 'PE10_C5:%'
      THEN to_jsonb('PE10_C5: admit only exact governed cutover event with benchmark, safe-change and independent review receipts, not first-evolution qualitative PASS'::text)
    WHEN x.value LIKE 'PE10_C6:%'
      THEN to_jsonb('PE10_C6: qualified material transactional dry-run on exact candidate, positive and negative controls, BEGIN/ROLLBACK, no runtime effect, receipt'::text)
    WHEN x.value LIKE 'PE10_C7:%'
      THEN to_jsonb('PE10_C7: exact v0.2 registry+contract+matching candidate policy authority; separate activation gate, no automatic promotion'::text)
    ELSE to_jsonb(x.value) END ORDER BY x.ordinality)
    FROM jsonb_array_elements_text(w.acceptance_criteria) WITH ORDINALITY x(value,ordinality))
 WHERE w.id=v_work;
 IF NOT FOUND THEN RAISE EXCEPTION 'PE10_MACROLOT_WORK_CRITERIA_MISSING'; END IF;

 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=v_work AND checkpoint_code=ANY(v_codes) AND status='PENDING')<>4
 THEN RAISE EXCEPTION 'PE10_MACROLOT_UNAUTHORIZED_CHECKPOINT_STATE_CHANGE'; END IF;
END $pe$;

INSERT INTO public.lf_error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
SELECT x.codigo,'PROFILE_EVOLUTION',x.titulo,x.descripcion,x.causa_raiz,
 'Missing checkpoint source+action+governance parity',
 x.prevencion,v.validacion,'HIGH',1,clock_timestamp(),clock_timestamp(),
 'PE10_C3_C7_MACROLOT','ACTIVO','supabase://programacion.engineering_plan_units/PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10'
FROM (VALUES
 ('LF-PE10-C4-LEGACY-UNCLASSIFIED-20261013-001',
 'Cutover v0.1 open-execution gate had missing source and 6 unclassified executions',
 '25 updater executions IN_PROGRESS: 19 explicit v0.1, 6 missing contract version',
 'Gate named only v0.1 despite SQL candidate blocking all operation IN_PROGRESS; 6 unclassified cases lack classification',
 'Read both exact v0.1 and unclassified; require zero without mass lifecycle mutation; classify every unclassified operation and use canonical transition'),
 ('LF-PE10-C5-C7-CUTOVER-SOURCE-GAP-20261013-001',
 'Three cutover checkpoints had missing source inputs and incomplete authority scope',
 'C5 no admissible event; C6 READBACK_ONCE despite transactional dry-run; C7 catalog validator checked only registry and no matching contract/policy',
 'Checkpoint contracts described obligations but did not bind executable source or real material test or full authority',
 'Reconcile checkpoint contract+action+source_pack+governance; qualify a bounded material test with rollback; require registry, contract and matching candidate policy'),
 ('LF-PE10-C3-ADMISSION-LITERAL-DRIFT-20261013-001',
 'PE10_C3 leftover admission_receipt_rule still expected legacy AUDIT_VERDICT',
 'Active review-v3 emits INDEPENDENT_REVIEW_RECEIPT but old literal survived after consumer migration',
 'Partial contract edits left an obsolete single-field requirement',
 'Update all consumer acceptance fields together and verify same typed canonical receipt; do not infer semantic PASS')) 
  AS x(codigo,titulo,descripcion,causa_raiz,prevencion)
CROSS JOIN LATERAL (SELECT CASE WHEN x.codigo='LF-PE10-C4-LEGACY-UNCLASSIFIED-20261013-001'
  THEN 'C4 blocks with 19 v0.1 + 6 unclassified; readbacks must remain fail-closed'
 WHEN x.codigo='LF-PE10-C5-C7-CUTOVER-SOURCE-GAP-20261013-001'
  THEN 'C5 0 events, C6 exact RUN_TEST transport planned without execution, C7 no v0.2 authority'
 ELSE 'C3 only current INDEPENDENT_REVIEW_RECEIPT is admitted; review pending' END AS validacion) v
WHERE NOT EXISTS(select 1 from public.lf_error_knowledge e where e.codigo=x.codigo);
COMMIT;
