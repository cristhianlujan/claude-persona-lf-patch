-- Correct R17 event contract nature before first RUNTIME_PREFLIGHT execution.
-- Operational preflight is a factual, readbackable diagnostic receipt and must
-- NOT reuse skill artifact test-evidence/v2 (which requires lf_skill_artifacts).
-- Final R17 readiness remains governed by the existing Operations step judge.
DO $r17_nature$
DECLARE
  c_event_type constant text := 'RUNTIME_PREFLIGHT';
  c_actor constant text := 'EXEC-IG-M105-R17-EVENT-NATURE-CORRECTION-20261014-001';
  c_contract constant jsonb := jsonb_build_object(
    'active',true,
    'rationale','Operational R17 preflight facts: exact caller source/rollback, measured phased timings, explicit DB-rollback applicability, idempotency plan and currentness, with external artifact references. This receipt never claims PASS or authorizes runtime; existing Operations judges decide readiness.',
    'contract_mode','OPERATIONAL',
    'allowed_evidence_schemas',jsonb_build_array('operational-event/v2')
  );
  v_request bigint;
  v_hash text;
  v_approval bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.v_lf_event_type_contract_audit_v2
    WHERE event_type=c_event_type
      AND contract_mode='VALIDATION_ACCEPTANCE'
      AND allowed_evidence_schemas=ARRAY['test-evidence/v2']::text[]
      AND governance_state='GOVERNED_V2'
      AND contract_version=1
  ) OR EXISTS (SELECT 1 FROM public.lf_eventos WHERE evento_tipo=c_event_type)
  THEN RAISE EXCEPTION 'R17_NATURE_CORRECTION_PRESTATE_DRIFT'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activos
    WHERE codigo_activo='EVENT_CONTRACT_GOVERNANCE'
      AND estado_operativo='ACTIVO'
      AND metadata#>>'{transversal_inventory,inventory_status}'='ACTIVE_SHARED_ENFORCEMENT'
  ) THEN RAISE EXCEPTION 'R17_EVENT_GOVERNANCE_NOT_ACTIVE'; END IF;

  v_request := private.fn_create_lf_event_type_contract_request_v2(
    c_event_type,'UPDATE',c_contract,c_actor
  );
  SELECT proposed_contract_sha256 INTO STRICT v_hash
  FROM private.lf_event_type_contract_change_requests_v2
  WHERE id=v_request AND status='REQUESTED';

  INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,
    payload,origen,created_at,created_by_execution_id
  ) VALUES (
    'EVENT_TYPE_CONTRACT_CHANGE_APPROVED',
    'EVENT_TYPE_CONTRACT',c_event_type,
    'Governed correction of the R17 event nature before any operational event: distinguish factual preflight receipts from Skill artifact acceptance gates; no Edge deploy authority.',
    'INFO',
    jsonb_build_object(
      'evidence_schema_version','event-type-contract-governance/v1',
      'decision','APPROVED',
      'request_id',v_request,'event_type',c_event_type,
      'proposed_contract_sha256',v_hash,
      'approved_at',clock_timestamp(),
      'execution_id',c_actor
    ),
    'DERIVE_FROM_EXECUTION_ID',clock_timestamp(),c_actor
  ) RETURNING id INTO v_approval;

  PERFORM private.fn_approve_lf_event_type_contract_request_v2(v_request,v_approval);
  PERFORM private.fn_apply_lf_event_type_contract_change_v2(v_request);

  IF NOT EXISTS (
    SELECT 1 FROM public.v_lf_event_type_contract_audit_v2
    WHERE event_type=c_event_type AND active=true
      AND contract_version=2
      AND contract_mode='OPERATIONAL'
      AND allowed_evidence_schemas=ARRAY['operational-event/v2']::text[]
      AND governance_state='GOVERNED_V2'
      AND last_change_request_id=v_request
      AND last_change_event_id=v_approval
  ) OR EXISTS (
    SELECT 1 FROM public.lf_eventos WHERE evento_tipo=c_event_type
  ) THEN RAISE EXCEPTION 'R17_NATURE_CORRECTION_READBACK_FAILED'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_registry r
    JOIN public.lf_router_action_registry a USING(operation_code)
    WHERE r.operation_code='DEPLOY_SUPABASE_EDGE_FUNCTION_LF'
      AND r.status='CANDIDATO_READ_ONLY'
      AND r.lifecycle_state_code='OP_CANDIDATE'
      AND a.write_allowed=false
  ) THEN RAISE EXCEPTION 'R17_NATURE_CORRECTION_UNEXPECTED_ACTIVATION'; END IF;
END $r17_nature$;
