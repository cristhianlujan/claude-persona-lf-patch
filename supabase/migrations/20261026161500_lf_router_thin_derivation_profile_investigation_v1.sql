-- ACT-0001: Router derives; selected profile investigates Product in READ_ONLY mode.
BEGIN;

DO $pre$
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure
     )) <> '318ca19a07d615a729a7666334a98cf0' THEN
    RAISE EXCEPTION 'LF_ROUTER_THIN_ROUTE_SOURCE_DRIFT';
  END IF;
  IF md5(pg_get_functiondef(
       'public.lf_router_product_profile_after_selection_v1(jsonb,jsonb)'::regprocedure
     )) <> 'c2ee5dddc27e4ce636de5c2bf7d0527e' THEN
    RAISE EXCEPTION 'LF_ROUTER_THIN_AFTER_SELECTION_SOURCE_DRIFT';
  END IF;
END
$pre$;

DO $route$
DECLARE
  d text;
  a text;
  b text;
  p1 integer;
  p2 integer;
BEGIN
  d:=pg_get_functiondef(
    'public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure
  );

  IF strpos(d,E'  v_profile_selection_request jsonb;\n  v_pc jsonb;\nBEGIN')=0 THEN
    RAISE EXCEPTION 'LF_ROUTER_THIN_DECL_DRIFT';
  END IF;
  d:=replace(
    d,
    E'  v_profile_selection_request jsonb;\n  v_pc jsonb;\nBEGIN',
    E'  v_profile_selection_request jsonb;\nBEGIN'
  );

  a:=E'    IF v_channel=\'PRODUCTO\' THEN\n      -- Read canonical Product truth before choosing any worker.\n';
  b:=E'\n\n\n\n    -- If no exact aggregate product context is available, preserve the bounded\n';
  p1:=strpos(d,a);
  p2:=strpos(d,b);
  IF p1<=0 OR p2<=p1 THEN
    RAISE EXCEPTION 'LF_ROUTER_THIN_PRODUCT_BLOCK_DRIFT';
  END IF;

  d:=substring(d from 1 for p1-1) || $block$
    IF v_channel='PRODUCTO' THEN
      v_profile_selection_request:=
        public.lf_profile_selector_semantic_prepare_v1(
          p_stage1->>'texto_original'
        );

      RETURN v_base||jsonb_build_object(
        'paso','PRODUCTO_PROFILE_SELECTION_REQUIRED',
        'router_work_mode','DERIVATION_ONLY',
        'canonical_investigation_owner','SELECTED_PROFILE_READ_ONLY',
        'profile_context_hydrator','public.lf_profile_execution_channel_context_v1',
        'profile_selection_request',v_profile_selection_request,
        'profile_selection_result_contract','LF_PROFILE_SELECTOR_SEMANTIC_RESULT_V1',
        'profile_selection_consumer','public.lf_profile_selector_semantic_consume_raw_v1',
        'profile_selection_resume_entrypoint','public.lf_router_product_profile_after_selection_raw_v1',
        'profile_selection_candidate_count',
          (v_profile_selection_request->>'catalog_profile_count')::integer,
        'gate2_after_profile_selection',true,
        'motivo_es','ACT-0001 clasifica y deriva. El perfil seleccionado investiga la fuente canonica en solo lectura.',
        'siguiente_paso_es','Seleccionar un perfil CURRENT y derivar investigacion READ_ONLY; cualquier cambio posterior usa una operacion gobernada separada.',
        'downstream_execution_allowed',false
      );
    END IF;
$block$ || substring(d from p2);

  EXECUTE d;
END
$route$;

DO $after$
DECLARE
  d text;
  p1 integer;
  p2 integer;
BEGIN
  d:=pg_get_functiondef(
    'public.lf_router_product_profile_after_selection_v1(jsonb,jsonb)'::regprocedure
  );

  IF strpos(d,E'  v_profile_action_binding jsonb;\n  v_pc jsonb;\nBEGIN')=0 THEN
    RAISE EXCEPTION 'LF_ROUTER_THIN_AFTER_DECL_DRIFT';
  END IF;
  d:=replace(
    d,
    E'  v_profile_action_binding jsonb;\n  v_pc jsonb;\nBEGIN',
    E'  v_profile_action_binding jsonb;\nBEGIN'
  );

  p1:=strpos(d,E'  -- Fail closed if canonical Product context cannot be re-read before Gate2.\n');
  p2:=strpos(d,E'  v_rs:=public.lf_router_resolve_v1(\n');
  IF p1<=0 OR p2<=p1 THEN
    RAISE EXCEPTION 'LF_ROUTER_THIN_AFTER_CONTEXT_BLOCK_DRIFT';
  END IF;
  d:=substring(d from 1 for p1-1) || substring(d from p2);

  IF strpos(d,E'    \'product_context_read_before_gate2\',true,\n    \'product_context_read\',v_pc-\'product_context\',\n')=0 THEN
    RAISE EXCEPTION 'LF_ROUTER_THIN_AFTER_OUTPUT_DRIFT';
  END IF;
  d:=replace(
    d,
    E'    \'product_context_read_before_gate2\',true,\n    \'product_context_read\',v_pc-\'product_context\',\n',
    E'    \'canonical_investigation_owner\',\'SELECTED_PROFILE_READ_ONLY\',\n    \'profile_context_hydrator\',\'public.lf_profile_execution_channel_context_v1\',\n'
  );

  EXECUTE d;
END
$after$;

COMMENT ON FUNCTION public.lf_router_route_v1(jsonb,jsonb,boolean) IS
'ACT-0001 Stage2: clasifica y deriva; no investiga contexto funcional. La investigacion PRODUCTO pertenece a la ejecucion READ_ONLY del perfil seleccionado.';

COMMENT ON FUNCTION public.lf_router_product_profile_after_selection_v1(jsonb,jsonb) IS
'Valida perfil CURRENT y prepara Gate2; no investiga Product. El contexto se hidrata dentro de la ejecucion gobernada del perfil.';

DO $post$
DECLARE
  r text;
  a text;
  c text;
BEGIN
  r:=pg_get_functiondef(
    'public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure
  );
  a:=pg_get_functiondef(
    'public.lf_router_product_profile_after_selection_v1(jsonb,jsonb)'::regprocedure
  );
  c:=pg_get_functiondef(
    'public.lf_profile_execution_channel_context_v1(text,jsonb,jsonb)'::regprocedure
  );

  IF strpos(r,'lf_router_product_context_v1')>0
     OR strpos(a,'lf_router_product_context_v1')>0 THEN
    RAISE EXCEPTION 'LF_ROUTER_THIN_ROUTER_STILL_INVESTIGATES';
  END IF;

  IF strpos(c,'lf_router_product_context_v1')=0
     OR strpos(c,'HYDRATED_BY_EXECUTION')=0 THEN
    RAISE EXCEPTION 'LF_ROUTER_THIN_PROFILE_HYDRATION_MISSING';
  END IF;

  IF strpos(r,'DERIVATION_ONLY')=0
     OR strpos(a,'SELECTED_PROFILE_READ_ONLY')=0 THEN
    RAISE EXCEPTION 'LF_ROUTER_THIN_CONTRACT_MISSING';
  END IF;
END
$post$;

COMMIT;
