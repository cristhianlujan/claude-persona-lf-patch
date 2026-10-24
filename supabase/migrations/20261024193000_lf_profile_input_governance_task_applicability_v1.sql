-- Profile Input Governance applicability: direct binding is capability, not mandatory execution.
-- Canonical read/extraction tasks bypass IG; analysis/completeness/change tasks remain governed.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_profile_input_governance_requirement_v1(
  p_handoff jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  v_request jsonb:=p_handoff->'semantic_request';
  v_binding jsonb;
  v_validation jsonb;
  v_profile text:=p_handoff->>'profile_code';
  v_task_intent text;
  v_requirement text;
BEGIN
  IF jsonb_typeof(v_request)<>'object' OR nullif(v_profile,'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_IG_TASK_BINDING_MISSING',
      'input_governance_requirement','REQUIRED_BY_TASK'
    );
  END IF;

  v_validation:=public.lf_router_semantic_action_binding_validate_v1(
    v_request,v_profile,'PERFIL'
  );
  IF coalesce((v_validation->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_IG_TASK_BINDING_INVALID',
      'binding_validation',v_validation,
      'input_governance_requirement','REQUIRED_BY_TASK'
    );
  END IF;

  v_binding:=v_request->'router_action_binding';
  v_task_intent:=upper(nullif(btrim(coalesce(v_binding->>'profile_task_intent','')),''));
  v_requirement:=upper(nullif(btrim(coalesce(v_binding->>'input_governance_requirement','')),''));

  -- Legacy handoffs remain fail-safe: connected profiles continue through IG
  -- until ACT-0001 emits an explicit task-level applicability decision.
  IF v_task_intent IS NULL OR v_requirement IS NULL THEN
    RETURN jsonb_build_object(
      'status','REQUIRED',
      'blocking_code',null,
      'profile_task_intent',v_task_intent,
      'input_governance_requirement','REQUIRED_BY_TASK',
      'reason','LEGACY_OR_UNCLASSIFIED_TASK_FAIL_SAFE'
    );
  END IF;

  IF v_task_intent='READ_PRODUCT_DEFINITION'
     AND v_requirement='NOT_REQUIRED_CANONICAL_READ' THEN
    RETURN jsonb_build_object(
      'status','NOT_REQUIRED',
      'blocking_code',null,
      'profile_task_intent',v_task_intent,
      'input_governance_requirement',v_requirement,
      'reason','EXACT_CANONICAL_READ_OR_EXTRACTION_NO_INPUT_ENRICHMENT'
    );
  END IF;

  IF v_requirement='REQUIRED_BY_TASK' THEN
    RETURN jsonb_build_object(
      'status','REQUIRED',
      'blocking_code',null,
      'profile_task_intent',v_task_intent,
      'input_governance_requirement',v_requirement,
      'reason','TASK_REQUIRES_CONTEXT_COMPLETENESS_OR_COMPOSITION'
    );
  END IF;

  RETURN jsonb_build_object(
    'status','BLOCKED',
    'blocking_code','BLOCK_PROFILE_IG_TASK_REQUIREMENT_INVALID',
    'profile_task_intent',v_task_intent,
    'input_governance_requirement',coalesce(v_requirement,'REQUIRED_BY_TASK')
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_input_governance_requirement_v1(jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_input_governance_requirement_v1(jsonb)
  TO service_role,supabase_read_only_user;

-- ACT-0001 stamps the task applicability inside the already integrity-bound
-- router_action_binding. Scope remains a target descriptor only.
DO $patch_router_task_binding$
DECLARE
  v_def text;
  v_old_decl text;
  v_new_decl text;
  v_old_block text;
  v_new_block text;
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure
     )) <> '591c1f23db8b1d19b1a610f19c061cb4' THEN
    RAISE EXCEPTION 'PROFILE_IG_TASK_ROUTE_SOURCE_DRIFT';
  END IF;

  v_def:=pg_get_functiondef(
    'public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure
  );

  v_old_decl:=E'  v_pc jsonb;\n';
  v_new_decl:=E'  v_pc jsonb;\n'
    ||E'  v_profile_task_intent text;\n'
    ||E'  v_profile_ig_requirement text;\n'
    ||E'  v_profile_action_binding jsonb;\n';

  IF strpos(v_def,v_old_decl)=0 THEN
    RAISE EXCEPTION 'PROFILE_IG_TASK_ROUTE_DECL_ANCHOR_MISSING';
  END IF;
  v_def:=replace(v_def,v_old_decl,v_new_decl);

  v_old_block:=E'      v_rs:=public.lf_router_resolve_v1(\n'
    ||E'        p_stage1->>''texto_original'',\n'
    ||E'        ''PERFIL-PRODUCT-DIRECTOR-LF'',\n'
    ||E'        ''PROFILE_EXECUTION'',\n'
    ||E'        ''PERFIL'',\n'
    ||E'        ''ROUTER''\n'
    ||E'      );\n\n'
    ||E'      IF v_rs->>''blocking_code''<>''BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED''';

  v_new_block:=E'      v_rs:=public.lf_router_resolve_v1(\n'
    ||E'        p_stage1->>''texto_original'',\n'
    ||E'        ''PERFIL-PRODUCT-DIRECTOR-LF'',\n'
    ||E'        ''PROFILE_EXECUTION'',\n'
    ||E'        ''PERFIL'',\n'
    ||E'        ''ROUTER''\n'
    ||E'      );\n\n'
    ||E'      v_profile_task_intent:=upper(coalesce(p_stage1->>''accion'',''''));\n'
    ||E'      v_profile_ig_requirement:=case\n'
    ||E'        when v_profile_task_intent=''READ_PRODUCT_DEFINITION'' then ''NOT_REQUIRED_CANONICAL_READ''\n'
    ||E'        else ''REQUIRED_BY_TASK''\n'
    ||E'      end;\n\n'
    ||E'      IF jsonb_typeof(v_rs#>''{semantic_handoff_v2,router_action_binding}'')=''object'' THEN\n'
    ||E'        v_profile_action_binding:=\n'
    ||E'          (v_rs#>''{semantic_handoff_v2,router_action_binding}'')\n'
    ||E'          ||jsonb_build_object(\n'
    ||E'            ''profile_task_intent'',v_profile_task_intent,\n'
    ||E'            ''input_governance_requirement'',v_profile_ig_requirement\n'
    ||E'          );\n'
    ||E'        v_profile_action_binding:=v_profile_action_binding||jsonb_build_object(\n'
    ||E'          ''binding_sha256'',\n'
    ||E'          ''sha256:''||encode(\n'
    ||E'            extensions.digest(\n'
    ||E'              convert_to((v_profile_action_binding-''binding_sha256'')::text,''UTF8''),\n'
    ||E'              ''sha256''\n'
    ||E'            ),\n'
    ||E'            ''hex''\n'
    ||E'          )\n'
    ||E'        );\n'
    ||E'        v_rs:=jsonb_set(\n'
    ||E'          v_rs,\n'
    ||E'          ''{semantic_handoff_v2,router_action_binding}'',\n'
    ||E'          v_profile_action_binding,\n'
    ||E'          true\n'
    ||E'        );\n'
    ||E'      END IF;\n\n'
    ||E'      IF v_rs->>''blocking_code''<>''BLOCK_EXPLICIT_TARGET_INTENT_ATTESTATION_REQUIRED''';

  IF strpos(v_def,v_old_block)=0 THEN
    RAISE EXCEPTION 'PROFILE_IG_TASK_ROUTE_PRODUCT_ANCHOR_MISSING';
  END IF;

  v_def:=replace(v_def,v_old_block,v_new_block);
  EXECUTE v_def;
END
$patch_router_task_binding$;

-- input_validate consumes the Router-bound task decision.
DO $patch_input_validate$
DECLARE
  v_def text;
  v_old_decl text;
  v_new_decl text;
  v_old_logic text;
  v_new_logic text;
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)'::regprocedure
     )) <> 'ba055cf23eda92042cbc13bfedcf4e10' THEN
    RAISE EXCEPTION 'PROFILE_IG_TASK_INPUT_VALIDATE_SOURCE_DRIFT';
  END IF;

  v_def:=pg_get_functiondef(
    'public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)'::regprocedure
  );

  v_old_decl:=E'  v_ig jsonb;\n  v_direct_profile_ig boolean:=false;\n';
  v_new_decl:=E'  v_ig jsonb;\n'
    ||E'  v_direct_profile_ig boolean:=false;\n'
    ||E'  v_task_requirement jsonb;\n';

  IF strpos(v_def,v_old_decl)=0 THEN
    RAISE EXCEPTION 'PROFILE_IG_TASK_INPUT_DECL_ANCHOR_MISSING';
  END IF;
  v_def:=replace(v_def,v_old_decl,v_new_decl);

  v_old_logic:=E'  SELECT EXISTS(\n'
    ||E'    SELECT 1\n'
    ||E'    FROM public.lf_activo_relaciones r\n'
    ||E'    WHERE r.codigo_activo=v_exec.target_code\n'
    ||E'      AND r.relacionado_codigo=''INPUT_GOVERNANCE_EXECUTION_CONTRACT''\n'
    ||E'      AND r.relacion_tipo=''GOBERNADO_POR''\n'
    ||E'  ) INTO v_direct_profile_ig;\n\n'
    ||E'  IF v_direct_profile_ig THEN\n';

  v_new_logic:=E'  v_task_requirement:=public.lf_profile_input_governance_requirement_v1(p_handoff);\n'
    ||E'  IF v_task_requirement->>''status''=''BLOCKED'' THEN\n'
    ||E'    RETURN jsonb_build_object(\n'
    ||E'      ''status'',''BLOCKED'',\n'
    ||E'      ''blocking_code'',coalesce(v_task_requirement->>''blocking_code'',''BLOCK_PROFILE_IG_TASK_BINDING_INVALID''),\n'
    ||E'      ''input_governance_task'',v_task_requirement,\n'
    ||E'      ''router_reentry_required'',false\n'
    ||E'    );\n'
    ||E'  END IF;\n\n'
    ||E'  IF v_task_requirement->>''status''=''NOT_REQUIRED'' THEN\n'
    ||E'    v_ig:=jsonb_build_object(\n'
    ||E'      ''applicable'',false,\n'
    ||E'      ''status'',''NOT_REQUIRED'',\n'
    ||E'      ''blocking_code'',null,\n'
    ||E'      ''decision'',''SKIP'',\n'
    ||E'      ''continuation_allowed'',true,\n'
    ||E'      ''binding_mode'',''DIRECT_PROFILE_CAPABILITY_NOT_INVOKED'',\n'
    ||E'      ''profile_task_intent'',v_task_requirement->>''profile_task_intent'',\n'
    ||E'      ''input_governance_requirement'',v_task_requirement->>''input_governance_requirement'',\n'
    ||E'      ''reason'',v_task_requirement->>''reason''\n'
    ||E'    );\n'
    ||E'  ELSE\n'
    ||E'    SELECT EXISTS(\n'
    ||E'      SELECT 1\n'
    ||E'      FROM public.lf_activo_relaciones r\n'
    ||E'      WHERE r.codigo_activo=v_exec.target_code\n'
    ||E'        AND r.relacionado_codigo=''INPUT_GOVERNANCE_EXECUTION_CONTRACT''\n'
    ||E'        AND r.relacion_tipo=''GOBERNADO_POR''\n'
    ||E'    ) INTO v_direct_profile_ig;\n\n'
    ||E'    IF v_direct_profile_ig THEN\n';

  IF strpos(v_def,v_old_logic)=0 THEN
    RAISE EXCEPTION 'PROFILE_IG_TASK_INPUT_LOGIC_ANCHOR_MISSING';
  END IF;
  v_def:=replace(v_def,v_old_logic,v_new_logic);

  -- Close the task-level ELSE around the existing direct/adaptor selection.
  IF strpos(v_def,E'  IF coalesce((v_ig->>''applicable'')::boolean,false)')=0 THEN
    RAISE EXCEPTION 'PROFILE_IG_TASK_INPUT_CLOSE_ANCHOR_MISSING';
  END IF;
  v_def:=replace(
    v_def,
    E'  IF coalesce((v_ig->>''applicable'')::boolean,false)',
    E'  END IF;\n\n  IF coalesce((v_ig->>''applicable'')::boolean,false)'
  );

  EXECUTE v_def;
END
$patch_input_validate$;

-- Acceptance: canonical read bypasses IG; change remains governed.
DO $acceptance$
DECLARE
  v_read_route jsonb;
  v_change_route jsonb;
  v_read_request jsonb;
  v_change_request jsonb;
  v_read_gate jsonb;
  v_change_gate jsonb;
BEGIN
  v_read_route:=public.lf_router_route_v1(
    jsonb_build_object(
      'schema_version','LF_ROUTER_STAGE1_V2',
      'texto_original','Dame las reglas en el login B2B',
      'downstream_execution_allowed',false,
      'es_operacion',true,
      'ambiguo',false,
      'formas_busqueda',jsonb_build_array('login B2B','B2B-AUTH-001','reglas login'),
      'alternativas','[]'::jsonb,
      'correcciones','[]'::jsonb,
      'canal_candidato','PRODUCTO',
      'negocio_codigo','LF',
      'negocios_afectados','[]'::jsonb,
      'razon_seleccion','Consulta de definición funcional canónica.',
      'accion','READ_PRODUCT_DEFINITION',
      'sujeto','B2B-AUTH-001',
      'alcance',jsonb_build_object(
        'target_type','PANTALLA',
        'target_hint','B2B-AUTH-001',
        'resolution_status','UNRESOLVED'
      )
    ),
    '{}'::jsonb,
    false
  );
  v_read_request:=v_read_route->'gate2_request';

  IF v_read_route->>'paso'<>'PRODUCTO_GATE2_PERFIL'
     OR v_read_request#>>'{router_action_binding,profile_task_intent}'<>'READ_PRODUCT_DEFINITION'
     OR v_read_request#>>'{router_action_binding,input_governance_requirement}'<>'NOT_REQUIRED_CANONICAL_READ'
     OR coalesce((public.lf_router_semantic_action_binding_validate_v1(
          v_read_request,'PERFIL-PRODUCT-DIRECTOR-LF','PERFIL'
        )->>'valid')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'PROFILE_IG_CANONICAL_READ_ROUTE_ACCEPTANCE_FAILED:%',v_read_route;
  END IF;

  v_read_gate:=public.lf_profile_input_governance_requirement_v1(
    jsonb_build_object(
      'profile_code','PERFIL-PRODUCT-DIRECTOR-LF',
      'semantic_request',v_read_request
    )
  );
  IF v_read_gate->>'status'<>'NOT_REQUIRED' THEN
    RAISE EXCEPTION 'PROFILE_IG_CANONICAL_READ_NOT_SKIPPED:%',v_read_gate;
  END IF;

  v_change_route:=public.lf_router_route_v1(
    jsonb_build_object(
      'schema_version','LF_ROUTER_STAGE1_V2',
      'texto_original','Agregar una nueva regla funcional al login B2B.',
      'downstream_execution_allowed',false,
      'es_operacion',true,
      'ambiguo',false,
      'formas_busqueda',jsonb_build_array('login B2B','B2B-AUTH-001'),
      'alternativas','[]'::jsonb,
      'correcciones','[]'::jsonb,
      'canal_candidato','PRODUCTO',
      'negocio_codigo','LF',
      'negocios_afectados','[]'::jsonb,
      'razon_seleccion','Modifica definición funcional canónica.',
      'accion','CHANGE_PRODUCT_DEFINITION',
      'sujeto','B2B-AUTH-001',
      'alcance',jsonb_build_object(
        'target_type','PANTALLA',
        'target_hint','B2B-AUTH-001',
        'resolution_status','UNRESOLVED'
      )
    ),
    '{}'::jsonb,
    false
  );
  v_change_request:=v_change_route->'gate2_request';

  IF v_change_request#>>'{router_action_binding,input_governance_requirement}'<>'REQUIRED_BY_TASK' THEN
    RAISE EXCEPTION 'PROFILE_IG_CHANGE_MUST_REMAIN_REQUIRED:%',v_change_route;
  END IF;

  v_change_gate:=public.lf_profile_input_governance_requirement_v1(
    jsonb_build_object(
      'profile_code','PERFIL-PRODUCT-DIRECTOR-LF',
      'semantic_request',v_change_request
    )
  );
  IF v_change_gate->>'status'<>'REQUIRED' THEN
    RAISE EXCEPTION 'PROFILE_IG_CHANGE_GATE_ACCEPTANCE_FAILED:%',v_change_gate;
  END IF;
END
$acceptance$;

COMMIT;
