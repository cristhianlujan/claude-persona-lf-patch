-- Governed Gate2 -> GPT_NATIVE bridge for EJECUCION_PERFIL_LF.
-- The bridge is service-role/admin only. Read-only callers never receive mutation authority.
BEGIN;

-- PRODUCTO channel hydration creates a second, governed context event.
-- Trust validation must accept that producer in addition to the base preflight producer.
DO $patch_channel_context_trust$
DECLARE
  v_def text;
  v_old text;
  v_new text;
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_profile_execution_trust_validation_v1(text,text,jsonb)'::regprocedure
     )) <> 'b896393013dcf0cf7d4820432d666572' THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_BRIDGE_TRUST_V1_SOURCE_DRIFT';
  END IF;

  v_def:=pg_get_functiondef(
    'public.lf_profile_execution_trust_validation_v1(text,text,jsonb)'::regprocedure
  );
  v_old:=E'      where id=event_id and created_by_execution_id=p_execution_id and payload->>''producer''=''fn_lf_router_preflight_v1'';\n';
  v_new:=E'      where id=event_id and created_by_execution_id=p_execution_id\n'
    ||E'        and payload->>''producer'' in (''fn_lf_router_preflight_v1'',''lf_profile_execution_channel_context_v1'');\n';

  IF strpos(v_def,v_old)=0 THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_BRIDGE_CONTEXT_TRUST_ANCHOR_MISSING';
  END IF;

  v_def:=replace(v_def,v_old,v_new);
  EXECUTE v_def;
END
$patch_channel_context_trust$;


-- Canonical read/extraction must not hydrate the 75k-token aggregate screen
-- contract. For an exact READ_PRODUCT_DEFINITION, project the directly-bound
-- screen rules compactly and keep the inherited/effective aggregate lazy.
DO $guard_product_channel_context$
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_profile_execution_channel_context_v1(text,jsonb,jsonb)'::regprocedure
     )) <> 'a316971ae1274a1497a7b1d6956c0d40' THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_BRIDGE_CHANNEL_CONTEXT_SOURCE_DRIFT';
  END IF;
END
$guard_product_channel_context$;

CREATE OR REPLACE FUNCTION public.lf_profile_execution_channel_context_v1(
  p_execution_id text,
  p_base_context jsonb,
  p_handoff jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private','extensions','lf_ops','lf_design'
AS $fn$
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
      p_handoff->'scope'
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
      'producer','lf_profile_execution_channel_context_v1',
      'execution_id',p_execution_id,
      'channel','PRODUCTO',
      'base_context_receipt_ref',p_base_context->>'context_receipt_ref',
      'context_receipt',v_capsule
    ),
    'DB_FUNCTION',
    p_execution_id
  ) RETURNING id INTO v_event_id;

  v_budget_event_id:=nextval('private.lf_context_budget_events_v2_id_seq');
  INSERT INTO private.lf_context_budget_events_v2(
    id,execution_id,estimated_tokens,context_status,source,recommendation,
    evidence_event_id
  ) VALUES (
    v_budget_event_id,p_execution_id,v_tokens,v_status,
    'lf_profile_execution_channel_context_v1',
    case
      when v_status='YELLOW'
        then 'Prefer lazy reads for any additional Product detail.'
      else null
    end,
    v_event_id
  );

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
$fn$;

COMMENT ON FUNCTION public.lf_profile_execution_channel_context_v1(text,jsonb,jsonb) IS
'Channel context hydrator for EJECUCION_PERFIL_LF. Exact canonical Product reads receive a compact direct-rule projection with the inherited/effective aggregate lazy; change/analysis tasks retain the full governed Product context path.';

CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_begin_v1(
  p_stage1 jsonb,
  p_semantic_result jsonb,
  p_executor_mode text DEFAULT 'GPT_NATIVE',
  p_actor_execution_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  v_route jsonb;
  v_request jsonb;
  v_validation jsonb;
  v_materialized jsonb;
  v_actor text;
BEGIN
  IF jsonb_typeof(p_stage1)<>'object'
     OR jsonb_typeof(p_semantic_result)<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_INPUT_INVALID'
    );
  END IF;

  IF upper(coalesce(p_executor_mode,''))<>'GPT_NATIVE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_EXECUTOR_MODE',
      'required_executor_mode','GPT_NATIVE'
    );
  END IF;

  v_route:=public.lf_router_route_v1(p_stage1,'{}'::jsonb,false);
  IF v_route->>'paso'<>'PRODUCTO_GATE2_PERFIL'
     OR v_route->>'canal_candidato'<>'PRODUCTO'
     OR v_route->>'negocio_codigo'<>'LF'
     OR jsonb_typeof(v_route->'gate2_request')<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_ROUTE_NOT_READY',
      'route',v_route
    );
  END IF;

  v_request:=v_route->'gate2_request';
  v_validation:=public.lf_router_semantic_resume_validate_v1(
    v_request,p_semantic_result
  );
  IF v_validation->>'status'<>'VALID'
     OR coalesce((v_validation->>'router_resume_allowed')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_GATE2_INVALID',
      'gate2_validation',v_validation
    );
  END IF;

  v_actor:=coalesce(
    nullif(btrim(p_actor_execution_id),''),
    'PROFILE-NATIVE-BRIDGE-'||upper(substr(v_request->>'request_sha256',1,20))
  );

  v_materialized:=public.lf_router_profile_execution_after_gate2_v1(
    v_request,
    p_semantic_result,
    v_route->>'canal_candidato',
    v_route->>'negocio_codigo',
    v_route->'alcance',
    'GPT_NATIVE',
    v_actor,
    NULL
  );

  IF v_materialized->>'status'<>'NATIVE_EXECUTION_READY' THEN
    RETURN v_materialized||jsonb_build_object(
      'bridge_status','BLOCKED',
      'bridge_stage','GATE2_MATERIALIZATION'
    );
  END IF;

  RETURN v_materialized||jsonb_build_object(
    'bridge_status','READY',
    'bridge_stage','NATIVE_EXECUTION_MATERIALIZED',
    'stage1',p_stage1,
    'gate2_validation',v_validation,
    'router_route_summary',jsonb_build_object(
      'paso',v_route->>'paso',
      'canal_candidato',v_route->>'canal_candidato',
      'negocio_codigo',v_route->>'negocio_codigo',
      'perfil_candidato',v_route->>'perfil_candidato'
    )
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)
  FROM PUBLIC,anon,authenticated,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)
  TO service_role;

COMMENT ON FUNCTION public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text) IS
'Trusted bridge entrypoint. Re-derives Stage2 from the supplied LF Stage1 packet, validates semantic Gate2, then materializes EJECUCION_PERFIL_LF in GPT_NATIVE mode. Never grants read-only callers execution authority.';


CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_prepare_v1(
  p_execution_id text,
  p_source_revision text,
  p_source_digest text,
  p_actor_execution_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_handoff jsonb;
  v_valid jsonb;
  v_actor text;
  v_slug text;
  v_source_ref text;
  v_existing text;
  v_step jsonb;
  v_input jsonb;
  v_base_context jsonb;
  v_context jsonb;
  v_baseline jsonb;
  v_clean integer;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR coalesce(p_source_revision,'') !~ '^[0-9a-f]{40}$'
     OR coalesce(p_source_digest,'') !~ '^sha256:[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_SOURCE_BINDING_INVALID'
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.status<>'IN_PROGRESS'
     OR e.manifest->>'executor_mode'<>'GPT_NATIVE'
     OR e.manifest->>'executor_provider'<>'OPENAI_CHATGPT_NATIVE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_EXECUTION_INVALID'
    );
  END IF;

  v_handoff:=e.manifest->'router_profile_handoff';
  v_valid:=public.lf_router_profile_execution_handoff_validate_v1(
    v_handoff,
    v_handoff->>'literal_request',
    e.target_code
  );
  IF coalesce((v_valid->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_HANDOFF_INVALID',
      'handoff_validation',v_valid
    );
  END IF;

  SELECT metadata->>'profile_slug' INTO v_slug
  FROM public.lf_activos
  WHERE codigo_activo=e.target_code
    AND tipo_activo='PERFIL'
    AND archived_at IS NULL;

  IF nullif(v_slug,'') IS NULL
     OR nullif(e.target_repo,'') IS NULL
     OR nullif(e.target_path,'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_SOURCE_UNRESOLVED'
    );
  END IF;

  v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);
  v_source_ref:='github://'||e.target_repo||'@'||p_source_revision||'/'||e.target_path;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='profile_resolve';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'profile_resolve',
      'supabase://public.lf_activos/'||e.target_code,
      jsonb_build_object(
        'exact_profile_resolved',true,
        'codigo_activo',e.target_code,
        'profile_slug',v_slug
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_RESOLVE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='profile_source_read';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'profile_source_read',
      v_source_ref,
      jsonb_build_object(
        'profile_source_ref',v_source_ref,
        'source_revision',p_source_revision,
        'profile_source_digest',p_source_digest,
        'profile_source_path',e.target_path
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_SOURCE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT evidence_payload INTO v_input
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='input_validate'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_input IS NULL THEN
    v_input:=public.lf_profile_execution_input_validate_v1(
      p_execution_id,
      v_handoff->>'literal_request',
      v_source_ref,
      v_handoff
    );

    IF v_input->>'status'<>'READY' THEN
      RETURN jsonb_build_object(
        'status',coalesce(v_input->>'status','BLOCKED'),
        'blocking_code',coalesce(
          v_input->>'blocking_code',
          'BLOCK_PROFILE_NATIVE_BRIDGE_INPUT_VALIDATE_NOT_READY'
        ),
        'execution_id',p_execution_id,
        'input_validate',v_input,
        'router_reentry_required',false
      );
    END IF;

    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'input_validate',
      'supabase://public.lf_profile_execution_input_validate_v1/'||p_execution_id,
      v_input,
      v_actor
    );
  END IF;

  SELECT evidence_payload INTO v_context
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='context_admission'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_context IS NULL THEN
    v_base_context:=public.lf_profile_execution_context_admission_v1(p_execution_id);
    IF v_base_context->>'status'<>'READY' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code',coalesce(
          v_base_context->>'blocking_code',
          'BLOCK_PROFILE_NATIVE_BRIDGE_BASE_CONTEXT_NOT_READY'
        ),
        'base_context',v_base_context
      );
    END IF;

    v_context:=public.lf_profile_execution_channel_context_v1(
      p_execution_id,
      v_base_context,
      v_handoff
    );
    IF v_context->>'status'<>'READY' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code',coalesce(
          v_context->>'blocking_code',
          'BLOCK_PROFILE_NATIVE_BRIDGE_CHANNEL_CONTEXT_NOT_READY'
        ),
        'channel_context',v_context
      );
    END IF;

    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'context_admission',
      v_context->>'context_receipt_ref',
      v_context,
      v_actor
    );
  END IF;

  SELECT evidence_payload INTO v_baseline
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='research_baseline_freeze'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_baseline IS NULL THEN
    v_baseline:=public.lf_profile_execution_research_baseline_v1(
      p_execution_id,
      NULL,
      v_actor
    );
    IF coalesce(v_baseline->>'outcome','') NOT IN (
         'STEP_RECORDED',
         'STEP_ALREADY_RECORDED'
       )
       AND NOT EXISTS(
         SELECT 1
         FROM public.lf_operation_execution_steps
         WHERE execution_id=p_execution_id
           AND step_id='research_baseline_freeze'
           AND status='STEP_PASS_WITH_EVIDENCE'
       ) THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_BASELINE_NOT_READY',
        'baseline_result',v_baseline
      );
    END IF;

    SELECT evidence_payload INTO v_baseline
    FROM public.lf_operation_execution_steps
    WHERE execution_id=p_execution_id
      AND step_id='research_baseline_freeze'
      AND status='STEP_PASS_WITH_EVIDENCE';
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_clean<>7 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PRE_MODEL_STEP_COUNT',
      'clean_step_count',v_clean,
      'expected_clean_step_count',7
    );
  END IF;

  RETURN jsonb_build_object(
    'status','NATIVE_MODEL_INPUT_READY',
    'execution_id',p_execution_id,
    'operation_code','EJECUCION_PERFIL_LF',
    'profile_code',e.target_code,
    'profile_slug',v_slug,
    'profile_source_ref',v_source_ref,
    'profile_source_digest',p_source_digest,
    'literal_request',v_handoff->>'literal_request',
    'input_governance',v_input->'input_governance',
    'context_receipt_ref',v_context->>'context_receipt_ref',
    'context_receipt_digest',v_context->>'context_receipt_digest',
    'context_capsule',v_context->'context_capsule',
    'research_baseline',v_baseline,
    'clean_step_count',v_clean,
    'next_step','execute_profile',
    'next_action','EXECUTE_PRODUCT_DIRECTOR_IN_CURRENT_GPT_NATIVE_CONTEXT',
    'semantic_judge_after_output','INDEPENDENT_CONTEXT_REQUIRED',
    'router_reentry_required',false
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_native_bridge_prepare_v1(text,text,text,text)
  FROM PUBLIC,anon,authenticated,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_profile_native_bridge_prepare_v1(text,text,text,text)
  TO service_role;

COMMENT ON FUNCTION public.lf_profile_native_bridge_prepare_v1(text,text,text,text) IS
'Advances an already authorized GPT_NATIVE EJECUCION_PERFIL_LF through the seven pre-model steps. It validates handoff/scope, applies task-level Input Governance, hydrates channel context, and never calls a model.';


CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_record_output_v1(
  p_execution_id text,
  p_profile_output jsonb,
  p_validation jsonb,
  p_raw_evidence_ref text,
  p_validator_evidence_ref text,
  p_actor_execution_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $fn$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_actor text;
  v_context public.lf_operation_execution_steps%rowtype;
  v_baseline public.lf_operation_execution_steps%rowtype;
  v_source public.lf_operation_execution_steps%rowtype;
  v_existing text;
  v_candidate_digest text;
  v_raw_sha text;
  v_step jsonb;
  v_clean integer;
  v_source_refs jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR jsonb_typeof(p_profile_output)<>'object'
     OR jsonb_typeof(p_validation)<>'object'
     OR coalesce((p_validation->>'valid')::boolean,false) IS NOT TRUE
     OR (
       jsonb_typeof(p_validation->'blocking_codes')='array'
       AND jsonb_array_length(p_validation->'blocking_codes')<>0
     )
     OR nullif(btrim(coalesce(p_raw_evidence_ref,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_validator_evidence_ref,'')),'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_INPUT_INVALID'
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.status<>'IN_PROGRESS'
     OR e.manifest->>'executor_mode'<>'GPT_NATIVE'
     OR e.manifest->>'executor_provider'<>'OPENAI_CHATGPT_NATIVE'
     OR e.manifest ? 'queue_request_id'
     OR nullif(e.manifest->>'runtime_target','') IS NOT NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_EXECUTION_INVALID'
    );
  END IF;

  SELECT * INTO v_context
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='context_admission'
    AND status='STEP_PASS_WITH_EVIDENCE';

  SELECT * INTO v_baseline
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='research_baseline_freeze'
    AND status='STEP_PASS_WITH_EVIDENCE';

  SELECT * INTO v_source
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='profile_source_read'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_context.step_id IS NULL
     OR v_baseline.step_id IS NULL
     OR v_source.step_id IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_PREDECESSOR_NOT_CLEAN'
    );
  END IF;

  v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);
  v_candidate_digest:='sha256:'||encode(
    extensions.digest(convert_to(p_profile_output::text,'UTF8'),'sha256'),
    'hex'
  );
  v_raw_sha=substr(v_candidate_digest,8);
  v_source_refs:=jsonb_build_array(
    v_source.evidence_payload->>'profile_source_ref',
    v_context.evidence_payload->>'context_receipt_ref'
  );

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='execute_profile';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'execute_profile',
      p_raw_evidence_ref,
      jsonb_build_object(
        'context_receipt_digest',v_context.evidence_payload->>'context_receipt_digest',
        'context_receipt_ref',v_context.evidence_payload->>'context_receipt_ref',
        'context_transport',jsonb_build_object(
          'profile_source_mode','JIT_BY_REF',
          'jit_resolver_ref','supabase://public.v_lf_fuente_operativa/EVIDENCE_RESOLVER_REGISTRY',
          'jit_only',true,
          'policy_payloads',false,
          'full_ekb_entries',false,
          'full_readmes',false,
          'full_prefetch_count',0,
          'hydrated_refs','[]'::jsonb
        ),
        'profile_output',p_profile_output,
        'candidate_digest',v_candidate_digest,
        'raw_output_sha256',v_raw_sha,
        'research_baseline_digest',
          v_baseline.evidence_payload#>>'{research_baseline_binding,baseline_digest}',
        'research_baseline_ref',v_baseline.evidence_payload->>'baseline_receipt_ref',
        'source_refs',v_source_refs
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_EXECUTE_PROFILE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='output_validate';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'output_validate',
      p_validator_evidence_ref,
      jsonb_build_object(
        'output_contract_result','PASS',
        'deterministic_validation',
          p_validation||jsonb_build_object(
            'status','PASS',
            'candidate_digest',v_candidate_digest
          ),
        'raw_output_sha256',v_raw_sha
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_VALIDATE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_clean<>9 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_POST_MODEL_STEP_COUNT',
      'clean_step_count',v_clean,
      'expected_clean_step_count',9
    );
  END IF;

  RETURN jsonb_build_object(
    'status','NATIVE_PRODUCER_VALIDATED',
    'execution_id',p_execution_id,
    'profile_code',e.target_code,
    'candidate_digest',v_candidate_digest,
    'raw_output_sha256',v_raw_sha,
    'clean_step_count',v_clean,
    'next_step','semantic_judge',
    'next_action','RUN_INDEPENDENT_SEMANTIC_JUDGE',
    'independent_semantic_judge_required',true,
    'producer_may_self_authorize',false,
    'terminal_authority_ready',false,
    'router_reentry_required',false
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.lf_profile_native_bridge_record_output_v1(
  text,jsonb,jsonb,text,text,text
) FROM PUBLIC,anon,authenticated,supabase_read_only_user;
GRANT EXECUTE ON FUNCTION public.lf_profile_native_bridge_record_output_v1(
  text,jsonb,jsonb,text,text,text
) TO service_role;

COMMENT ON FUNCTION public.lf_profile_native_bridge_record_output_v1(
  text,jsonb,jsonb,text,text,text
) IS
'Records the current-chat GPT_NATIVE producer RAW plus deterministic profile validation. It deliberately stops at 9/11 and requires an independent semantic judge; the producer cannot self-authorize terminal PASS.';


-- Real pre-model canary. The Merge Train applies this migration and therefore
-- owns the only database-write transport used to materialize the execution.
DO $profile_native_login_rules_canary$
DECLARE
  v_stage1 jsonb;
  v_route jsonb;
  v_request jsonb;
  v_body jsonb;
  v_semantic_result jsonb;
  v_begin jsonb;
  v_prepare jsonb;
  v_execution_id text;
  v_actor text;
BEGIN
  v_stage1:=jsonb_build_object(
    'schema_version','LF_ROUTER_STAGE1_V2',
    'texto_original','Dame las reglas en el login B2B',
    'downstream_execution_allowed',false,
    'es_operacion',true,
    'ambiguo',false,
    'formas_busqueda',jsonb_build_array(
      'login B2B','B2B-AUTH-001','reglas login'
    ),
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
  );

  v_route:=public.lf_router_route_v1(v_stage1,'{}'::jsonb,false);
  IF v_route->>'paso'<>'PRODUCTO_GATE2_PERFIL'
     OR v_route->>'perfil_candidato'<>'PERFIL-PRODUCT-DIRECTOR-LF'
     OR v_route#>>'{gate2_request,router_action_binding,profile_task_intent}'
          <>'READ_PRODUCT_DEFINITION'
     OR v_route#>>'{gate2_request,router_action_binding,input_governance_requirement}'
          <>'NOT_REQUIRED_CANONICAL_READ' THEN
    RAISE EXCEPTION
      'PROFILE_NATIVE_LOGIN_RULES_CANARY_ROUTE_FAILED:%',v_route;
  END IF;

  v_request:=v_route->'gate2_request';
  v_body:=jsonb_build_object(
    'schema_version','LF_ROUTER_SEMANTIC_RESULT_V1',
    'request_sha256',v_request->>'request_sha256',
    'decision','RESOLVED',
    'positive_target_refs',jsonb_build_array('PERFIL-PRODUCT-DIRECTOR-LF'),
    'excluded_target_refs',coalesce(v_request->'excluded_target_refs','[]'::jsonb),
    'allowed_scope',coalesce(v_request->'allowed_scope','[]'::jsonb),
    'forbidden_scope',coalesce(v_request->'forbidden_scope','[]'::jsonb),
    'conditions',coalesce(v_request->'conditions','[]'::jsonb),
    'material_ambiguities','[]'::jsonb,
    'clarification_question',null
  );
  v_semantic_result:=v_body||jsonb_build_object(
    'semantic_receipt_sha256',
    encode(
      extensions.digest(convert_to(v_body::text,'UTF8'),'sha256'),
      'hex'
    )
  );

  v_actor:='EXEC-PROFILE-NATIVE-LOGIN-RULES-CANARY-20261024';
  v_begin:=public.lf_profile_native_bridge_begin_v1(
    v_stage1,v_semantic_result,'GPT_NATIVE',v_actor
  );

  IF v_begin->>'status'<>'NATIVE_EXECUTION_READY'
     OR v_begin->>'bridge_status'<>'READY'
     OR v_begin->>'profile_code'<>'PERFIL-PRODUCT-DIRECTOR-LF'
     OR coalesce((v_begin->>'router_reentry_required')::boolean,true) IS TRUE THEN
    RAISE EXCEPTION
      'PROFILE_NATIVE_LOGIN_RULES_CANARY_BEGIN_FAILED:%',v_begin;
  END IF;

  v_execution_id:=v_begin->>'execution_id';
  IF nullif(v_execution_id,'') IS NULL THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_LOGIN_RULES_CANARY_EXECUTION_ID_MISSING';
  END IF;

  v_prepare:=public.lf_profile_native_bridge_prepare_v1(
    v_execution_id,
    'fc88aca0874f3bee7d4dbe29379e975989b26cb2',
    'sha256:1ddca16b29e65e6748f61fdc31e02081ca3990c67b079be705dde3a6a3c58209',
    v_execution_id
  );

  IF v_prepare->>'status'<>'NATIVE_MODEL_INPUT_READY' THEN
    RAISE EXCEPTION
      'PROFILE_NATIVE_LOGIN_RULES_CANARY_PREPARE_FAILED:%',v_prepare;
  END IF;

  IF v_prepare->>'profile_source_ref' <>
       'github://cristhianlujan/claude-persona-lf-patch@fc88aca0874f3bee7d4dbe29379e975989b26cb2/profiles/product_director_lf/SKILL.md'
     OR v_prepare->>'profile_source_digest' <>
       'sha256:1ddca16b29e65e6748f61fdc31e02081ca3990c67b079be705dde3a6a3c58209' THEN
    RAISE EXCEPTION
      'PROFILE_NATIVE_LOGIN_RULES_CANARY_SOURCE_BINDING_FAILED:ref=% digest=%',
      v_prepare->>'profile_source_ref',v_prepare->>'profile_source_digest';
  END IF;

  IF v_prepare#>>'{input_governance,status}'<>'NOT_REQUIRED'
     OR v_prepare#>>'{input_governance,input_governance_requirement}'
          <>'NOT_REQUIRED_CANONICAL_READ' THEN
    RAISE EXCEPTION
      'PROFILE_NATIVE_LOGIN_RULES_CANARY_IG_NOT_SKIPPED:%',
      v_prepare->'input_governance';
  END IF;

  IF coalesce((v_prepare->>'clean_step_count')::integer,0)<>7 THEN
    RAISE EXCEPTION
      'PROFILE_NATIVE_LOGIN_RULES_CANARY_STEP_COUNT:%',
      v_prepare->>'clean_step_count';
  END IF;

  IF v_prepare#>>'{context_capsule,channel_context,product_context,schema_version}'
       <>'LF_PRODUCT_CANONICAL_RULE_READ_V1'
     OR v_prepare#>>'{context_capsule,channel_context,product_context,subject_ref}'
       <>'B2B-AUTH-001'
     OR coalesce((
       v_prepare#>>'{context_capsule,channel_context,product_context,direct_rule_count}'
     )::integer,0)<>71
     OR coalesce((
       v_prepare#>>'{context_capsule,channel_context,product_context,effective_rule_count}'
     )::integer,0)<>283 THEN
    RAISE EXCEPTION
      'PROFILE_NATIVE_LOGIN_RULES_CANARY_CONTEXT_FAILED:%',
      v_prepare#>'{context_capsule,channel_context,product_context}';
  END IF;

  IF coalesce((v_prepare#>>'{context_capsule,context_budget,estimated_tokens}')::integer,999999)>3000
     OR v_prepare#>>'{context_capsule,context_budget,status}' NOT IN ('GREEN','YELLOW') THEN
    RAISE EXCEPTION
      'PROFILE_NATIVE_LOGIN_RULES_CANARY_CONTEXT_BUDGET_FAILED:%',
      v_prepare#>'{context_capsule,context_budget}';
  END IF;
END
$profile_native_login_rules_canary$;


DO $postcheck$
DECLARE
  v_trust text;
BEGIN
  v_trust:=pg_get_functiondef(
    'public.lf_profile_execution_trust_validation_v1(text,text,jsonb)'::regprocedure
  );

  IF position('lf_profile_execution_channel_context_v1' in v_trust)=0 THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_BRIDGE_CHANNEL_CONTEXT_TRUST_NOT_INSTALLED';
  END IF;

  IF has_function_privilege(
       'supabase_read_only_user',
       'public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'supabase_read_only_user',
       'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'supabase_read_only_user',
       'public.lf_profile_native_bridge_record_output_v1(text,jsonb,jsonb,text,text,text)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_BRIDGE_READ_ONLY_EXECUTION_GRANT_FORBIDDEN';
  END IF;

  IF NOT has_function_privilege(
       'service_role',
       'public.lf_profile_native_bridge_begin_v1(jsonb,jsonb,text,text)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'service_role',
       'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)',
       'EXECUTE'
     )
     OR NOT has_function_privilege(
       'service_role',
       'public.lf_profile_native_bridge_record_output_v1(text,jsonb,jsonb,text,text,text)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_BRIDGE_SERVICE_ROLE_GRANT_MISSING';
  END IF;
END
$postcheck$;

COMMIT;
