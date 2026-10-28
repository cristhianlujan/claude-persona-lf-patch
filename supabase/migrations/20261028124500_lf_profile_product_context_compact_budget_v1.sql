-- LF governed native profile, exact production source pinned.
-- Budget is not increased. Oversize Product context is projected with
-- canonical refs + SHA256; fail closed when even compact projection is RED.
-- No screen/profile constants, no grants, no direct product writes.
DO $guard$
DECLARE v_oid oid:=to_regprocedure('public.lf_profile_execution_channel_context_v1(text,jsonb,jsonb)');
BEGIN
 IF v_oid IS NULL
    OR md5(pg_get_functiondef(v_oid))<>'21fc9a6559c0843ac11c368fa45fb105'
    OR NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_oid)
    OR pg_get_userbyid((SELECT proowner FROM pg_proc WHERE oid=v_oid))<>'postgres'
 THEN RAISE EXCEPTION 'LF_PRODUCT_CONTEXT_COMPACT_BASELINE_DRIFT'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.lf_profile_execution_channel_context_v1(p_execution_id text, p_base_context jsonb, p_handoff jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'extensions', 'lf_ops', 'lf_design'
AS $function$
DECLARE
  v_valid jsonb;
  v_pc jsonb;
  v_capsule jsonb;
  v_bytes bigint;
  v_tokens bigint;
  v_soft bigint;
  v_hard bigint;
  v_status text;
  v_event_id bigint;
  v_budget_event_id bigint;
  v_digest text;
  v_task_intent text;
  v_ig_requirement text;
  v_screen_id integer;
  v_screen_code text;
  v_screen_name text;
  v_screen_status text;
  v_screen_version text;
  v_module_code text;
  v_shell_code text;
  v_direct_rules jsonb:='[]'::jsonb;
  v_category_counts jsonb:='{}'::jsonb;
  v_effective_rule_count integer:=0;
  v_product_scope jsonb;
  v_screen_selection_result jsonb;
  v_screen_selection_request jsonb;
  v_screen_selection_validation jsonb;
BEGIN
  v_valid:=public.lf_router_profile_execution_handoff_validate_v1(
    p_handoff,
    p_handoff->>'literal_request',
    p_handoff->>'profile_code'
  );
  IF coalesce((v_valid->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_CHANNEL_CONTEXT_HANDOFF_INVALID',
      'handoff_validation',v_valid,
      'server_validated',false
    );
  END IF;

  IF p_handoff->>'channel'<>'PRODUCTO' THEN
    RETURN p_base_context||jsonb_build_object(
      'channel_context_mode','NOT_REQUIRED',
      'channel',p_handoff->>'channel'
    );
  END IF;

  v_task_intent:=upper(coalesce(
    p_handoff#>>'{semantic_request,router_action_binding,profile_task_intent}',
    ''
  ));
  v_ig_requirement:=upper(coalesce(
    p_handoff#>>'{semantic_request,router_action_binding,input_governance_requirement}',
    ''
  ));

  v_product_scope:=coalesce(p_handoff->'scope','{}'::jsonb);

  IF v_ig_requirement='REQUIRED_BY_TASK'
     AND upper(coalesce(p_handoff#>>'{scope,target_type}',''))='PANTALLA' THEN

    SELECT manifest->'screen_selection_result'
      INTO v_screen_selection_result
    FROM public.lf_operation_execution
    WHERE execution_id=p_execution_id
      AND operation_code='EJECUCION_PERFIL_LF'
      AND status='IN_PROGRESS';

    v_screen_selection_request:=public.lf_profile_screen_selector_semantic_prepare_v1(
      p_handoff->>'literal_request',
      p_handoff->'scope'
    );

    IF v_screen_selection_result IS NULL
       OR jsonb_typeof(v_screen_selection_result)<>'object' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PRODUCT_CHANNEL_CONTEXT_SCREEN_SELECTION_MISSING',
        'server_validated',false
      );
    END IF;

    v_screen_selection_validation:=public.lf_profile_screen_selector_semantic_validate_v1(
      v_screen_selection_request,
      v_screen_selection_result
    );

    IF v_screen_selection_validation->>'status'<>'VALID'
       OR v_screen_selection_result->>'decision'<>'SELECTED'
       OR nullif(v_screen_selection_result->>'selected_screen_code','') IS NULL THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PRODUCT_CHANNEL_CONTEXT_SCREEN_SELECTION_INVALID',
        'screen_selection_validation',v_screen_selection_validation,
        'server_validated',false
      );
    END IF;

    v_product_scope:=v_product_scope||jsonb_build_object(
      'target_hint',v_screen_selection_result->>'selected_screen_code',
      'resolution_status','RESOLVED',
      'resolved_screen_code',v_screen_selection_result->>'selected_screen_code',
      'resolution_method','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC'
    );
  END IF;

  IF v_task_intent='READ_PRODUCT_DEFINITION'
     AND v_ig_requirement='NOT_REQUIRED_CANONICAL_READ' THEN

    SELECT p.id,p.codigo,p.nombre,p.estado,p.version,p.module_code,m.app_shell_code
      INTO v_screen_id,v_screen_code,v_screen_name,v_screen_status,v_screen_version,
           v_module_code,v_shell_code
    FROM lf_ops.pantallas p
    JOIN lf_ops.modulos m ON m.module_code=p.module_code
    WHERE p.activa
      AND (
        upper(p.codigo)=upper(coalesce(p_handoff#>>'{scope,target_hint}',''))
        OR upper(p.nombre)=upper(coalesce(p_handoff#>>'{scope,target_hint}',''))
      );

    IF v_screen_id IS NULL THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PRODUCT_CANONICAL_READ_SUBJECT_NOT_RESOLVED',
        'target_hint',p_handoff#>>'{scope,target_hint}',
        'server_validated',false
      );
    END IF;

    SELECT coalesce(
      jsonb_agg(
        jsonb_build_array(r.codigo,r.titulo,r.estado)
        ORDER BY r.categoria,r.codigo
      ),
      '[]'::jsonb
    )
      INTO v_direct_rules
    FROM lf_ops.reglas_pantallas rp
    JOIN lf_ops.reglas r ON r.id=rp.regla_id
    WHERE rp.pantalla_id=v_screen_id;

    SELECT coalesce(jsonb_object_agg(q.categoria,q.cnt ORDER BY q.categoria),'{}'::jsonb)
      INTO v_category_counts
    FROM (
      SELECT r.categoria,count(*)::integer cnt
      FROM lf_ops.reglas_pantallas rp
      JOIN lf_ops.reglas r ON r.id=rp.regla_id
      WHERE rp.pantalla_id=v_screen_id
      GROUP BY r.categoria
    ) q;

    SELECT jsonb_array_length(coalesce(sc.contract->'rules','[]'::jsonb))
      INTO v_effective_rule_count
    FROM lf_ops.fn_screen_contract_v1(
      v_shell_code,v_module_code,v_screen_code
    ) sc
    LIMIT 1;

    v_pc:=jsonb_build_object(
      'schema_version','LF_PRODUCT_CANONICAL_RULE_READ_V1',
      'status','RESOLVED',
      'subject_ref',v_screen_code,
      'subject_name',v_screen_name,
      'screen_status',v_screen_status,
      'screen_version',v_screen_version,
      'task_intent',v_task_intent,
      'input_governance_requirement',v_ig_requirement,
      'direct_rule_count',jsonb_array_length(v_direct_rules),
      'effective_rule_count',coalesce(v_effective_rule_count,0),
      'rule_tuple_schema',jsonb_build_array('code','title','status'),
      'direct_rules',v_direct_rules,
      'category_counts',v_category_counts,
      'direct_rules_ref','supabase://lf_ops.reglas_pantallas/'||v_screen_code,
      'effective_rules_ref',
        'supabase://lf_ops.fn_screen_contract_v1/'||
        v_shell_code||'/'||v_module_code||'/'||v_screen_code||'#rules',
      'projection_mode','COMPACT_DIRECT_RULES_EFFECTIVE_AGGREGATE_LAZY',
      'canonical_read_only',true
    );
  ELSE
    v_pc:=public.lf_router_product_context_v1(
      p_handoff->>'literal_request',
      v_product_scope
    );
    IF v_pc->>'status' IS DISTINCT FROM 'RESOLVED' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PRODUCT_CHANNEL_CONTEXT_NOT_RESOLVED',
        'product_context_summary',v_pc-'product_context',
        'server_validated',false
      );
    END IF;
  END IF;

  v_capsule:=coalesce(p_base_context->'context_capsule','{}'::jsonb)
    ||jsonb_build_object(
      'channel_context',
      jsonb_build_object(
        'channel','PRODUCTO',
        'screen_selection_receipt_sha256',
          case
            when jsonb_typeof(v_screen_selection_result)='object'
              then v_screen_selection_result->>'semantic_receipt_sha256'
            else null
          end,
        'source',case
          when v_pc->>'schema_version'='LF_PRODUCT_CANONICAL_RULE_READ_V1'
            then 'lf_ops.reglas_pantallas + lf_ops.fn_screen_contract_v1#rule_count'
          else 'public.lf_router_product_context_v1'
        end,
        'product_context',v_pc
      )
    );

  v_bytes:=octet_length(v_capsule::text);
  v_tokens:=ceil(v_bytes/4.0)::bigint;
  v_soft:=coalesce((p_base_context->>'soft_limit_tokens')::bigint,1500);
  v_hard:=coalesce((p_base_context->>'hard_limit_tokens')::bigint,3000);
  v_status:=case
    when v_tokens>v_hard then 'RED'
    when v_tokens>v_soft then 'YELLOW'
    else 'GREEN'
  end;

  -- Keep the hard context gate. The full canonical Product snapshot can be
  -- much larger than this execution's context token budget. When that happens,
  -- transmit only source-bound metadata, an exact snapshot digest and lazy refs.
  -- Actual rules/elements MUST be read from the pinned canonical sources for
  -- model execution; absence of a valid source still blocks the operation.
  IF v_status='RED'
     AND v_pc->>'schema_version'='LF_ROUTER_PRODUCT_CONTEXT_V1'
     AND v_pc->>'status'='RESOLVED'
     AND jsonb_typeof(v_pc->'product_context')='object'
     AND nullif(v_pc->>'subject_ref','') IS NOT NULL
     AND nullif(v_pc#>>'{canonical_context_source,app_shell_code}','') IS NOT NULL
     AND nullif(v_pc#>>'{canonical_context_source,module_code}','') IS NOT NULL
  THEN
    v_pc:=(v_pc-'product_context')
      ||jsonb_build_object(
        'projection_mode','CANONICAL_CONTEXT_COMPACT_LAZY_V1',
        'full_context_requires_lazy_read',true,
        'product_context',jsonb_build_object(
          'projection_mode','CANONICAL_SOURCE_REF_WITH_SNAPSHOT_DIGEST_V1',
          'full_snapshot_sha256','sha256:'||encode(
            extensions.digest(convert_to((v_pc->'product_context')::text,'UTF8'),'sha256'),'hex'
          ),
          'full_snapshot_bytes',octet_length((v_pc->'product_context')::text),
          'canonical_contract_ref',
            'supabase://lf_ops.fn_screen_contract_v1/'||
            (v_pc#>>'{canonical_context_source,app_shell_code}')||'/'||
            (v_pc#>>'{canonical_context_source,module_code}')||'/'||
            (v_pc->>'subject_ref'),
          'canonical_elements_ref',
            'supabase://lf_ops.pantalla_elementos/'||(v_pc->>'subject_ref')
        )
      );
    v_capsule:=jsonb_set(
      v_capsule,'{channel_context,product_context}',v_pc,true
    );
    v_bytes:=octet_length(v_capsule::text);
    v_tokens:=ceil(v_bytes/4.0)::bigint;
    v_status:=case
      when v_tokens>v_hard then 'RED'
      when v_tokens>v_soft then 'YELLOW'
      else 'GREEN'
    end;
  END IF;

  IF v_status='RED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PRODUCT_CHANNEL_CONTEXT_BUDGET_RED',
      'context_projection_schema',v_pc->>'schema_version',
      'estimated_tokens',v_tokens,
      'hard_limit_tokens',v_hard,
      'server_validated',false
    );
  END IF;

  v_capsule:=jsonb_set(
    v_capsule,
    '{context_budget}',
    jsonb_build_object(
      'estimated_tokens',v_tokens,
      'soft_limit_tokens',v_soft,
      'hard_limit_tokens',v_hard,
      'status',v_status
    ),
    true
  );

  INSERT INTO public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,origen,
    created_by_execution_id
  ) VALUES (
    'SESION_INICIO','ACTIVO','ACT-0001',
    'Channel-specific context hydration for governed profile execution.',
    'INFO',
    jsonb_build_object(
      'evidence_schema_version','operational-event/v2',
      'producer','lf_profile_execution_channel_context_v1',
      'purpose','Hydrate bounded channel-specific Product context for governed profile execution.',
      'occurred_at',clock_timestamp(),
      'execution_id',p_execution_id,
      'acceptance_declared',false,
      'channel','PRODUCTO',
      'base_context_receipt_ref',p_base_context->>'context_receipt_ref',
      'context_receipt',v_capsule
    ),
    'DB_FUNCTION',
    p_execution_id
  ) RETURNING id INTO v_event_id;

  INSERT INTO private.lf_context_budget_events_v2(
    execution_id,estimated_tokens,context_status,source,recommendation,
    evidence_event_id
  ) VALUES (
    p_execution_id,v_tokens,v_status,
    'lf_profile_execution_channel_context_v1',
    case
      when v_status='YELLOW'
        then 'Prefer lazy reads for any additional Product detail.'
      else null
    end,
    v_event_id
  )
  RETURNING id INTO v_budget_event_id;

  v_digest:='sha256:'||encode(
    extensions.digest(convert_to(v_capsule::text,'UTF8'),'sha256'),'hex'
  );

  RETURN p_base_context
    ||jsonb_build_object(
      'status','READY',
      'blocking_code',null,
      'server_validated',true,
      'channel','PRODUCTO',
      'channel_context_mode',
        case
          when v_pc->>'schema_version'='LF_PRODUCT_CANONICAL_RULE_READ_V1'
            then 'CANONICAL_READ_COMPACT'
          else 'HYDRATED_BY_EXECUTION'
        end,
      'context_event_id',v_event_id,
      'context_budget_event_id',v_budget_event_id,
      'context_receipt_ref',
        'supabase://public.lf_eventos/'||v_event_id::text||'#context_receipt',
      'context_receipt_digest',v_digest,
      'context_budget_status',v_status,
      'context_capsule_estimated_tokens',v_tokens,
      'context_capsule_bytes',v_bytes,
      'context_capsule',v_capsule
    );
END
$function$;

DO $verify$
DECLARE v_oid oid:='public.lf_profile_execution_channel_context_v1(text,jsonb,jsonb)'::regprocedure;
BEGIN
 IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_oid)
    OR position('CANONICAL_CONTEXT_COMPACT_LAZY_V1' IN pg_get_functiondef(v_oid))=0
    OR position('BLOCK_PRODUCT_CHANNEL_CONTEXT_BUDGET_RED' IN pg_get_functiondef(v_oid))=0
    OR position('full_snapshot_sha256' IN pg_get_functiondef(v_oid))=0
 THEN RAISE EXCEPTION 'LF_PRODUCT_CONTEXT_COMPACT_POSTCHECK_FAILED'; END IF;
END $verify$;
