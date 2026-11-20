-- Issue #3878: SKILL IG is READ_ONLY; exhausted runtime attempts become
-- durable Step40 findings via existing lf_skill_invoke_v1 + profile step writer.
-- No historical run or ticket edit, no new transport, no production grant.
BEGIN;
DO $preimage$ BEGIN
 IF md5(pg_get_functiondef('public.lf_skill_h_input_governance_context_pack_v1(jsonb)'::regprocedure)) <> '6ded239c430e9167f51320bf4ca38b77'
 THEN RAISE EXCEPTION 'SOURCE_STATE_DRIFT:ig_skill_handler'; END IF;
 IF md5(pg_get_functiondef('public.lf_profile_skill_runtime_ticket_issue_v1(text,text,jsonb)'::regprocedure)) <> 'df2d4163aecfb1a68a1df621ee064577'
 THEN RAISE EXCEPTION 'SOURCE_STATE_DRIFT:skill_ticket_issuer'; END IF;
END $preimage$;
CREATE OR REPLACE FUNCTION public.lf_skill_h_input_governance_context_pack_v1(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'programacion'
AS $function$
DECLARE
 v_exec public.lf_operation_execution%rowtype;
 v_ig jsonb; v_runtime text; v_slug text; v_screen integer;
 v_first_ticket_expires timestamptz;
 v_attempts integer; v_consumed integer;
BEGIN
 IF jsonb_typeof(p_input)<>'object' OR
    coalesce(p_input->>'consumer','')<>'CONTEXT_PACK' OR
    coalesce(p_input#>>'{scope,resolution_status}','')<>'RESOLVED' OR
    nullif(p_input->>'execution_id','') IS NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_IG_PROFILE_SCOPE_INVALID');
 END IF;
 SELECT * INTO v_exec FROM public.lf_operation_execution
 WHERE execution_id=p_input->>'execution_id'
   AND operation_code='EJECUCION_PERFIL_LF'
   AND target_type='PERFIL' AND status='IN_PROGRESS';
 IF NOT FOUND OR v_exec.target_code IS DISTINCT FROM p_input->>'profile_code' THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_IG_PARENT_NOT_CURRENT');
 END IF;
 v_ig:=programacion.fn_lf_profile_input_governance_resolve_v1(
   p_input->>'request_text',v_exec.target_code,p_input->'scope','CONTEXT_PACK');
 IF v_ig->>'status'='INPUT_GOVERNANCE_REQUIRED' THEN
   -- Profile IG is an optional READ_ONLY dependency. Two prior ticket
   -- attempts are the hard per-parent bound. Never re-issue endlessly.
   SELECT count(*)::integer, count(*) FILTER (WHERE consumed_at IS NOT NULL)::integer
     INTO v_attempts,v_consumed
   FROM private.lf_profile_skill_runtime_ticket_v1 t
   WHERE t.execution_id=p_input->>'execution_id'
     AND t.skill_code='INPUT_GOVERNANCE_CONTEXT_PACK';
   IF v_attempts>=2 THEN
     RETURN jsonb_build_object(
       'status','BLOCKED',
       'blocking_code','SKILL_IG_RUNTIME_ATTEMPTS_EXHAUSTED_AS_FINDING',
       'skill_code','INPUT_GOVERNANCE_CONTEXT_PACK',
       'input_governance',v_ig||jsonb_build_object(
         'status','BLOCKED','decision','BLOCKED',
         'blocking_code','SKILL_IG_RUNTIME_ATTEMPTS_EXHAUSTED_AS_FINDING',
         'analysis_scope','READ_ONLY_WITH_IG_FINDINGS',
         'promotion_authorized',false,'production_authorized',false),
       'findings',jsonb_build_array(jsonb_build_object(
         'finding_type','IG_RUNTIME_NOT_VERIFIED',
         'attempt_count',v_attempts,'ticket_consumed_count',v_consumed,
         'reason','IG_WORKER_409_401_TIMEOUT_OR_INCOMPLETE',
         'production_authorized',false)),
       'promotion_authorized',false,'production_authorized',false);
   END IF;
   -- The existing profile-owned ticket TTL is the DB-authoritative wait bound,
   -- not a caller-provided timeout. Future tickets cannot extend the first TTL.
   SELECT min(t.expires_at) INTO v_first_ticket_expires
   FROM private.lf_profile_skill_runtime_ticket_v1 t
   WHERE t.execution_id=p_input->>'execution_id'
     AND t.skill_code='INPUT_GOVERNANCE_CONTEXT_PACK';
   IF v_first_ticket_expires IS NOT NULL AND clock_timestamp()>v_first_ticket_expires THEN
     RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','SKILL_IG_RUNTIME_TIMEOUT_AS_FINDING',
        'skill_code','INPUT_GOVERNANCE_CONTEXT_PACK',
        'input_governance',v_ig||jsonb_build_object(
          'status','BLOCKED','decision','BLOCKED',
          'blocking_code','SKILL_IG_RUNTIME_TIMEOUT_AS_FINDING',
          'analysis_scope','READ_ONLY_WITH_IG_FINDINGS',
          'production_authorized',false,'promotion_authorized',false),
        'findings',jsonb_build_array(jsonb_build_object(
           'finding_type','SKILL_RUNTIME_TIMEOUT',
           'skill_code','INPUT_GOVERNANCE_CONTEXT_PACK',
           'source_run_status',v_ig->>'status',
           'first_ticket_expiry',v_first_ticket_expires)),
        'production_authorized',false,'promotion_authorized',false);
   END IF;
   SELECT c.especificacion->>'runtime_orchestrator' INTO v_runtime
   FROM programacion.contratos c JOIN programacion.versiones_agente v ON v.id=c.version_id
   JOIN programacion.agentes a ON a.id=v.agente_id
   WHERE a.agente_codigo='INPUT_GOVERNANCE_AGENT'
     AND c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
     AND c.estado='defined' AND c.fail_closed
   ORDER BY c.version_id DESC LIMIT 1;
   v_slug:=split_part(coalesce(v_runtime,''),':',2);
   v_screen:=(v_ig->>'pantalla_id')::integer;
   IF coalesce(v_runtime,'') NOT LIKE 'SUPABASE_EDGE_FUNCTION:%'
     OR v_slug !~ '^[a-z0-9][a-z0-9-]{0,62}$'
     OR v_screen IS NULL OR v_screen<1 THEN
       RETURN jsonb_build_object('status','BLOCKED',
         'blocking_code','SKILL_IG_RUNTIME_CONTRACT_INVALID','findings',jsonb_build_array(v_ig));
   END IF;
   RETURN jsonb_build_object('status','RUNTIME_REQUIRED','skill_code','INPUT_GOVERNANCE_CONTEXT_PACK',
     'runtime_request',jsonb_build_object(
       'transport','DIRECT_EDGE_INVOCATION','runtime_slug',v_slug,
       'legacy_ticket_adapter','INPUT_GOVERNANCE_CONTEXT_PACK_V1',
       'request_body',jsonb_build_object('pantalla_id',v_screen,'consumer','CONTEXT_PACK'),
       'terminal_statuses',jsonb_build_array('READY','BLOCKED','HUMAN_DECISION_REQUIRED'),
       'continuation_statuses',jsonb_build_array('VALIDATOR_RESUME_REQUIRED'),
       'queue_required',false,'polling_required',false),
     'input_governance',v_ig,'production_authorized',false);
 END IF;
 RETURN jsonb_build_object('status',coalesce(v_ig->>'status','BLOCKED'),
   'blocking_code',v_ig->>'blocking_code',
   'input_governance',v_ig,
   'findings',CASE WHEN v_ig->>'status'='BLOCKED' THEN jsonb_build_array(v_ig)
       ELSE '[]'::jsonb END,
   'production_authorized',false,'promotion_authorized',false);
END
$function$;
CREATE OR REPLACE FUNCTION public.lf_profile_skill_runtime_ticket_issue_v1(p_execution_id text, p_skill_code text, p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'extensions'
AS $function$
DECLARE
 v_e public.lf_operation_execution%rowtype;
 v_plan jsonb;v_invoked jsonb;v_req jsonb;
 v_catalog_runtime_slug text;
 v_id uuid:=extensions.gen_random_uuid();
 v_exp timestamptz:=clock_timestamp()+interval '5 minutes';
 v_screen integer;
 v_existing_tickets integer;
BEGIN
 IF jsonb_typeof(p_input)<>'object'
   OR p_input->>'execution_id' IS DISTINCT FROM p_execution_id THEN
  RETURN jsonb_build_object('status','BLOCKED','code','SKILL_TICKET_INPUT_INVALID');
 END IF;
 SELECT * INTO v_e FROM public.lf_operation_execution e
 WHERE e.execution_id=p_execution_id AND e.operation_code='EJECUCION_PERFIL_LF'
   AND e.target_type='PERFIL' AND e.status='IN_PROGRESS';
 IF NOT FOUND OR p_input->>'profile_code' IS DISTINCT FROM v_e.target_code THEN
  RETURN jsonb_build_object('status','BLOCKED','code','SKILL_TICKET_PARENT_INVALID');
 END IF;
 v_plan:=public.lf_profile_execution_plan_v1(v_e.target_code,
   v_e.manifest#>>'{router_profile_handoff,channel}',NULL);
 IF v_plan->>'status'<>'READY' OR NOT EXISTS(
    SELECT 1 FROM jsonb_array_elements(v_plan->'skills') sk
    WHERE sk->>'skill_code'=p_skill_code AND sk->>'effect'='READ_ONLY'
 ) THEN RETURN jsonb_build_object(
   'status','BLOCKED','code','SKILL_TICKET_NOT_POLICY_SELECTED'); END IF;
 v_invoked:=public.lf_profile_skill_invoke_selected_v1(
    p_execution_id,v_e.manifest#>>'{router_profile_handoff,channel}',
    p_skill_code,p_input,NULL);
 v_req:=v_invoked->'runtime_request';
 SELECT c.runtime_slug INTO v_catalog_runtime_slug FROM public.lf_skill_catalog_v1 c
 WHERE c.skill_code=p_skill_code AND c.status='READY' AND c.effect='READ_ONLY';
 IF coalesce(v_catalog_runtime_slug,'') !~ '^[a-z0-9][a-z0-9-]{0,62}$'
 OR v_catalog_runtime_slug IS DISTINCT FROM v_req->>'runtime_slug' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','SKILL_RUNTIME_CATALOG_SLUG_MISMATCH');
 END IF;
 IF v_invoked->>'status'<>'RUNTIME_REQUIRED'
    OR v_req->>'transport'<>'DIRECT_EDGE_INVOCATION'
    OR coalesce(v_req->>'runtime_slug','') !~ '^[a-z0-9][a-z0-9-]{0,62}$'
    OR jsonb_typeof(v_req->'request_body')<>'object' THEN
    RETURN jsonb_build_object('status','BLOCKED','code','SKILL_TICKET_RUNTIME_NOT_ATTESTED',
      'skill_status',v_invoked->>'status');
 END IF;
 -- Strong DB-side bound and serialized ticket issue: no third ticket,
 -- including retries racing across native clients for the same RUN.
 PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('LF_PROFILE_SKILL_TICKET_CAP:'||
       p_execution_id||':'||p_skill_code,0));
 SELECT count(*)::integer INTO v_existing_tickets
 FROM private.lf_profile_skill_runtime_ticket_v1
 WHERE execution_id=p_execution_id AND skill_code=p_skill_code;
 IF v_existing_tickets>=2 THEN
   RETURN jsonb_build_object('status','BLOCKED',
     'code','SKILL_RUNTIME_TICKET_CAP_EXHAUSTED',
     'attempt_count',v_existing_tickets,'production_authorized',false);
 END IF;
 INSERT INTO private.lf_profile_skill_runtime_ticket_v1(
   ticket_id,execution_id,skill_code,runtime_slug,request_body,
   request_sha256,expires_at
 ) VALUES (
   v_id,p_execution_id,p_skill_code,v_req->>'runtime_slug',v_req->'request_body',
   encode(extensions.digest(convert_to(p_input::text,'UTF8'),'sha256'),'hex'),v_exp
 );
 IF v_req->>'legacy_ticket_adapter'='INPUT_GOVERNANCE_CONTEXT_PACK_V1' THEN
   v_screen:=nullif(v_req#>>'{request_body,pantalla_id}','')::integer;
   IF p_skill_code<>'INPUT_GOVERNANCE_CONTEXT_PACK'
     OR v_screen IS NULL OR v_screen<1
     OR v_req#>>'{request_body,consumer}'<>'CONTEXT_PACK' THEN
     RAISE EXCEPTION 'SKILL_IG_ADAPTER_SCOPE_INVALID';
   END IF;
   INSERT INTO private.lf_profile_input_governance_runtime_ticket_v1(
     ticket_id,execution_id,pantalla_id,consumer,
     router_handoff_fingerprint,expires_at
   ) VALUES(
     v_id,p_execution_id,v_screen,'CONTEXT_PACK',
     v_e.manifest#>>'{router_profile_handoff,fingerprint_sha256}',v_exp
   );
 END IF;
 RETURN jsonb_build_object('status','AUTHORIZED','ticket',v_id::text,
   'execution_id',p_execution_id,'skill_code',p_skill_code,
   'runtime_slug',v_req->>'runtime_slug',
   'expires_at',v_exp,'transport','DIRECT_EDGE_INVOCATION');
END
$function$;
COMMIT;
