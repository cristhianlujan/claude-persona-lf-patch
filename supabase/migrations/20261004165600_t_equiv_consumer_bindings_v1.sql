-- T-EQUIV / PAULO-034 — guarded consumer binding proofs.
-- Proves IG/M7.8 and one non-IG consumer. No consumer logic or runtime execution is performed.

DO $bindings$
DECLARE
  v_capability constant text := 'CONTROL_EQUIVALENCE_JUDGE';
  v_version text;
  v_manifest_sha text;
  v_plan_digest text;
  v_request_sha text;
  v_orch jsonb;
  v_consumer jsonb;
  v_receipt jsonb;
  v_receipt_id uuid;
  v_bind jsonb;
BEGIN
  SELECT version,manifest_sha256 INTO v_version,v_manifest_sha
  FROM public.lf_capability_current
  WHERE capability_code=v_capability;
  IF NOT FOUND OR v_version<>'1.0.0' OR v_manifest_sha !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'BLOCK_T_EQUIV_CAPABILITY_NOT_CURRENT';
  END IF;

  -- IG consumer proof: M7.8 exact cached/non-cached parity.
  v_plan_digest:=encode(extensions.digest(convert_to('IG_CURATOR_VALIDATOR_REFACTOR_V2:M7.8|CONTROL_EQUIVALENCE_JUDGE|EXACT_ONLY','UTF8'),'sha256'),'hex');
  v_request_sha:=encode(extensions.digest(convert_to('T-EQUIV-IG-M7-8-20261004-V1','UTF8'),'sha256'),'hex');

  v_orch:=public.fn_lf_operation_reserve_execution_v1(
    'T-EQUIV-ORCH-IG-M7-8-20261004-V1','ORQUESTACION_PIPELINE_LF',
    'ENGINEERING_PLAN_UNIT_BINDING_PROOF','IG_CURATOR_VALIDATOR_REFACTOR_V2:M7.8',
    't-equiv-orch-ig-m7-8-20261004-v1',v_request_sha,'T-EQUIV-ORCH-IG-M7-8-20261004-V1',
    NULL,NULL,
    jsonb_build_object('purpose','T_EQUIV_IG_BINDING_PROOF','consumer_unit','M7.8','capability_code',v_capability,'policy_mode','EXACT_ONLY_ALL_DIVERGENCE_BLOCKS','effects_executed',false)
  );
  IF coalesce(v_orch->>'result','') NOT IN ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION') THEN
    RAISE EXCEPTION 'BLOCK_T_EQUIV_IG_ORCH_RESERVE:%',v_orch::text;
  END IF;

  v_consumer:=public.fn_lf_operation_reserve_execution_v1(
    'T-EQUIV-IG-M7-8-20261004-V1','GITHUB_CONTRACT_GATE_LF',
    'ENGINEERING_PLAN_UNIT_BINDING_PROOF','IG_CURATOR_VALIDATOR_REFACTOR_V2:M7.8',
    't-equiv-ig-m7-8-20261004-v1',v_request_sha,'T-EQUIV-ORCH-IG-M7-8-20261004-V1',
    NULL,NULL,
    jsonb_build_object('orchestrator_execution_id','T-EQUIV-ORCH-IG-M7-8-20261004-V1','plan_digest',v_plan_digest,'capability_code',v_capability,'consumer_plan','IG_CURATOR_VALIDATOR_REFACTOR_V2','consumer_unit','M7.8','policy_mode','EXACT_ONLY_ALL_DIVERGENCE_BLOCKS','effects_executed',false)
  );
  IF coalesce(v_consumer->>'result','') NOT IN ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION') THEN
    RAISE EXCEPTION 'BLOCK_T_EQUIV_IG_CONSUMER_RESERVE:%',v_consumer::text;
  END IF;

  v_receipt:=public.fn_lf_orchestrator_dispatch_receipt_v1(
    'T-EQUIV-ORCH-IG-M7-8-20261004-V1','T-EQUIV-IG-M7-8-20261004-V1',v_capability,v_plan_digest,
    jsonb_build_object('consumer_plan','IG_CURATOR_VALIDATOR_REFACTOR_V2','consumer_unit','M7.8','purpose','BINDING_PROOF_ONLY','policy_mode','EXACT_ONLY_ALL_DIVERGENCE_BLOCKS','effects_executed',false),
    'T-EQUIV-ORCH-IG-M7-8-20261004-V1'
  );
  IF coalesce((v_receipt->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_EQUIV_IG_DISPATCH:%',v_receipt::text;
  END IF;
  v_receipt_id:=(v_receipt->>'receipt_id')::uuid;

  v_bind:=public.fn_lf_capability_bind_from_orchestrator_v1(
    'T-EQUIV-IG-M7-8-20261004-V1',v_capability,v_manifest_sha,v_plan_digest,v_receipt_id,'T-EQUIV-IG-M7-8-20261004-V1'
  );
  IF coalesce((v_bind->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_EQUIV_IG_BIND:%',v_bind::text;
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM public.lf_capability_binding b JOIN public.lf_capability_current c USING(capability_code)
    WHERE b.execution_id='T-EQUIV-IG-M7-8-20261004-V1' AND b.capability_code=v_capability
      AND b.binding_state='BOUND' AND b.bound_version=c.version AND b.bound_manifest_sha256=c.manifest_sha256
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_EQUIV_IG_BIND_READBACK';
  END IF;

  UPDATE public.lf_operation_execution
  SET status='COMPLETED',completed_at=coalesce(completed_at,clock_timestamp()),
      checkpoint_payload=jsonb_build_object('schema_version','LF_T_EQUIV_BINDING_PROOF_V1','consumer_plan','IG_CURATOR_VALIDATOR_REFACTOR_V2','consumer_unit','M7.8','capability_code',v_capability,'bound_version',v_version,'bound_manifest_sha256',v_manifest_sha,'policy_mode','EXACT_ONLY_ALL_DIVERGENCE_BLOCKS','dispatch_receipt_id',v_receipt_id,'effects_executed',false),
      updated_by_execution_id='T-EQUIV-IG-M7-8-20261004-V1',updated_at=clock_timestamp()
  WHERE execution_id='T-EQUIV-IG-M7-8-20261004-V1';

  UPDATE public.lf_operation_execution
  SET status='COMPLETED',completed_at=coalesce(completed_at,clock_timestamp()),
      checkpoint_payload=jsonb_build_object('schema_version','LF_T_EQUIV_ORCHESTRATION_PROOF_V1','consumer_execution_id','T-EQUIV-IG-M7-8-20261004-V1','capability_code',v_capability,'dispatch_receipt_id',v_receipt_id,'effects_executed',false),
      updated_by_execution_id='T-EQUIV-ORCH-IG-M7-8-20261004-V1',updated_at=clock_timestamp()
  WHERE execution_id='T-EQUIV-ORCH-IG-M7-8-20261004-V1';

  -- Independent non-IG consumer proof. Consumer owns its D2 meaning.
  v_plan_digest:=encode(extensions.digest(convert_to('NON_IG:OPS_CONFIG_EQUIVALENCE_FIXTURE|CONTROL_EQUIVALENCE_JUDGE|D2_CONSUMER_POLICY','UTF8'),'sha256'),'hex');
  v_request_sha:=encode(extensions.digest(convert_to('T-EQUIV-NONIG-OPS-CONFIG-20261004-V1','UTF8'),'sha256'),'hex');

  v_orch:=public.fn_lf_operation_reserve_execution_v1(
    'T-EQUIV-ORCH-NONIG-OPS-CONFIG-20261004-V1','ORQUESTACION_PIPELINE_LF',
    'CAPABILITY_CONSUMER_BINDING_PROOF','NON_IG:OPS_CONFIG_EQUIVALENCE_FIXTURE',
    't-equiv-orch-nonig-ops-config-20261004-v1',v_request_sha,'T-EQUIV-ORCH-NONIG-OPS-CONFIG-20261004-V1',
    NULL,NULL,
    jsonb_build_object('purpose','T_EQUIV_NON_IG_BINDING_PROOF','consumer_ref','NON_IG:OPS_CONFIG_EQUIVALENCE_FIXTURE','capability_code',v_capability,'policy_mode','CONSUMER_DECLARED_D2','effects_executed',false)
  );
  IF coalesce(v_orch->>'result','') NOT IN ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION') THEN
    RAISE EXCEPTION 'BLOCK_T_EQUIV_NONIG_ORCH_RESERVE:%',v_orch::text;
  END IF;

  v_consumer:=public.fn_lf_operation_reserve_execution_v1(
    'T-EQUIV-NONIG-OPS-CONFIG-20261004-V1','GITHUB_CONTRACT_GATE_LF',
    'CAPABILITY_CONSUMER_BINDING_PROOF','NON_IG:OPS_CONFIG_EQUIVALENCE_FIXTURE',
    't-equiv-nonig-ops-config-20261004-v1',v_request_sha,'T-EQUIV-ORCH-NONIG-OPS-CONFIG-20261004-V1',
    NULL,NULL,
    jsonb_build_object('orchestrator_execution_id','T-EQUIV-ORCH-NONIG-OPS-CONFIG-20261004-V1','plan_digest',v_plan_digest,'capability_code',v_capability,'consumer_ref','NON_IG:OPS_CONFIG_EQUIVALENCE_FIXTURE','policy_mode','CONSUMER_DECLARED_D2','effects_executed',false)
  );
  IF coalesce(v_consumer->>'result','') NOT IN ('RESERVED_NEW_EXECUTION','REPLAY_EXISTING_EXECUTION') THEN
    RAISE EXCEPTION 'BLOCK_T_EQUIV_NONIG_CONSUMER_RESERVE:%',v_consumer::text;
  END IF;

  v_receipt:=public.fn_lf_orchestrator_dispatch_receipt_v1(
    'T-EQUIV-ORCH-NONIG-OPS-CONFIG-20261004-V1','T-EQUIV-NONIG-OPS-CONFIG-20261004-V1',v_capability,v_plan_digest,
    jsonb_build_object('consumer_ref','NON_IG:OPS_CONFIG_EQUIVALENCE_FIXTURE','purpose','BINDING_PROOF_ONLY','policy_mode','CONSUMER_DECLARED_D2','effects_executed',false),
    'T-EQUIV-ORCH-NONIG-OPS-CONFIG-20261004-V1'
  );
  IF coalesce((v_receipt->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_EQUIV_NONIG_DISPATCH:%',v_receipt::text;
  END IF;
  v_receipt_id:=(v_receipt->>'receipt_id')::uuid;

  v_bind:=public.fn_lf_capability_bind_from_orchestrator_v1(
    'T-EQUIV-NONIG-OPS-CONFIG-20261004-V1',v_capability,v_manifest_sha,v_plan_digest,v_receipt_id,'T-EQUIV-NONIG-OPS-CONFIG-20261004-V1'
  );
  IF coalesce((v_bind->>'ready')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'BLOCK_T_EQUIV_NONIG_BIND:%',v_bind::text;
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM public.lf_capability_binding b JOIN public.lf_capability_current c USING(capability_code)
    WHERE b.execution_id='T-EQUIV-NONIG-OPS-CONFIG-20261004-V1' AND b.capability_code=v_capability
      AND b.binding_state='BOUND' AND b.bound_version=c.version AND b.bound_manifest_sha256=c.manifest_sha256
  ) THEN
    RAISE EXCEPTION 'BLOCK_T_EQUIV_NONIG_BIND_READBACK';
  END IF;

  UPDATE public.lf_operation_execution
  SET status='COMPLETED',completed_at=coalesce(completed_at,clock_timestamp()),
      checkpoint_payload=jsonb_build_object('schema_version','LF_T_EQUIV_BINDING_PROOF_V1','consumer_ref','NON_IG:OPS_CONFIG_EQUIVALENCE_FIXTURE','capability_code',v_capability,'bound_version',v_version,'bound_manifest_sha256',v_manifest_sha,'policy_mode','CONSUMER_DECLARED_D2','dispatch_receipt_id',v_receipt_id,'effects_executed',false),
      updated_by_execution_id='T-EQUIV-NONIG-OPS-CONFIG-20261004-V1',updated_at=clock_timestamp()
  WHERE execution_id='T-EQUIV-NONIG-OPS-CONFIG-20261004-V1';

  UPDATE public.lf_operation_execution
  SET status='COMPLETED',completed_at=coalesce(completed_at,clock_timestamp()),
      checkpoint_payload=jsonb_build_object('schema_version','LF_T_EQUIV_ORCHESTRATION_PROOF_V1','consumer_execution_id','T-EQUIV-NONIG-OPS-CONFIG-20261004-V1','capability_code',v_capability,'dispatch_receipt_id',v_receipt_id,'effects_executed',false),
      updated_by_execution_id='T-EQUIV-ORCH-NONIG-OPS-CONFIG-20261004-V1',updated_at=clock_timestamp()
  WHERE execution_id='T-EQUIV-ORCH-NONIG-OPS-CONFIG-20261004-V1';
END
$bindings$;
