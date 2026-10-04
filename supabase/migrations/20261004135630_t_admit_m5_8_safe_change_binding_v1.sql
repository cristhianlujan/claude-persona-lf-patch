-- T-ADMIT / PAULO-185 — IG consumer binding proof for planned consumer M5.8.
-- This migration does not execute M5.8 and does not copy SAFE_CHANGE_ADMISSION logic.
-- It uses the existing orchestrator dispatch receipt + guarded capability binder.

DO $binding$
DECLARE
  v_orch_id constant text := 'T-ADMIT-ORCH-M5-8-20261004-V1';
  v_consumer_id constant text := 'T-ADMIT-IG-M5-8-20261004-V1';
  v_plan_digest constant text := '1fde9e92637befc0c6ec8c4f2b852648ff80d82cd81bee010e85aedb1ebecb36';
  v_orch_request_sha constant text := 'c2742c30b8455909a3f9fb6d3b00f67210ef862011db46bf35bb21204c7ba3f5';
  v_consumer_request_sha constant text := '17e8fc1579348b72f891ba98815a7c56958a6f6aea1ee501a31d4211a970bd6b';
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
  WHERE capability_code='SAFE_CHANGE_ADMISSION';
  IF NOT FOUND OR v_version<>'1.0.0' OR v_manifest_sha !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_BIND_SAFE_CHANGE_NOT_CURRENT';
  END IF;

  v_orch:=public.fn_lf_operation_reserve_execution_v1(
    v_orch_id,'ORQUESTACION_PIPELINE_LF',
    'ENGINEERING_PLAN_UNIT_BINDING_PROOF','IG_CURATOR_VALIDATOR_REFACTOR_V2:M5.8',
    't-admit-orch-m5-8-20261004-v1',v_orch_request_sha,v_orch_id,
    NULL,NULL,
    jsonb_build_object(
      'purpose','T_ADMIT_IG_BINDING_PROOF',
      'consumer_unit','M5.8',
      'capability_code','SAFE_CHANGE_ADMISSION',
      'effects_executed',false
    )
  );
  IF coalesce(v_orch->>'result','') NOT IN ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION') THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_BIND_ORCH_RESERVE:%',v_orch::text;
  END IF;

  v_consumer:=public.fn_lf_operation_reserve_execution_v1(
    v_consumer_id,'GITHUB_CONTRACT_GATE_LF',
    'ENGINEERING_PLAN_UNIT_BINDING_PROOF','IG_CURATOR_VALIDATOR_REFACTOR_V2:M5.8',
    't-admit-ig-m5-8-20261004-v1',v_consumer_request_sha,v_orch_id,
    NULL,NULL,
    jsonb_build_object(
      'orchestrator_execution_id',v_orch_id,
      'plan_digest',v_plan_digest,
      'capability_code','SAFE_CHANGE_ADMISSION',
      'consumer_plan','IG_CURATOR_VALIDATOR_REFACTOR_V2',
      'consumer_unit','M5.8',
      'mode','BINDING_PROOF_ONLY',
      'effects_executed',false
    )
  );
  IF coalesce(v_consumer->>'result','') NOT IN ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION') THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_BIND_CONSUMER_RESERVE:%',v_consumer::text;
  END IF;

  IF NOT EXISTS(SELECT 1 FROM public.lf_operation_execution WHERE execution_id=v_orch_id AND status='IN_PROGRESS')
     OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution WHERE execution_id=v_consumer_id AND status='IN_PROGRESS') THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_BIND_EXECUTION_NOT_ACTIVE';
  END IF;

  v_receipt:=public.fn_lf_orchestrator_dispatch_receipt_v1(
    v_orch_id,v_consumer_id,'SAFE_CHANGE_ADMISSION',v_plan_digest,
    jsonb_build_object(
      'consumer_plan','IG_CURATOR_VALIDATOR_REFACTOR_V2',
      'consumer_unit','M5.8',
      'purpose','BINDING_PROOF_ONLY',
      'effects_executed',false
    ),
    v_orch_id
  );
  IF coalesce((v_receipt->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_BIND_DISPATCH:%',v_receipt::text;
  END IF;
  v_receipt_id:=(v_receipt->>'receipt_id')::uuid;

  v_bind:=public.fn_lf_capability_bind_from_orchestrator_v1(
    v_consumer_id,'SAFE_CHANGE_ADMISSION',v_manifest_sha,v_plan_digest,v_receipt_id,v_consumer_id
  );
  IF coalesce((v_bind->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_BIND_GUARDED_BIND:%',v_bind::text;
  END IF;

  IF NOT EXISTS(
    SELECT 1
    FROM public.lf_capability_binding b
    JOIN public.lf_capability_current c USING(capability_code)
    WHERE b.execution_id=v_consumer_id
      AND b.capability_code='SAFE_CHANGE_ADMISSION'
      AND b.binding_state='BOUND'
      AND b.bound_version=c.version
      AND b.bound_manifest_sha256=c.manifest_sha256
      AND c.version=v_version
      AND c.manifest_sha256=v_manifest_sha
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_ADMIT_BIND_EXACT_READBACK_FAILED';
  END IF;

  UPDATE public.lf_operation_execution
  SET status='COMPLETED',
      completed_at=coalesce(completed_at,clock_timestamp()),
      checkpoint_payload=jsonb_build_object(
        'schema_version','LF_T_ADMIT_BINDING_PROOF_V1',
        'capability_code','SAFE_CHANGE_ADMISSION',
        'consumer_plan','IG_CURATOR_VALIDATOR_REFACTOR_V2',
        'consumer_unit','M5.8',
        'bound_version',v_version,
        'bound_manifest_sha256',v_manifest_sha,
        'dispatch_receipt_id',v_receipt_id,
        'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
        'effects_executed',false
      ),
      updated_by_execution_id=v_consumer_id,
      updated_at=clock_timestamp()
  WHERE execution_id=v_consumer_id;

  UPDATE public.lf_operation_execution
  SET status='COMPLETED',
      completed_at=coalesce(completed_at,clock_timestamp()),
      checkpoint_payload=jsonb_build_object(
        'schema_version','LF_T_ADMIT_ORCHESTRATION_PROOF_V1',
        'consumer_execution_id',v_consumer_id,
        'capability_code','SAFE_CHANGE_ADMISSION',
        'dispatch_receipt_id',v_receipt_id,
        'effects_executed',false
      ),
      updated_by_execution_id=v_orch_id,
      updated_at=clock_timestamp()
  WHERE execution_id=v_orch_id;
END
$binding$;
