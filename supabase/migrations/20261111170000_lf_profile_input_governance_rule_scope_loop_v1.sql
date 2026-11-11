-- Issue #3779 | Step40 REGLA scope via existing screen IG, no second IG or Router change.
-- Source-first, sandbox/CI candidate; never direct apply. PANTALLA branch preserved.
BEGIN;
DO $check_live$
BEGIN
 IF md5(pg_get_functiondef(
  'public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)'::regprocedure))
    IS DISTINCT FROM '9293aa23cb29f3bb984a37799b6e5ff3'
 THEN RAISE EXCEPTION 'BLOCK_PROFILE_RULE_SCOPE_STEP40_LIVE_MD5_DRIFT'; END IF;
 -- Writer source is separately pinned and patched by preceding #3787 migration.
END $check_live$;
-- Read-only internal extension of the existing profile IG dependency.
-- Calls the EXACT existing per-screen IG; it is not a second IG entrypoint.
CREATE FUNCTION public.lf_profile_rule_screen_loop_preflight_v1(
 p_execution_id text,p_handoff jsonb
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','programacion','lf_ops'
AS $rule_scope$
DECLARE
 v_parent public.lf_operation_execution%ROWTYPE;
 v_scope jsonb:=p_handoff->'scope';
 v_hint text:=nullif(btrim(coalesce(v_scope->>'target_hint','')),'');
 v_mode text;
 v_rule_code text;
 v_rule_count integer;
 v_catalog_sha text;
 v_edge_count integer;
 v_linked integer;
 v_active integer;
 v_inactive integer;
 v_bad integer:=0;
 v_screen_count integer:=0;
 v_current jsonb;
 v_ig_raw jsonb;
 v_results jsonb:='[]'::jsonb;
 v_unlinked jsonb:='[]'::jsonb;
 v_unlinked_count integer:=0;
 v_inactive_count integer:=0;
 v_rule_sha text;
 v_authority jsonb;
 v_s record;
 v_r record;
 v_return_status text;
 v_blocking_code text;
BEGIN
 SELECT * INTO v_parent FROM public.lf_operation_execution
 WHERE execution_id=p_execution_id AND operation_code='EJECUCION_PERFIL_LF'
   AND target_type='PERFIL' AND target_code='PERFIL-PRODUCT-DIRECTOR-LF'
   AND status='IN_PROGRESS';
 IF NOT FOUND OR v_parent.manifest->>'read_only' IS DISTINCT FROM 'true'
   OR v_parent.manifest->>'no_write' IS DISTINCT FROM 'true'
   OR v_parent.manifest->>'no_promotion' IS DISTINCT FROM 'true'
   OR v_parent.manifest#>>'{router_profile_handoff,router_authorization_receipt,profile_execution_allowed}'
     IS DISTINCT FROM 'true'
 THEN RETURN jsonb_build_object('status','BLOCKED','applicable',true,
   'blocking_code','BLOCK_PROFILE_RULE_IG_PARENT_NOT_AUTHORIZED',
   'decision','BLOCKED','continuation_allowed',false); END IF;
 IF p_handoff IS DISTINCT FROM v_parent.manifest->'router_profile_handoff'
   OR upper(coalesce(v_scope->>'target_type',''))<>'REGLA'
 THEN RETURN jsonb_build_object('status','BLOCKED','applicable',true,
   'blocking_code','BLOCK_PROFILE_RULE_IG_HANDOFF_SCOPE_CHANGED',
   'decision','BLOCKED','continuation_allowed',false); END IF;
 v_authority:=public.lf_profile_input_governance_requirement_v1(p_handoff);
 IF v_authority->>'status' IS DISTINCT FROM 'REQUIRED'
    OR v_authority->>'input_governance_requirement' IS DISTINCT FROM 'REQUIRED_BY_TASK'
 THEN RETURN jsonb_build_object('status','BLOCKED','applicable',true,
   'blocking_code','BLOCK_PROFILE_RULE_IG_REQUIRED_TASK_NOT_ATTESTED',
   'decision','BLOCKED','continuation_allowed',false); END IF;

 IF upper(coalesce(v_scope->>'resolution_status',''))='RESOLVED'
    AND v_hint ~ '^[A-Z0-9][A-Z0-9_-]{3,159}$' THEN
   v_mode:='ONE_CANONICAL_RULE';v_rule_code:=v_hint;
   SELECT count(*) INTO v_rule_count FROM lf_ops.reglas WHERE codigo=v_rule_code;
   IF v_rule_count<>1 THEN RETURN jsonb_build_object(
     'status','BLOCKED','applicable',true,'decision','BLOCKED',
     'blocking_code','BLOCK_PROFILE_RULE_IG_RULE_NOT_FOUND',
     'rule_code',v_rule_code,'continuation_allowed',false); END IF;
   v_rule_sha:=public.lf_asset_snapshot_sha_v1('REGLA',v_rule_code);
   IF coalesce(v_rule_sha,'') !~ '^[0-9a-f]{64}$'
     OR (v_scope ? 'expected_rule_sha256' AND
       v_scope->>'expected_rule_sha256' IS DISTINCT FROM v_rule_sha)
   THEN RETURN jsonb_build_object(
     'status','BLOCKED','applicable',true,'decision','BLOCKED',
     'blocking_code','BLOCK_PROFILE_RULE_IG_SOURCE_HASH_CHANGED',
     'rule_code',v_rule_code,'continuation_allowed',false); END IF;
 ELSIF upper(coalesce(v_scope->>'resolution_status',''))='UNRESOLVED'
       AND v_hint='Conjunto canónico 578 reglas lf_ops.reglas' THEN
   v_mode:='ALL_CANONICAL_RULES';
   SELECT count(*),md5(string_agg(r.id::text||':'||r.codigo,E'\n'
     ORDER BY r.id)) INTO v_rule_count,v_catalog_sha FROM lf_ops.reglas r;
   SELECT count(*) INTO v_edge_count FROM lf_ops.reglas_pantallas;
   IF v_rule_count<>578 OR v_edge_count<>6176
     OR v_catalog_sha IS DISTINCT FROM 'c758e1215c5fe5a11d34d42456a09664'
     OR (v_scope ? 'expected_catalog_md5' AND
         v_scope->>'expected_catalog_md5' IS DISTINCT FROM v_catalog_sha)
   THEN RETURN jsonb_build_object(
     'status','BLOCKED','applicable',true,'decision','BLOCKED',
     'blocking_code','BLOCK_PROFILE_RULE_IG_BATCH_SOURCE_HASH_CHANGED',
     'observed_rule_count',v_rule_count,'observed_catalog_md5',v_catalog_sha,
     'continuation_allowed',false); END IF;
 ELSE RETURN jsonb_build_object(
   'status','BLOCKED','applicable',true,'decision','BLOCKED',
   'blocking_code','BLOCK_PROFILE_RULE_IG_SCOPE_UNRESOLVED',
   'continuation_allowed',false); END IF;

 -- Canonical rule identity is read directly even when no screen exists.
 -- Never manufacture an association or infer screen validation.
 FOR v_r IN SELECT r.codigo,
   count(rp.pantalla_id) AS linked,
   count(rp.pantalla_id) FILTER(WHERE p.activa) AS active,
   count(rp.pantalla_id) FILTER(WHERE NOT p.activa) AS inactive
   FROM lf_ops.reglas r
   LEFT JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
   LEFT JOIN lf_ops.pantallas p ON p.id=rp.pantalla_id
   WHERE v_mode='ALL_CANONICAL_RULES' OR r.codigo=v_rule_code
   GROUP BY r.id,r.codigo ORDER BY r.codigo
 LOOP
   v_rule_sha:=public.lf_asset_snapshot_sha_v1('REGLA',v_r.codigo);
   IF coalesce(v_rule_sha,'') !~ '^[0-9a-f]{64}$'
   THEN RETURN jsonb_build_object(
      'status','BLOCKED','applicable',true,'decision','BLOCKED',
      'blocking_code','BLOCK_PROFILE_RULE_IG_RULE_SOURCE_UNVERIFIED',
      'rule_code',v_r.codigo,'continuation_allowed',false); END IF;
   IF v_r.active=0 THEN
      IF v_r.inactive>0 THEN v_inactive_count:=v_inactive_count+1;
      ELSE v_unlinked_count:=v_unlinked_count+1; END IF;
      v_unlinked:=v_unlinked||jsonb_build_array(jsonb_build_object(
        'rule_code',v_r.codigo,'source_snapshot_sha256',v_rule_sha,
        'scope_class',CASE WHEN v_r.inactive>0 THEN
          'INACTIVE_SCREEN_SCOPE_DECISION_REQUIRED'
          ELSE 'CANONICAL_RULE_NO_SCREEN' END,
        'source_present',true,
        'screen_ig_ready',false));
   END IF;
 END LOOP;

 -- Distinct screen IDs: 6,176 links do not imply 6,176 IG invocations.
 -- Existing IG owns its CURRENT and freshness validation.
 FOR v_s IN SELECT DISTINCT p.id,p.codigo
   FROM lf_ops.pantallas p
   JOIN lf_ops.reglas_pantallas rp ON rp.pantalla_id=p.id
   JOIN lf_ops.reglas r ON r.id=rp.regla_id
   WHERE p.activa AND (v_mode='ALL_CANONICAL_RULES'
                    OR r.codigo=v_rule_code)
   ORDER BY p.codigo,p.id
 LOOP
   v_screen_count:=v_screen_count+1;
   v_ig_raw:=programacion.fn_input_governance_execute(v_s.id,'CONTEXT_PACK');
   v_current:=NULL;
   IF v_ig_raw->>'status'='READY'
     AND v_ig_raw->>'execution_mode'='REUSE_COMPLETED_CURRENT_RUN'
     AND coalesce(v_ig_raw->>'run_id','') ~ '^[1-9][0-9]*$'
     AND coalesce(v_ig_raw->>'output_sha256','') ~ '^[0-9a-f]{64}$'
   THEN
     v_current:=programacion.fn_input_run_source_currentness_v1(
         (v_ig_raw->>'run_id')::bigint);
   END IF;
   IF v_ig_raw->>'status' IS DISTINCT FROM 'READY'
      OR coalesce((v_current->>'source_current')::boolean,false) IS NOT TRUE
   THEN v_bad:=v_bad+1; END IF;
   v_results:=v_results||jsonb_build_array(jsonb_build_object(
     'pantalla_id',v_s.id,'screen_code',v_s.codigo,
     'ig_status',v_ig_raw->>'status',
     'ig_run_id',v_ig_raw->'run_id',
     'ig_output_sha256',v_ig_raw->>'output_sha256',
     'source_current',coalesce((v_current->>'source_current')::boolean,false),
     'validated_by','CURRENTNESS_AUTHORITY',
     'screen_ig_ready',v_ig_raw->>'status'='READY'
         AND coalesce((v_current->>'source_current')::boolean,false)));
 END LOOP;
 IF v_inactive_count>0 THEN
   v_return_status:='BLOCKED';
   v_blocking_code:='BLOCK_PROFILE_RULE_IG_INACTIVE_SCREEN_SCOPE_UNATTESTED';
 ELSIF v_bad>0 THEN
   v_return_status:='BLOCKED';
   v_blocking_code:='BLOCK_PROFILE_RULE_IG_SCREEN_NOT_CURRENT';
 ELSE
   v_return_status:='READY';v_blocking_code:=NULL;
 END IF;
 RETURN jsonb_build_object(
   'applicable',true,'status',v_return_status,
   'blocking_code',v_blocking_code,
   'decision',CASE WHEN v_return_status='READY' THEN 'PASS' ELSE 'BLOCKED' END,
   'continuation_allowed',v_return_status='READY',
   'profile_code',v_parent.target_code,'scope_type','REGLA',
   'scope_mode',v_mode,'consumer','CONTEXT_PACK',
   'binding_mode','DIRECT_PROFILE_RULE_SCREEN_LOOP',
   'rule_count',v_rule_count,'rule_code',v_rule_code,
   'catalog_md5',v_catalog_sha,'rule_source_sha256',
      CASE WHEN v_mode='ONE_CANONICAL_RULE' THEN
        public.lf_asset_snapshot_sha_v1('REGLA',v_rule_code) ELSE NULL END,
   'screen_count',v_screen_count,
   'screen_not_current_count',v_bad,
   'screen_results',v_results,
   'no_screen_rule_count',v_unlinked_count,
   'inactive_only_rule_count',v_inactive_count,
   'canonical_rule_exceptions',v_unlinked,
   'source_scope_validated',true,
   'currentness_authority_checked',v_screen_count>0,
   'screen_ig_required_only_when_linked',true,
   'mutation_authorized',false,
   'production_authorized',false,
   'promotion_authorized',false,
   'governance_receipts_independent',false,
   'router_reentry_required',false);
END $rule_scope$;
REVOKE ALL ON FUNCTION public.lf_profile_rule_screen_loop_preflight_v1(text,jsonb)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_rule_screen_loop_preflight_v1(text,jsonb)
 TO service_role;
CREATE OR REPLACE FUNCTION public.lf_profile_execution_input_validate_v1(p_execution_id text, p_input_literal text, p_input_source_ref text, p_handoff jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'programacion'
AS $function$
DECLARE
  v_exec public.lf_operation_execution%rowtype;
  v_handoff_validation jsonb;
  v_scope jsonb;
  v_adapters jsonb:='[]'::jsonb;
  v_ig jsonb;
  v_direct_profile_ig boolean:=false;
  v_task_requirement jsonb;
  v_screen_request jsonb;
  v_screen_result jsonb;
  v_screen_validation jsonb;
  v_resolved_scope jsonb;
  v_ig_runtime_orchestrator text;
  v_ig_runtime_slug text;
BEGIN
  SELECT * INTO v_exec
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR v_exec.operation_code<>'EJECUCION_PERFIL_LF'
     OR v_exec.target_type<>'PERFIL'
     OR v_exec.status<>'IN_PROGRESS' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_INPUT_VALIDATE_EXECUTION_INVALID',
      'router_reentry_required',false
    );
  END IF;

  v_handoff_validation:=public.lf_router_profile_execution_handoff_validate_v1(
    p_handoff,p_input_literal,v_exec.target_code
  );
  IF coalesce((v_handoff_validation->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_INPUT_VALIDATE_HANDOFF_INVALID',
      'handoff_validation',v_handoff_validation,
      'router_reentry_required',false
    );
  END IF;

  v_scope:=public.lf_profile_execution_scope_authority_packet_v1(
    p_execution_id,p_input_literal,p_input_source_ref
  );
  IF v_scope->>'status' IS DISTINCT FROM 'READY'
     OR jsonb_typeof(v_scope->'scope_authority_packet')<>'object'
     OR nullif(v_scope->>'scope_packet_sha256','') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_INPUT_VALIDATE_SCOPE_NOT_READY',
      'scope_result',v_scope,
      'router_reentry_required',false
    );
  END IF;

  v_task_requirement:=public.lf_profile_input_governance_requirement_v1(p_handoff);
  IF v_task_requirement->>'status'='BLOCKED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code',coalesce(v_task_requirement->>'blocking_code','BLOCK_PROFILE_IG_TASK_BINDING_INVALID'),
      'input_governance_task',v_task_requirement,
      'router_reentry_required',false
    );
  END IF;

  IF v_task_requirement->>'status'='NOT_REQUIRED' THEN
    v_ig:=jsonb_build_object(
      'applicable',false,
      'status','NOT_REQUIRED',
      'blocking_code',null,
      'decision','SKIP',
      'continuation_allowed',true,
      'binding_mode','DIRECT_PROFILE_CAPABILITY_NOT_INVOKED',
      'profile_task_intent',v_task_requirement->>'profile_task_intent',
      'input_governance_requirement',v_task_requirement->>'input_governance_requirement',
      'reason',v_task_requirement->>'reason'
    );
  ELSE
    SELECT EXISTS(
      SELECT 1
      FROM public.lf_activo_relaciones r
      WHERE r.codigo_activo=v_exec.target_code
        AND r.relacionado_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
        AND r.relacion_tipo='GOBERNADO_POR'
    ) INTO v_direct_profile_ig;

    IF v_direct_profile_ig AND upper(coalesce(p_handoff#>>'{scope,target_type}',''))='REGLA' THEN
      v_ig:=public.lf_profile_rule_screen_loop_preflight_v1(p_execution_id,p_handoff);
    ELSIF v_direct_profile_ig THEN
      IF upper(coalesce(p_handoff#>>'{scope,target_type}',''))<>'PANTALLA' THEN
        RETURN jsonb_build_object(
          'status','BLOCKED',
          'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_SCREEN_SCOPE_REQUIRED',
          'router_reentry_required',false
        );
      END IF;

      v_screen_request:=public.lf_profile_screen_selector_semantic_prepare_v1(
        p_input_literal,
        p_handoff->'scope'
      );

      IF v_screen_request->>'status'<>'READY'
         OR coalesce((v_screen_request->>'candidate_screen_count')::integer,0)<=0 THEN
        RETURN jsonb_build_object(
          'status','SCREEN_SELECTION_NO_MATCH',
          'blocking_code','BLOCK_PROFILE_SCREEN_SELECTION_NO_CANDIDATES',
          'screen_selection_request',v_screen_request,
          'router_reentry_required',false,
          'next_action','REFINE_OR_CLARIFY_SCREEN_SCOPE'
        );
      END IF;

      v_screen_result:=v_exec.manifest->'screen_selection_result';

      IF v_screen_result IS NULL OR jsonb_typeof(v_screen_result)<>'object' THEN
        RETURN jsonb_build_object(
          'status','SCREEN_SELECTION_REQUIRED',
          'blocking_code',null,
          'execution_id',p_execution_id,
          'screen_selection_request',v_screen_request,
          'selection_mode','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC',
          'semantic_selection_required',true,
          'submit_entrypoint','public.lf_profile_screen_selector_semantic_submit_v1',
          'submit_raw_entrypoint','public.lf_profile_screen_selector_semantic_submit_raw_v1',
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false,
          'next_action','RUN_SCREEN_SEMANTIC_SELECTION_AND_SUBMIT'
        );
      END IF;

      v_screen_validation:=public.lf_profile_screen_selector_semantic_validate_v1(
        v_screen_request,v_screen_result
      );

      IF v_screen_validation->>'status'<>'VALID' THEN
        RETURN jsonb_build_object(
          'status','BLOCKED',
          'blocking_code','BLOCK_PROFILE_SCREEN_SELECTION_RECEIPT_INVALID',
          'screen_selection_validation',v_screen_validation,
          'router_reentry_required',false
        );
      END IF;

      IF v_screen_result->>'decision'='AMBIGUOUS' THEN
        RETURN jsonb_build_object(
          'status','SCREEN_SELECTION_AMBIGUOUS',
          'blocking_code','BLOCK_PROFILE_SCREEN_SELECTION_AMBIGUOUS',
          'screen_selection_request',v_screen_request,
          'screen_selection_result',v_screen_result,
          'screen_selection_validation',v_screen_validation,
          'router_reentry_required',false,
          'next_action','HUMAN_OR_CALLER_DECISION_REQUIRED'
        );
      ELSIF v_screen_result->>'decision'='NO_MATCH' THEN
        RETURN jsonb_build_object(
          'status','SCREEN_SELECTION_NO_MATCH',
          'blocking_code','BLOCK_PROFILE_SCREEN_SELECTION_NO_MATCH',
          'screen_selection_request',v_screen_request,
          'screen_selection_result',v_screen_result,
          'screen_selection_validation',v_screen_validation,
          'router_reentry_required',false,
          'next_action','REFINE_OR_CLARIFY_SCREEN_SCOPE'
        );
      ELSIF v_screen_result->>'decision'<>'SELECTED' THEN
        RETURN jsonb_build_object(
          'status','BLOCKED',
          'blocking_code','BLOCK_PROFILE_SCREEN_SELECTION_DECISION_INVALID',
          'screen_selection_result',v_screen_result,
          'router_reentry_required',false
        );
      END IF;

      v_resolved_scope:=coalesce(p_handoff->'scope','{}'::jsonb)
        ||jsonb_build_object(
          'target_hint',v_screen_result->>'selected_screen_code',
          'resolution_status','RESOLVED',
          'resolved_screen_code',v_screen_result->>'selected_screen_code',
          'resolution_method','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC',
          'screen_selection_request',v_screen_request,
          'screen_selection_result',v_screen_result
        );

      v_ig:=programacion.fn_lf_profile_input_governance_resolve_v1(
        p_input_literal,
        v_exec.target_code,
        v_resolved_scope,
        'CONTEXT_PACK'
      );

      v_ig:=v_ig||jsonb_build_object(
        'screen_selection',jsonb_build_object(
          'request_sha256',v_screen_request->>'request_sha256',
          'catalog_sha256',v_screen_request->>'catalog_sha256',
          'decision',v_screen_result->>'decision',
          'selected_screen_code',v_screen_result->>'selected_screen_code',
          'semantic_receipt_sha256',v_screen_result->>'semantic_receipt_sha256'
        )
      );
    ELSE
      SELECT coalesce(jsonb_agg(to_jsonb(x) order by x.adapter_code),'[]'::jsonb)
        INTO v_adapters
      FROM public.v_lf_router_adapter_bindings x
      WHERE x.target_asset_code=v_exec.target_code;

      IF jsonb_array_length(v_adapters)>0 THEN
        v_ig:=programacion.fn_lf_profile_adapter_input_governance_resolve_v1(
          p_input_literal,v_adapters,'CONTEXT_PACK'
        );
      ELSE
        v_ig:=jsonb_build_object(
          'applicable',false,
          'status','NOT_REQUIRED',
          'blocking_code',null,
          'decision','N/A',
          'continuation_allowed',true,
          'required_by_adapters','[]'::jsonb,
          'binding_mode','NONE'
        );
      END IF;
    END IF;
  END IF;

  -- Scope validation and IG security clearance are distinct decisions.
  -- Read-only report work may continue with VERIFIED internal findings;
  -- downstream effects and any IG READY/production claim remain prohibited.
  IF v_task_requirement->>'status'='REQUIRED'
     AND v_exec.manifest->>'read_only'='true'
     AND v_exec.manifest->>'no_write'='true'
     AND v_exec.manifest->>'no_promotion'='true'
     AND v_exec.manifest->>'automatic_impact'='false'
     AND v_exec.manifest->>'governed_repair_write'='false'
     AND p_handoff#>>'{scope,target_type}'='PANTALLA'
     AND v_ig->>'applicable'='true'
     AND v_ig->>'status'='BLOCKED'
     AND v_ig->>'decision'='BLOCKED'
     AND v_ig->>'continuation_allowed'='false'
     AND v_ig->>'blocking_code'='BLOCK_PROFILE_INPUT_GOVERNANCE'
     AND v_ig->>'profile_code'=v_exec.target_code
     AND v_ig->>'consumer'='CONTEXT_PACK'
     AND v_ig->>'binding_mode'='DIRECT_PROFILE'
     AND v_ig->>'pantalla_id' ~ '^[1-9][0-9]*$'
     AND jsonb_typeof(v_ig->'governance_result')='object'
     AND v_ig#>>'{governance_result,status}'='BLOCKED'
     AND v_ig#>>'{governance_result,consumer}'='CONTEXT_PACK'
     AND v_ig#>>'{governance_result,pantalla_id}'=v_ig->>'pantalla_id'
     AND v_ig#>>'{governance_result,remediation_state}'='INTERNAL_REMEDIATION_REQUIRED'
     AND v_ig#>>'{governance_result,owner_interruption_required}'='false'
     AND v_ig#>>'{governance_result,promotion_authorized}'='false'
     AND v_ig#>>'{governance_result,production_authorized}'='false'
     AND v_ig#>>'{governance_result,execution_mode}'='REUSE_COMPLETED_CURRENT_RUN'
     AND v_ig#>>'{governance_result,run_id}' ~ '^[1-9][0-9]*$'
     AND coalesce(v_ig#>>'{governance_result,output_sha256}','') ~ '^[0-9a-f]{64}$'
     AND v_ig#>>'{governance_result,predecision_crosscheck,status}'='CANONICAL_READBACK_ONLY'
     AND v_ig#>>'{governance_result,predecision_crosscheck,run_id}'=v_ig#>>'{governance_result,run_id}'
     AND coalesce(v_ig#>>'{governance_result,predecision_crosscheck,deterministic_finding_count}','') ~ '^[1-9][0-9]*$'
  THEN
    RETURN jsonb_build_object(
      'status','READY',
      'blocking_code',null,
      'server_validated',true,
      'input_scope','ROUTER_AUTHORIZED_PROFILE_EXECUTION',
      'activation_trigger_match',true,
      'scope_authority_packet',v_scope->'scope_authority_packet',
      'scope_authority_packet_sha256',v_scope->>'scope_packet_sha256',
      'analysis_scope','READ_ONLY_WITH_IG_FINDINGS',
      'input_validation_only',true,
      'ig_security_state','BLOCKED',
      'ig_security_clearance',false,
      'ig_continuation_allowed',false,
      'production_authorized',false,
      'promotion_authorized',false,
      'mutation_authorized',false,
      'allowed_actions',jsonb_build_array('ANALYZE','PROPOSE','VALIDATE','REPORT'),
      'input_governance',
        v_ig||jsonb_build_object(
          'analysis_scope','READ_ONLY_WITH_IG_FINDINGS',
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false
        ),
      'router_handoff_fingerprint',p_handoff->>'fingerprint_sha256',
      'router_reentry_required',false
    );
  END IF;

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

  RETURN jsonb_build_object(
    'status','READY',
    'blocking_code',null,
    'server_validated',true,
    'input_scope','ROUTER_AUTHORIZED_PROFILE_EXECUTION',
    'activation_trigger_match',true,
    'scope_authority_packet',v_scope->'scope_authority_packet',
    'scope_authority_packet_sha256',v_scope->>'scope_packet_sha256',
    'input_governance',
      coalesce(v_ig,'{}'::jsonb)||jsonb_build_object(
        'resume_via','EJECUCION_PERFIL_LF/input_validate',
        'router_reentry_required',false
      ),
    'router_handoff_fingerprint',p_handoff->>'fingerprint_sha256',
    'router_reentry_required',false
  );
END
$function$
;
REVOKE ALL ON FUNCTION public.lf_profile_execution_input_validate_v1(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_execution_input_validate_v1(text,text,text,jsonb) TO service_role;
COMMIT;
