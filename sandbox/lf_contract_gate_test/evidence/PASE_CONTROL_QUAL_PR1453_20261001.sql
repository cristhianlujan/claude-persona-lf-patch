-- PASE_CONTROL_QUALIFICATION_V1 evidence SQL for PR #1453
-- Repository: cristhianlujan/claude-persona-lf-patch
-- Base/main: acd9895d1b8c4f7d44f11eae5e943618e9baa16f
-- Candidate head: 4e8d6070fe40eb6825fa676430a11fc95b1b5a0a
-- Candidate: CHANGESET_GOVERNANCE_LF_V1
-- Evidence-only branch: evidence/pase-control-qual-pr1453-20261001-001
-- This file does not modify PR #1453 and is not a migration.

-- 1) Dry run executed with BEGIN/ROLLBACK.
begin;
insert into public.lf_operation_execution(
 execution_id,operation_code,target_type,target_code,target_repo,target_path,status,
 started_at,completed_at,manifest,created_by_execution_id,updated_by_execution_id,
 idempotency_key,request_sha256
) values (
 'EXEC-PASE-CONTROL-QUAL-PR1453-20261001-001','GITHUB_CONTRACT_GATE_LF','REPOSITORY_GOVERNED_PATHS','PASE_CONTROL_QUALIFICATION_PR1453',
 'cristhianlujan/claude-persona-lf-patch','sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_change_family_registry_v1.json','COMPLETED',
 clock_timestamp(),clock_timestamp(),'{"purpose":"PASE_CONTROL_QUALIFICATION_V1_INDEPENDENT_EXACT_HEAD","pr_number":1453,"base_sha":"acd9895d1b8c4f7d44f11eae5e943618e9baa16f","candidate_head":"4e8d6070fe40eb6825fa676430a11fc95b1b5a0a","candidate_id":"CHANGESET_GOVERNANCE_LF_V1","changed_paths":["sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_change_family_registry_v1.json"],"changed_path_count":1,"qualified_only":true,"operation_closed":true,"independent_qualifier":true,"qualification_authority":"PASE_CONTROL_QUALIFICATION_V1","qualification_checks_complete":true,"validator_revision_method":"SHA256_RAW_BYTES_OF_VALIDATOR_AT_BASE","validator_path":"sandbox/lf_contract_gate_test/pase_control_qualification/pase_control_qualification_v1.py","validator_blob_sha1":"4325559154b510922702bbc17c3cf9838063df42","validator_revision_sha256":"cfddf11831c69f6edff6eb3c266796e33fd215dcb024f8f22b57ba899e68a77c","pase_run_id":36941187909,"pase_job_id":110632797989,"pase_status":"SUCCESS","e2e_run_id":null,"e2e_status":"SKIP_POST_PASE_L6_E2E_NOT_CHANGED","merge_gate_first_run_id":36941183986,"merge_gate_first_job_id":110632808855,"merge_gate_first_result":"BLOCK_PASE_MERGE_GATE_QUALIFICATION_MISSING","independent_change_admission_job_id":110632809279,"independent_change_admission_status":"SUCCESS","activation_authorized":false,"cutover_authorized":false,"rebind_authorized":false,"legacy_retirement_authorized":false,"production_touched":false,"runtime_or_deploy_touched":false,"live_domain_controls_executed":false,"operation_policy_snapshot_verified":true}'::jsonb,
 'CHATGPT-PASE-CONTROL-QUAL-PR1453-20261001','CHATGPT-PASE-CONTROL-QUAL-PR1453-20261001',
 'PASE-CONTROL-QUAL-PR1453-4e8d6070',encode(extensions.digest(convert_to('PASE-CONTROL-QUAL-PR1453-4e8d6070|4e8d6070fe40eb6825fa676430a11fc95b1b5a0a','UTF8'),'sha256'),'hex')
);
select public.lf_record_control_system_qualification_v1(
 'CHANGESET_GOVERNANCE_LF_V1','cristhianlujan/claude-persona-lf-patch','cfddf11831c69f6edff6eb3c266796e33fd215dcb024f8f22b57ba899e68a77c','EXEC-PASE-CONTROL-QUAL-PR1453-20261001-001','{"schema_version":"lf-pase-control-qualification/v1","qualification_type":"CONTROL_REFACTOR","repository":"cristhianlujan/claude-persona-lf-patch","candidate_id":"CHANGESET_GOVERNANCE_LF_V1","declared_owner":"LF_GOVERNANCE","base_sha":"acd9895d1b8c4f7d44f11eae5e943618e9baa16f","head_sha":"4e8d6070fe40eb6825fa676430a11fc95b1b5a0a","observed_main_sha":"acd9895d1b8c4f7d44f11eae5e943618e9baa16f","scope_paths":["sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_change_family_registry_v1.json"],"owner_local_tests":["python3 LOCAL_EXACT_HEAD_ADMISSION_HARNESS.py --head 4e8d6070fe40eb6825fa676430a11fc95b1b5a0a --registry-blob 5b73541d0e80be6e3b57a48791024277e9f71e68","python3 LOCAL_EXACT_HEAD_ADMISSION_HARNESS.py --head 4e8d6070fe40eb6825fa676430a11fc95b1b5a0a --registry-blob 5b73541d0e80be6e3b57a48791024277e9f71e68 --repeat"],"boundary_invariants":["DEFAULT_GITHUB_REMAINS_DENY","ONE_EXACT_GITHUB_PATH_ONLY","NO_PREFIX_OR_WILDCARD_EXPANSION","FIXED_FAMILIES_UNCHANGED","FAMILY_CONTROLS_UNCHANGED","NO_CARRIER_ROUTE_REGISTRY_WORKFLOW_OR_RUNTIME_CHANGE","NO_ACTIVATION_CUTOVER_REBIND_OR_LEGACY_RETIREMENT"],"expected_coverage":["EXACT_BASE_HEAD_IDENTITY","SINGLE_LINE_EXACT_GITHUB_ADMISSION","DECLARED_OWNER_AND_INDEPENDENT_QUALIFIER","LOCAL_REPOSITORY_PATH_ADMISSION_AND_REGISTRY_TESTS","EXACT_PATH_BOUNDARY","NEGATIVE_UNREGISTERED_AND_VARIANT_FAIL_CLOSED","NO_OUT_OF_SCOPE_EFFECTS","DETERMINISTIC_REPLAY","NO_REPLACEMENT_REPLAY_REQUIRED","PRIOR_GITHUB_EXACT_COVERAGE_PRESERVED","HEAD_BOUND_EVIDENCE"],"replacement":null}'::jsonb,'{"schema_version":"lf-pase-control-qualification-result/v1","candidate_id":"CHANGESET_GOVERNANCE_LF_V1","base_sha":"acd9895d1b8c4f7d44f11eae5e943618e9baa16f","head_sha":"4e8d6070fe40eb6825fa676430a11fc95b1b5a0a","declared_owner":"LF_GOVERNANCE","checks":[{"id":"Q01","status":"PASS","evidence":["github:PR1453 exact base=acd9895d1b8c4f7d44f11eae5e943618e9baa16f head=4e8d6070fe40eb6825fa676430a11fc95b1b5a0a; main==base observed 2026-10-02T00:06:33.237287Z..00:06:37.572645Z","github-actions:PASE run 36941187909 job 110632797989 exact head=4e8d6070fe40eb6825fa676430a11fc95b1b5a0a base=acd9895d1b8c4f7d44f11eae5e943618e9baa16f SUCCESS"]},{"id":"Q02","status":"PASS","evidence":["github:compare acd9895d1b8c4f7d44f11eae5e943618e9baa16f...4e8d6070fe40eb6825fa676430a11fc95b1b5a0a files=1 additions=1 deletions=0; path=sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_change_family_registry_v1.json; patch adds only .github/workflows/lf-input-governance-recurate-dispatch.yml"]},{"id":"Q03","status":"PASS","evidence":["qualification:declared_owner=LF_GOVERNANCE; authority=PASE_CONTROL_QUALIFICATION_V1; independent_qualifier=true; candidate does not author its own verdict"]},{"id":"Q04","status":"PASS","evidence":["local:4e8d6070fe40eb6825fa676430a11fc95b1b5a0a: registry_blob=5b73541d0e80be6e3b57a48791024277e9f71e68 repository_path_admission=PASS change_family_registry=PASS","local:4e8d6070fe40eb6825fa676430a11fc95b1b5a0a: two focused exact-head runs complete with identical outputs"]},{"id":"Q05","status":"PASS","evidence":["github:4e8d6070fe40eb6825fa676430a11fc95b1b5a0a: path_admission.default_github=DENY; exact delta={.github/workflows/lf-input-governance-recurate-dispatch.yml}; fixed_families and family_controls identical to base"]},{"id":"Q06","status":"PASS","evidence":["local:4e8d6070fe40eb6825fa676430a11fc95b1b5a0a: new exact path -> PASS_GITHUB_EXACT_PATH_ADMISSION","local:4e8d6070fe40eb6825fa676430a11fc95b1b5a0a: .github/workflows/unregistered-pr1453-probe.yml -> FAIL_UNAUTHORIZED_GITHUB_PATH","local:4e8d6070fe40eb6825fa676430a11fc95b1b5a0a: .github/workflows/lf-input-governance-recurate-dispatch-copy.yml -> FAIL_UNAUTHORIZED_GITHUB_PATH"]},{"id":"Q07","status":"PASS","evidence":["github:compare acd9895d1b8c4f7d44f11eae5e943618e9baa16f...4e8d6070fe40eb6825fa676430a11fc95b1b5a0a touches only sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_change_family_registry_v1.json; no carrier, route registry, workflow, service runtime or Supabase runtime path changed"]},{"id":"Q08","status":"PASS","evidence":["local:4e8d6070fe40eb6825fa676430a11fc95b1b5a0a: run1 == run2 byte-for-byte JSON outcome for admission/registry/negative probes"]},{"id":"Q09","status":"NA","evidence":[]},{"id":"Q10","status":"PASS","evidence":["github:4e8d6070fe40eb6825fa676430a11fc95b1b5a0a: all 15 base github_exact entries preserved; head count=16; set(head)-set(base) is exactly the authorized dispatch path"]},{"id":"Q11","status":"PASS","evidence":["github-actions:run 36941187909 job 110632797989 SUCCESS exact head=4e8d6070fe40eb6825fa676430a11fc95b1b5a0a; plan changed_paths contains only registry path","github-actions:prequalification Merge Gate run 36941183986 job 110632808855 exact head=4e8d6070fe40eb6825fa676430a11fc95b1b5a0a blocked only BLOCK_PASE_MERGE_GATE_QUALIFICATION_MISSING; candidate_code_executed=false","local:4e8d6070fe40eb6825fa676430a11fc95b1b5a0a: all PASS evidence generated from registry blob 5b73541d0e80be6e3b57a48791024277e9f71e68 fetched at exact head"]}],"external_findings":[],"coverage_complete":true,"verdict":"CANDIDATE_QUALIFIED","qualified_only":true,"activation_authorized":false,"cutover_authorized":false,"rebind_authorized":false,"legacy_retirement_authorized":false}'::jsonb
);
select public.lf_control_system_qualification_readback_v1(
 'CHANGESET_GOVERNANCE_LF_V1','cristhianlujan/claude-persona-lf-patch','acd9895d1b8c4f7d44f11eae5e943618e9baa16f','4e8d6070fe40eb6825fa676430a11fc95b1b5a0a'
);
rollback;

-- Post-rollback verification used:
select exists(select 1 from public.lf_operation_execution where execution_id='EXEC-PASE-CONTROL-QUAL-PR1453-20261001-001') as execution_exists_after_rollback,
       exists(select 1 from public.lf_qualification_receipts where subject_type='CONTROL_SYSTEM' and subject_code='CHANGESET_GOVERNANCE_LF_V1' and qualification_input->>'head_sha'='4e8d6070fe40eb6825fa676430a11fc95b1b5a0a') as qualification_exists_after_rollback;

-- 2) Durable qualification application executed.
begin;
insert into public.lf_operation_execution(
 execution_id,operation_code,target_type,target_code,target_repo,target_path,status,
 started_at,completed_at,manifest,created_by_execution_id,updated_by_execution_id,
 idempotency_key,request_sha256
) values (
 'EXEC-PASE-CONTROL-QUAL-PR1453-20261001-001','GITHUB_CONTRACT_GATE_LF','REPOSITORY_GOVERNED_PATHS','PASE_CONTROL_QUALIFICATION_PR1453',
 'cristhianlujan/claude-persona-lf-patch','sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_change_family_registry_v1.json','COMPLETED',
 clock_timestamp(),clock_timestamp(),'{"purpose":"PASE_CONTROL_QUALIFICATION_V1_INDEPENDENT_EXACT_HEAD","pr_number":1453,"base_sha":"acd9895d1b8c4f7d44f11eae5e943618e9baa16f","candidate_head":"4e8d6070fe40eb6825fa676430a11fc95b1b5a0a","candidate_id":"CHANGESET_GOVERNANCE_LF_V1","changed_paths":["sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_change_family_registry_v1.json"],"changed_path_count":1,"qualified_only":true,"operation_closed":true,"independent_qualifier":true,"qualification_authority":"PASE_CONTROL_QUALIFICATION_V1","qualification_checks_complete":true,"validator_revision_method":"SHA256_RAW_BYTES_OF_VALIDATOR_AT_BASE","validator_path":"sandbox/lf_contract_gate_test/pase_control_qualification/pase_control_qualification_v1.py","validator_blob_sha1":"4325559154b510922702bbc17c3cf9838063df42","validator_revision_sha256":"cfddf11831c69f6edff6eb3c266796e33fd215dcb024f8f22b57ba899e68a77c","pase_run_id":36941187909,"pase_job_id":110632797989,"pase_status":"SUCCESS","e2e_run_id":null,"e2e_status":"SKIP_POST_PASE_L6_E2E_NOT_CHANGED","merge_gate_first_run_id":36941183986,"merge_gate_first_job_id":110632808855,"merge_gate_first_result":"BLOCK_PASE_MERGE_GATE_QUALIFICATION_MISSING","independent_change_admission_job_id":110632809279,"independent_change_admission_status":"SUCCESS","activation_authorized":false,"cutover_authorized":false,"rebind_authorized":false,"legacy_retirement_authorized":false,"production_touched":false,"runtime_or_deploy_touched":false,"live_domain_controls_executed":false,"operation_policy_snapshot_verified":true}'::jsonb,
 'CHATGPT-PASE-CONTROL-QUAL-PR1453-20261001','CHATGPT-PASE-CONTROL-QUAL-PR1453-20261001',
 'PASE-CONTROL-QUAL-PR1453-4e8d6070',encode(extensions.digest(convert_to('PASE-CONTROL-QUAL-PR1453-4e8d6070|4e8d6070fe40eb6825fa676430a11fc95b1b5a0a','UTF8'),'sha256'),'hex')
);
select public.lf_record_control_system_qualification_v1(
 'CHANGESET_GOVERNANCE_LF_V1','cristhianlujan/claude-persona-lf-patch','cfddf11831c69f6edff6eb3c266796e33fd215dcb024f8f22b57ba899e68a77c','EXEC-PASE-CONTROL-QUAL-PR1453-20261001-001','{"schema_version":"lf-pase-control-qualification/v1","qualification_type":"CONTROL_REFACTOR","repository":"cristhianlujan/claude-persona-lf-patch","candidate_id":"CHANGESET_GOVERNANCE_LF_V1","declared_owner":"LF_GOVERNANCE","base_sha":"acd9895d1b8c4f7d44f11eae5e943618e9baa16f","head_sha":"4e8d6070fe40eb6825fa676430a11fc95b1b5a0a","observed_main_sha":"acd9895d1b8c4f7d44f11eae5e943618e9baa16f","scope_paths":["sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_change_family_registry_v1.json"],"owner_local_tests":["python3 LOCAL_EXACT_HEAD_ADMISSION_HARNESS.py --head 4e8d6070fe40eb6825fa676430a11fc95b1b5a0a --registry-blob 5b73541d0e80be6e3b57a48791024277e9f71e68","python3 LOCAL_EXACT_HEAD_ADMISSION_HARNESS.py --head 4e8d6070fe40eb6825fa676430a11fc95b1b5a0a --registry-blob 5b73541d0e80be6e3b57a48791024277e9f71e68 --repeat"],"boundary_invariants":["DEFAULT_GITHUB_REMAINS_DENY","ONE_EXACT_GITHUB_PATH_ONLY","NO_PREFIX_OR_WILDCARD_EXPANSION","FIXED_FAMILIES_UNCHANGED","FAMILY_CONTROLS_UNCHANGED","NO_CARRIER_ROUTE_REGISTRY_WORKFLOW_OR_RUNTIME_CHANGE","NO_ACTIVATION_CUTOVER_REBIND_OR_LEGACY_RETIREMENT"],"expected_coverage":["EXACT_BASE_HEAD_IDENTITY","SINGLE_LINE_EXACT_GITHUB_ADMISSION","DECLARED_OWNER_AND_INDEPENDENT_QUALIFIER","LOCAL_REPOSITORY_PATH_ADMISSION_AND_REGISTRY_TESTS","EXACT_PATH_BOUNDARY","NEGATIVE_UNREGISTERED_AND_VARIANT_FAIL_CLOSED","NO_OUT_OF_SCOPE_EFFECTS","DETERMINISTIC_REPLAY","NO_REPLACEMENT_REPLAY_REQUIRED","PRIOR_GITHUB_EXACT_COVERAGE_PRESERVED","HEAD_BOUND_EVIDENCE"],"replacement":null}'::jsonb,'{"schema_version":"lf-pase-control-qualification-result/v1","candidate_id":"CHANGESET_GOVERNANCE_LF_V1","base_sha":"acd9895d1b8c4f7d44f11eae5e943618e9baa16f","head_sha":"4e8d6070fe40eb6825fa676430a11fc95b1b5a0a","declared_owner":"LF_GOVERNANCE","checks":[{"id":"Q01","status":"PASS","evidence":["github:PR1453 exact base=acd9895d1b8c4f7d44f11eae5e943618e9baa16f head=4e8d6070fe40eb6825fa676430a11fc95b1b5a0a; main==base observed 2026-10-02T00:06:33.237287Z..00:06:37.572645Z","github-actions:PASE run 36941187909 job 110632797989 exact head=4e8d6070fe40eb6825fa676430a11fc95b1b5a0a base=acd9895d1b8c4f7d44f11eae5e943618e9baa16f SUCCESS"]},{"id":"Q02","status":"PASS","evidence":["github:compare acd9895d1b8c4f7d44f11eae5e943618e9baa16f...4e8d6070fe40eb6825fa676430a11fc95b1b5a0a files=1 additions=1 deletions=0; path=sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_change_family_registry_v1.json; patch adds only .github/workflows/lf-input-governance-recurate-dispatch.yml"]},{"id":"Q03","status":"PASS","evidence":["qualification:declared_owner=LF_GOVERNANCE; authority=PASE_CONTROL_QUALIFICATION_V1; independent_qualifier=true; candidate does not author its own verdict"]},{"id":"Q04","status":"PASS","evidence":["local:4e8d6070fe40eb6825fa676430a11fc95b1b5a0a: registry_blob=5b73541d0e80be6e3b57a48791024277e9f71e68 repository_path_admission=PASS change_family_registry=PASS","local:4e8d6070fe40eb6825fa676430a11fc95b1b5a0a: two focused exact-head runs complete with identical outputs"]},{"id":"Q05","status":"PASS","evidence":["github:4e8d6070fe40eb6825fa676430a11fc95b1b5a0a: path_admission.default_github=DENY; exact delta={.github/workflows/lf-input-governance-recurate-dispatch.yml}; fixed_families and family_controls identical to base"]},{"id":"Q06","status":"PASS","evidence":["local:4e8d6070fe40eb6825fa676430a11fc95b1b5a0a: new exact path -> PASS_GITHUB_EXACT_PATH_ADMISSION","local:4e8d6070fe40eb6825fa676430a11fc95b1b5a0a: .github/workflows/unregistered-pr1453-probe.yml -> FAIL_UNAUTHORIZED_GITHUB_PATH","local:4e8d6070fe40eb6825fa676430a11fc95b1b5a0a: .github/workflows/lf-input-governance-recurate-dispatch-copy.yml -> FAIL_UNAUTHORIZED_GITHUB_PATH"]},{"id":"Q07","status":"PASS","evidence":["github:compare acd9895d1b8c4f7d44f11eae5e943618e9baa16f...4e8d6070fe40eb6825fa676430a11fc95b1b5a0a touches only sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_change_family_registry_v1.json; no carrier, route registry, workflow, service runtime or Supabase runtime path changed"]},{"id":"Q08","status":"PASS","evidence":["local:4e8d6070fe40eb6825fa676430a11fc95b1b5a0a: run1 == run2 byte-for-byte JSON outcome for admission/registry/negative probes"]},{"id":"Q09","status":"NA","evidence":[]},{"id":"Q10","status":"PASS","evidence":["github:4e8d6070fe40eb6825fa676430a11fc95b1b5a0a: all 15 base github_exact entries preserved; head count=16; set(head)-set(base) is exactly the authorized dispatch path"]},{"id":"Q11","status":"PASS","evidence":["github-actions:run 36941187909 job 110632797989 SUCCESS exact head=4e8d6070fe40eb6825fa676430a11fc95b1b5a0a; plan changed_paths contains only registry path","github-actions:prequalification Merge Gate run 36941183986 job 110632808855 exact head=4e8d6070fe40eb6825fa676430a11fc95b1b5a0a blocked only BLOCK_PASE_MERGE_GATE_QUALIFICATION_MISSING; candidate_code_executed=false","local:4e8d6070fe40eb6825fa676430a11fc95b1b5a0a: all PASS evidence generated from registry blob 5b73541d0e80be6e3b57a48791024277e9f71e68 fetched at exact head"]}],"external_findings":[],"coverage_complete":true,"verdict":"CANDIDATE_QUALIFIED","qualified_only":true,"activation_authorized":false,"cutover_authorized":false,"rebind_authorized":false,"legacy_retirement_authorized":false}'::jsonb
);
commit;

-- 3) Canonical exact-head confirmation executed.
select public.lf_control_system_qualification_readback_v1(
 'CHANGESET_GOVERNANCE_LF_V1','cristhianlujan/claude-persona-lf-patch','acd9895d1b8c4f7d44f11eae5e943618e9baa16f','4e8d6070fe40eb6825fa676430a11fc95b1b5a0a'
);

-- 4) Debt event payload was validated before write:
select private.fn_lf_event_contract_assessment_v3(
 'READBACK_VERIFICADO','PASE_GOVERNANCE_DEBT','PASE_QUAL_VALIDATOR_REVISION_METHOD_INCONSISTENT',
 'Deuda no bloqueante: PR1282 y PR1385 registraron validator_revision_sha256=0cb91bca... sin método reproducible aun usando el mismo blob de validador; PR1244, PR1246 y PR1257 usan SHA256 crudo reproducible cfddf118.... Pregunta abierta a Cristhian, owner LF_GOVERNANCE.',jsonb_build_object(
'evidence_schema_version','operational-event/v2',
'execution_id','EXEC-PASE-CONTROL-QUAL-PR1453-20261001-001',
'producer','PASE_CONTROL_QUALIFICATION_V1',
'purpose','Registrar deuda de gobernanza no bloqueante sobre inconsistencia histórica del método de validator_revision_sha256.',
'occurred_at',clock_timestamp(),
'acceptance_declared',false,
'production_authorized',false,
'runtime_or_deploy_touched',false,
'finding_code','PASE_QUAL_VALIDATOR_REVISION_METHOD_INCONSISTENT',
'owner','LF_GOVERNANCE',
'question_open_to','Cristhian',
'validator_path','sandbox/lf_contract_gate_test/pase_control_qualification/pase_control_qualification_v1.py',
'validator_blob_sha1','4325559154b510922702bbc17c3cf9838063df42',
'canonical_method','SHA256_RAW_BYTES_OF_VALIDATOR_AT_BASE',
'canonical_validator_revision_sha256','cfddf11831c69f6edff6eb3c266796e33fd215dcb024f8f22b57ba899e68a77c',
'unreproducible_validator_revision_sha256','0cb91bca3befbf493edcd2bc3f9e7589d1e14d76aa4b685a73a6f11ca4b53bde',
'receipts_with_unreproducible_method',jsonb_build_array('PR1282','PR1385'),
'receipts_with_raw_sha256_method',jsonb_build_array('PR1244','PR1246','PR1257'),
'existing_receipts_mutated',false
),'EXEC-PASE-CONTROL-QUAL-PR1453-20261001-001'
);

-- 5) Canonical successful debt-event insert.
-- NOTE: an earlier attempt supplied id explicitly and PostgreSQL rejected it because id is GENERATED ALWAYS;
-- no event row was persisted by that rejected statement. The successful statement below uses the identity natively.
insert into public.lf_eventos(
 evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,origen,created_by_execution_id
) values (
 'READBACK_VERIFICADO','PASE_GOVERNANCE_DEBT','PASE_QUAL_VALIDATOR_REVISION_METHOD_INCONSISTENT',
 'Deuda no bloqueante: PR1282 y PR1385 registraron validator_revision_sha256=0cb91bca... sin método reproducible aun usando el mismo blob de validador; PR1244, PR1246 y PR1257 usan SHA256 crudo reproducible cfddf118.... Pregunta abierta a Cristhian, owner LF_GOVERNANCE.','WARN',jsonb_build_object(
'evidence_schema_version','operational-event/v2',
'execution_id','EXEC-PASE-CONTROL-QUAL-PR1453-20261001-001',
'producer','PASE_CONTROL_QUALIFICATION_V1',
'purpose','Registrar deuda de gobernanza no bloqueante sobre inconsistencia histórica del método de validator_revision_sha256.',
'occurred_at',clock_timestamp(),
'acceptance_declared',false,
'production_authorized',false,
'runtime_or_deploy_touched',false,
'finding_code','PASE_QUAL_VALIDATOR_REVISION_METHOD_INCONSISTENT',
'owner','LF_GOVERNANCE',
'question_open_to','Cristhian',
'validator_path','sandbox/lf_contract_gate_test/pase_control_qualification/pase_control_qualification_v1.py',
'validator_blob_sha1','4325559154b510922702bbc17c3cf9838063df42',
'canonical_method','SHA256_RAW_BYTES_OF_VALIDATOR_AT_BASE',
'canonical_validator_revision_sha256','cfddf11831c69f6edff6eb3c266796e33fd215dcb024f8f22b57ba899e68a77c',
'unreproducible_validator_revision_sha256','0cb91bca3befbf493edcd2bc3f9e7589d1e14d76aa4b685a73a6f11ca4b53bde',
'receipts_with_unreproducible_method',jsonb_build_array('PR1282','PR1385'),
'receipts_with_raw_sha256_method',jsonb_build_array('PR1244','PR1246','PR1257'),
'existing_receipts_mutated',false
),'PASE_CONTROL_QUALIFICATION_V1','EXEC-PASE-CONTROL-QUAL-PR1453-20261001-001'
);
