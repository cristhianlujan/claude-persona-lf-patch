-- LF / Profile Input Governance / CONTEXT_PACK direct continuation.
-- Removes the profile path dependency on ig_direct_requests_v1 + 30s cron polling.
-- Scope is deliberately narrow:
--   * Router / Gate2 unchanged.
--   * semantic screen selection unchanged.
--   * STORY_CREATOR / MANUAL consumers unchanged.
--   * legacy IG queue objects are not dropped here.
--   * CONTEXT_PACK is dispatched through the canonical released IG orchestrator.
BEGIN;

DO $precheck$
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)'::regprocedure
     )) <> '81112ac1a627653691dd5421e43d5ef0' THEN
    RAISE EXCEPTION 'PROFILE_IG_DIRECT_EDGE_INPUT_VALIDATE_SOURCE_DRIFT';
  END IF;

  IF md5(pg_get_functiondef(
       'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure
     )) <> '197bbe5b24981855fcfd19c6c2d0ac30' THEN
    RAISE EXCEPTION 'PROFILE_IG_DIRECT_EDGE_NATIVE_BRIDGE_SOURCE_DRIFT';
  END IF;

  IF NOT EXISTS(
    SELECT 1
    FROM programacion.contratos c
    JOIN programacion.versiones_agente v ON v.id=c.version_id
    JOIN programacion.agentes a ON a.id=v.agente_id
    WHERE a.agente_codigo='INPUT_GOVERNANCE_AGENT'
      AND c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
      AND c.estado='defined'
      AND c.fail_closed
      AND c.especificacion->>'runtime_orchestrator'
          LIKE 'SUPABASE_EDGE_FUNCTION:%'
      AND EXISTS(
        SELECT 1
        FROM jsonb_array_elements_text(c.especificacion->'allowed_consumers') x(v)
        WHERE x.v='CONTEXT_PACK'
      )
  ) THEN
    RAISE EXCEPTION 'PROFILE_IG_DIRECT_EDGE_CONTRACT_NOT_RESOLVABLE';
  END IF;

  IF NOT EXISTS(
    SELECT 1
    FROM public.lf_capability_registry r
    JOIN public.lf_capability_current c USING(capability_code)
    WHERE r.capability_code='INPUT_GOVERNANCE'
      AND r.status='ACTIVE'
  ) THEN
    RAISE EXCEPTION 'PROFILE_IG_DIRECT_EDGE_CAPABILITY_NOT_CURRENT';
  END IF;
END
$precheck$;

DO $patch_input_validate$
DECLARE
  d text;
  old_decl text := $old$
  v_resolved_scope jsonb;
BEGIN
$old$;
  new_decl text := $new$
  v_resolved_scope jsonb;
  v_ig_runtime_orchestrator text;
  v_ig_runtime_slug text;
BEGIN
$new$;
  old_block text := $old$
  IF coalesce((v_ig->>'applicable')::boolean,false)
     AND coalesce((v_ig->>'continuation_allowed')::boolean,false) IS NOT TRUE THEN

    IF v_ig->>'status'='INPUT_GOVERNANCE_REQUIRED'
       AND v_ig->>'decision'='PENDING'
       AND v_ig->>'consumer'='CONTEXT_PACK'
       AND coalesce(v_ig->>'pantalla_id','') ~ '^[0-9]+$'
    THEN
      v_ig:=v_ig||jsonb_build_object(
        'dispatch',
        programacion.fn_input_governance_queue_submit_v1(
          (v_ig->>'pantalla_id')::integer,
          'CONTEXT_PACK'
        ),
        'dispatch_owner','INPUT_GOVERNANCE_INTERNAL_RUNTIME',
        'dispatch_transport','POSTGRES_SQL_WORKER:ig-direct-sql-worker-v1'
      );
    END IF;

    RETURN jsonb_build_object(
      'status',coalesce(v_ig->>'status','BLOCKED'),
      'blocking_code',coalesce(v_ig->>'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_NOT_READY'),
      'input_governance',
        v_ig||jsonb_build_object(
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false
        ),
      'scope_authority_packet',v_scope->'scope_authority_packet',
      'scope_authority_packet_sha256',v_scope->>'scope_packet_sha256',
      'router_handoff_fingerprint',p_handoff->>'fingerprint_sha256',
      'router_reentry_required',false,
      'next_action','RETRY_INPUT_VALIDATE_AFTER_INPUT_GOVERNANCE'
    );
  END IF;
$old$;
  new_block text := $new$
  IF coalesce((v_ig->>'applicable')::boolean,false)
     AND coalesce((v_ig->>'continuation_allowed')::boolean,false) IS NOT TRUE THEN

    IF v_ig->>'status'='INPUT_GOVERNANCE_REQUIRED'
       AND v_ig->>'decision'='PENDING'
       AND v_ig->>'consumer'='CONTEXT_PACK'
       AND coalesce(v_ig->>'pantalla_id','') ~ '^[0-9]+$'
    THEN
      SELECT c.especificacion->>'runtime_orchestrator'
        INTO v_ig_runtime_orchestrator
      FROM programacion.contratos c
      JOIN programacion.versiones_agente v ON v.id=c.version_id
      JOIN programacion.agentes a ON a.id=v.agente_id
      WHERE a.agente_codigo='INPUT_GOVERNANCE_AGENT'
        AND c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
        AND c.estado='defined'
        AND c.fail_closed
        AND EXISTS(
          SELECT 1
          FROM jsonb_array_elements_text(c.especificacion->'allowed_consumers') x(v)
          WHERE x.v='CONTEXT_PACK'
        )
      ORDER BY c.version_id DESC
      LIMIT 1;

      v_ig_runtime_slug:=case
        when coalesce(v_ig_runtime_orchestrator,'') LIKE 'SUPABASE_EDGE_FUNCTION:%'
          then split_part(v_ig_runtime_orchestrator,':',2)
        else null
      end;

      IF nullif(v_ig_runtime_slug,'') IS NULL
         OR v_ig_runtime_slug !~ '^[a-z0-9][a-z0-9-]{0,62}$' THEN
        RETURN jsonb_build_object(
          'status','BLOCKED',
          'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_RUNTIME_ORCHESTRATOR_INVALID',
          'input_governance',v_ig,
          'router_reentry_required',false
        );
      END IF;

      RETURN jsonb_build_object(
        'status','INPUT_GOVERNANCE_RUNTIME_REQUIRED',
        'blocking_code',null,
        'execution_id',p_execution_id,
        'input_governance',
          v_ig||jsonb_build_object(
            'runtime_request',jsonb_build_object(
              'transport','DIRECT_EDGE_INVOCATION',
              'runtime_orchestrator',v_ig_runtime_orchestrator,
              'runtime_slug',v_ig_runtime_slug,
              'request_body',jsonb_build_object(
                'pantalla_id',(v_ig->>'pantalla_id')::integer,
                'consumer','CONTEXT_PACK'
              ),
              'terminal_statuses',jsonb_build_array(
                'READY','HUMAN_DECISION_REQUIRED','BLOCKED'
              ),
              'continuation_statuses',jsonb_build_array(
                'VALIDATOR_RESUME_REQUIRED'
              ),
              'continuation_action','REINVOKE_SAME_RUNTIME_IMMEDIATELY',
              'queue_required',false,
              'polling_required',false
            ),
            'dispatch_owner','INPUT_GOVERNANCE_INTERNAL_RUNTIME',
            'dispatch_transport','DIRECT_EDGE_INVOCATION',
            'resume_via','EJECUCION_PERFIL_LF/input_validate',
            'router_reentry_required',false
          ),
        'scope_authority_packet',v_scope->'scope_authority_packet',
        'scope_authority_packet_sha256',v_scope->>'scope_packet_sha256',
        'router_handoff_fingerprint',p_handoff->>'fingerprint_sha256',
        'router_reentry_required',false,
        'next_action','RUN_INPUT_GOVERNANCE_RUNTIME_AND_RETRY_SAME_NATIVE_BRIDGE_PREPARE'
      );
    END IF;

    RETURN jsonb_build_object(
      'status',coalesce(v_ig->>'status','BLOCKED'),
      'blocking_code',coalesce(v_ig->>'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_NOT_READY'),
      'input_governance',
        v_ig||jsonb_build_object(
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false
        ),
      'scope_authority_packet',v_scope->'scope_authority_packet',
      'scope_authority_packet_sha256',v_scope->>'scope_packet_sha256',
      'router_handoff_fingerprint',p_handoff->>'fingerprint_sha256',
      'router_reentry_required',false,
      'next_action','RETRY_INPUT_VALIDATE_AFTER_INPUT_GOVERNANCE'
    );
  END IF;
$new$;
BEGIN
  d:=pg_get_functiondef(
    'public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)'::regprocedure
  );

  IF (length(d)-length(replace(d,old_decl,'')))/length(old_decl)<>1 THEN
    RAISE EXCEPTION 'PROFILE_IG_DIRECT_EDGE_INPUT_DECLARE_ANCHOR_DRIFT';
  END IF;
  d:=replace(d,old_decl,new_decl);

  IF (length(d)-length(replace(d,old_block,'')))/length(old_block)<>1 THEN
    RAISE EXCEPTION 'PROFILE_IG_DIRECT_EDGE_INPUT_BLOCK_ANCHOR_DRIFT';
  END IF;
  d:=replace(d,old_block,new_block);

  EXECUTE d;
END
$patch_input_validate$;

DO $patch_native_bridge$
DECLARE
  d text;
  old_block text := $old$
      IF v_input->>'status'='INPUT_GOVERNANCE_REQUIRED'
         AND v_input->>'next_action'='RETRY_INPUT_VALIDATE_AFTER_INPUT_GOVERNANCE'
         AND v_input#>>'{input_governance,dispatch,status}'='QUEUED'
      THEN
        RETURN jsonb_build_object(
          'status','INPUT_GOVERNANCE_PENDING',
          'blocking_code',null,
          'execution_id',p_execution_id,
          'input_validate',v_input,
          'input_governance_request_id',
            v_input#>'{input_governance,dispatch,request_id}',
          'input_governance_transport',
            v_input#>>'{input_governance,dispatch_transport}',
          'next_action','RETRY_SAME_NATIVE_BRIDGE_PREPARE',
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false
        );
      END IF;
$old$;
  new_block text := $new$
      IF v_input->>'status'='INPUT_GOVERNANCE_RUNTIME_REQUIRED'
         AND v_input->>'next_action'='RUN_INPUT_GOVERNANCE_RUNTIME_AND_RETRY_SAME_NATIVE_BRIDGE_PREPARE'
         AND v_input#>>'{input_governance,runtime_request,transport}'='DIRECT_EDGE_INVOCATION'
         AND v_input#>>'{input_governance,runtime_request,request_body,consumer}'='CONTEXT_PACK'
      THEN
        RETURN jsonb_build_object(
          'status','INPUT_GOVERNANCE_RUNTIME_REQUIRED',
          'blocking_code',null,
          'execution_id',p_execution_id,
          'input_validate',v_input,
          'input_governance_runtime_request',
            v_input#>'{input_governance,runtime_request}',
          'input_governance_transport','DIRECT_EDGE_INVOCATION',
          'next_action','RUN_INPUT_GOVERNANCE_RUNTIME_AND_RETRY_SAME_NATIVE_BRIDGE_PREPARE',
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false
        );
      END IF;
$new$;
BEGIN
  d:=pg_get_functiondef(
    'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure
  );

  IF (length(d)-length(replace(d,old_block,'')))/length(old_block)<>1 THEN
    RAISE EXCEPTION 'PROFILE_IG_DIRECT_EDGE_NATIVE_BRIDGE_ANCHOR_DRIFT';
  END IF;

  d:=replace(d,old_block,new_block);
  EXECUTE d;
END
$patch_native_bridge$;

COMMENT ON FUNCTION public.lf_profile_execution_input_validate_v1(text,text,text,jsonb) IS
'Validates authorized profile input. Task-bound CONTEXT_PACK Input Governance uses the released INPUT_GOVERNANCE Edge orchestrator directly when refresh is required; no SQL queue, cron polling or ACT-0001 re-entry is used.';

COMMENT ON FUNCTION public.lf_profile_native_bridge_prepare_v1(text,text,text,text) IS
'Prepares governed GPT_NATIVE profile execution. When CONTEXT_PACK Input Governance requires refresh, exposes a direct Edge runtime request and resumes the same EJECUCION_PERFIL_LF after the IG orchestrator reaches a terminal result.';

DO $postcheck$
DECLARE
  validate_src text;
  bridge_src text;
  orchestrator text;
BEGIN
  validate_src:=pg_get_functiondef(
    'public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)'::regprocedure
  );
  bridge_src:=pg_get_functiondef(
    'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure
  );

  SELECT c.especificacion->>'runtime_orchestrator'
    INTO orchestrator
  FROM programacion.contratos c
  JOIN programacion.versiones_agente v ON v.id=c.version_id
  JOIN programacion.agentes a ON a.id=v.agente_id
  WHERE a.agente_codigo='INPUT_GOVERNANCE_AGENT'
    AND c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
    AND c.estado='defined'
    AND c.fail_closed
  ORDER BY c.version_id DESC
  LIMIT 1;

  IF orchestrator NOT LIKE 'SUPABASE_EDGE_FUNCTION:%' THEN
    RAISE EXCEPTION 'PROFILE_IG_DIRECT_EDGE_ORCHESTRATOR_POSTCHECK_FAIL:%',orchestrator;
  END IF;

  IF strpos(validate_src,'fn_input_governance_queue_submit_v1')>0
     OR strpos(validate_src,'''POSTGRES_SQL_WORKER:ig-direct-sql-worker-v1''')>0
     OR strpos(validate_src,'''INPUT_GOVERNANCE_PENDING''')>0
     OR strpos(bridge_src,'''INPUT_GOVERNANCE_PENDING''')>0
     OR strpos(bridge_src,'input_governance_request_id')>0
  THEN
    RAISE EXCEPTION 'PROFILE_IG_DIRECT_EDGE_QUEUE_RESIDUE_IN_PROFILE_PATH';
  END IF;

  IF strpos(validate_src,'''DIRECT_EDGE_INVOCATION''')=0
     OR strpos(validate_src,'''CONTEXT_PACK''')=0
     OR strpos(validate_src,'''queue_required'',false')=0
     OR strpos(validate_src,'''polling_required'',false')=0
     OR strpos(validate_src,'lf_profile_screen_selector_semantic_prepare_v1')=0
     OR strpos(validate_src,'''DETERMINISTIC_SHORTLIST_THEN_SEMANTIC''')=0
     OR strpos(bridge_src,'''INPUT_GOVERNANCE_RUNTIME_REQUIRED''')=0
     OR strpos(bridge_src,'''RUN_INPUT_GOVERNANCE_RUNTIME_AND_RETRY_SAME_NATIVE_BRIDGE_PREPARE''')=0
  THEN
    RAISE EXCEPTION 'PROFILE_IG_DIRECT_EDGE_REQUIRED_CONTRACT_MISSING';
  END IF;

  IF strpos(validate_src,'''STORY_CREATOR''')>0
     OR strpos(bridge_src,'''STORY_CREATOR''')>0
     OR strpos(validate_src,'lf_router_resolve_v1')>0
     OR strpos(bridge_src,'lf_router_resolve_v1')>0
  THEN
    RAISE EXCEPTION 'PROFILE_IG_DIRECT_EDGE_SCOPE_OR_ROUTER_REGRESSION';
  END IF;
END
$postcheck$;

COMMIT;
