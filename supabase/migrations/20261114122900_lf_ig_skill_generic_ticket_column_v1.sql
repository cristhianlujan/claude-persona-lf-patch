-- LF issue #3876: generic ticket column contract drift (consumer does not exist).
-- Read-only profile, no production authorization; fail closed on function drift.
BEGIN;
DO $preimage$ BEGIN
  IF md5(pg_get_functiondef('public.lf_skill_h_input_governance_context_pack_v1(jsonb)'::regprocedure)) <> '855cde1d7ea6c29392fff374a62f0c83' THEN
    RAISE EXCEPTION 'SOURCE_STATE_DRIFT:lf_skill_h_input_governance_context_pack_v1';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='private' AND table_name='lf_profile_skill_runtime_ticket_v1' AND column_name='skill_code')
     OR EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='private' AND table_name='lf_profile_skill_runtime_ticket_v1' AND column_name='consumer') THEN
    RAISE EXCEPTION 'SKILL_TICKET_SCHEMA_DRIFT';
  END IF;
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
COMMIT;
