-- T-TARGET-EVID / PAULO-186 — IG consumer binding proof for planned consumer N-6.
-- This migration does not execute N-6 and does not copy provider logic.

DO $binding$
DECLARE
  v_orch_id constant text := 'T-TARGET-EVID-ORCH-N6-20261004-V1';
  v_consumer_id constant text := 'T-TARGET-EVID-IG-N6-20261004-V1';
  v_plan_digest constant text := '040091c33e65c29457120474cb8e15d170707e52121385c8205022401e680f26';
  v_orch_request_sha constant text := 'ca57231e4f51b7f8befbbfb44c0373387f4467df2f420ebca9ca5340ebe9101f';
  v_consumer_request_sha constant text := '686f929f91c2d63e0ee4f0c568d11e382f953ef5999b3daff74f75c047f0c472';
  v_manifest_sha text;
  v_version text;
  v_orch jsonb;
  v_consumer jsonb;
  v_receipt jsonb;
  v_receipt_id uuid;
  v_bind jsonb;
BEGIN
  SELECT version,manifest_sha256 INTO v_version,v_manifest_sha
  FROM public.lf_capability_current
  WHERE capability_code='TARGETED_EVIDENCE_ACQUISITION';
  IF NOT FOUND OR v_version<>'1.0.0' OR v_manifest_sha !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'BLOCK_T_TARGET_EVID_BIND_CAPABILITY_NOT_CURRENT';
  END IF;

  v_orch:=public.fn_lf_operation_reserve_execution_v1(
    v_orch_id,'ORQUESTACION_PIPELINE_LF',
    'ENGINEERING_PLAN_UNIT_BINDING_PROOF','IG_CURATOR_VALIDATOR_REFACTOR_V2:N-6',
    't-target-evid-orch-n6-20261004-v1',v_orch_request_sha,v_orch_id,
    NULL,NULL,
    jsonb_build_object('purpose','T_TARGET_EVID_IG_BINDING_PROOF','consumer_unit','N-6','capability_code','TARGETED_EVIDENCE_ACQUISITION','effects_executed',false)
  );
  IF coalesce(v_orch->>'result','') NOT IN ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION') THEN
    RAISE EXCEPTION 'BLOCK_T_TARGET_EVID_BIND_ORCH_RESERVE:%',v_orch::text;
  END IF;

  v_consumer:=public.fn_lf_operation_reserve_execution_v1(
    v_consumer_id,'GITHUB_CONTRACT_GATE_LF',
    'ENGINEERING_PLAN_UNIT_BINDING_PROOF','IG_CURATOR_VALIDATOR_REFACTOR_V2:N-6',
    't-target-evid-ig-n6-20261004-v1',v_consumer_request_sha,v_orch_id,
    NULL,NULL,
    jsonb_build_object('orchestrator_execution_id',v_orch_id,'plan_digest',v_plan_digest,'capability_code','TARGETED_EVIDENCE_ACQUISITION','consumer_plan','IG_CURATOR_VALIDATOR_REFACTOR_V2','consumer_unit','N-6','mode','BINDING_PROOF_ONLY','effects_executed',false)
  );
  IF coalesce(v_consumer->>'result','') NOT IN ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION') THEN
    RAISE EXCEPTION 'BLOCK_T_TARGET_EVID_BIND_CONSUMER_RESERVE:%',v_consumer::text;
  END IF;

  v_receipt:=public.fn_lf_orchestrator_dispatch_receipt_v1(
    v_orch_id,v_consumer_id,'TARGETED_EVIDENCE_ACQUISITION',v_plan_digest,
    jsonb_build_object('consumer_plan','IG_CURATOR_VALIDATOR_REFACTOR_V2','consumer_unit','N-6','purpose','BINDING_PROOF_ONLY','effects_executed',false),
    v_orch_id
  );
  IF coalesce((v_receipt->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_TARGET_EVID_BIND_DISPATCH:%',v_receipt::text;
  END IF;
  v_receipt_id:=(v_receipt->>'receipt_id')::uuid;

  v_bind:=public.fn_lf_capability_bind_from_orchestrator_v1(
    v_consumer_id,'TARGETED_EVIDENCE_ACQUISITION',v_manifest_sha,v_plan_digest,v_receipt_id,v_consumer_id
  );
  IF coalesce((v_bind->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_TARGET_EVID_BIND_GUARDED_BIND:%',v_bind::text;
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM public.lf_capability_binding b JOIN public.lf_capability_current c USING(capability_code)
    WHERE b.execution_id=v_consumer_id AND b.capability_code='TARGETED_EVIDENCE_ACQUISITION'
      AND b.binding_state='BOUND' AND b.bound_version=c.version AND b.bound_manifest_sha256=c.manifest_sha256
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_TARGET_EVID_BIND_EXACT_READBACK_FAILED';
  END IF;

  UPDATE public.lf_operation_execution
  SET status='COMPLETED',completed_at=coalesce(completed_at,clock_timestamp()),
      checkpoint_payload=jsonb_build_object('schema_version','LF_T_TARGET_EVID_BINDING_PROOF_V1','capability_code','TARGETED_EVIDENCE_ACQUISITION','consumer_plan','IG_CURATOR_VALIDATOR_REFACTOR_V2','consumer_unit','N-6','bound_version',v_version,'bound_manifest_sha256',v_manifest_sha,'dispatch_receipt_id',v_receipt_id,'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1','effects_executed',false),
      updated_by_execution_id=v_consumer_id,updated_at=clock_timestamp()
  WHERE execution_id=v_consumer_id;

  UPDATE public.lf_operation_execution
  SET status='COMPLETED',completed_at=coalesce(completed_at,clock_timestamp()),
      checkpoint_payload=jsonb_build_object('schema_version','LF_T_TARGET_EVID_ORCHESTRATION_PROOF_V1','consumer_execution_id',v_consumer_id,'capability_code','TARGETED_EVIDENCE_ACQUISITION','dispatch_receipt_id',v_receipt_id,'effects_executed',false),
      updated_by_execution_id=v_orch_id,updated_at=clock_timestamp()
  WHERE execution_id=v_orch_id;
END
$binding$;