-- PE10 C6: immutable fixture-validation provenance, NOT production cutover.
-- GitHub: https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/39846185403
-- Provider-checked exact PR head cf6553b19b216bf7d6d43c1875576c6f8e1a7933; source bytes matched in producer.
-- Deliberately ANCHORED, not VERIFIED: examples are NOT evolved candidates.
-- Integration through authorized ACTUALIZACION_DB_LF / LF Migration Merge Train.
BEGIN;
DO $pe10_c6_provider$
DECLARE
 v_slug constant text := 'systemic_root_cause_repair_lf';
 v_head constant text := 'cf6553b19b216bf7d6d43c1875576c6f8e1a7933';
 v_run constant bigint := 39846185403;
 v_evidence_sha constant text := '9a15c3ed165cb55b0d9309133083af86b2692df03294b049c5f6c7a0d925db50';
 v_example jsonb := $ci_evidence${"capability_code":"PACK_VALIDATION_HARNESS","cutover_authorized":false,"evidence_scope":"PROFILE_CANONICAL_EXAMPLES_NOT_EVOLVED_CANDIDATE","evidence_sha256":"9a15c3ed165cb55b0d9309133083af86b2692df03294b049c5f6c7a0d925db50","gate_code":"PROFILE_OUTPUT_CONTRACT_VALIDATION","github_actions_run_id":"39846185403","github_readback_source_sha256":{"negative_raw_output":"48fd7ce6999751f9df96115a7d626df8b23111f24d824b486faee468e68e9640","positive_raw_output":"504ee8192c94b726db37736bebc31008c365c49dd77872526b3ca76610ddb949","producer":"5c8934be3a86aac3410d879dfc2a298d1eb0c84ca59dd0aac224087df5bc675b","runner":"4ef0e3b4e4d3ca10417cc6dbf9dca79a3d252ee626871eab55d43b1f481a0b26","runtime_binding":"3408c4e1c4213ca2c615a909cd7530f6dae202f0d911610673741a969a9f336b","schema":"18ee653127fc938852248b0a5d50975558d6498b1d27f625cb6b04bccf173170","validator":"501a03881730d3bfcd99f66cd87452a1c8c3dd25f2a4a11cdf96743eed3e19be"},"negative_result":{"admission_authorized":false,"blocking_codes":[],"canonical_json_schema_executed":true,"independent_review_executed":false,"profile_validator_executed":false,"profile_write_authorized":false,"provider_attested":false,"raw_output_sha256":"48fd7ce6999751f9df96115a7d626df8b23111f24d824b486faee468e68e9640","runtime_activation_authorized":false,"runtime_binding_sha256":"3408c4e1c4213ca2c615a909cd7530f6dae202f0d911610673741a969a9f336b","schema":"PROFILE_OUTPUT_VALIDATION_RESULT_V1","shape_errors":[{"code":"CANONICAL_JSON_SCHEMA_REJECTED:additionalProperties","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"},{"code":"CANONICAL_JSON_SCHEMA_REJECTED:required","path":"$"}],"source_readback_matched":true,"source_refs":{"raw_output":"profiles/systemic_root_cause_repair_lf/examples/bad_output.json","schema":"profiles/systemic_root_cause_repair_lf/schemas/output.schema.json","validator":"profiles/systemic_root_cause_repair_lf/validators/runtime_validate.py"},"status":"EXPECTED_NEGATIVE_REJECTED_BY_SHAPE","structural_check_executed":true},"positive_result":{"admission_authorized":false,"blocking_codes":[],"canonical_json_schema_executed":true,"independent_review_executed":false,"profile_validator_executed":true,"profile_write_authorized":false,"provider_attested":false,"raw_output_sha256":"504ee8192c94b726db37736bebc31008c365c49dd77872526b3ca76610ddb949","runtime_activation_authorized":false,"runtime_binding_sha256":"3408c4e1c4213ca2c615a909cd7530f6dae202f0d911610673741a969a9f336b","schema":"PROFILE_OUTPUT_VALIDATION_RESULT_V1","shape_errors":[],"source_readback_matched":true,"source_refs":{"raw_output":"profiles/systemic_root_cause_repair_lf/examples/good_output.json","schema":"profiles/systemic_root_cause_repair_lf/schemas/output.schema.json","validator":"profiles/systemic_root_cause_repair_lf/validators/runtime_validate.py"},"status":"CANDIDATE_OUTPUT_PARITY_OBSERVED","structural_check_executed":true,"validator_errors":[],"validator_exit_code":0,"validator_stdout_sha256":"fc660df5ddb24694abc66cf34c83594adab5c6295fca14fa1959daf15fe148ac"},"production_activation":false,"profile_slug":"systemic_root_cause_repair_lf","provider":"GITHUB","receipt_issued":false,"schema":"PE10_C6_GITHUB_PROVIDER_OUTPUT_SOURCE_READBACK_V1","source_head_sha":"cf6553b19b216bf7d6d43c1875576c6f8e1a7933"}$ci_evidence$::jsonb;
 v_plan_sha text;
 v_orch text;
 v_producer text;
 v_ledger text;
 v_cap_sha text;
 v_response jsonb;
 v_dispatch jsonb;
 v_binding jsonb;
 v_anchor jsonb;
 v_current_result jsonb;
 v_receipt_id uuid;
 v_subject_type text;
 v_raw_path text;
 v_raw_sha text;
 v_receipts jsonb := '[]'::jsonb;
 v_actor constant text := 'EXEC-PE10-C6-OUTPUT-EXAMPLE-PROVENANCE-20261022-V1';
 v_code constant text := 'PE10_C6.OUTPUT_EXAMPLE_SOURCE_BOUND_ANCHORED.V1';
 v_audit jsonb;
 v_event_id bigint;
BEGIN
 IF v_example->>'schema' IS DISTINCT FROM 'PE10_C6_GITHUB_PROVIDER_OUTPUT_SOURCE_READBACK_V1'
  OR v_example->>'evidence_scope' IS DISTINCT FROM 'PROFILE_CANONICAL_EXAMPLES_NOT_EVOLVED_CANDIDATE'
  OR v_example->>'source_head_sha' IS DISTINCT FROM v_head
  OR v_example->>'github_actions_run_id' IS DISTINCT FROM v_run::text
  OR v_example->>'evidence_sha256' IS DISTINCT FROM v_evidence_sha
  OR v_example->>'receipt_issued' IS DISTINCT FROM 'false'
  OR v_example->>'production_activation' IS DISTINCT FROM 'false'
  OR v_example#>>'{positive_result,status}' IS DISTINCT FROM 'CANDIDATE_OUTPUT_PARITY_OBSERVED'
  OR v_example#>>'{negative_result,status}' IS DISTINCT FROM 'EXPECTED_NEGATIVE_REJECTED_BY_SHAPE'
  OR v_example#>>'{positive_result,profile_validator_executed}' IS DISTINCT FROM 'true'
  OR v_example#>>'{negative_result,profile_validator_executed}' IS DISTINCT FROM 'false'
  OR v_example#>>'{positive_result,canonical_json_schema_executed}' IS DISTINCT FROM 'true'
  OR v_example#>>'{negative_result,canonical_json_schema_executed}' IS DISTINCT FROM 'true'
  OR v_example#>>'{positive_result,admission_authorized}' IS DISTINCT FROM 'false'
  OR v_example#>>'{negative_result,admission_authorized}' IS DISTINCT FROM 'false'
  OR v_example#>>'{positive_result,runtime_activation_authorized}' IS DISTINCT FROM 'false'
  OR v_example#>>'{negative_result,runtime_activation_authorized}' IS DISTINCT FROM 'false'
  OR v_example#>>'{positive_result,raw_output_sha256}' IS DISTINCT FROM '504ee8192c94b726db37736bebc31008c365c49dd77872526b3ca76610ddb949'
  OR v_example#>>'{negative_result,raw_output_sha256}' IS DISTINCT FROM '48fd7ce6999751f9df96115a7d626df8b23111f24d824b486faee468e68e9640'
  OR v_example#>>'{positive_result,runtime_binding_sha256}' IS DISTINCT FROM '3408c4e1c4213ca2c615a909cd7530f6dae202f0d911610673741a969a9f336b'
  OR jsonb_array_length(v_example#>'{negative_result,shape_errors}')=0
 THEN RAISE EXCEPTION 'PE10_OUTPUT_SOURCE_BOUND_PROVIDER_RESULT_INVALID'; END IF;
 IF (SELECT version FROM public.lf_operation_registry
      WHERE operation_code='ACTUALIZACION_PERFIL_LF') IS DISTINCT FROM 'v0.1'
  OR (SELECT count(*) FROM public.lf_operation_steps WHERE operation_code='ACTUALIZACION_PERFIL_LF' AND active)<>15
  OR (SELECT count(*) FROM public.lf_operation_steps WHERE operation_code='ACTUALIZACION_PERFIL_LF'
       AND step_id IN ('method_selection','evolution_decision') AND active)<>0
  OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=1103 AND checkpoint_code IN ('PE10_C6','PE10_C7') AND status='PENDING')<>2
  OR EXISTS(SELECT 1 FROM public.lf_eventos WHERE entidad_codigo=v_code)
  OR EXISTS(SELECT 1 FROM private.lf_evidence_ledger_v1
       WHERE subject_type IN ('PROFILE_OUTPUT_VALIDATION_POSITIVE','PROFILE_OUTPUT_VALIDATION_NEGATIVE')
         AND subject_ref=v_slug)
 THEN RAISE EXCEPTION 'PE10_OUTPUT_FIXTURE_LEDGER_PRESTATE_CHANGED'; END IF;
 IF (SELECT count(*) FROM private.lf_evidence_resolver_registry_v1
       WHERE resolver_id='LF_GITHUB_SOURCE_READBACK_V1' AND provider='GITHUB'
         AND verification_method='GITHUB_API_READBACK_PLUS_OFFLINE_HASH'
         AND trust_level='TRUSTED_PROVIDER_BOUND' AND active)<>1
  OR NOT EXISTS(SELECT 1 FROM public.lf_capability_registry
       WHERE capability_code='PACK_VALIDATION_HARNESS' AND status='ACTIVE')
  OR NOT EXISTS(SELECT 1 FROM public.lf_capability_current
       WHERE capability_code='PACK_VALIDATION_HARNESS' AND version='1.0.0')
 THEN RAISE EXCEPTION 'PE10_OUTPUT_PROVIDER_CAPABILITY_UNAVAILABLE'; END IF;
 SELECT c.manifest_sha256 INTO STRICT v_cap_sha
 FROM public.lf_capability_current c JOIN public.lf_capability_registry r
  USING(capability_code)
 WHERE c.capability_code='EVIDENCE_LEDGER' AND r.status='ACTIVE';
 v_plan_sha := encode(extensions.digest(convert_to(
   jsonb_build_object('schema','PE10_C6_PROVIDER_ANCHORED_FIXTURE_PLAN_V1',
    'profile_slug',v_slug,'provider_run',v_run,'source_head_sha',v_head,
    'source_evidence_sha256',v_evidence_sha,
    'positive_sha256','504ee8192c94b726db37736bebc31008c365c49dd77872526b3ca76610ddb949',
    'negative_sha256','48fd7ce6999751f9df96115a7d626df8b23111f24d824b486faee468e68e9640',
    'ledger_cap_sha256',v_cap_sha)::text,
    'UTF8'),'sha256'),'hex');
 v_orch := 'EXEC-PE10-C6-OUTPUT-ORCH-'||substr(v_plan_sha,1,16);
 v_producer := 'EXEC-PE10-C6-OUTPUT-PRODUCER-'||substr(v_plan_sha,1,16);
 v_ledger := 'EXEC-PE10-C6-OUTPUT-LEDGER-'||substr(v_plan_sha,1,16);

 v_response:=public.fn_lf_operation_reserve_execution_v1(
  v_orch,'ORQUESTACION_PIPELINE_LF','PROFILE_OUTPUT_VALIDATION',v_slug,
  'pe10:c6:output:orch:'||v_plan_sha,v_plan_sha,v_orch,null,null,
  jsonb_build_object('schema','PE10_C6_OUTPUT_ORCHESTRATOR_V1',
    'capability_code','EVIDENCE_LEDGER','source_head_sha',v_head,
    'plan_digest',v_plan_sha,'production_activation',false,
    'evidence_scope','PROFILE_CANONICAL_EXAMPLES_NOT_EVOLVED_CANDIDATE'));
 IF v_response->>'status' IS DISTINCT FROM 'IN_PROGRESS'
  OR v_response->>'execution_id' IS DISTINCT FROM v_orch
 THEN RAISE EXCEPTION 'PE10_C6_OUTPUT_ORCHESTRATOR_RESERVE_FAILED:%',v_response; END IF;
 v_response:=public.fn_lf_operation_reserve_execution_v1(
  v_producer,'ORQUESTACION_PIPELINE_LF','PROFILE_OUTPUT_VALIDATION',v_slug,
  'pe10:c6:output:producer:'||v_plan_sha,v_plan_sha,v_orch,null,null,
  jsonb_build_object('schema','PE10_C6_OUTPUT_PRODUCER_V1',
    'orchestrator_execution_id',v_orch,'plan_digest',v_plan_sha,
    'capability_code','PACK_VALIDATION_HARNESS',
    'source_head_sha',v_head,
    'provider_ref','github-api://repos/cristhianlujan/claude-persona-lf-patch@'||v_head||
      '/actions/runs/'||v_run::text,
    'producer_evidence_sha256',v_evidence_sha,
    'evidence_scope','PROFILE_CANONICAL_EXAMPLES_NOT_EVOLVED_CANDIDATE'));
 IF v_response->>'status' IS DISTINCT FROM 'IN_PROGRESS'
  OR v_response->>'execution_id' IS DISTINCT FROM v_producer
 THEN RAISE EXCEPTION 'PE10_C6_OUTPUT_PRODUCER_RESERVE_FAILED:%',v_response; END IF;
 v_response:=public.fn_lf_operation_reserve_execution_v1(
  v_ledger,'ORQUESTACION_PIPELINE_LF','PROFILE_OUTPUT_VALIDATION',v_slug,
  'pe10:c6:output:ledger:'||v_plan_sha,v_plan_sha,v_orch,null,null,
  jsonb_build_object('schema','PE10_C6_OUTPUT_LEDGER_V1',
    'orchestrator_execution_id',v_orch,'producer_execution_id',v_producer,
    'plan_digest',v_plan_sha,'capability_code','EVIDENCE_LEDGER',
    'source_head_sha',v_head,
    'evidence_scope','PROFILE_CANONICAL_EXAMPLES_NOT_EVOLVED_CANDIDATE'));
 IF v_response->>'status' IS DISTINCT FROM 'IN_PROGRESS'
  OR v_response->>'execution_id' IS DISTINCT FROM v_ledger
 THEN RAISE EXCEPTION 'PE10_C6_OUTPUT_LEDGER_RESERVE_FAILED:%',v_response; END IF;
 v_dispatch:=public.fn_lf_orchestrator_dispatch_receipt_v1(
  v_orch,v_ledger,'EVIDENCE_LEDGER',v_plan_sha,
  jsonb_build_object('subject_types',jsonb_build_array(
    'PROFILE_OUTPUT_VALIDATION_POSITIVE','PROFILE_OUTPUT_VALIDATION_NEGATIVE'),
    'subject_ref',v_slug,'source_head_sha',v_head,
    'producer_execution_id',v_producer,
    'provider','GITHUB','resolver_id','LF_GITHUB_SOURCE_READBACK_V1',
    'fixture_validation_only',true),v_orch);
 IF NOT coalesce((v_dispatch->>'ready')::boolean,false)
 THEN RAISE EXCEPTION 'PE10_C6_OUTPUT_DISPATCH_FAILED:%',v_dispatch; END IF;
 v_binding:=public.fn_lf_capability_bind_from_orchestrator_v1(
  v_ledger,'EVIDENCE_LEDGER',v_cap_sha,v_plan_sha,
  (v_dispatch->>'receipt_id')::uuid,v_orch);
 IF NOT coalesce((v_binding->>'ready')::boolean,false)
 THEN RAISE EXCEPTION 'PE10_C6_OUTPUT_LEDGER_BIND_FAILED:%',v_binding; END IF;

 FOR v_subject_type,v_current_result,v_raw_path,v_raw_sha IN
  SELECT *
  FROM (VALUES
   ('PROFILE_OUTPUT_VALIDATION_POSITIVE',
     v_example->'positive_result',
     'profiles/'||v_slug||'/examples/good_output.json',
     '504ee8192c94b726db37736bebc31008c365c49dd77872526b3ca76610ddb949'),
   ('PROFILE_OUTPUT_VALIDATION_NEGATIVE',
     v_example->'negative_result',
     'profiles/'||v_slug||'/examples/bad_output.json',
     '48fd7ce6999751f9df96115a7d626df8b23111f24d824b486faee468e68e9640')
  ) AS fixture(subject_type,validation_result,raw_path,raw_sha)
 LOOP
  IF v_current_result->>'raw_output_sha256' IS DISTINCT FROM v_raw_sha
   OR v_current_result#>>'{source_refs,raw_output}' IS DISTINCT FROM v_raw_path
  THEN RAISE EXCEPTION 'PE10_C6_PROVIDER_RESULT_SOURCE_DRIFT:%',v_subject_type; END IF;
  v_anchor:=public.fn_lf_evidence_ledger_anchor_v1(
   v_producer,'PACK_VALIDATION_HARNESS','PROFILE_OUTPUT_CONTRACT_VALIDATION',
   'PROFILE_OUTPUT_VALIDATION_RESULT',v_subject_type,v_slug,v_raw_sha,v_head,
   'github://cristhianlujan/claude-persona-lf-patch/blob/'||v_head||'/'||v_raw_path,
   'LF_GITHUB_SOURCE_READBACK_V1','GITHUB',
   'github-api://repos/cristhianlujan/claude-persona-lf-patch@'||v_head||
       '/actions/runs/'||v_run::text,
   'GITHUB_API_READBACK_PLUS_OFFLINE_HASH','ANCHORED',
   jsonb_build_object(
     'provider_readback_verified',true,'digest_recomputed',true,
     'github_actions_run_id',v_run,'github_actions_status','SUCCESS',
     'github_source_head_sha',v_head,
     'source_hashes_provider_verified',v_example->'github_readback_source_sha256',
     'source_evidence_sha256',v_evidence_sha,
     'fixture_validation_only',true,
     'candidate_output_provider_e2e_verified',false,
     'production_activation',false),
   v_current_result||jsonb_build_object(
     'profile_slug',v_slug,
     'source_head_sha',v_head,
     'evidence_scope','PROFILE_CANONICAL_EXAMPLES_NOT_EVOLVED_CANDIDATE',
     'example_fixture_only',true,
     'producer_evidence_sha256',v_evidence_sha,
     'provider_run_id',v_run,
     'output_cutover_authorized',false,
     'candidate_output_provider_e2e_verified',false,
     'production_activation',false),
   v_ledger);
  v_receipt_id:=(v_anchor->>'receipt_id')::uuid;
  IF v_anchor->>'decision' IS DISTINCT FROM 'ANCHORED'
   OR v_receipt_id IS NULL
   OR NOT EXISTS (
     SELECT 1 FROM private.lf_evidence_ledger_v1 l
     WHERE l.receipt_id=v_receipt_id AND l.execution_id=v_producer
      AND l.created_by_execution_id=v_ledger
      AND l.capability_code='PACK_VALIDATION_HARNESS'
      AND l.gate_code='PROFILE_OUTPUT_CONTRACT_VALIDATION'
      AND l.receipt_kind='PROFILE_OUTPUT_VALIDATION_RESULT'
      AND l.subject_type=v_subject_type AND l.subject_ref=v_slug
      AND l.subject_sha256=v_raw_sha AND l.source_head_sha=v_head
      AND l.verification_state='ANCHORED' AND l.verified_at IS NULL
      AND l.receipt_payload->>'example_fixture_only'='true'
      AND l.receipt_payload->>'output_cutover_authorized'='false'
   ) THEN RAISE EXCEPTION 'PE10_C6_OUTPUT_FIXTURE_ANCHOR_READBACK_INVALID:%',v_subject_type; END IF;
  IF public.lf_profile_update_verified_receipt_v1(
   v_subject_type,v_slug,v_receipt_id::text,v_raw_sha,v_head) IS NOT false
  THEN RAISE EXCEPTION 'PE10_C6_FIXTURE_RECEIPT_PREMATURELY_VERIFIED:%',v_subject_type; END IF;
  v_receipts:=v_receipts||jsonb_build_array(
     jsonb_build_object('subject_type',v_subject_type,
       'receipt_id',v_receipt_id,'verification_state','ANCHORED',
       'subject_sha256',v_raw_sha));
 END LOOP;

 IF (SELECT count(*) FROM private.lf_evidence_ledger_v1
   WHERE subject_type IN ('PROFILE_OUTPUT_VALIDATION_POSITIVE','PROFILE_OUTPUT_VALIDATION_NEGATIVE')
    AND subject_ref=v_slug AND verification_state='ANCHORED'
    AND receipt_payload->>'example_fixture_only'='true')<>2
  OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=1103 AND checkpoint_code IN ('PE10_C6','PE10_C7')
      AND status='PENDING')<>2
 THEN RAISE EXCEPTION 'PE10_C6_OUTPUT_PROVIDER_LEDGER_FINAL_STATE_INVALID'; END IF;

 v_audit:=jsonb_build_object(
  'evidence_schema_version','operational-event/v2',
  'execution_id',v_actor,
  'producer','LF_MIGRATION_TRAIN_PE10_C6_OUTPUT_PROVIDER_ANCHOR',
  'purpose','Archive GitHub-verified positive/negative canonical fixture validations without authorizing evolved output cutover',
  'occurred_at',clock_timestamp(),
  'producer_actions_run',v_run,
  'provider_source_head_sha',v_head,
  'producer_evidence_sha256',v_evidence_sha,
  'anchored_receipts',v_receipts,
  'producer_execution_id',v_producer,
  'ledger_execution_id',v_ledger,
  'example_fixture_only',true,
  'real_candidate_evolved_output_verified',false,
  'output_receipts_verified_count',0,
  'cutover_authorized',false,
  'checkpoint_pass',false,'production_activation',false,
  'acceptance_declared',false);
 IF private.fn_lf_event_acceptance_signal_v2(
   'ARTIFACT_RECONCILED',v_code,
   'PE10 C6 GitHub-bound example validations anchored only; candidate outputs still pending',v_audit)
 IS NOT NULL THEN RAISE EXCEPTION 'PE10_C6_ANCHORED_FIXTURE_FALSE_ACCEPTANCE'; END IF;
 INSERT INTO public.lf_eventos(
  evento_tipo,entidad_tipo,entidad_codigo,descripcion,
  severidad,origen,created_by_execution_id,payload
 ) VALUES (
  'ARTIFACT_RECONCILED','PROGRAM_PLAN',v_code,
  'PE10 C6 two provider-bound fixture validations ANCHORED; C6 remains PENDING',
  'INFO','DERIVE_FROM_EXECUTION_ID',v_actor,v_audit)
 RETURNING id INTO v_event_id;
 IF NOT EXISTS (
   SELECT 1 FROM public.lf_eventos WHERE id=v_event_id
    AND payload->>'checkpoint_pass'='false'
    AND payload->>'output_receipts_verified_count'='0'
    AND jsonb_array_length(payload->'anchored_receipts')=2
 ) THEN RAISE EXCEPTION 'PE10_C6_PROVIDER_AUDIT_FAILED'; END IF;
END $pe10_c6_provider$;
COMMIT;
