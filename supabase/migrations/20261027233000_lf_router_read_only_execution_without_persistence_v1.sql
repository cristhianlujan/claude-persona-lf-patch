-- ACT-0001: read-only routing without per-request operation-execution writes.
-- One router, two execution authorities: derivation-only versus governed effects.
-- No changes to existing governed writer or to profile Gate2/handoff.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_router_pipeline_read_only_v1(
  p_literal_request text,
  p_stage1 jsonb
) RETURNS jsonb
LANGUAGE plpgsql STABLE
SECURITY INVOKER
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  v_literal text := btrim(coalesce(p_literal_request,''));
  v_validation jsonb;
  v_route jsonb;
  v_transition jsonb;
BEGIN
  IF v_literal='' THEN
    RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_REQUEST_REQUIRED');
  END IF;

  IF p_stage1 IS NULL
     OR jsonb_typeof(p_stage1)<>'object'
     OR p_stage1->>'schema_version'<>'LF_ROUTER_STAGE1_V2'
     OR p_stage1->>'texto_original' IS DISTINCT FROM v_literal
  THEN
    RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','BLOCK_ROUTER_READ_ONLY_STAGE1_REQUEST_MISMATCH',
      'effect_authority',false);
  END IF;

  v_validation := public.lf_router_stage1_validate_v2(p_stage1);
  IF v_validation->>'valid'<>'true' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED','blocking_code','BLOCK_ROUTER_STAGE1_INVALID',
      'stage1_validation',v_validation,'effect_authority',false);
  END IF;

  -- Existing Stage2 performs deterministic derivation and prepares the
  -- existing semantic profile-selection request, without recording a run.
  v_route := public.lf_router_route_v1(p_stage1,'{}'::jsonb,false);
  v_transition := public.lf_router_route_transition_resolve_v1(v_route);

  IF v_transition->>'status'<>'RESOLVED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED','blocking_code','BLOCK_ROUTER_READ_ONLY_TRANSITION_INVALID',
      'stage1_validation',v_validation,
      'stage2_route',v_route,'transition',v_transition,
      'effect_authority',false);
  END IF;

  -- A read-only response is not an authorization receipt. A write/effect
  -- remains on the separate, pre-existing governed execution path.
  RETURN jsonb_build_object(
    'status','READ_ONLY_ROUTE_READY',
    'schema_version','LF_ROUTER_READ_ONLY_ROUTE_V1',
    'router','ACT-0001',
    'request',v_literal,
    'stage1_payload',p_stage1,
    'stage1_validation',v_validation,
    'stage2_route',v_route,
    'transition',v_transition,
    'next_step',v_transition->>'next_step',
    'trace_persistence','NONE',
    'execution_id',NULL,
    'effect_authority',false,
    'downstream_execution_allowed',false,
    'caller_selects_next_step',false
  );
END
$fn$;

-- Deployment guard: read-only entrypoint may never be SECURITY DEFINER
-- or VOLATILE; these enforce the no-internal-writes contract.
DO $guard$
DECLARE v_security_definer boolean; v_volatility char;
BEGIN
 SELECT prosecdef, provolatile INTO v_security_definer,v_volatility
 FROM pg_proc
 WHERE oid='public.lf_router_pipeline_read_only_v1(text,jsonb)'::regprocedure;
 IF v_security_definer OR v_volatility <> 's' THEN
   RAISE EXCEPTION 'ROUTER_READ_ONLY_EXECUTION_CONTRACT_INVALID';
 END IF;
END
$guard$;

COMMIT;
