-- Move Card Update controlled-assurance semantics from historical S36 ownership
-- to the existing CARD_OPERATIONS domain owner.
-- EKB:
--   S36-ASSURANCE-BOUNDARY-CONTAMINATION-001
--   CARD-UPDATE-CONTROLLED-ASSURANCE-STALE-EXECUTIONS-001
-- Source-first candidate only. No live apply in this PR.
-- Historical S36 executions are preserved as evidence and may not resume after cutover.

DO $cutover$
DECLARE
  v_oid oid;
  v_def text;
  v_new text;
  v_old text;
  v_count integer;
  v_allowed jsonb;
BEGIN
  -- Fail closed if a legacy Card execution is actively leased. Historical rows with
  -- no active lease remain immutable evidence and are blocked on any later resume.
  IF EXISTS (
    SELECT 1
    FROM public.lf_operation_execution e
    WHERE e.operation_code='ACTUALIZACION_CARD_LF'
      AND e.status='IN_PROGRESS'
      AND (
        coalesce(e.manifest->>'mode','') LIKE 'S36_CONTROLLED_ASSURANCE%'
        OR e.manifest->>'assurance_owner'='S36'
      )
      AND e.lease_owner IS NOT NULL
      AND e.lease_expires_at IS NOT NULL
      AND e.lease_expires_at>now()
  ) THEN
    RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_LEGACY_ACTIVE_LEASE_BLOCKS_CUTOVER';
  END IF;

  SELECT allowed INTO v_allowed
  FROM public.lf_operation_contracts
  WHERE operation_code='ACTUALIZACION_CARD_LF'
    AND contract_code='CONTRACT-ACTUALIZACION-CARD-LF-v0.3'
    AND status='CANDIDATO_READ_ONLY';

  IF v_allowed IS NULL THEN
    RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_CONTRACT_V03_MISSING';
  END IF;
  IF v_allowed->>'expertise_assessment_mode' IS DISTINCT FROM 'INDEPENDENT_HOLDOUT_OR_S36_ASSURANCE'
     OR v_allowed->>'s36_controlled_assurance_mode' IS DISTINCT FROM 'S36_CONTROLLED_ASSURANCE'
     OR v_allowed->>'s36_controlled_assurance_scope' IS DISTINCT FROM 'CARD_UPDATE_I8_PREPROMOTION_E2E'
     OR v_allowed->'s36_controlled_assurance_write' IS DISTINCT FROM 'true'::jsonb THEN
    RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_CONTRACT_PRESTATE_MISMATCH';
  END IF;

  UPDATE public.lf_operation_contracts
  SET allowed = (
      allowed
      - 's36_controlled_assurance_mode'
      - 's36_controlled_assurance_scope'
      - 's36_controlled_assurance_write'
      - 's36_controlled_assurance_runtime_activation'
      - 's36_controlled_assurance_promotion_authorized'
      - 's36_controlled_assurance_production_activation'
      - 's36_controlled_assurance_requires_exact_readback'
      - 's36_controlled_assurance_requires_exact_rollback'
      - 's36_controlled_assurance_router_activation_authorized'
      - 's36_controlled_assurance_requires_exact_qualifying_receipt'
    )
    || jsonb_build_object(
      'expertise_assessment_mode','INDEPENDENT_HOLDOUT_OR_INDEPENDENT_REVIEW',
      'card_controlled_assurance_mode','CARD_UPDATE_CONTROLLED_ASSURANCE',
      'card_controlled_assurance_scope','CARD_UPDATE_I8_PREPROMOTION_E2E',
      'card_controlled_assurance_owner','CARD_OPERATIONS',
      'card_controlled_assurance_write',true,
      'card_controlled_assurance_runtime_activation',false,
      'card_controlled_assurance_promotion_authorized',false,
      'card_controlled_assurance_production_activation',false,
      'card_controlled_assurance_requires_exact_readback',true,
      'card_controlled_assurance_requires_exact_rollback',true,
      'card_controlled_assurance_router_activation_authorized',false,
      'card_controlled_assurance_requires_exact_qualifying_receipt',true,
      'legacy_s36_execution_policy','BLOCK_REQUIRES_RECONCILIATION'
    ),
      updated_by_execution_id='EXEC-ASSURANCE-REDESIGN-EKB-DB-20260926-001'
  WHERE operation_code='ACTUALIZACION_CARD_LF'
    AND contract_code='CONTRACT-ACTUALIZACION-CARD-LF-v0.3'
    AND status='CANDIDATO_READ_ONLY';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_CONTRACT_UPDATE_MISSING';
  END IF;

  -- New Card controlled-assurance executions are owned by CARD_OPERATIONS.
  v_oid := to_regprocedure('public.lf_card_update_controlled_assurance_begin_v1(text,text,uuid,text,text,text)');
  IF v_oid IS NULL THEN RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_BEGIN_MISSING'; END IF;
  SELECT pg_get_functiondef(v_oid) INTO v_def;
  v_count := (length(v_def)-length(replace(v_def,'S36_CONTROLLED_ASSURANCE','')))/length('S36_CONTROLLED_ASSURANCE');
  IF v_count<>2 THEN RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_BEGIN_MODE_PRESTATE:%',v_count; END IF;
  v_new := replace(v_def,'S36_CONTROLLED_ASSURANCE','CARD_UPDATE_CONTROLLED_ASSURANCE');
  v_old := $$'assurance_owner','S36'$$;
  v_count := (length(v_new)-length(replace(v_new,v_old,'')))/length(v_old);
  IF v_count<>1 THEN RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_BEGIN_OWNER_PRESTATE:%',v_count; END IF;
  v_new := replace(v_new,v_old,$$'assurance_owner','CARD_OPERATIONS'$$);
  v_old := 'Transactional init for S36 controlled Card assurance; no production/runtime/promotion/Router authority.';
  v_count := (length(v_new)-length(replace(v_new,v_old,'')))/length(v_old);
  IF v_count<>1 THEN RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_BEGIN_NOTE_PRESTATE:%',v_count; END IF;
  v_new := replace(v_new,v_old,'Transactional init for CARD_OPERATIONS controlled Card assurance; no production/runtime/promotion/Router authority.');
  EXECUTE v_new;

  -- Wrapper: legacy S36 executions may not progress; new write-phase checks bind Card owner.
  v_oid := to_regprocedure('public.lf_record_card_operation_step_v1(text,text,text,jsonb,text)');
  IF v_oid IS NULL THEN RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_STEP_RECORDER_MISSING'; END IF;
  SELECT pg_get_functiondef(v_oid) INTO v_def;
  v_old := $$  if step_order_now>85 then
    select * into x from public.lf_operation_execution where execution_id=p_execution_id;$$;
  v_count := (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);
  IF v_count<>1 THEN RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_STEP_LEGACY_ANCHOR_PRESTATE:%',v_count; END IF;
  v_new := replace(v_def,v_old,$$  select * into x from public.lf_operation_execution where execution_id=p_execution_id;
  if found and (
       coalesce(x.manifest->>'mode','') like 'S36_CONTROLLED_ASSURANCE%'
       or x.manifest->>'assurance_owner'='S36'
     ) then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_UPDATE_LEGACY_S36_EXECUTION_REQUIRES_RECONCILIATION','durable',false);
  end if;

  if step_order_now>85 then
    select * into x from public.lf_operation_execution where execution_id=p_execution_id;$$);
  v_old := $$(x.manifest->>'mode') is distinct from 'S36_CONTROLLED_ASSURANCE'$$;
  v_count := (length(v_new)-length(replace(v_new,v_old,'')))/length(v_old);
  IF v_count<>1 THEN RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_STEP_MODE_PRESTATE:%',v_count; END IF;
  v_new := replace(v_new,v_old,$$(x.manifest->>'mode') is distinct from 'CARD_UPDATE_CONTROLLED_ASSURANCE'$$);
  v_old := $$(x.manifest->>'assurance_owner') is distinct from 'S36'$$;
  v_count := (length(v_new)-length(replace(v_new,v_old,'')))/length(v_old);
  IF v_count<>1 THEN RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_STEP_OWNER_PRESTATE:%',v_count; END IF;
  v_new := replace(v_new,v_old,$$(x.manifest->>'assurance_owner') is distinct from 'CARD_OPERATIONS'$$);
  EXECUTE v_new;

  -- Step validator: block legacy continuation explicitly, then require Card-owned manifest.
  v_oid := to_regprocedure('public.lf_validate_card_update_step_evidence_v6(text,text,jsonb)');
  IF v_oid IS NULL THEN RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_STEP_VALIDATOR_MISSING'; END IF;
  SELECT pg_get_functiondef(v_oid) INTO v_def;
  v_old := $$  if (x.manifest->>'mode') is distinct from 'S36_CONTROLLED_ASSURANCE'$$;
  v_count := (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);
  IF v_count<>1 THEN RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_VALIDATOR_ANCHOR_PRESTATE:%',v_count; END IF;
  v_new := replace(v_def,v_old,$$  if coalesce(x.manifest->>'mode','') like 'S36_CONTROLLED_ASSURANCE%'
     or x.manifest->>'assurance_owner'='S36' then
    return jsonb_build_object('valid',false,'code','CARD_UPDATE_LEGACY_S36_EXECUTION_REQUIRES_RECONCILIATION','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
  end if;
  if (x.manifest->>'mode') is distinct from 'CARD_UPDATE_CONTROLLED_ASSURANCE'$$);
  v_old := $$(x.manifest->>'assurance_owner') is distinct from 'S36'$$;
  v_count := (length(v_new)-length(replace(v_new,v_old,'')))/length(v_old);
  IF v_count<>1 THEN RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_VALIDATOR_OWNER_PRESTATE:%',v_count; END IF;
  v_new := replace(v_new,v_old,$$(x.manifest->>'assurance_owner') is distinct from 'CARD_OPERATIONS'$$);
  EXECUTE v_new;

  -- Reversible E2E canary: new executions use Card owner; legacy executions block.
  v_oid := to_regprocedure('public.lf_run_card_update_controlled_assurance_e2e_v1(text,text)');
  IF v_oid IS NULL THEN RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_E2E_MISSING'; END IF;
  SELECT pg_get_functiondef(v_oid) INTO v_def;
  v_old := $$  if jsonb_typeof(x.manifest->'controlled_assurance_e2e_receipt')='object' then$$;
  v_count := (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);
  IF v_count<>1 THEN RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_E2E_LEGACY_ANCHOR_PRESTATE:%',v_count; END IF;
  v_new := replace(v_def,v_old,$$  if coalesce(x.manifest->>'mode','') like 'S36_CONTROLLED_ASSURANCE%'
     or x.manifest->>'assurance_owner'='S36' then
    return jsonb_build_object('outcome','BLOCKED','code','CARD_UPDATE_LEGACY_S36_EXECUTION_REQUIRES_RECONCILIATION');
  end if;

  if jsonb_typeof(x.manifest->'controlled_assurance_e2e_receipt')='object' then$$);
  v_count := (length(v_new)-length(replace(v_new,'S36_CONTROLLED_ASSURANCE','')))/length('S36_CONTROLLED_ASSURANCE');
  IF v_count<>3 THEN
    -- Two legacy-block compatibility refs + one remaining operational mode/write-route token
    -- are expected before operational replacement below.
    RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_E2E_MODE_PRESTATE:%',v_count;
  END IF;
  -- Replace only operational exact values; keep legacy compatibility predicate untouched.
  v_new := replace(v_new,$$(x.manifest->>'mode') is distinct from 'S36_CONTROLLED_ASSURANCE'$$,$$(x.manifest->>'mode') is distinct from 'CARD_UPDATE_CONTROLLED_ASSURANCE'$$);
  v_new := replace(v_new,'S36_CONTROLLED_ASSURANCE_SUPABASE_IMMUTABLE_CONTENT_VERSION_INSERT','CARD_UPDATE_CONTROLLED_ASSURANCE_SUPABASE_IMMUTABLE_CONTENT_VERSION_INSERT');
  v_old := $$(x.manifest->>'assurance_owner') is distinct from 'S36'$$;
  v_count := (length(v_new)-length(replace(v_new,v_old,'')))/length(v_old);
  IF v_count<>1 THEN RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_E2E_OWNER_GUARD_PRESTATE:%',v_count; END IF;
  v_new := replace(v_new,v_old,$$(x.manifest->>'assurance_owner') is distinct from 'CARD_OPERATIONS'$$);
  v_old := $$'assurance_owner','S36'$$;
  v_count := (length(v_new)-length(replace(v_new,v_old,'')))/length(v_old);
  IF v_count<>1 THEN RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_E2E_OWNER_METADATA_PRESTATE:%',v_count; END IF;
  v_new := replace(v_new,v_old,$$'assurance_owner','CARD_OPERATIONS'$$);
  v_old := $$'-s36-assurance-'$$;
  v_count := (length(v_new)-length(replace(v_new,v_old,'')))/length(v_old);
  IF v_count<>1 THEN RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_E2E_VERSION_PRESTATE:%',v_count; END IF;
  v_new := replace(v_new,v_old,$$'-card-controlled-assurance-'$$);
  EXECUTE v_new;

  -- Card expertise no longer treats S36 as an assessor/reviewer identity.
  v_oid := to_regprocedure('public.lf_validate_card_expertise_gate_v1(text,text,jsonb)');
  IF v_oid IS NULL THEN RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_EXPERTISE_VALIDATOR_MISSING'; END IF;
  SELECT pg_get_functiondef(v_oid) INTO v_def;
  v_count := (length(v_def)-length(replace(v_def,'S36_ASSURANCE','')))/length('S36_ASSURANCE');
  IF v_count<>2 THEN RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_EXPERTISE_REVIEW_PRESTATE:%',v_count; END IF;
  v_new := replace(v_def,'S36_ASSURANCE','INDEPENDENT_REVIEW');
  EXECUTE v_new;

  -- Contract readback: historical S36 keys are gone from active v0.3 contract.
  SELECT allowed INTO v_allowed
  FROM public.lf_operation_contracts
  WHERE operation_code='ACTUALIZACION_CARD_LF'
    AND contract_code='CONTRACT-ACTUALIZACION-CARD-LF-v0.3'
    AND status='CANDIDATO_READ_ONLY';
  IF v_allowed->>'expertise_assessment_mode' IS DISTINCT FROM 'INDEPENDENT_HOLDOUT_OR_INDEPENDENT_REVIEW'
     OR v_allowed->>'card_controlled_assurance_mode' IS DISTINCT FROM 'CARD_UPDATE_CONTROLLED_ASSURANCE'
     OR v_allowed->>'card_controlled_assurance_owner' IS DISTINCT FROM 'CARD_OPERATIONS'
     OR v_allowed ? 's36_controlled_assurance_mode'
     OR v_allowed ? 's36_controlled_assurance_write' THEN
    RAISE EXCEPTION 'LF_CARD_CONTROLLED_ASSURANCE_CONTRACT_POSTSTATE_MISMATCH';
  END IF;
END
$cutover$;
