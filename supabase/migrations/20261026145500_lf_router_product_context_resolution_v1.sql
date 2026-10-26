-- ACT-0001: restore canonical Product read before dynamic profile selection.
-- Regression fixed: 20261025000500 replaced the PRODUCTO context-first block with
-- immediate profile selection. Keep dynamic profile selection, but only after a
-- canonical read. No updater/insert or runtime effect is authorized here.
BEGIN;

DO $precheck$
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure
     )) <> 'b6b5d10fd21912c8303222aea0c98927' THEN
    RAISE EXCEPTION 'LF_ROUTER_PRODUCT_CONTEXT_FIRST_ROUTE_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_router_product_profile_after_selection_v1(jsonb,jsonb)'::regprocedure
     )) <> '7e77862c060fba95b58389f410b31902' THEN
    RAISE EXCEPTION 'LF_ROUTER_PRODUCT_CONTEXT_FIRST_AFTER_SELECTION_SOURCE_DRIFT';
  END IF;
END
$precheck$;

-- Read-only audit access only. Execution/materialization functions remain service_role-only.
GRANT EXECUTE ON FUNCTION public.lf_router_product_context_v1(text,jsonb)
  TO supabase_read_only_user;

DO $patch_route$
DECLARE
  d text;
  decl_old text;
  decl_new text;
  marker_start text;
  marker_end text;
  block_new text;
  p_start integer;
  p_end integer;
BEGIN
  d:=pg_get_functiondef(
    'public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure
  );

  decl_old:=$old$
  v_base jsonb;
  v_profile_selection_request jsonb;
BEGIN$old$;
  decl_new:=$new$
  v_base jsonb;
  v_profile_selection_request jsonb;
  v_pc jsonb;
BEGIN$new$;

  IF (length(d)-length(replace(d,decl_old,'')))/length(decl_old)<>1 THEN
    RAISE EXCEPTION 'LF_PRODUCT_CONTEXT_FIRST_ROUTE_DECLARATION_DRIFT';
  END IF;
  d:=replace(d,decl_old,decl_new);

  marker_start:=$m$
    IF v_channel='PRODUCTO' THEN
      v_profile_selection_request:=
$m$;
  marker_end:=$m$


    -- If no exact aggregate product context is available, preserve the bounded
$m$;

  p_start:=strpos(d,marker_start);
  p_end:=strpos(d,marker_end);

  IF p_start<=0 OR p_end<=p_start THEN
    RAISE EXCEPTION 'LF_PRODUCT_CONTEXT_FIRST_ROUTE_BLOCK_DRIFT:start=% end=%',
      p_start,p_end;
  END IF;

  block_new:=$new$
    IF v_channel='PRODUCTO' THEN
      -- Read canonical Product truth before choosing any worker.
      v_pc:=public.lf_router_product_context_v1(
        p_stage1->>'texto_original',
        v_scope
      );

      IF v_pc->>'status'='RESOLVED' THEN
        v_profile_selection_request:=
          public.lf_profile_selector_semantic_prepare_v1(
            p_stage1->>'texto_original'
          );

        RETURN v_base||jsonb_build_object(
          'paso','PRODUCTO_PROFILE_SELECTION_REQUIRED',
          'product_context_read_before_profile_selection',true,
          'product_context_read',v_pc-'product_context',
          'product_context_mutation_authority',false,
          'profile_selection_request',v_profile_selection_request,
          'profile_selection_result_contract','LF_PROFILE_SELECTOR_SEMANTIC_RESULT_V1',
          'profile_selection_consumer','public.lf_profile_selector_semantic_consume_raw_v1',
          'profile_selection_resume_entrypoint','public.lf_router_product_profile_after_selection_raw_v1',
          'profile_selection_candidate_count',
            (v_profile_selection_request->>'catalog_profile_count')::integer,
          'gate2_after_profile_selection',true,
          'motivo_es','Producto verifico primero la fuente canonica actual; solo despues prepara la seleccion dinamica del perfil sin conceder efectos.',
          'siguiente_paso_es','Seleccionar un perfil CURRENT para analizar en solo lectura. Cualquier updater/insert requiere una operacion gobernada separada y Merge Train.',
          'downstream_execution_allowed',false
        );
      END IF;
    END IF;
$new$;

  d:=substring(d from 1 for p_start-1)
     ||block_new
     ||substring(d from p_end);

  EXECUTE d;
END
$patch_route$;

DO $patch_after_selection$
DECLARE
  d text;
  decl_old text;
  decl_new text;
  marker text;
  guard_new text;
  out_old text;
  out_new text;
BEGIN
  d:=pg_get_functiondef(
    'public.lf_router_product_profile_after_selection_v1(jsonb,jsonb)'::regprocedure
  );

  decl_old:=$old$
  v_profile_action_binding jsonb;
BEGIN$old$;
  decl_new:=$new$
  v_profile_action_binding jsonb;
  v_pc jsonb;
BEGIN$new$;

  IF (length(d)-length(replace(d,decl_old,'')))/length(decl_old)<>1 THEN
    RAISE EXCEPTION 'LF_PRODUCT_CONTEXT_FIRST_AFTER_SELECTION_DECLARATION_DRIFT';
  END IF;
  d:=replace(d,decl_old,decl_new);

  marker:=$m$
  v_rs:=public.lf_router_resolve_v1(
$m$;
  guard_new:=$new$
  -- Fail closed if canonical Product context cannot be re-read before Gate2.
  v_pc:=public.lf_router_product_context_v1(
    p_stage1->>'texto_original',
    p_stage1->'alcance'
  );

  IF v_pc->>'status'<>'RESOLVED' THEN
    RETURN v_base||jsonb_build_object(
      'status','BLOCKED',
      'paso','PRODUCTO_CONTEXT_RECHECK_FAILED',
      'blocking_code','BLOCK_PRODUCT_CONTEXT_NOT_RESOLVED_BEFORE_GATE2',
      'product_context_read_before_gate2',true,
      'product_context_read',v_pc-'product_context',
      'siguiente_paso_es','Resolver nuevamente la fuente canonica en PRODUCTO; no preparar Gate2.',
      'downstream_execution_allowed',false
    );
  END IF;

  v_rs:=public.lf_router_resolve_v1(
$new$;

  IF (length(d)-length(replace(d,marker,'')))/length(marker)<>1 THEN
    RAISE EXCEPTION 'LF_PRODUCT_CONTEXT_FIRST_AFTER_SELECTION_RESOLVER_DRIFT';
  END IF;
  d:=replace(d,marker,guard_new);

  out_old:=$old$
    'profile_selection_receipt_sha256',p_selection_result->>'semantic_receipt_sha256',
    'gate2_request',$old$;
  out_new:=$new$
    'profile_selection_receipt_sha256',p_selection_result->>'semantic_receipt_sha256',
    'product_context_read_before_gate2',true,
    'product_context_read',v_pc-'product_context',
    'gate2_request',$new$;

  IF (length(d)-length(replace(d,out_old,'')))/length(out_old)<>1 THEN
    RAISE EXCEPTION 'LF_PRODUCT_CONTEXT_FIRST_AFTER_SELECTION_OUTPUT_DRIFT';
  END IF;
  d:=replace(d,out_old,out_new);

  EXECUTE d;
END
$patch_after_selection$;

COMMENT ON FUNCTION public.lf_router_route_v1(jsonb,jsonb,boolean) IS
'Punto unico Stage2 ACT-0001. PRODUCTO lee primero sujeto/contexto canonico vigente y solo despues prepara seleccion dinamica de perfil. Seleccion de perfil no concede efectos. PROGRAMACION requiere definicion vigente; OPERACIONES exige capacidad y alcance autorizados.';

COMMENT ON FUNCTION public.lf_router_product_context_v1(text,jsonb) IS
'ACT-0001 read-only Product context loader. Resolves canonical subject first, then loads aggregate screen context. EXECUTE is allowed to service_role and supabase_read_only_user only; it never grants mutation authority.';

DO $postcheck$
DECLARE
  s jsonb;
  r jsonb;
  pc jsonb;
  submit jsonb;
BEGIN
  s:=jsonb_build_object(
    'schema_version','LF_ROUTER_STAGE1_V2',
    'texto_original','Cambiar únicamente el texto del botón principal de la pantalla Iniciar sesión B2B a “Acceder”, sin modificar la autenticación, las validaciones ni otras partes de la pantalla.',
    'downstream_execution_allowed',false,
    'es_operacion',true,
    'ambiguo',false,
    'respuesta_directa',false,
    'sujeto','botón principal de la pantalla Iniciar sesión B2B',
    'accion','cambiar texto visible',
    'formas_busqueda',jsonb_build_array(
      'botón principal Iniciar sesión B2B',
      'texto visible botón Login B2B'
    ),
    'alternativas','[]'::jsonb,
    'pregunta_usuario',null,
    'capability_hint',null,
    'correcciones','[]'::jsonb,
    'canal_candidato','PRODUCTO',
    'negocio_codigo','LF',
    'negocios_afectados','[]'::jsonb,
    'ruta_transversal',null,
    'razon_seleccion','La solicitud cambia una definición visible del producto y excluye cambios de autenticación y validaciones.',
    'alcance',jsonb_build_object(
      'target_type','PANTALLA',
      'target_hint','Iniciar sesión B2B',
      'resolution_status','UNRESOLVED'
    )
  );

  pc:=public.lf_router_product_context_v1(
    s->>'texto_original',
    s->'alcance'
  );

  IF pc->>'status' IS DISTINCT FROM 'RESOLVED'
     OR pc->>'subject_ref' IS DISTINCT FROM 'B2B-AUTH-001'
     OR pc->>'screen_version' IS DISTINCT FROM 'v0.5'
  THEN
    RAISE EXCEPTION 'LF_PRODUCT_CONTEXT_FIRST_CANONICAL_READ_FAILED:%',
      pc-'product_context';
  END IF;

  SELECT x INTO submit
  FROM jsonb_array_elements(pc#>'{product_context,elements}') x
  WHERE x->>'element_code'='B2B_AUTH001_SUBMIT'
  LIMIT 1;

  IF submit IS NULL OR submit->>'label_visible' IS DISTINCT FROM 'Acceder' THEN
    RAISE EXCEPTION 'LF_PRODUCT_CONTEXT_FIRST_LOGIN_LABEL_REGRESSION:%',submit;
  END IF;

  r:=public.lf_router_route_v1(s,'{}'::jsonb,false);

  IF r->>'paso' IS DISTINCT FROM 'PRODUCTO_PROFILE_SELECTION_REQUIRED'
     OR coalesce((r->>'product_context_read_before_profile_selection')::boolean,false) IS NOT TRUE
     OR r#>>'{product_context_read,status}' IS DISTINCT FROM 'RESOLVED'
     OR r#>>'{product_context_read,subject_ref}' IS DISTINCT FROM 'B2B-AUTH-001'
     OR coalesce((r->>'product_context_mutation_authority')::boolean,true) IS NOT FALSE
     OR coalesce((r->>'downstream_execution_allowed')::boolean,true) IS NOT FALSE
     OR jsonb_typeof(r->'profile_selection_request') IS DISTINCT FROM 'object'
  THEN
    RAISE EXCEPTION 'LF_PRODUCT_CONTEXT_FIRST_ROUTE_REGRESSION:%',r;
  END IF;

  IF NOT has_function_privilege(
       'supabase_read_only_user',
       'public.lf_router_product_context_v1(text,jsonb)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'LF_PRODUCT_CONTEXT_FIRST_READ_ONLY_EXECUTE_MISSING';
  END IF;

  -- Read-only investigation is widened; execution/materialization is not.
  IF has_function_privilege(
       'supabase_read_only_user',
       'public.lf_router_profile_execution_after_gate2_v1(jsonb,jsonb,text,text,jsonb,text,text,text)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'LF_PRODUCT_CONTEXT_FIRST_EXECUTION_PRIVILEGE_WIDENED';
  END IF;

  IF strpos(
       pg_get_functiondef(
         'public.lf_router_product_profile_after_selection_v1(jsonb,jsonb)'::regprocedure
       ),
       'BLOCK_PRODUCT_CONTEXT_NOT_RESOLVED_BEFORE_GATE2'
     )=0 THEN
    RAISE EXCEPTION 'LF_PRODUCT_CONTEXT_FIRST_GATE2_RECHECK_MISSING';
  END IF;
END
$postcheck$;

COMMIT;
