-- Profile Updater: source-verified real S26 evaluation using the existing
-- EVIDENCE_LEDGER + orchestrator contracts. No new adapter, status cutover,
-- autonomous method invocation, or production activation.
-- GitHub CI: https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/39705018628
-- Frozen GitHub merge commit: 8dabb3a1bfd68dc90b78b09233000bce92d35ee9
BEGIN;
DO $assessment$
DECLARE
  v_slug CONSTANT text := 'systemic_root_cause_repair_lf';
  v_head CONSTANT text := '8dabb3a1bfd68dc90b78b09233000bce92d35ee9';
  v_blob CONSTANT text := 'b0864fbdd96a6874bcf7c7f048a2280abb94df69';
  v_source_sha CONSTANT text := '2187c2671d0c05e7db0939b987c0a64f032e8d837603470b1330be61cf4e21f7';
  v_assessment_sha CONSTANT text := '692618756e551011b52487bc7091ed5f14f166c66f99f9ecea95619c0f5634fc';
  v_canonical CONSTANT text := $canonical${"evidence":{"structural_compatibility":{"refs":[{"action":"BIND_EXECUTION_PARTITION","authority_required":false,"dimension":"B12_EXECUTION_PARTITION"},{"action":"BIND_EXECUTION_BUDGET","authority_required":false,"dimension":"B13_EXECUTION_BUDGET"}],"status":"FAIL"}},"signals":{}}$canonical$;
  v_input jsonb;
  v_plan_sha text;
  v_current_cap_sha text;
  v_orch text;
  v_producer text;
  v_ledger text;
  v_res jsonb;
  v_dispatch jsonb;
  v_bind jsonb;
  v_anchor jsonb;
  v_receipt uuid;
BEGIN
  -- The assessment came from the real checked-out GitHub source, not a mock.
  IF encode(extensions.digest(convert_to(v_canonical,'UTF8'),'sha256'),'hex')
       IS DISTINCT FROM v_assessment_sha THEN
    RAISE EXCEPTION 'PROFILE_ASSESSMENT_CANONICAL_INPUT_DIGEST_MISMATCH';
  END IF;
  v_input := v_canonical::jsonb;
  IF v_input#>>'{evidence,structural_compatibility,status}' IS DISTINCT FROM 'FAIL'
     OR jsonb_array_length(v_input#>'{evidence,structural_compatibility,refs}')<>2
  THEN RAISE EXCEPTION 'PROFILE_ASSESSMENT_INPUT_NOT_REAL_S26'; END IF;
  IF (SELECT status FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=1103 AND checkpoint_code='PE10_C5') IS DISTINCT FROM 'DONE'
     OR (SELECT version FROM public.lf_operation_registry
      WHERE operation_code='ACTUALIZACION_PERFIL_LF') IS DISTINCT FROM 'v0.1'
     OR (SELECT count(*) FROM public.lf_operation_steps
      WHERE operation_code='ACTUALIZACION_PERFIL_LF'
        AND step_order IN (35,37) AND active)<>0
  THEN RAISE EXCEPTION 'PROFILE_ASSESSMENT_PRECONDITION_DRIFT'; END IF;
  IF EXISTS(
    SELECT 1 FROM private.lf_evidence_ledger_v1
     WHERE subject_type='PROFILE_ASSESSMENT' AND subject_ref=v_slug
       AND subject_sha256=v_assessment_sha AND source_head_sha=v_head
  ) THEN RAISE EXCEPTION 'PROFILE_ASSESSMENT_RECEIPT_ALREADY_EXISTS'; END IF;
  IF (SELECT count(*) FROM private.lf_evidence_resolver_registry_v1
      WHERE resolver_id='LF_GITHUB_SOURCE_READBACK_V1'
        AND provider='GITHUB'
        AND verification_method='GITHUB_API_READBACK_PLUS_OFFLINE_HASH'
        AND trust_level='TRUSTED_PROVIDER_BOUND' AND active)<>1
  THEN RAISE EXCEPTION 'PROFILE_ASSESSMENT_TRUSTED_SOURCE_UNAVAILABLE'; END IF;
  SELECT c.manifest_sha256 INTO STRICT v_current_cap_sha
  FROM public.lf_capability_current c JOIN public.lf_capability_registry r
    USING(capability_code)
  WHERE c.capability_code='EVIDENCE_LEDGER' AND r.status='ACTIVE';
  v_plan_sha := encode(extensions.digest(convert_to(
    jsonb_build_object('schema','LF_PROFILE_ASSESSMENT_PLAN_V1',
      'profile_slug',v_slug,'source_head_sha',v_head,
      'source_blob_sha1',v_blob,'source_sha256',v_source_sha,
      'assessment_sha256',v_assessment_sha,'capability_sha256',v_current_cap_sha,
      'github_actions_run',39705018628)::text,'UTF8'),'sha256'),'hex');
  v_orch := 'EXEC-PE10-ASSESS-ORCH-'||substr(v_plan_sha,1,16);
  v_producer := 'EXEC-PE10-ASSESS-PRODUCER-'||substr(v_plan_sha,1,16);
  v_ledger := 'EXEC-PE10-ASSESS-LEDGER-'||substr(v_plan_sha,1,16);

  v_res := public.fn_lf_operation_reserve_execution_v1(
    v_orch,'ORQUESTACION_PIPELINE_LF','PROFILE_ASSESSMENT',v_slug,
    'pe10:assessment:orch:'||v_plan_sha,v_plan_sha,v_orch,null,null,
    jsonb_build_object('schema','LF_PROFILE_ASSESSMENT_ORCH_V1',
      'plan_digest',v_plan_sha,'subject_type','PROFILE_ASSESSMENT',
      'subject_ref',v_slug,'subject_sha256',v_assessment_sha,
      'source_head_sha',v_head,'capability_code','EVIDENCE_LEDGER',
      'production_activation',false));
  IF v_res->>'status' IS DISTINCT FROM 'IN_PROGRESS'
     OR v_res->>'execution_id' IS DISTINCT FROM v_orch
  THEN RAISE EXCEPTION 'PROFILE_ASSESSMENT_ORCHESTRATOR_RESERVE_FAILED:%',v_res; END IF;

  v_res := public.fn_lf_operation_reserve_execution_v1(
    v_producer,'ORQUESTACION_PIPELINE_LF','PROFILE_ASSESSMENT',v_slug,
    'pe10:assessment:producer:'||v_plan_sha,v_plan_sha,v_orch,null,null,
    jsonb_build_object('schema','LF_PROFILE_ASSESSMENT_PRODUCER_V1',
      'orchestrator_execution_id',v_orch,'producer_execution_id',v_producer,
      'plan_digest',v_plan_sha,'capability_code','EVIDENCE_LEDGER',
      'subject_sha256',v_assessment_sha,'source_head_sha',v_head));
  IF v_res->>'status' IS DISTINCT FROM 'IN_PROGRESS'
     OR v_res->>'execution_id' IS DISTINCT FROM v_producer
  THEN RAISE EXCEPTION 'PROFILE_ASSESSMENT_PRODUCER_RESERVE_FAILED:%',v_res; END IF;

  v_res := public.fn_lf_operation_reserve_execution_v1(
    v_ledger,'ORQUESTACION_PIPELINE_LF','PROFILE_ASSESSMENT',v_slug,
    'pe10:assessment:ledger:'||v_plan_sha,v_plan_sha,v_orch,null,null,
    jsonb_build_object('schema','LF_PROFILE_ASSESSMENT_LEDGER_V1',
      'orchestrator_execution_id',v_orch,'producer_execution_id',v_producer,
      'plan_digest',v_plan_sha,'capability_code','EVIDENCE_LEDGER',
      'subject_sha256',v_assessment_sha,'source_head_sha',v_head));
  IF v_res->>'status' IS DISTINCT FROM 'IN_PROGRESS'
     OR v_res->>'execution_id' IS DISTINCT FROM v_ledger
  THEN RAISE EXCEPTION 'PROFILE_ASSESSMENT_LEDGER_RESERVE_FAILED:%',v_res; END IF;

  v_dispatch := public.fn_lf_orchestrator_dispatch_receipt_v1(
    v_orch,v_ledger,'EVIDENCE_LEDGER',v_plan_sha,
    jsonb_build_object('subject_type','PROFILE_ASSESSMENT',
      'subject_ref',v_slug,'subject_sha256',v_assessment_sha,
      'source_head_sha',v_head,'producer_execution_id',v_producer,
      'provider','GITHUB','resolver_id','LF_GITHUB_SOURCE_READBACK_V1'),v_orch);
  IF NOT coalesce((v_dispatch->>'ready')::boolean,false)
  THEN RAISE EXCEPTION 'PROFILE_ASSESSMENT_LEDGER_DISPATCH_FAILED:%',v_dispatch; END IF;
  v_bind := public.fn_lf_capability_bind_from_orchestrator_v1(
    v_ledger,'EVIDENCE_LEDGER',v_current_cap_sha,v_plan_sha,
    (v_dispatch->>'receipt_id')::uuid,v_orch);
  IF NOT coalesce((v_bind->>'ready')::boolean,false)
  THEN RAISE EXCEPTION 'PROFILE_ASSESSMENT_LEDGER_BIND_FAILED:%',v_bind; END IF;

  v_anchor := public.fn_lf_evidence_ledger_anchor_v1(
    v_producer,'EVIDENCE_LEDGER','PROFILE_ASSESSMENT_REAL_S26',
    'PROFILE_ASSESSMENT_RESULT','PROFILE_ASSESSMENT',v_slug,
    v_assessment_sha,v_head,
    'github://cristhianlujan/claude-persona-lf-patch/blob/'||v_head||
     '/profiles/'||v_slug||'/SKILL.md',
    'LF_GITHUB_SOURCE_READBACK_V1','GITHUB',
    'github-api://repos/cristhianlujan/claude-persona-lf-patch@'||v_head||'/actions/runs/39705018628',
    'GITHUB_API_READBACK_PLUS_OFFLINE_HASH','VERIFIED',
    jsonb_build_object(
      'provider_readback_verified',true,
      'digest_recomputed',true,
      'github_commit_provider_readback',true,
      'github_source_blob_readback',v_blob,
      'github_source_sha256',v_source_sha,
      'github_actions_run_id',39705018628,
      'github_actions_status','SUCCESS',
      'assessment_sha256_recomputed_in_sql',true,
      'source_compatibility_count',13,
      'source_compatibility_pass_count',11,
      'nonstructural_domain_skill_claimed',false,
      'independent_method_qualification_claimed',false,
      'production_activation',false),
    jsonb_build_object(
      'schema','LF_PROFILE_ASSESSMENT_REAL_S26_V1',
      'assessment_schema','PROFILE_ASSESSMENT_V1',
      'profile_slug',v_slug,
      'source_head_sha',v_head,
      'source_blob_sha1',v_blob,
      'source_sha256',v_source_sha,
      'assessment_input',v_input,
      'assessment_status','EVIDENCE_SUFFICIENT',
      'evolution_mode','PATCH',
      'structural_decision','UPDATE_REQUIRED',
      's26_score',11,'s26_total',13,
      'failed_dimensions',jsonb_build_array('B12_EXECUTION_PARTITION','B13_EXECUTION_BUDGET'),
      'evidence_scope','STRUCTURAL_ONLY',
      'other_dimensions','UNKNOWN',
      'source_only_tests_passed',68,
      'real_assessment_run_id',39705018628,
      'method_execution_permitted',false,
      'cutover_authorized',false,
      'production_activated',false),
    v_ledger);
  v_receipt := (v_anchor->>'receipt_id')::uuid;

  IF v_receipt IS NULL
     OR NOT EXISTS(
       SELECT 1 FROM private.lf_evidence_ledger_v1 l
       WHERE l.receipt_id=v_receipt AND l.execution_id=v_producer
         AND l.created_by_execution_id=v_ledger
         AND l.subject_type='PROFILE_ASSESSMENT' AND l.subject_ref=v_slug
         AND l.subject_sha256=v_assessment_sha AND l.source_head_sha=v_head
         AND l.verification_state='VERIFIED'
         AND l.resolver_id='LF_GITHUB_SOURCE_READBACK_V1'
         AND l.provider='GITHUB'
         AND l.receipt_payload->>'evolution_mode'='PATCH'
         AND l.receipt_payload->>'production_activated'='false'
     )
     OR public.lf_profile_update_verified_receipt_v1(
       'PROFILE_ASSESSMENT',v_slug,v_receipt::text,v_assessment_sha,v_head) IS DISTINCT FROM true
     OR public.lf_profile_update_verified_receipt_v1(
       'PROFILE_ASSESSMENT',v_slug,v_receipt::text,repeat('0',64),v_head) IS NOT false
     OR public.lf_profile_update_verified_receipt_v1(
       'PROFILE_ASSESSMENT',v_slug,v_receipt::text,v_assessment_sha,repeat('0',40)) IS NOT false
  THEN RAISE EXCEPTION 'PROFILE_ASSESSMENT_RECEIPT_READBACK_FAILED'; END IF;
  IF (SELECT version FROM public.lf_operation_registry
       WHERE operation_code='ACTUALIZACION_PERFIL_LF') IS DISTINCT FROM 'v0.1'
     OR (SELECT count(*) FROM public.lf_operation_steps
         WHERE operation_code='ACTUALIZACION_PERFIL_LF'
           AND step_order IN (35,37) AND active)<>0
  THEN RAISE EXCEPTION 'PROFILE_ASSESSMENT_PRODUCTION_CHANGED'; END IF;
END
$assessment$;
COMMIT;
