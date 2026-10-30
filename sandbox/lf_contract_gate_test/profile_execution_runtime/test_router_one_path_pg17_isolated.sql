-- Isolated PostgreSQL 17.6 ONLY. The candidate migration must already have applied.
-- No Supabase credentials; do not execute against a live database.
DO $verify$
DECLARE
  x text;
BEGIN
  IF (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='lf_router_pipeline_context_profile_admit_v2' and p.provolatile='s') <> 1
  THEN RAISE EXCEPTION 'STAGE06_NOT_STABLE'; END IF;
  IF position('lf_router_profile_execution_after_gate2_v1(' in pg_get_functiondef('public.lf_router_pipeline_context_profile_admit_v2(jsonb,text)'::regprocedure)) > 0
  THEN RAISE EXCEPTION 'STAGE06_STILL_CALLS_LEGACY_WRITER'; END IF;

  FOREACH x IN ARRAY ARRAY[
    'lf_router_pipeline_begin_v1(text)',
    'lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)',
    'lf_router_pipeline_profile_handoff_continue_v1(text,text)',
    'lf_router_profile_execution_after_gate2_v1(jsonb,jsonb,text,text,jsonb,text,text,text)'
  ]
  LOOP
    IF position('write_performed' in pg_get_functiondef(('public.'||x)::regprocedure))=0
       OR position('BLOCKED' in pg_get_functiondef(('public.'||x)::regprocedure))=0
    THEN RAISE EXCEPTION 'LEGACY_ENTRY_NOT_INERT:%',x; END IF;
  END LOOP;
  IF position('GATE2_AUTO_MATERIALIZER' in pg_get_functiondef('public.lf_router_profile_after_selection_v1(jsonb,jsonb)'::regprocedure))>0
  THEN RAISE EXCEPTION 'STILL_ADVERTISES_LEGACY_GATE2'; END IF;
  IF position('profile_execution_begin_from_router_context_v1' in pg_get_functiondef('public.lf_router_profile_after_selection_v1(jsonb,jsonb)'::regprocedure))=0
  THEN RAISE EXCEPTION 'STAGE07_POINTER_MISSING'; END IF;
END $verify$;

-- Inert calls must neither write rows nor raise.
DO $negative$
BEGIN
 IF public.lf_router_pipeline_begin_v1('login B2B')->>'status'<>'BLOCKED'
  OR public.lf_profile_native_bridge_begin_v1('{}'::jsonb,'{}'::jsonb,'GPT_NATIVE',NULL)->>'status'<>'BLOCKED'
  OR public.lf_router_pipeline_profile_handoff_continue_v1('no-execution','GPT_NATIVE')->>'status'<>'BLOCKED'
  OR public.lf_router_profile_execution_after_gate2_v1('{}'::jsonb,'{}'::jsonb,'PRODUCTO','LF','{}'::jsonb,'GPT_NATIVE',NULL,NULL)->>'status'<>'BLOCKED'
 THEN RAISE EXCEPTION 'DEPRECATED_ENTRY_EXECUTED'; END IF;
 IF EXISTS(select 1 from public.lf_operation_execution)
   OR EXISTS(select 1 from public.lf_operation_execution_steps)
 THEN RAISE EXCEPTION 'UNEXPECTED_WRITES_DURING_NEGATIVES'; END IF;
END $negative$;

-- Only the isolated harness replaces dependencies. Stage 06 under test remains exact.
CREATE OR REPLACE FUNCTION public.lf_router_stage1_validate_v2(j jsonb) RETURNS jsonb
LANGUAGE sql STABLE AS $$ SELECT '{"valid":true}'::jsonb $$;
CREATE OR REPLACE FUNCTION public.lf_router_route_v1(j jsonb, opts jsonb, is_write boolean)
RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT '{"profile_selection_request":{"schema_version":"LF_PROFILE_SELECTOR_SEMANTIC_REQUEST_V1"}}'::jsonb
$$;
CREATE OR REPLACE FUNCTION public.lf_router_route_transition_resolve_v1(j jsonb)
RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT '{"status":"RESOLVED","transition_code":"PROFILE_SELECTION_REQUIRED","next_step":"profile_semantic_selection"}'::jsonb
$$;
CREATE OR REPLACE FUNCTION public.lf_profile_selector_semantic_validate_v1(req jsonb, decision jsonb)
RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT '{"status":"VALID"}'::jsonb $$;
CREATE OR REPLACE FUNCTION public.lf_router_profile_after_selection_v1(p_stage1 jsonb, p_selection_result jsonb)
RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT '{"status":"READY_FOR_GATE2","gate2_request":{"action":"PROFILE_EXECUTION"}}'::jsonb
$$;
CREATE OR REPLACE FUNCTION public.lf_router_profile_gate2_result_from_selection_v1(req jsonb, decision jsonb)
RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT '{"status":"READY","gate2_result":{"decision":"RESOLVED"}}'::jsonb
$$;
CREATE OR REPLACE FUNCTION public.lf_router_profile_execution_handoff_v1(req jsonb, result jsonb, channel text, business text, scope jsonb)
RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT '{"status":"READY","handoff":{"operation_code":"EJECUCION_PERFIL_LF","profile_code":"PERFIL-PRODUCT-DIRECTOR-LF","fingerprint_sha256":"test-fixture-not-authority"}}'::jsonb
$$;
INSERT INTO public.lf_router_action_registry(asset_type,action_code,operation_code,status,write_allowed,requires_existing_target)
VALUES ('PERFIL','PROFILE_EXECUTION','EJECUCION_PERFIL_LF','ACTIVE',false,true);

DO $positive$
DECLARE
  s1 jsonb := '{"schema_version":"LF_ROUTER_STAGE1_V2","texto_original":"Revisar login B2B para identificar las reglas que le faltan","canal_candidato":"PRODUCTO","negocio_codigo":"LF","alcance":{}}';
  selection jsonb := '{"decision":"SELECTED","selected_profile_code":"PERFIL-PRODUCT-DIRECTOR-LF"}';
  route jsonb;
  trans jsonb;
  after_sel jsonb;
  gate jsonb;
  ctx jsonb;
  admitted jsonb;
  blocked jsonb;
BEGIN
 route := public.lf_router_route_v1(s1,'{}'::jsonb,false);
 trans := public.lf_router_route_transition_resolve_v1(route);
 after_sel := public.lf_router_profile_after_selection_v1(s1,selection);
 gate := public.lf_router_profile_gate2_result_from_selection_v1(after_sel->'gate2_request',selection);
 ctx := jsonb_build_object(
   'schema_version','LF_ROUTER_EXECUTION_PIPELINE_V1',
   'status','GATE2_DERIVED_PENDING_GOVERNED_ADMISSION',
   'transport_mode','CONTEXT_TRANSPORT',
   'effect_authority',false,'downstream_execution_allowed',false,
   'stage1_payload',s1,'route_result',route,'transition',trans,
   'semantic_result',selection,'semantic_validation',public.lf_profile_selector_semantic_validate_v1(route->'profile_selection_request',selection),
   'after_selection_result',after_sel,'gate2_derivation',gate);
 admitted := public.lf_router_pipeline_context_profile_admit_v2(ctx,'GPT_NATIVE');
 IF admitted->>'status'<>'PROFILE_HANDOFF_READY'
   OR admitted->>'write_performed'<>'false'
   OR admitted->>'next_action'<>'EJECUCION_PERFIL_LF_BEGIN_REQUIRED'
   OR admitted->'execution_id' IS DISTINCT FROM 'null'::jsonb
 THEN RAISE EXCEPTION 'STAGE06_HANDOFF_INVALID:%',admitted; END IF;

 blocked := public.lf_router_pipeline_context_profile_admit_v2(ctx,'REMOTE_API');
 IF blocked->>'status'<>'BLOCKED'
 THEN RAISE EXCEPTION 'REMOTE_API_NOT_BLOCKED:%',blocked; END IF;
 IF EXISTS(select 1 from public.lf_operation_execution)
   OR EXISTS(select 1 from public.lf_operation_execution_steps)
 THEN RAISE EXCEPTION 'STAGE06_PERFORMED_WRITE'; END IF;
END $positive$;
SELECT 'PASS_ROUTER_ONE_PATH_PG17_ISOLATED' AS result;
