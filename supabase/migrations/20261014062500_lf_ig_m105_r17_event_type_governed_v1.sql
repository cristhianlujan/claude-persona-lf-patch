-- R17 / M10.5 — introduce the exact RUNTIME_PREFLIGHT event type via
-- the existing transversal EVENT_CONTRACT_GOVERNANCE governed request route.
-- This does NOT record an R17 PASS, deploy any Edge Function, promote release,
-- authorize an operator or trigger an IG/CP2 job.
DO $r17_event_type$
DECLARE
  c_event_type constant text := 'RUNTIME_PREFLIGHT';
  c_actor constant text := 'EXEC-IG-M105-R17-EVENT-TYPE-REGISTRY-20261014-001';
  c_contract constant jsonb := jsonb_build_object(
    'active',true,
    'rationale','R17 runtime preflight validation receipt: source/live parity, measured phase timing, rollback or explicit DB N/A, idempotency, and independent closure evidence. PASS only with verified facts, never with a source merge alone.',
    'contract_mode','VALIDATION_ACCEPTANCE',
    'allowed_evidence_schemas',jsonb_build_array('test-evidence/v2')
  );
  v_request bigint;
  v_approval bigint;
  v_hash text;
  v_before bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activos
    WHERE codigo_activo='EVENT_CONTRACT_GOVERNANCE'
      AND estado_operativo='ACTIVO'
      AND metadata#>>'{transversal_inventory,inventory_status}'='ACTIVE_SHARED_ENFORCEMENT'
  ) OR NOT EXISTS (
    SELECT 1 FROM public.lf_prevention_rules
    WHERE regla_codigo='PRV-RUNTIME-CHANGE-PREFLIGHT-GATE-001'
      AND activa=true
      AND regla ILIKE '%RUNTIME_PREFLIGHT%'
  ) THEN
    RAISE EXCEPTION 'R17_EVENT_TYPE_TRANSVERSAL_AUTHORITY_MISSING';
  END IF;

  IF EXISTS (SELECT 1 FROM private.lf_event_type_contracts_v2
             WHERE event_type=c_event_type)
     OR EXISTS (SELECT 1 FROM public.lf_eventos WHERE evento_tipo=c_event_type)
     OR EXISTS (SELECT 1 FROM private.lf_event_type_contract_change_requests_v2
                WHERE event_type=c_event_type)
  THEN RAISE EXCEPTION 'R17_EVENT_TYPE_NOT_NEW_OR_PREEXISTING'; END IF;

  SELECT count(*) INTO v_before FROM private.lf_event_type_contracts_v2;

  v_request := private.fn_create_lf_event_type_contract_request_v2(
    c_event_type,'INSERT',c_contract,c_actor
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
    'Governed approval of the new R17 validation event contract required by the already active prevention rule; this event grants no runtime authorization.',
    'INFO',
    jsonb_build_object(
      'evidence_schema_version','event-type-contract-governance/v1',
      'decision','APPROVED',
      'request_id',v_request,
      'event_type',c_event_type,
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
    WHERE event_type=c_event_type
      AND contract_mode='VALIDATION_ACCEPTANCE'
      AND active=true
      AND governance_state='GOVERNED_V2'
      AND allowed_evidence_schemas=ARRAY['test-evidence/v2']::text[]
      AND last_change_request_id=v_request
      AND last_change_event_id=v_approval
  ) OR (SELECT count(*) FROM private.lf_event_type_contracts_v2) <> v_before+1
    OR EXISTS (SELECT 1 FROM public.lf_eventos WHERE evento_tipo=c_event_type)
  THEN RAISE EXCEPTION 'R17_EVENT_TYPE_REGISTRATION_READBACK_FAILED'; END IF;

  -- Protect the Operations route from accidental activation while R17 is incomplete.
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_registry r
    JOIN public.lf_router_action_registry route USING(operation_code)
    WHERE r.operation_code='DEPLOY_SUPABASE_EDGE_FUNCTION_LF'
      AND r.status='CANDIDATO_READ_ONLY' AND r.lifecycle_state_code='OP_CANDIDATE'
      AND route.write_allowed=false
  ) THEN RAISE EXCEPTION 'R17_EVENT_TYPE_UNEXPECTED_RUNTIME_ACTIVATION'; END IF;
END $r17_event_type$;
