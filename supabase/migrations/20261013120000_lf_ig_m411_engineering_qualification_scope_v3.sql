-- IG M4.11 / PAULO-143: reconcile construction qualification with R11 novation.
-- LF Migration Merge Train ONLY. No direct database writes, runtime changes,
-- oracle promotion, production activation, capability-current modifications,
-- checkpoint lifecycle mutations, or unrelated units.
-- EKB: AUD-045; IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001;
-- IG-M412-ORACLE-VERSION-PIN-AND-INDEPENDENCE-DRIFT-001;
-- IG-M412-SEMANTIC-SCOPE-IMPLICIT-EMPTY-001;
-- INDEPENDENCE-CONTRACT-APPLICABILITY-001.
DO $m411_v3$
DECLARE
 v_u record; v_nov jsonb; v_assert jsonb; v_meta jsonb; v_src jsonb;
 v_specs jsonb; v_cp3 jsonb; v_cp4 jsonb; v_cp5 jsonb; v_cp6 jsonb;
 v_input jsonb; v_code text; v_read3 text; v_read5 text; v_read6 text;
 v_n int; v_n2 int; v_n3 int; v_fn text; v_boot jsonb;
 v_out3 jsonb; v_out4 jsonb; v_out5 jsonb; v_out6 jsonb;
BEGIN
 SELECT u.id,u.work_item_id,u.unit_metadata,w.status
 INTO STRICT v_u FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
 AND u.unit_code='M4.11' AND u.disposition='ASSIGNED' FOR UPDATE OF u,w;
 IF v_u.status IS DISTINCT FROM 'IN_PROGRESS'
 OR v_u.unit_metadata#>>'{m411_admission_boundary_v1,version}' IS DISTINCT FROM '2.0.0'
 OR v_u.unit_metadata#>>'{action_specs_v1,DECISIONAL_BINDING_VIA_RELEASE,status}'
    IS DISTINCT FROM 'BLOCK_INDEPENDENCE_RECEIPT_REQUIRED'
 THEN RAISE EXCEPTION 'M411_SCOPE_V3_PRESTATE_CHANGED'; END IF;
 IF NOT EXISTS (
 SELECT 1 FROM programacion.engineering_work_checkpoints c
 WHERE c.work_item_id=v_u.work_item_id AND c.checkpoint_code='PREREQ_GATES_PASS'
 AND c.status='DONE'
 AND c.evidence_ref LIKE '%readback=IG_M411_UPSTREAM_READBACK_V1:PASS%'
 ) OR EXISTS (
 SELECT 1 FROM programacion.engineering_work_checkpoints c
 WHERE c.work_item_id=v_u.work_item_id AND c.sequence_no>=3
 AND (c.status<>'PENDING' OR c.evidence_ref IS NOT NULL)
 ) THEN RAISE EXCEPTION 'M411_SCOPE_V3_CP_LIFECYCLE_CHANGED'; END IF;
 SELECT count(*) INTO v_n FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
 AND u.unit_code IN ('M9.2','M4.12') AND w.status='DONE';
 IF v_n<>2 THEN RAISE EXCEPTION 'M411_SCOPE_V3_UPSTREAM_NOT_DONE'; END IF;
 SELECT count(*) INTO v_n FROM programacion.engineering_work_checkpoints c
 JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
 AND u.unit_code='M9.2' AND c.status='DONE';
 IF v_n<>6 THEN RAISE EXCEPTION 'M411_SCOPE_V3_M92_NOT_6_OF_6'; END IF;
 SELECT payload INTO STRICT v_nov FROM public.lf_eventos
 WHERE id=20635 AND entidad_codigo='IG_CV_REFACTOR_V2.L0.M4.12.R11_NOVATION';
 IF v_nov->>'schema_novation' IS DISTINCT FROM 'IG_R11_NOVATION_V1'
 OR v_nov->>'original_criterion_met' IS DISTINCT FROM 'false'
 OR v_nov->>'validator_independent_of_curator' IS DISTINCT FROM 'false'
 OR v_nov->>'promotion_authorized' IS DISTINCT FROM 'false'
 OR v_nov->>'production_authorized' IS DISTINCT FROM 'false'
 OR v_nov->'new_controls' IS DISTINCT FROM
 '["FACTS_INVARIANTS","LOGIC_SEVERITY_INVARIANT","CORRELATION_DEFECT_INJECTION"]'::jsonb
 THEN RAISE EXCEPTION 'M411_SCOPE_V3_R11_NOVATION_DRIFT'; END IF;
 SELECT c.assertion_receipt INTO STRICT v_assert
 FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
 AND u.unit_code='M4.12' AND c.checkpoint_code='CORRELATION_RERUN'
 AND c.status='DONE';
 IF v_assert->>'passed' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'M411_SCOPE_V3_M412_BEHAVIORAL_NOT_PROVEN'; END IF;
 IF (SELECT count(*) FROM programacion.provenance_receipts
 WHERE id=1667 AND receipt_kind='EVIDENCE_VERIFICATION'
 AND subject_ref='plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.12/CUTOVER_READY'
 AND receipt_sha256='b4b8174360d8478c122340ca25973ba54cdcd7785d2d168ae8271840fc0c7fc5'
 AND payload->>'verification_status'='VERIFIED'
 AND payload->>'bundle_sha256'='db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f'
 AND payload#>>'{manifest,production_activation}'='false')<>1
 THEN RAISE EXCEPTION 'M411_SCOPE_V3_M912_SIGNED_BUNDLE_DRIFT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_capability_current
 WHERE capability_code='INPUT_GOVERNANCE' AND version='1.0.0')
 THEN RAISE EXCEPTION 'M411_SCOPE_V3_CURRENT_CHANGED'; END IF;
 SELECT count(*),
 count(*) FILTER (WHERE f.value->'validator_oracle_strategy'->>'activation_state'='DECLARED_FOR_M4_INDEPENDENT_ORACLE'),
 count(*) FILTER (WHERE f.value->'validator_oracle_strategy'->>'current_validator_independence_claim'='false')
 INTO v_n,v_n2,v_n3
 FROM programacion.contratos c
 CROSS JOIN LATERAL jsonb_each(c.especificacion->'families') f
 WHERE c.id=46 AND c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
 AND c.version_id=19 AND c.estado='defined';
 IF v_n<>47 OR v_n2<>47 OR v_n3<>47
 THEN RAISE EXCEPTION 'M411_SCOPE_V3_REGISTRY_47_DRIFT'; END IF;
 SELECT pg_get_functiondef(p.oid) INTO STRICT v_fn
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='programacion' AND p.proname='fn_input_validator_oracle_admission_v1';
 IF position('''comparison_only'',true' in v_fn)=0
 OR position('''semantic_pass_authorized'',false' in v_fn)=0
 OR position('''promotion_authorized'',false' in v_fn)=0
 OR position('ADMITTED_COMPARISON_ONLY' in v_fn)=0
 THEN RAISE EXCEPTION 'M411_SCOPE_V3_COMPARISON_ONLY_GUARD_CHANGED'; END IF;
 IF EXISTS(SELECT 1 FROM programacion.provenance_receipts r
 WHERE r.subject_ref='plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M4.11/DECISIONAL_BINDING_VIA_RELEASE'
 AND r.payload->>'verification_status'='VERIFIED')
 THEN RAISE EXCEPTION 'M411_SCOPE_V3_EXISTING_RELEASE_ADMISSION_REASSESS'; END IF;

 v_read3:=$q$WITH u AS (
 SELECT p.unit_code,w.status FROM programacion.engineering_plan_units p
 JOIN programacion.engineering_work_items w ON w.id=p.work_item_id
 WHERE p.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
 AND p.unit_code IN ('M9.2','M4.12')
 ), f AS (
 SELECT count(*) n,
 count(*) FILTER (WHERE x.value->'validator_oracle_strategy'->>'activation_state'='DECLARED_FOR_M4_INDEPENDENT_ORACLE') shadow,
 count(*) FILTER (WHERE x.value->'validator_oracle_strategy'->>'current_validator_independence_claim'='false') no_claim
 FROM programacion.contratos c
 CROSS JOIN LATERAL jsonb_each(c.especificacion->'families') x
 WHERE c.id=46 AND c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
 ), e AS (
 SELECT payload FROM public.lf_eventos WHERE id=20635
 ), r AS (
 SELECT id FROM programacion.provenance_receipts
 WHERE id=1667 AND receipt_sha256='b4b8174360d8478c122340ca25973ba54cdcd7785d2d168ae8271840fc0c7fc5'
 AND payload->>'verification_status'='VERIFIED'
 AND payload#>>'{manifest,production_activation}'='false'
 )
 SELECT jsonb_build_object('contract','IG_M411_ENGINEERING_SCOPE_V3',
 'status',CASE WHEN (SELECT count(*) FROM u WHERE status='DONE')=2
 AND (SELECT n FROM f)=47 AND (SELECT shadow FROM f)=47
 AND (SELECT no_claim FROM f)=47 AND (SELECT count(*) FROM r)=1
 AND (SELECT payload->>'validator_independent_of_curator' FROM e)='false'
 AND (SELECT payload->>'promotion_authorized' FROM e)='false'
 THEN 'PASS_ENGINEERING_BOUNDARY' ELSE 'BLOCKED' END,
 'm92_m412_done',(SELECT count(*) FROM u WHERE status='DONE'),
 'shadow_strategies',(SELECT shadow FROM f),
 'm412_novation_event',20635,'m912_cutover_receipt',1667,
 'semantic_independence_proven',false,
 'decisional_oracle_authorized',false,'production_authorized',false) result$q$;
 v_read5:=$q$SELECT jsonb_build_object(
 'contract','IG_M411_SHADOW_STRATEGIES_47_V3',
 'status',CASE WHEN count(*)=47
 AND count(*) FILTER(WHERE f.value->'validator_oracle_strategy'->>'activation_state'='DECLARED_FOR_M4_INDEPENDENT_ORACLE')=47
 AND count(*) FILTER(WHERE f.value->'validator_oracle_strategy'->>'current_validator_independence_claim'='false')=47
 THEN 'PASS_DECLARATIVE_ONLY' ELSE 'BLOCKED' END,
 'families',count(*),'shadow_only',true,'semantic_independence_certified',false) result
 FROM programacion.contratos c CROSS JOIN LATERAL jsonb_each(c.especificacion->'families') f
 WHERE c.id=46 AND c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'$q$;
 v_read6:=$q$WITH c AS (
 SELECT checkpoint_code,status,evidence_ref FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=(SELECT work_item_id FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M4.11')
 ) SELECT jsonb_build_object('contract','IG_M411_TERMINAL_ENGINEERING_V3',
 'status',CASE WHEN (SELECT count(*) FROM c WHERE status='DONE')=5
 AND (SELECT count(*) FROM c WHERE status='DONE' AND nullif(btrim(evidence_ref),'') IS NOT NULL)=5
 AND (SELECT status FROM c WHERE checkpoint_code='ORACLE_ACTIVATION_READBACK')='PENDING'
 AND (SELECT version FROM public.lf_capability_current WHERE capability_code='INPUT_GOVERNANCE')='1.0.0'
 AND (SELECT payload->>'promotion_authorized' FROM public.lf_eventos WHERE id=20635)='false'
 THEN 'PASS_ENGINEERING_ONLY' ELSE 'BLOCKED' END,
 'prior_checkpoints_done',(SELECT count(*) FROM c WHERE status='DONE'),
 'decisional_oracle_authorized',false,'production_authorized',false) result$q$;

 v_meta:=v_u.unit_metadata; v_specs:=v_meta->'action_specs_v1';
 v_cp3:=v_specs->'DECISIONAL_BINDING_VIA_RELEASE';
 v_cp4:=v_specs->'NO_PASS_WITHOUT_ORACLE_NEG';
 v_cp5:=v_specs->'FAMILY_COVERAGE_47';
 v_cp6:=v_specs->'ORACLE_ACTIVATION_READBACK';
 IF v_cp4->>'action_kind' IS DISTINCT FROM 'BOUNDED_CHECKPOINT_TEST_AUTHORING'
 OR v_cp5->>'action_kind' IS DISTINCT FROM 'READBACK_ONCE'
 OR COALESCE(v_cp6->>'action_kind',
   programacion.fn_engineering_checkpoint_action_spec_v3(
     'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','ORACLE_ACTIVATION_READBACK'
   )->>'action_kind') IS DISTINCT FROM 'READBACK_ONCE'
 THEN RAISE EXCEPTION 'M411_SCOPE_V3_OTHER_CP_CONTRACT_DRIFT'; END IF;
 v_cp3:=v_cp3||jsonb_build_object(
 'status','READY','precision','M411_ENGINEERING_SCOPE_ONLY_V3',
 'contract_family','SHADOW_BEHAVIORAL_ENGINEERING_QUALIFICATION',
 'action_kind','READBACK_ONCE','recipe_mode','READBACK_EXACT',
 'mutation_policy','NO_DOMAIN_MUTATION','requires_material_execution',false,
 'checkpoint_title','Readback de M9.2/M4.12 y frontera shadow; sin activar oracle',
 'expected','M9.2 6/6 DONE, M4.12 behavioral event 20635 PASS, 47/47 shadow strategies, M9.12 exact receipt 1667. Comparison-only. No independence or promotion claimed.',
 'action_steps',jsonb_build_array('READ_M92_M412_SIGNED_BOUNDARY','ASSERT_R11_BEHAVIORAL_PASS',
 'CHECK_47_SHADOW_ONLY_AND_RECEIPT_1667','ASSERT_NO_DECISIONAL_PROMOTION',
 'PERSIST_CP3_WITH_NONEMPTY_EVIDENCE'),
 'target',jsonb_build_object('declared_assets','[]'::jsonb,
 'declared_events',jsonb_build_array(20635),
 'declared_objects',jsonb_build_array('programacion.engineering_plan_units',
 'programacion.engineering_work_items','programacion.engineering_work_checkpoints',
 'programacion.provenance_receipts','programacion.contratos','public.lf_eventos',
 'public.lf_capability_current'),'declared_artifacts','[]'::jsonb),
 'verification_queries',jsonb_build_array(v_read3),'source_pack_missing_typed','[]'::jsonb,
 'required_evidence_contract',jsonb_build_object(
 'phase','SHADOW_ENGINEERING_QUALIFICATION','evidence_ref_required',true,
 'm9_2_done',true,'m4_12_behavioural_event',20635,'m912_cutover_receipt_id',1667,
 'bundle_sha256','db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f',
 'semantic_independence_proven',false,'t_indep_required_for_cp3',false,
 'separate_decisional_release_requires_t_indep',true,
 'decisional_promotion_authorized',false,'production_activation_authorized',false),
 'forbidden',coalesce(v_cp3->'forbidden','[]'::jsonb)||
 jsonb_build_array('DONE_IMPLIES_SEMANTIC_INDEPENDENCE','DONE_AUTHORIZES_RELEASE',
 'REQUIRE_LIVE_T_INDEP_FOR_ENGINEERING_READBACK','CREATE_NEW_ORACLE')
 );
 v_cp4:=v_cp4||jsonb_build_object(
 'checkpoint_title','Negativo real: sin oracle admitido no hay PASS semantico',
 'expected','Bounded negative against existing admission guard. Unadmitted oracle never gives semantic PASS; must show real test execution and machine assertion, not a declaration.',
 'test_execution_contract',coalesce(v_cp4->'test_execution_contract','{}'::jsonb)||
 jsonb_build_object(
 'canonical_exit_criterion','Engineering qualification only: no semantic PASS without admitted oracle; no live release.',
 'checkpoint_title_context','Unadmitted independent oracle => no semantic PASS; comparison-only is not decisional.',
 'declared_objects',coalesce(v_cp4#>'{test_execution_contract,declared_objects}','[]'::jsonb)||
 jsonb_build_array('programacion.fn_input_validator_oracle_admission_v1')),
 'forbidden',coalesce(v_cp4->'forbidden','[]'::jsonb)||
 jsonb_build_array('SYNTHETIC_PASS_FROM_DECLARATION','ACTIVATE_ORACLE_FOR_TEST')
 );
 v_cp4:=jsonb_set(v_cp4,'{target,declared_objects}',
 coalesce(v_cp4#>'{target,declared_objects}','[]'::jsonb)||
 jsonb_build_array('programacion.fn_input_validator_oracle_admission_v1'),true);
 v_cp5:=v_cp5||jsonb_build_object(
 'precision','M411_DECLARATIVE_SHADOW_COVERAGE_47_V3',
 'checkpoint_title','47/47 estrategias shadow declaradas, sin claim de independencia',
 'expected','47/47 shadow strategies declared for comparison; 47/47 semantic independence claim=false. No runtime decisional claim.',
 'verification_queries',jsonb_build_array(v_read5),
 'target',jsonb_build_object('declared_assets','[]'::jsonb,'declared_events','[]'::jsonb,
 'declared_objects',jsonb_build_array('programacion.contratos'),
 'declared_artifacts','[]'::jsonb),
 'required_evidence_contract',jsonb_build_object('phase','DECLARATIVE_SHADOW_COVERAGE',
 'registry_contract_id',46,'family_count',47,'evidence_ref_required',true,
 'semantic_independence_proven',false),
 'forbidden',coalesce(v_cp5->'forbidden','[]'::jsonb)||
 jsonb_build_array('INFER_47_SEMANTIC_ORACLES_ADMITTED')
 );
 v_cp6:=v_cp6||jsonb_build_object(
 'precision','M411_ENGINEERING_TERMINAL_READBACK_V3',
 'checkpoint_title','Readback terminal de ingenieria shadow; sin activacion',
 'expected','CP1-CP5 DONE with genuine evidence; CP6 PENDING before readback; INPUT_GOVERNANCE current unchanged and no decisional promotion.',
 'verification_queries',jsonb_build_array(v_read6),
 'target',jsonb_build_object('declared_assets','[]'::jsonb,'declared_events',jsonb_build_array(20635),
 'declared_objects',jsonb_build_array('programacion.engineering_plan_units',
 'programacion.engineering_work_checkpoints','public.lf_eventos','public.lf_capability_current'),
 'declared_artifacts','[]'::jsonb),
 'required_evidence_contract',jsonb_build_object('phase','ENGINEERING_TERMINAL_READBACK',
 'prior_checkpoints_required',5,'evidence_ref_required',true,
 'decisional_promotion_authorized',false,'production_activation_authorized',false),
 'forbidden',coalesce(v_cp6->'forbidden','[]'::jsonb)||
 jsonb_build_array('REQUIRE_PRODUCTION_FOR_ENGINEERING_DONE','FAKE_LIVE_RUN')
 );
 v_specs:=v_specs||jsonb_build_object(
 'DECISIONAL_BINDING_VIA_RELEASE',v_cp3,
 'NO_PASS_WITHOUT_ORACLE_NEG',v_cp4,
 'FAMILY_COVERAGE_47',v_cp5,
 'ORACLE_ACTIVATION_READBACK',v_cp6);
 v_meta:=jsonb_set(v_meta,'{action_specs_v1}',v_specs,true);
 v_src:=v_meta->'source_pack_v1';
 FOR v_code IN SELECT unnest(array['DECISIONAL_BINDING_VIA_RELEASE',
 'FAMILY_COVERAGE_47','ORACLE_ACTIVATION_READBACK']) LOOP
  v_input:=coalesce(v_src#>array['checkpoint_inputs',v_code],'{}'::jsonb);
  v_input:=jsonb_set(v_input,'{inputs,queries}',CASE v_code
   WHEN 'DECISIONAL_BINDING_VIA_RELEASE' THEN jsonb_build_array(v_read3)
   WHEN 'FAMILY_COVERAGE_47' THEN jsonb_build_array(v_read5)
   ELSE jsonb_build_array(v_read6) END,true);
  v_input:=jsonb_set(v_input,'{inputs,assets}','[]'::jsonb,true);
  v_input:=jsonb_set(v_input,'{inputs,artifacts}','[]'::jsonb,true);
  v_input:=jsonb_set(v_input,'{inputs,events}',CASE WHEN v_code='FAMILY_COVERAGE_47'
   THEN '[]'::jsonb ELSE '[20635]'::jsonb END,true);
  v_input:=jsonb_set(v_input,'{inputs,db_objects}',CASE v_code
   WHEN 'DECISIONAL_BINDING_VIA_RELEASE' THEN v_cp3#>'{target,declared_objects}'
   WHEN 'FAMILY_COVERAGE_47' THEN v_cp5#>'{target,declared_objects}'
   ELSE v_cp6#>'{target,declared_objects}' END,true);
  v_src:=jsonb_set(v_src,array['checkpoint_inputs',v_code],v_input,true);
 END LOOP;
 v_input:=coalesce(v_src#>'{checkpoint_inputs,NO_PASS_WITHOUT_ORACLE_NEG}','{}'::jsonb);
 v_input:=jsonb_set(v_input,'{inputs,db_objects}',
 coalesce(v_input#>'{inputs,db_objects}','[]'::jsonb)||
 jsonb_build_array('programacion.fn_input_validator_oracle_admission_v1'),true);
 v_src:=jsonb_set(v_src,'{checkpoint_inputs,NO_PASS_WITHOUT_ORACLE_NEG}',v_input,true);
 v_meta:=jsonb_set(v_meta,'{source_pack_v1}',v_src,true);
 v_meta:=jsonb_set(v_meta,'{m411_admission_boundary_v1}',
 coalesce(v_meta->'m411_admission_boundary_v1','{}'::jsonb)||jsonb_build_object(
 'version','3.0.0','unit_scope','CONSTRUCTION_SANDBOX_SHADOW_QUALIFICATION',
 'cp3_scope','HISTORICAL_BEHAVIORAL_AND_MECHANISM_READBACK',
 'cp4_negative','NO_SEMANTIC_PASS_WITHOUT_ADMITTED_ORACLE',
 'cp5_scope','DECLARED_SHADOW_47_NOT_DECISIONAL',
 'cp6_scope','ENGINEERING_TERMINAL_NOT_ACTIVATION',
 'm412_r11_novation_event',20635,'semantic_independence_proven',false,
 'separate_release_requires_t_indep',true,
 'separate_release_dimensions',jsonb_build_array('DEPENDENCIES','DATA','AUTHOR'),
 'separate_release_subject_must_be_frozen',true,
 'separate_release_fail_closed_without_receipt',true,
 'super_admin_cutover_authority','CAPABILITY_CUTOVER',
 'decisional_promotion','NOT_AUTHORIZED','production_activation','NOT_AUTHORIZED'),true);
 v_meta:=jsonb_set(v_meta,'{m411_scope_contract_v3}',jsonb_build_object(
 'scope','ENGINEERING_QUALIFICATION_SHADOW_COMPARISON_ONLY',
 'not_scope',jsonb_build_array('SEMANTIC_DECISIONAL_ADMISSION','PRODUCTION_ACTIVATION'),
 'R11_novation_event',20635,'no_new_engine',true,
 'semantic_independence_claim',false,'decisional_promotion_authorized',false),true);
 UPDATE programacion.engineering_plan_units SET
 title='Calificacion shadow del Validator; release decisional separado',
 exit_criterion='ENGINEERING ONLY: CP2 signed M9.12 receipt 1667; CP3 reuse M9.2 6/6 and M4.12 R11 event 20635 behavioral PASS without semantic independence claim; CP4 real negative no semantic PASS without admitted oracle; CP5 47/47 declarative shadow strategies with independence_claim=false; CP6 CP1-CP5 genuine evidence and terminal readback. No runtime/production/decisional activation. Separate CAPABILITY_CUTOVER must require T-INDEP DEPENDENCIES/DATA/AUTHOR on exact signed candidate and governed authorization.',
 unit_metadata=v_meta WHERE id=v_u.id;
 UPDATE programacion.engineering_work_items SET
 title='M4.11 — Calificacion shadow; activacion decisional independiente',
 objective='Qualify constructed shadow comparison and preserved negative; reuse M9.2/M4.12. No semantic, decisional, or production promotion.',
 expected_result='M9.2/M4.12 historical readback; real negative; 47/47 declared shadow strategies; engineering terminal readback only.',
 acceptance_criteria=jsonb_build_array(
 'CP2 signed receipt 1667 remains VERIFIED and DONE',
 'CP3 M9.2 6/6 + M4.12 R11 event 20635 behavioral PASS, comparison-only; no T-INDEP assertion',
 'CP4 real negative plus machine assertion: no semantic PASS without admitted oracle',
 'CP5 47/47 shadow strategies declared, 47/47 current independence claim=false',
 'CP6 prior CP1-CP5 DONE with evidence_ref and INPUT_GOVERNANCE current unchanged',
 'M4.11 DONE does NOT authorize release: separate CAPABILITY_CUTOVER requires independent T-INDEP on exact subject/bundle, actual authorization and fail-closed receipt')
 WHERE id=v_u.work_item_id;
 UPDATE programacion.engineering_work_checkpoints SET title=CASE checkpoint_code
 WHEN 'DECISIONAL_BINDING_VIA_RELEASE' THEN 'CP3 — Readback M9.2/M4.12; no oracle promotion'
 WHEN 'NO_PASS_WITHOUT_ORACLE_NEG' THEN 'CP4 — Real negative: no admitted oracle, no semantic PASS'
 WHEN 'FAMILY_COVERAGE_47' THEN 'CP5 — 47/47 declared shadow strategies'
 WHEN 'ORACLE_ACTIVATION_READBACK' THEN 'CP6 — Terminal engineering readback without activation'
 ELSE title END
 WHERE work_item_id=v_u.work_item_id AND checkpoint_code IN
 ('DECISIONAL_BINDING_VIA_RELEASE','NO_PASS_WITHOUT_ORACLE_NEG',
 'FAMILY_COVERAGE_47','ORACLE_ACTIVATION_READBACK');
 v_out3:=programacion.fn_engineering_checkpoint_action_spec_v3(
 'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','DECISIONAL_BINDING_VIA_RELEASE');
 v_out4:=programacion.fn_engineering_checkpoint_action_spec_v3(
 'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','NO_PASS_WITHOUT_ORACLE_NEG');
 v_out5:=programacion.fn_engineering_checkpoint_action_spec_v3(
 'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','FAMILY_COVERAGE_47');
 v_out6:=programacion.fn_engineering_checkpoint_action_spec_v3(
 'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','ORACLE_ACTIVATION_READBACK');
 v_boot:=programacion.fn_engineering_unit_bootstrap_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11');
 IF v_out3->>'status' IS DISTINCT FROM 'READY'
 OR v_out3->>'action_kind' IS DISTINCT FROM 'READBACK_ONCE'
 OR v_out3#>>'{required_evidence_contract,semantic_independence_proven}' IS DISTINCT FROM 'false'
 OR v_out4->>'action_kind' IS DISTINCT FROM 'BOUNDED_CHECKPOINT_TEST_AUTHORING'
 OR v_out4#>>'{assertion_contract,pass_when,test_passed}' IS DISTINCT FROM 'true'
 OR v_out5->>'action_kind' IS DISTINCT FROM 'READBACK_ONCE'
 OR v_out6->>'action_kind' IS DISTINCT FROM 'READBACK_ONCE'
 OR v_boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM 'DECISIONAL_BINDING_VIA_RELEASE'
 OR v_boot#>>'{state,done_checkpoint_count}' IS DISTINCT FROM '2'
 OR v_boot#>>'{state,checkpoint_count}' IS DISTINCT FROM '6'
 THEN RAISE EXCEPTION 'M411_SCOPE_V3_POSTCONTRACT_DRIFT:%',v_out3->>'status'; END IF;
 IF EXISTS(SELECT 1 FROM programacion.engineering_work_checkpoints
 WHERE work_item_id=v_u.work_item_id AND sequence_no>=3 AND status<>'PENDING')
 THEN RAISE EXCEPTION 'M411_SCOPE_V3_UNAUTHORIZED_CHECKPOINT_STATUS_CHANGE'; END IF;
END;
$m411_v3$;

-- Append-only EKB on successful migration only; no registry in a spreadsheet.
INSERT INTO transversal.error_knowledge (
 codigo,categoria,titulo,descripcion,causa_raiz,prevencion,validacion,
 severidad,lote_origen,pr,estado,evidencia,lifecycle_phase,source_ref
)
SELECT
 'IG-M411-CONSTRUCTION-VS-DECISIONAL-SCOPE-CONFLATION-001',
 'CONTRATO_GOBERNANZA',
 'CP3 confundio la calificacion shadow con la autorizacion de release decisional',
 'CP3/CP6 requerian T-INDEP y runs decisionales para cerrar ingenieria aunque M4.12 habia novado R11 y el oracle existente es comparison-only.',
 'Criterio de cierre del plan y admision operacional combinados, contradiciendo R11 event 20635 y EKB AUD-045.',
 'En construccion permitir cierre con R11 behavioral PASS, 47/47 declaradas, negativo real y readback; separar CAPABILITY_CUTOVER con T-INDEP autentico y permiso real para decisiones semanticas. Ajustar unidad, checkpoints y gobernanza juntos.',
 'Positive: M9.2 6/6; M4.12 behavior PASS; M9.12 verified receipt 1667; 47/47 shadow. Negative: no semantic independence and oracle function forbids promotion. CP3-CP6 remain PENDING until actual checkpoint execution.',
 'ALTA','M4.11','lf_ig_m411_engineering_qualification_scope_v3',
 'ACTIVO','AUD-045; event://20635; provenance_receipts/1667; IG_M411_ENGINEERING_SCOPE_V3',
 'construction',
 'supabase/migrations/20261013120000_lf_ig_m411_engineering_qualification_scope_v3.sql'
WHERE NOT EXISTS(SELECT 1 FROM transversal.error_knowledge
 WHERE codigo='IG-M411-CONSTRUCTION-VS-DECISIONAL-SCOPE-CONFLATION-001');
