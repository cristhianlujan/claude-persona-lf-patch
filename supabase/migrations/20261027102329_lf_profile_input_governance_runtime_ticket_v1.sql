-- LF / Profile Runtime / automatic CONTEXT_PACK authorization ticket.
-- Binds a short-lived, one-use caller ticket to the SAME EJECUCION_PERFIL_LF.
-- No Router re-entry, no SQL queue, no cron, no service-role secret on the profile worker.
BEGIN;

CREATE TABLE IF NOT EXISTS private.lf_profile_input_governance_runtime_ticket_v1 (
  ticket_id uuid PRIMARY KEY,
  execution_id text NOT NULL,
  pantalla_id integer NOT NULL CHECK (pantalla_id > 0),
  consumer text NOT NULL CHECK (consumer = 'CONTEXT_PACK'),
  router_handoff_fingerprint text NOT NULL,
  issued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  consumed_by text,
  CONSTRAINT lf_profile_ig_runtime_ticket_expiry_check
    CHECK (expires_at > issued_at),
  CONSTRAINT lf_profile_ig_runtime_ticket_consumed_check
    CHECK (
      (consumed_at IS NULL AND consumed_by IS NULL)
      OR
      (consumed_at IS NOT NULL AND consumed_by = 'LF_PROFILES_GOVERNANCE_CALLER_V1')
    )
);

REVOKE ALL ON TABLE private.lf_profile_input_governance_runtime_ticket_v1
  FROM PUBLIC, anon, authenticated, service_role;

CREATE INDEX IF NOT EXISTS idx_lf_profile_ig_runtime_ticket_open
  ON private.lf_profile_input_governance_runtime_ticket_v1(execution_id, expires_at)
  WHERE consumed_at IS NULL;

CREATE OR REPLACE FUNCTION public.lf_profile_input_governance_runtime_ticket_issue_v1(
  p_execution_id text,
  p_input_literal text,
  p_input_evidence_ref text,
  p_handoff jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, extensions, programacion
AS $function$
DECLARE
  v_validation jsonb;
  v_request jsonb;
  v_body jsonb;
  v_ticket uuid := extensions.gen_random_uuid();
  v_pantalla_id integer;
  v_expires_at timestamptz := clock_timestamp() + interval '5 minutes';
  v_exists boolean;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_input_literal,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_input_evidence_ref,'')),'') IS NULL
     OR jsonb_typeof(p_handoff) IS DISTINCT FROM 'object'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_IG_RUNTIME_TICKET_INPUT_INVALID'
    );
  END IF;

  SELECT EXISTS(
    SELECT 1
    FROM public.lf_operation_execution e
    WHERE e.execution_id=p_execution_id
      AND e.operation_code='EJECUCION_PERFIL_LF'
      AND e.target_type='PERFIL'
      AND e.status='IN_PROGRESS'
  ) INTO v_exists;

  IF NOT v_exists THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_IG_RUNTIME_EXECUTION_NOT_ACTIVE'
    );
  END IF;

  v_validation := public.lf_profile_execution_input_validate_v1(
    p_execution_id,
    p_input_literal,
    p_input_evidence_ref,
    p_handoff
  );

  IF v_validation->>'status' <> 'INPUT_GOVERNANCE_RUNTIME_REQUIRED'
     OR v_validation->>'next_action' <> 'RUN_INPUT_GOVERNANCE_RUNTIME_AND_RETRY_SAME_NATIVE_BRIDGE_PREPARE'
     OR coalesce((v_validation->>'router_reentry_required')::boolean,true)
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_IG_RUNTIME_NOT_REQUIRED',
      'input_validate_status',v_validation->>'status'
    );
  END IF;

  v_request := v_validation#>'{input_governance,runtime_request}';
  v_body := v_request->'request_body';

  IF jsonb_typeof(v_request) IS DISTINCT FROM 'object'
     OR v_request->>'transport' <> 'DIRECT_EDGE_INVOCATION'
     OR coalesce((v_request->>'queue_required')::boolean,true)
     OR coalesce((v_request->>'polling_required')::boolean,true)
     OR v_request->>'runtime_slug' <> 'input-governance-agent-v1'
     OR jsonb_typeof(v_body) IS DISTINCT FROM 'object'
     OR v_body->>'consumer' <> 'CONTEXT_PACK'
     OR coalesce(v_body->>'pantalla_id','') !~ '^[1-9][0-9]*$'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_IG_RUNTIME_REQUEST_INVALID'
    );
  END IF;

  v_pantalla_id := (v_body->>'pantalla_id')::integer;

  DELETE FROM private.lf_profile_input_governance_runtime_ticket_v1
  WHERE expires_at < clock_timestamp() - interval '1 day';

  INSERT INTO private.lf_profile_input_governance_runtime_ticket_v1(
    ticket_id,
    execution_id,
    pantalla_id,
    consumer,
    router_handoff_fingerprint,
    expires_at
  ) VALUES (
    v_ticket,
    p_execution_id,
    v_pantalla_id,
    'CONTEXT_PACK',
    coalesce(v_validation->>'router_handoff_fingerprint',''),
    v_expires_at
  );

  RETURN jsonb_build_object(
    'status','AUTHORIZED',
    'ticket',v_ticket::text,
    'execution_id',p_execution_id,
    'pantalla_id',v_pantalla_id,
    'consumer','CONTEXT_PACK',
    'transport','DIRECT_EDGE_INVOCATION',
    'expires_at',v_expires_at,
    'queue_required',false,
    'polling_required',false,
    'router_reentry_required',false
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_profile_input_governance_runtime_ticket_issue_v1(
  text,text,text,jsonb
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.lf_profile_input_governance_runtime_ticket_issue_v1(
  text,text,text,jsonb
) TO postgres;

CREATE OR REPLACE FUNCTION public.lf_profile_input_governance_runtime_ticket_consume_v1(
  p_ticket uuid,
  p_execution_id text,
  p_pantalla_id integer,
  p_consumer text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $function$
DECLARE
  v_row private.lf_profile_input_governance_runtime_ticket_v1%rowtype;
BEGIN
  IF p_ticket IS NULL
     OR nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR p_pantalla_id IS NULL OR p_pantalla_id < 1
     OR p_consumer <> 'CONTEXT_PACK'
  THEN
    RETURN jsonb_build_object(
      'authorized',false,
      'code','PROFILE_IG_RUNTIME_TICKET_CONSUME_INPUT_INVALID'
    );
  END IF;

  UPDATE private.lf_profile_input_governance_runtime_ticket_v1 t
  SET consumed_at=clock_timestamp(),
      consumed_by='LF_PROFILES_GOVERNANCE_CALLER_V1'
  WHERE t.ticket_id=p_ticket
    AND t.execution_id=p_execution_id
    AND t.pantalla_id=p_pantalla_id
    AND t.consumer=p_consumer
    AND t.consumed_at IS NULL
    AND t.expires_at > clock_timestamp()
    AND EXISTS(
      SELECT 1
      FROM public.lf_operation_execution e
      WHERE e.execution_id=t.execution_id
        AND e.operation_code='EJECUCION_PERFIL_LF'
        AND e.target_type='PERFIL'
        AND e.status='IN_PROGRESS'
    )
  RETURNING t.* INTO v_row;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'authorized',false,
      'code','PROFILE_IG_RUNTIME_TICKET_INVALID_OR_EXPIRED'
    );
  END IF;

  RETURN jsonb_build_object(
    'authorized',true,
    'execution_id',v_row.execution_id,
    'pantalla_id',v_row.pantalla_id,
    'consumer',v_row.consumer,
    'router_handoff_fingerprint',v_row.router_handoff_fingerprint,
    'consumed_at',v_row.consumed_at
  );
END
$function$;

REVOKE ALL ON FUNCTION public.lf_profile_input_governance_runtime_ticket_consume_v1(
  uuid,text,integer,text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_input_governance_runtime_ticket_consume_v1(
  uuid,text,integer,text
) TO service_role;

COMMENT ON FUNCTION public.lf_profile_input_governance_runtime_ticket_issue_v1(text,text,text,jsonb) IS
'Issues a 5-minute, one-use CONTEXT_PACK ticket only when the same active EJECUCION_PERFIL_LF currently returns INPUT_GOVERNANCE_RUNTIME_REQUIRED.';

COMMENT ON FUNCTION public.lf_profile_input_governance_runtime_ticket_consume_v1(uuid,text,integer,text) IS
'Atomically consumes a Profile Runtime CONTEXT_PACK ticket for lf-profiles-governance-caller-v1; no Router re-entry and no queue transport.';

COMMIT;
