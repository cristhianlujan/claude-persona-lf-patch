-- S36 / CURRENTNESS_AUTHORITY
-- Isolated registration only. No runtime activation and no mutation of existing rows.
-- Base SHA: daf63da6518ad7bdb146aabc5adab5cc0f1d7f1a

insert into public.lf_test_suites
(suite_code,module_code,name,version,status,execution_policy,metadata,created_by_execution_id)
values
(
  'TS-CURRENTNESS-AUTHORITY-V1',
  'LF_TEST_ASSURANCE',
  'Currentness Authority Assurance Matrix',
  'v1',
  'CANDIDATO',
  '{"deterministic_first":true,"false_pass_tolerance":0,"exact_revision":true,"independent_readback_required":true}'::jsonb,
  '{"matrix_family":"CAPABILITY_ASSURANCE","capability_code":"CURRENTNESS_AUTHORITY","base_sha":"daf63da6518ad7bdb146aabc5adab5cc0f1d7f1a","source_tests":["sandbox/lf_contract_gate_test/material_currentness/test_lf_currentness_authority_v1.py","sandbox/lf_contract_gate_test/material_currentness/test_lf_broker_currentness_bridge_v1.py"]}'::jsonb,
  'EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'
)
on conflict (suite_code) do nothing;

insert into public.lf_test_suite_cases
(suite_code,test_code,test_order,title,test_type,execution_mode,severity,preconditions,input_payload,expected_output,prohibited_output,status,metadata,created_by_execution_id)
values
(
  'TS-CURRENTNESS-AUTHORITY-V1','CUR-DET-001',10,
  'Compatible implementation change rebounds currentness without invalidating consumer',
  'DETERMINISTIC','AUTOMATED','CRITICAL','[]'::jsonb,
  '{"source_test":"sandbox/lf_contract_gate_test/material_currentness/test_lf_currentness_authority_v1.py::test_implementation_only_compatible_does_not_invalidate_consumer"}'::jsonb,
  '{"decision":"CURRENT_REBOUND","ready":true,"affected_root_material_ids":[]}'::jsonb,
  '{"forbid":["STALE_AFFECTED","UNKNOWN_FAIL_CLOSED"]}'::jsonb,
  'CANDIDATO','{"assurance_dimension":"FUNCTIONAL","existing_test":true}'::jsonb,
  'EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'
),
(
  'TS-CURRENTNESS-AUTHORITY-V1','CUR-DET-002',20,
  'Compatible contract change requires bounded validation',
  'DETERMINISTIC','AUTOMATED','CRITICAL','[]'::jsonb,
  '{"source_test":"sandbox/lf_contract_gate_test/material_currentness/test_lf_currentness_authority_v1.py::test_compatible_contract_change_requires_bounded_validation"}'::jsonb,
  '{"decision":"CURRENT_REBOUND","bounded_validation_required":true}'::jsonb,
  '{"forbid":["silent_compatibility_without_bounded_validation"]}'::jsonb,
  'CANDIDATO','{"assurance_dimension":"CURRENTNESS","existing_test":true}'::jsonb,
  'EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'
),
(
  'TS-CURRENTNESS-AUTHORITY-V1','CUR-DET-003',30,
  'Breaking contract change is selectively stale',
  'DETERMINISTIC','AUTOMATED','CRITICAL','[]'::jsonb,
  '{"source_test":"sandbox/lf_contract_gate_test/material_currentness/test_lf_currentness_authority_v1.py::test_breaking_contract_change_is_selectively_stale"}'::jsonb,
  '{"decision":"STALE_AFFECTED","ready":false,"selective_invalidation":true}'::jsonb,
  '{"forbid":["global_invalidation","CURRENT_REBOUND"]}'::jsonb,
  'CANDIDATO','{"assurance_dimension":"SELECTIVE_INVALIDATION","existing_test":true}'::jsonb,
  'EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'
),
(
  'TS-CURRENTNESS-AUTHORITY-V1','CUR-NEG-004',40,
  'Unknown or missing compatibility assessment fails closed',
  'ADVERSARIAL','AUTOMATED','CRITICAL','[]'::jsonb,
  '{"source_tests":["sandbox/lf_contract_gate_test/material_currentness/test_lf_currentness_authority_v1.py::test_unknown_compatibility_fails_closed","sandbox/lf_contract_gate_test/material_currentness/test_lf_currentness_authority_v1.py::test_missing_assessment_fails_closed_instead_of_assuming_breaking"]}'::jsonb,
  '{"decision":"UNKNOWN_FAIL_CLOSED","ready":false}'::jsonb,
  '{"forbid":["implicit_compatibility","silent_pass"]}'::jsonb,
  'CANDIDATO','{"assurance_dimension":"FAIL_CLOSED","existing_test":true}'::jsonb,
  'EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'
),
(
  'TS-CURRENTNESS-AUTHORITY-V1','CUR-REPLAY-005',50,
  'Compatibility proof cannot be replayed across contract context',
  'ADVERSARIAL','AUTOMATED','CRITICAL','[]'::jsonb,
  '{"source_test":"sandbox/lf_contract_gate_test/material_currentness/test_lf_currentness_authority_v1.py::test_replayed_or_wrong_context_proof_fails_closed"}'::jsonb,
  '{"decision":"UNKNOWN_FAIL_CLOSED","reason_prefix":"COMPATIBILITY_PROOF_CONTEXT_MISMATCH"}'::jsonb,
  '{"forbid":["cross_context_replay_pass"]}'::jsonb,
  'CANDIDATO','{"assurance_dimension":"REPLAY","existing_test":true}'::jsonb,
  'EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'
),
(
  'TS-CURRENTNESS-AUTHORITY-V1','CUR-EVID-006',60,
  'Source attestation is exact and rejects material or authority tamper',
  'ADVERSARIAL','AUTOMATED','CRITICAL','[]'::jsonb,
  '{"source_tests":["sandbox/lf_contract_gate_test/material_currentness/test_lf_currentness_authority_v1.py::test_source_attestation_verifies_offline_and_detects_rehashed_material_tamper","sandbox/lf_contract_gate_test/material_currentness/test_lf_currentness_authority_v1.py::test_source_attestation_rejects_wrong_expected_authority"]}'::jsonb,
  '{"valid_attestation":"ATTESTATION_VERIFIED_OFFLINE","tamper_rejected":true,"wrong_authority_rejected":true}'::jsonb,
  '{"forbid":["tampered_attestation_pass","wrong_repo_pass"]}'::jsonb,
  'CANDIDATO','{"assurance_dimension":"EVIDENCE_AUTHORITY","existing_test":true}'::jsonb,
  'EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'
),
(
  'TS-CURRENTNESS-AUTHORITY-V1','CUR-INT-007',70,
  'Broker bridge blocks stale, unproven, incomplete and mismatched currentness before rebind',
  'ADVERSARIAL','AUTOMATED','CRITICAL','[]'::jsonb,
  '{"source_tests":["sandbox/lf_contract_gate_test/material_currentness/test_lf_broker_currentness_bridge_v1.py::test_material_change_with_explicit_breaking_proof_blocks_selectively","sandbox/lf_contract_gate_test/material_currentness/test_lf_broker_currentness_bridge_v1.py::test_material_change_without_assessment_blocks_as_unproven","sandbox/lf_contract_gate_test/material_currentness/test_lf_broker_currentness_bridge_v1.py::test_incomplete_dependency_proof_blocks","sandbox/lf_contract_gate_test/material_currentness/test_lf_broker_currentness_bridge_v1.py::test_binding_base_mismatch_blocks_before_rebind"]}'::jsonb,
  '{"zero_effect_on_unproven":true,"binding_base_mismatch_blocks":true}'::jsonb,
  '{"forbid":["rebind_before_validation","unproven_currentness_pass"]}'::jsonb,
  'CANDIDATO','{"assurance_dimension":"INTEGRATION_FAIL_CLOSED","existing_test":true}'::jsonb,
  'EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'
),
(
  'TS-CURRENTNESS-AUTHORITY-V1','CUR-E2E-008',80,
  'Real consumer cannot bypass Currentness before material effect',
  'ADVERSARIAL','INDEPENDENT_REVIEW','CRITICAL','[{"consumer_binding_required":true}]'::jsonb,
  '{"case_family":"NO_BYPASS_BEFORE_EFFECT","consumers":["GITHUB_CONTRACT_GATE_LF","EJECUCION_ESTRATEGIA_LF"]}'::jsonb,
  '{"blocked_before_effect":true,"durable_receipt_required":true,"independent_readback_required":true}'::jsonb,
  '{"forbid":["material_effect_without_currentness","post_effect_currentness","self_attested_pass"]}'::jsonb,
  'CANDIDATO','{"assurance_dimension":"E2E_BYPASS","existing_test":false,"gap_closure_required":true}'::jsonb,
  'EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'
),
(
  'TS-CURRENTNESS-AUTHORITY-V1','CUR-E2E-009',90,
  'Currentness receipt cannot be replayed across execution, subject or revision',
  'ADVERSARIAL','INDEPENDENT_REVIEW','CRITICAL','[{"durable_receipt_required":true}]'::jsonb,
  '{"case_family":"RECEIPT_ANTI_REPLAY","dimensions":["execution_id","subject","source_revision"]}'::jsonb,
  '{"cross_context_replay_blocked":true,"same_context_readback_exact":true}'::jsonb,
  '{"forbid":["receipt_reanchor","old_receipt_pass"]}'::jsonb,
  'CANDIDATO','{"assurance_dimension":"E2E_REPLAY","existing_test":false,"gap_closure_required":true}'::jsonb,
  'EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'
),
(
  'TS-CURRENTNESS-AUTHORITY-V1','CUR-E2E-010',100,
  'Stateful write path validates Currentness before write and preserves zero effect on failure',
  'ADVERSARIAL','INDEPENDENT_REVIEW','CRITICAL','[{"material_write_possible":true}]'::jsonb,
  '{"case_family":"STATEFUL_PREWRITE_CURRENTNESS"}'::jsonb,
  '{"currentness_before_write":true,"zero_effect_on_failure":true}'::jsonb,
  '{"forbid":["write_then_validate","partial_write_on_failure"]}'::jsonb,
  'CANDIDATO','{"assurance_dimension":"STATEFUL_SEQUENCE","existing_test":false,"gap_closure_required":true}'::jsonb,
  'EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'
),
(
  'TS-CURRENTNESS-AUTHORITY-V1','CUR-SEM-011',110,
  'Self-declared compatibility classification is rejected as non-independent',
  'ADVERSARIAL','INDEPENDENT_REVIEW','CRITICAL','[{"semantic_classification_required":true}]'::jsonb,
  '{"case_family":"SEMANTIC_INDEPENDENCE_NEGATIVE","producer_equals_verifier":true}'::jsonb,
  '{"self_assessment_rejected":true,"independent_readback_required":true}'::jsonb,
  '{"forbid":["self_attested_semantic_pass","deterministic_verifier_as_semantic_authority"]}'::jsonb,
  'CANDIDATO','{"assurance_dimension":"SEMANTIC_INDEPENDENCE","existing_test":false,"coverage_state":"NOT_COVERED","gap_closure_required":true}'::jsonb,
  'EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'
),
(
  'TS-CURRENTNESS-AUTHORITY-V1','CUR-SEM-012',120,
  'Independent compatibility classification is bound to exact material and revision',
  'INTEGRATION','INDEPENDENT_REVIEW','CRITICAL','[{"semantic_classification_required":true}]'::jsonb,
  '{"case_family":"SEMANTIC_INDEPENDENCE_POSITIVE","producer_verifier_separation_required":true}'::jsonb,
  '{"independent_classifier_required":true,"exact_material_binding":true,"exact_revision_binding":true,"independent_readback_required":true}'::jsonb,
  '{"forbid":["unbound_semantic_classification","cross_revision_semantic_reuse"]}'::jsonb,
  'CANDIDATO','{"assurance_dimension":"SEMANTIC_INDEPENDENCE","existing_test":false,"coverage_state":"NOT_COVERED","gap_closure_required":true}'::jsonb,
  'EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'
)
on conflict (suite_code,test_code) do nothing;

insert into public.lf_assurance_claim_catalog
(claim_code,version,parent_claim_code,parent_claim_version,subject_type,subject_code,claim_class,claim_text,criticality,applicability,closure_rule,status,source_ref,created_by_execution_id)
values
('CURRENTNESS_AUTHORITY_ASSURED_V1',1,'LF_ASSURANCE_METHOD_V1',1,'CAPABILITY','CURRENTNESS_AUTHORITY','CURRENTNESS','Currentness is exact, fail-closed, selectively invalidating, replay-resistant and mandatory before material effect for every bound consumer.','CRITICAL','{"capability_code":"CURRENTNESS_AUTHORITY"}'::jsonb,'{"pass_requires":["CUR_MATERIAL_VALID_V1","CUR_EVIDENCE_BOUND_EXACT_V1","CUR_NO_BYPASS_BEFORE_EFFECT_V1","CUR_SEMANTIC_COMPATIBILITY_JUSTIFIED_V1","CUR_SELECTIVE_INVALIDATION_V1","CUR_RECEIPT_ANTI_REPLAY_V1","CUR_REQUIRED_REAL_RUNNER_V1"],"open_defeater_blocks_pass":true}'::jsonb,'CANDIDATO','github://sandbox/lf_contract_gate_test/material_currentness','EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'),
('CUR_MATERIAL_VALID_V1',1,'CURRENTNESS_AUTHORITY_ASSURED_V1',1,'CAPABILITY','CURRENTNESS_AUTHORITY','CURRENTNESS','Material dependency currentness is computed from exact bound/current material and incomplete or unknown compatibility fails closed.','CRITICAL','{}'::jsonb,'{"required_cases":["CUR-DET-001","CUR-DET-002","CUR-DET-003","CUR-NEG-004"]}'::jsonb,'CANDIDATO','github://sandbox/lf_contract_gate_test/material_currentness/test_lf_currentness_authority_v1.py','EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'),
('CUR_EVIDENCE_BOUND_EXACT_V1',1,'CURRENTNESS_AUTHORITY_ASSURED_V1',1,'CAPABILITY','CURRENTNESS_AUTHORITY','EVIDENCE','Currentness evidence is bound to the exact authority, material fingerprints and expected context.','CRITICAL','{}'::jsonb,'{"required_cases":["CUR-EVID-006"]}'::jsonb,'CANDIDATO','github://sandbox/lf_contract_gate_test/material_currentness/test_lf_currentness_authority_v1.py','EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'),
('CUR_NO_BYPASS_BEFORE_EFFECT_V1',1,'CURRENTNESS_AUTHORITY_ASSURED_V1',1,'CAPABILITY','CURRENTNESS_AUTHORITY','AUTHORITY','No bound consumer can produce a material effect before successful Currentness validation.','CRITICAL','{"consumers":["GITHUB_CONTRACT_GATE_LF","EJECUCION_ESTRATEGIA_LF"]}'::jsonb,'{"required_cases":["CUR-E2E-008","CUR-E2E-010"],"zero_effect_required":true}'::jsonb,'CANDIDATO','LF_S36_CURRENTNESS_ASSURANCE_20260917','EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'),
('CUR_SEMANTIC_COMPATIBILITY_JUSTIFIED_V1',1,'CURRENTNESS_AUTHORITY_ASSURED_V1',1,'CAPABILITY','CURRENTNESS_AUTHORITY','AUTHORITY','Compatibility classification used for Currentness is independently justified and cannot be self-declared by the deterministic verifier.','CRITICAL','{}'::jsonb,'{"required_cases":["CUR-SEM-011","CUR-SEM-012"],"independent_review_required":true,"self_assessment_forbidden":true}'::jsonb,'CANDIDATO','LF_S36_CURRENTNESS_ASSURANCE_20260917','EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'),
('CUR_SELECTIVE_INVALIDATION_V1',1,'CURRENTNESS_AUTHORITY_ASSURED_V1',1,'CAPABILITY','CURRENTNESS_AUTHORITY','CURRENTNESS','Only consumers transitively affected by changed material are invalidated.','HIGH','{}'::jsonb,'{"required_cases":["CUR-DET-003","CUR-INT-007"]}'::jsonb,'CANDIDATO','github://sandbox/lf_contract_gate_test/material_currentness','EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'),
('CUR_RECEIPT_ANTI_REPLAY_V1',1,'CURRENTNESS_AUTHORITY_ASSURED_V1',1,'CAPABILITY','CURRENTNESS_AUTHORITY','EVIDENCE','A Currentness receipt cannot transfer PASS across execution, subject or source revision.','CRITICAL','{}'::jsonb,'{"required_cases":["CUR-REPLAY-005","CUR-E2E-009"]}'::jsonb,'CANDIDATO','LF_S36_CURRENTNESS_ASSURANCE_20260917','EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'),
('CUR_REQUIRED_REAL_RUNNER_V1',1,'CURRENTNESS_AUTHORITY_ASSURED_V1',1,'CAPABILITY','CURRENTNESS_AUTHORITY','STRUCTURAL_COVERAGE','Real bound runners execute Currentness as a mandatory pre-effect gate and produce durable independently readable evidence.','CRITICAL','{"consumers":["GITHUB_CONTRACT_GATE_LF","EJECUCION_ESTRATEGIA_LF"]}'::jsonb,'{"required_cases":["CUR-E2E-008"],"exact_head_readback_required":true}'::jsonb,'CANDIDATO','LF_S36_CURRENTNESS_ASSURANCE_20260917','EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001')
on conflict (claim_code,version) do nothing;

insert into public.lf_assurance_obligation_catalog
(obligation_code,version,claim_code,claim_version,verification_method,positive_test_ref,negative_test_ref,adversarial_test_ref,evidence_contract,failure_taxonomy_code,required,status,source_ref,created_by_execution_id)
values
('CUR-OBL-MATERIAL-VALID-V1',1,'CUR_MATERIAL_VALID_V1',1,'TEST','CUR-DET-001,CUR-DET-002,CUR-DET-003','CUR-NEG-004',null,'{"suite":"TS-CURRENTNESS-AUTHORITY-V1","exact_revision":true}'::jsonb,'CURRENTNESS_MATERIAL_INVALID',true,'CANDIDATO','TS-CURRENTNESS-AUTHORITY-V1','EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'),
('CUR-OBL-EVIDENCE-EXACT-V1',1,'CUR_EVIDENCE_BOUND_EXACT_V1',1,'TEST','CUR-EVID-006','CUR-EVID-006','CUR-EVID-006','{"suite":"TS-CURRENTNESS-AUTHORITY-V1","authority_exact":true}'::jsonb,'CURRENTNESS_EVIDENCE_MISMATCH',true,'CANDIDATO','TS-CURRENTNESS-AUTHORITY-V1','EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'),
('CUR-OBL-NO-BYPASS-V1',1,'CUR_NO_BYPASS_BEFORE_EFFECT_V1',1,'INDEPENDENT_REVIEW',null,'CUR-E2E-008','CUR-E2E-010','{"zero_effect_required":true,"durable_receipt":true,"independent_readback":true}'::jsonb,'CURRENTNESS_BYPASS',true,'CANDIDATO','TS-CURRENTNESS-AUTHORITY-V1','EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'),
('CUR-OBL-SEMANTIC-INDEPENDENCE-V1',1,'CUR_SEMANTIC_COMPATIBILITY_JUSTIFIED_V1',1,'INDEPENDENT_REVIEW','CUR-SEM-012','CUR-SEM-011','CUR-SEM-011','{"producer_verifier_separation_required":true,"exact_material_binding":true,"exact_revision_binding":true}'::jsonb,'CURRENTNESS_SELF_ASSESSMENT',true,'CANDIDATO','TS-CURRENTNESS-AUTHORITY-V1','EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'),
('CUR-OBL-SELECTIVE-INVALIDATION-V1',1,'CUR_SELECTIVE_INVALIDATION_V1',1,'TEST','CUR-DET-003',null,'CUR-INT-007','{"selective_invalidation":true}'::jsonb,'CURRENTNESS_OVERINVALIDATION',true,'CANDIDATO','TS-CURRENTNESS-AUTHORITY-V1','EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'),
('CUR-OBL-ANTI-REPLAY-V1',1,'CUR_RECEIPT_ANTI_REPLAY_V1',1,'TEST','CUR-REPLAY-005','CUR-E2E-009','CUR-E2E-009','{"execution_subject_revision_bound":true}'::jsonb,'CURRENTNESS_REPLAY',true,'CANDIDATO','TS-CURRENTNESS-AUTHORITY-V1','EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'),
('CUR-OBL-REAL-RUNNER-V1',1,'CUR_REQUIRED_REAL_RUNNER_V1',1,'STRUCTURAL_COVERAGE',null,'CUR-E2E-008','CUR-E2E-010','{"consumers":["GITHUB_CONTRACT_GATE_LF","EJECUCION_ESTRATEGIA_LF"],"pre_effect_required":true}'::jsonb,'CURRENTNESS_RUNNER_OPTIONAL',true,'CANDIDATO','TS-CURRENTNESS-AUTHORITY-V1','EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001')
on conflict (obligation_code,version) do nothing;

insert into public.lf_assurance_defeater_catalog
(defeater_code,version,claim_code,claim_version,obligation_code,defeater_class,description,required_counterevidence,zero_effect_required,status,source_ref,created_by_execution_id)
values
('CUR-DEF-BYPASS-V1',1,'CUR_NO_BYPASS_BEFORE_EFFECT_V1',1,'CUR-OBL-NO-BYPASS-V1','BYPASS','A consumer reaches a material effect without a successful Currentness decision.','{"required":["negative_e2e","zero_effect_readback"]}'::jsonb,true,'CANDIDATO','TS-CURRENTNESS-AUTHORITY-V1','EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'),
('CUR-DEF-REPLAY-V1',1,'CUR_RECEIPT_ANTI_REPLAY_V1',1,'CUR-OBL-ANTI-REPLAY-V1','REPLAY','A receipt from another execution, subject or revision is accepted.','{"required":["cross_context_replay_negative","exact_binding_readback"]}'::jsonb,true,'CANDIDATO','TS-CURRENTNESS-AUTHORITY-V1','EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'),
('CUR-DEF-STALE-V1',1,'CUR_MATERIAL_VALID_V1',1,'CUR-OBL-MATERIAL-VALID-V1','STALE','Changed material is accepted as current without justified compatibility.','{"required":["breaking_change_negative","missing_assessment_negative"]}'::jsonb,true,'CANDIDATO','TS-CURRENTNESS-AUTHORITY-V1','EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'),
('CUR-DEF-SELF-ASSESS-V1',1,'CUR_SEMANTIC_COMPATIBILITY_JUSTIFIED_V1',1,'CUR-OBL-SEMANTIC-INDEPENDENCE-V1','EVIDENCE_NOT_INDEPENDENT','The same authority both classifies compatibility and verifies its own classification.','{"required":["independent_compatibility_authority","producer_verifier_separation"]}'::jsonb,false,'CANDIDATO','TS-CURRENTNESS-AUTHORITY-V1','EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'),
('CUR-DEF-POSTWRITE-V1',1,'CUR_NO_BYPASS_BEFORE_EFFECT_V1',1,'CUR-OBL-NO-BYPASS-V1','TOCTOU','Currentness is checked after or non-atomically with respect to a material write.','{"required":["prewrite_sequence_test","zero_effect_on_failure"]}'::jsonb,true,'CANDIDATO','TS-CURRENTNESS-AUTHORITY-V1','EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001')
on conflict (defeater_code,version) do nothing;

insert into public.lf_assurance_subject_bindings
(binding_code,subject_type,subject_code,standard_claim_code,standard_claim_version,benchmark_suite_code,activation_condition,required,status,source_ref,created_by_execution_id)
values
(
  'BIND-CURRENTNESS-AUTHORITY-ASSURANCE-V1',
  'CAPABILITY',
  'CURRENTNESS_AUTHORITY',
  'CURRENTNESS_AUTHORITY_ASSURED_V1',
  1,
  'TS-CURRENTNESS-AUTHORITY-V1',
  '{"when_capability_consumed":true,"consumers":["GITHUB_CONTRACT_GATE_LF","EJECUCION_ESTRATEGIA_LF"]}'::jsonb,
  true,
  'CANDIDATO',
  'LF_ASSURANCE_METHOD_V1',
  'EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'
)
on conflict (binding_code) do nothing;

-- Candidate consumer enrollment only. PENDING preserves the no-runtime-activation boundary.
insert into public.lf_test_requirement_bindings
(binding_code,subject_type,subject_code,characteristic_code,suite_code,required,min_pass_rate,false_pass_tolerance,independent_review_required,rollback_required,currentness_mode,activation_condition,effective_from,status,created_by_execution_id)
values
(
  'BIND-OP-GITHUB-CONTRACT-GATE-CURRENTNESS-V1',
  'OPERATION','GITHUB_CONTRACT_GATE_LF',null,'TS-CURRENTNESS-AUTHORITY-V1',
  true,1.0,0,true,false,'EXACT_REVISION','{"type":"ALWAYS"}'::jsonb,clock_timestamp(),'PENDING',
  'EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'
),
(
  'BIND-OP-STRATEGY-EXECUTOR-CURRENTNESS-V1',
  'OPERATION','EJECUCION_ESTRATEGIA_LF',null,'TS-CURRENTNESS-AUTHORITY-V1',
  true,1.0,0,true,true,'EXACT_REVISION','{"type":"ALWAYS"}'::jsonb,clock_timestamp(),'PENDING',
  'EXEC-S36-CURRENTNESS-ASSURANCE-MATRIX-20260917-001'
)
on conflict (binding_code) do nothing;
