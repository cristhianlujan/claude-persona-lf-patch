-- M7.10: bridge the actual deployed Validator RPC as well as the newer handoff
-- entrypoint. No Edge redeploy and no duplicate finalization.
CREATE OR REPLACE FUNCTION programacion.fn_ig_graph_finalize_validator_result_v1(
  p_run_id bigint,p_validator_identity text,p_result jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog,programacion,public
AS $bridge$
DECLARE v_handoff jsonb;v_graph jsonb;
BEGIN
  IF p_result->>'status' <> 'COMPLETED' THEN
    RETURN p_result;
  END IF;
  -- A new completed run without its persisted Curator receipt is not
  -- eligible for a silently skipped GRAPH_RECEIPT.
  v_handoff:=programacion.fn_input_governance_validator_handoff_assert_v1(p_run_id,NULL);
  v_graph:=programacion.fn_ig_graph_receipt_on_validator_completed_v1(
    p_run_id,p_validator_identity,(v_handoff->>'receipt_id')::bigint);
  IF v_graph->>'status'<>'PASS' THEN
    RAISE EXCEPTION 'IG_GRAPH_RUNTIME_EVIDENCE_NOT_VERIFIED';
  END IF;
  RETURN coalesce(p_result,'{}'::jsonb)||jsonb_build_object(
    'graph_receipts',v_graph);
END $bridge$;
REVOKE ALL ON FUNCTION programacion.fn_ig_graph_finalize_validator_result_v1(bigint,text,jsonb)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_graph_finalize_validator_result_v1(bigint,text,jsonb)
 TO service_role;

-- Legacy deployed Edge calls fn_input_governance_validator_validate_v1 directly.
-- Its COMPLETE result now passes through the common governed finalizer.
CREATE OR REPLACE FUNCTION programacion.fn_input_governance_validator_validate_v1(p_run_id bigint, p_validator_identity text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'programacion'
AS $function$
declare
  v_analysis text;
  v_bootstrap boolean;
  v_status text;
  v_admission jsonb;
  v_result jsonb;
  v_started timestamptz:=clock_timestamp();
  v_completed timestamptz;
  v_route text;
  v_chunk_no integer;
begin
  perform pg_advisory_xact_lock(
    pg_catalog.hashtextextended('IG_VALIDATOR_RUN:'||p_run_id::text,0)
  );

  select r.scope->>'analysis_revision',
         r.supersedes_run_id is null and r.scope->>'mode'='GOVERNED_CANONICAL_BOOTSTRAP_V1',
         r.status
    into v_analysis,v_bootstrap,v_status
  from programacion.input_readiness_runs r
  where r.id=p_run_id
    and r.version_id=public.fn_lf_version_compatibility_current_version_id_v1(
      'PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT'
    );

  if v_status is null then
    raise exception 'INPUT_GOVERNANCE_VALIDATOR_RUN_NOT_FOUND:%',p_run_id;
  end if;

  -- Every repeated chunk and terminal NOOP is re-admitted. CURATING is the first
  -- call; its transition trigger pins the source manifest before validator writes.
  if v_status in ('VALIDATING','COMPLETED') then
    v_admission:=programacion.fn_input_governance_continuation_currentness_v1(p_run_id);
    if not coalesce((v_admission->>'continuation_current')::boolean,false) then
      raise exception 'INPUT_GOVERNANCE_VALIDATOR_CONTINUATION_CURRENTNESS_BLOCKED:%:%',
        p_run_id,coalesce(v_admission->>'code','CURRENTNESS_UNKNOWN');
    end if;
  end if;

  if v_analysis='INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX' then
    v_result:=programacion.fn_input_governance_validate_v2(p_run_id,p_validator_identity);
    return programacion.fn_ig_graph_finalize_validator_result_v1(p_run_id,p_validator_identity,v_result);
  end if;

  if coalesce(v_bootstrap,false) then
    v_route:='BOOTSTRAP_VALIDATE_V1';
    v_result:=programacion.fn_input_governance_bootstrap_validate_v1(p_run_id,p_validator_identity);
  else
    v_route:='VALIDATOR_REBIND_V1';
    v_result:=programacion.fn_input_governance_validator_rebind_v1(p_run_id,p_validator_identity);
  end if;

  v_completed:=clock_timestamp();
  select coalesce(max(chunk_no),0)+1
    into v_chunk_no
  from programacion.input_validator_chunk_timings
  where run_id=p_run_id and validator_identity=p_validator_identity;

  insert into programacion.input_validator_chunk_timings(
    run_id,validator_identity,chunk_no,route,started_at,completed_at,duration_ms,
    result_status,validator_pass_count,family_count,pending_count
  ) values(
    p_run_id,p_validator_identity,v_chunk_no,v_route,v_started,v_completed,
    round(extract(epoch from(v_completed-v_started))*1000)::bigint,
    v_result->>'status',
    nullif(v_result->>'validator_pass_count','')::integer,
    nullif(v_result->>'family_count','')::integer,
    nullif(v_result->>'pending_count','')::integer
  );

  return programacion.fn_ig_graph_finalize_validator_result_v1(p_run_id,p_validator_identity,v_result);
end;
$function$;


-- The newer handoff entrypoint delegates to the same underlying validator
-- and must not issue a second independent dispatch.
CREATE OR REPLACE FUNCTION programacion.fn_input_governance_validator_validate_handoff_v1(p_run_id bigint, p_validator_identity text, p_receipt_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion', 'public'
AS $function$
declare
  v_handoff jsonb;
  v_result jsonb;
begin
  v_handoff:=programacion.fn_input_governance_validator_handoff_assert_v1(p_run_id,p_receipt_id);
  v_result:=programacion.fn_input_governance_validator_validate_v1(p_run_id,p_validator_identity);
  return coalesce(v_result,'{}'::jsonb) || jsonb_build_object('handoff_receipt',v_handoff);
end;
$function$;


DO $assert$
DECLARE a text;
BEGIN
 SELECT pg_get_functiondef(
   'programacion.fn_input_governance_validator_validate_v1(bigint,text)'::regprocedure) INTO a;
 IF position('fn_ig_graph_finalize_validator_result_v1' IN a)=0
    OR position('fn_input_governance_validate_v2' IN a)=0
 THEN RAISE EXCEPTION 'IG_GRAPH_RUNTIME_VALIDATOR_ROUTE_NOT_WIRED'; END IF;
END $assert$;
