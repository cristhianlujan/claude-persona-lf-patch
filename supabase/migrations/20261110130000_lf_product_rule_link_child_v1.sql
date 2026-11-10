-- LF #3774 / Lote 2: Product-owned RULE_LINK_APPLY. Candidate: no runtime cutover.
-- Reuses VINCULACION_REGLA_PANTALLA_LF and its 5 canonical judged steps.
-- Parent EJECUCION_PERFIL_LF remains READ_ONLY/NO_WRITE; child owns the link.
BEGIN;
DO $pre$
BEGIN
 IF md5(pg_get_functiondef('public.lf_skill_invoke_v1(text,text,jsonb)'::regprocedure))
   <> 'ac7e351e1834cbfb91aabf26e1a04a8d'
 OR md5(pg_get_functiondef('public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure))
   <> 'fe08a25c8e3c023d7181194d2dfdee0d'
 THEN RAISE EXCEPTION 'LINK_CHILD_SOURCE_DRIFT'; END IF;
 IF (SELECT count(*) FROM public.lf_skill_catalog_v1
   WHERE skill_code='RULE_LINK_APPLY' AND status='READY'
   AND opener_fn IS NULL AND effect='WRITE_GOVERNED'
   AND required_operation='VINCULACION_REGLA_PANTALLA_LF')<>1
 OR (SELECT count(*) FROM public.lf_operation_contracts
   WHERE operation_code='VINCULACION_REGLA_PANTALLA_LF'
   AND contract_code='CONTRACT-VINCULACION-REGLA-PANTALLA-LF-v1.1.0'
   AND status='ACTIVE_ENFORCEMENT')<>1
 OR (SELECT count(*) FROM public.lf_operation_registry
   WHERE operation_code='VINCULACION_REGLA_PANTALLA_LF'
   AND status='PRODUCCION_CONTROLADA')<>1
 THEN RAISE EXCEPTION 'LINK_CHILD_CATALOG_DRIFT'; END IF;
 IF to_regprocedure('public.lf_skill_o_rule_link_v1(text,jsonb,text,text,text)') IS NOT NULL
 THEN RAISE EXCEPTION 'LINK_CHILD_ALREADY_EXISTS'; END IF;
END $pre$;

-- Existing registered core decides PASS; not a direct insertion of PASS rows.
CREATE FUNCTION public.lf_skill_rule_link_step_v1(
 p_child text,p_step text,p_payload jsonb,p_ref text
) RETURNS void LANGUAGE plpgsql SECURITY INVOKER
SET search_path='pg_catalog','public'
AS $step$
DECLARE v jsonb;
BEGIN
 v:=public.lf_record_operation_step_core_v1(
 p_child,p_step,p_ref,p_payload,p_child,
 'VINCULACION_REGLA_PANTALLA_LF','REGLA_PANTALLA_RELATION',
 'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
 jsonb_build_object('valid',true,'code','SERVER_LINK_V1',
  'server_assertions',jsonb_build_array('required_evidence_present'),
  'server_hard_fails','[]'::jsonb),
 false,'lf_skill_rule_link_step_v1');
 IF v->>'outcome'<>'STEP_RECORDED' OR v->>'status'<>'PASS_CLEAN'
 THEN RAISE EXCEPTION 'LINK_CHILD_STEP_FAIL:%:%',p_step,coalesce(v->>'code','UNKNOWN'); END IF;
END $step$;

CREATE FUNCTION public.lf_skill_o_rule_link_v1(
 p_child text,p_input jsonb,p_parent text,p_run text,p_request_sha text
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER
SET search_path='pg_catalog','public','lf_ops','extensions'
AS $opener$
DECLARE
 par public.lf_operation_execution%ROWTYPE;
 inv public.lf_skill_invocation_v1%ROWTYPE;
 r lf_ops.reglas%ROWTYPE; s lf_ops.pantallas%ROWTYPE;
 outp jsonb; val jsonb; judge jsonb; refs jsonb; intent jsonb;
 op jsonb; rv jsonb; sh text; code text; sid int; ev text;
BEGIN
 IF p_input IS NULL OR jsonb_typeof(p_input)<>'object'
  OR coalesce(p_input->>'regla_codigo','') !~ '^[A-Z0-9][A-Z0-9_-]{3,159}$'
  OR coalesce(p_input->>'pantalla_id','') !~ '^[1-9][0-9]{0,8}$'
  OR p_input->>'target_type' IS DISTINCT FROM 'REGLA_PANTALLA_RELATION'
  OR p_input->>'target_code' IS DISTINCT FROM
     (p_input->>'regla_codigo')||'@'||(p_input->>'pantalla_id')
  OR coalesce(p_input->>'decision_id','')=''
  OR coalesce(p_input->>'analysis_snapshot_sha256','') !~ '^[0-9a-f]{64}$'
  OR jsonb_typeof(p_input->'link_intent') IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'LINK_CHILD_INPUT_INVALID'; END IF;
 code:=p_input->>'regla_codigo'; sid:=(p_input->>'pantalla_id')::int;
 intent:=p_input->'link_intent';
 IF (SELECT count(*) FROM jsonb_object_keys(intent))<>3
  OR intent->>'change_kind' IS DISTINCT FROM 'LINK_EXISTING_RULE'
  OR intent->>'rule_code' IS DISTINCT FROM code
 THEN RAISE EXCEPTION 'LINK_CHILD_INTENT_INVALID'; END IF;
 SELECT * INTO par FROM public.lf_operation_execution
 WHERE execution_id=p_parent AND operation_code='EJECUCION_PERFIL_LF'
  AND target_type='PERFIL' AND target_code='PERFIL-PRODUCT-DIRECTOR-LF'
  AND status='IN_PROGRESS' FOR UPDATE;
 IF NOT FOUND OR par.request_sha256 IS DISTINCT FROM p_request_sha
  OR par.manifest->>'read_only' IS DISTINCT FROM 'true'
  OR par.manifest->>'no_write' IS DISTINCT FROM 'true'
  OR par.manifest->>'no_promotion' IS DISTINCT FROM 'true'
  OR par.manifest#>>'{router_profile_handoff,router_authorization_receipt,profile_execution_allowed}' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'LINK_CHILD_PARENT_NOT_AUTHORIZED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_profile_write_authority_v1
  WHERE profile_code=par.target_code AND operation_code='VINCULACION_REGLA_PANTALLA_LF'
    AND status='ACTIVE')
 THEN RAISE EXCEPTION 'LINK_CHILD_PROFILE_AUTHORITY_MISSING'; END IF;
 SELECT * INTO inv FROM public.lf_skill_invocation_v1
 WHERE skill_run_id=p_run AND skill_code='RULE_LINK_APPLY'
  AND parent_execution_id=p_parent AND child_execution_id=p_child
  AND status='COMPLETED' AND profile_code=par.target_code
  AND input_sha256=encode(extensions.digest(convert_to(p_input::text,'UTF8'),'sha256'),'hex')
 FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'LINK_CHILD_INVOCATION_NOT_BOUND'; END IF;

 SELECT * INTO s FROM lf_ops.pantallas WHERE id=sid FOR SHARE;
 IF NOT FOUND OR s.codigo IS DISTINCT FROM intent->>'screen_code'
   OR s.codigo IS DISTINCT FROM par.manifest#>>'{screen_selection_result,selected_screen_code}'
 THEN RAISE EXCEPTION 'LINK_CHILD_SCREEN_SCOPE'; END IF;
 SELECT * INTO r FROM lf_ops.reglas WHERE codigo=code FOR SHARE;
 -- Approved rules only in this Product-owned entrypoint; no change to the
 -- generic relation operation's accepted CANDIDATO/VIGENTE contract.
 IF NOT FOUND OR r.estado IS DISTINCT FROM 'VIGENTE'
   OR r.pendiente_decision IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'LINK_CHILD_RULE_NOT_VIGENTE'; END IF;
 sh:=public.lf_asset_snapshot_sha_v1('REGLA',code);
 IF sh IS DISTINCT FROM p_input->>'analysis_snapshot_sha256'
 THEN RAISE EXCEPTION 'LINK_CHILD_STALE_RULE'; END IF;

 SELECT evidence_payload->'profile_output' INTO outp
 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_parent AND step_id='execute_profile'
   AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT evidence_payload INTO val FROM public.lf_operation_execution_steps
 WHERE execution_id=p_parent AND step_id='output_validate'
   AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT evidence_payload INTO judge FROM public.lf_operation_execution_steps
 WHERE execution_id=p_parent AND step_id='semantic_judge'
   AND status='STEP_PASS_WITH_EVIDENCE';
 IF outp IS NULL OR val IS NULL OR judge IS NULL
  OR val->>'output_contract_result' IS DISTINCT FROM 'PASS'
  OR judge->'unsupported_claims' IS DISTINCT FROM '[]'::jsonb
  OR judge->'blocking_codes' IS DISTINCT FROM '[]'::jsonb
  OR judge#>>'{semantic_judge_result,verdict}' NOT IN
    ('PASS_INDEPENDENT_SEMANTIC','PASS_REVIEWED_CURRENT_CONTEXT')
  OR judge#>>'{semantic_judge_result,candidate_sha256}'
    IS DISTINCT FROM val->>'raw_output_sha256'
 THEN RAISE EXCEPTION 'LINK_CHILD_JUDGE_NOT_CLEAN'; END IF;
 IF outp->>'worker' IS DISTINCT FROM 'product_director_lf'
  OR outp->>'output_type' IS DISTINCT FROM 'PRODUCT_DIRECTION_SPEC'
  OR outp->>'self_verdict' IS DISTINCT FROM 'PASS'
  OR outp#>>'{deliverable_created,authority_status}' NOT IN
    ('SUPPORTED','CONFLICT_RESOLVED')
  OR outp#>>'{deliverable_created,product_decision,decision_id}'
    IS DISTINCT FROM p_input->>'decision_id'
  OR outp#>'{deliverable_created,governed_rule_link}' IS DISTINCT FROM intent
 THEN RAISE EXCEPTION 'LINK_CHILD_NOT_IN_JUDGED_PRODUCT_OUTPUT'; END IF;
 refs:=outp#>'{deliverable_created,product_decision,source_refs}';
 IF jsonb_typeof(refs) IS DISTINCT FROM 'array'
  OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(refs) x
    WHERE x->>'source_ref'='supabase://lf_ops.reglas/'||code
      AND x->>'authority' IN ('AUTHORITATIVE','CONSTRAINT') AND x->>'current'='true')
  OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(refs) x
    WHERE x->>'source_ref'='supabase://lf_ops.pantallas/'||sid::text
      AND x->>'authority' IN ('AUTHORITATIVE','CONSTRAINT') AND x->>'current'='true')
 THEN RAISE EXCEPTION 'LINK_CHILD_AUTHORITY_REFS_MISSING'; END IF;

 rv:=public.fn_lf_operation_reserve_execution_v1(
  p_child,'VINCULACION_REGLA_PANTALLA_LF','REGLA_PANTALLA_RELATION',
  code||'@'||sid::text,'skill-child-v1:'||p_run,p_request_sha,p_parent,NULL,NULL,
  jsonb_build_object(
    'profile_handoff',jsonb_build_object(
      'source_execution_id',p_parent,'skill_run_id',p_run,'via','SKILL_INVOKER'),
    'rule_snapshot_sha256',sh,'promotion_authorized',false,'relation_only',true));
 IF rv->>'result' IS DISTINCT FROM 'RESERVED_NEW_EXECUTION'
  OR rv->>'execution_id' IS DISTINCT FROM p_child
 THEN RAISE EXCEPTION 'LINK_CHILD_RESERVATION_FAIL'; END IF;
 ev:='SKILLRUN:'||p_run;
 PERFORM public.lf_skill_rule_link_step_v1(p_child,'preflight',
  jsonb_build_object('ekb_refs',jsonb_build_array(
     'INPUT-GOV-DECISION-RULE-PROVENANCE-PARITY-001'),
    'execution_binding',p_child),ev||'/10');
 PERFORM public.lf_skill_rule_link_step_v1(p_child,'resolve_rule',
  jsonb_build_object('rule_code',code,'rule_id',r.id,'rule_state',r.estado),ev||'/20');
 PERFORM public.lf_skill_rule_link_step_v1(p_child,'resolve_screen',
  jsonb_build_object('pantalla_id',sid,'screen_code',s.codigo,'screen_active',s.activa),ev||'/30');
 op:=public.lf_regla_pantalla_link_v1(p_child,code,sid,NULL);
 IF op->>'result' NOT IN ('RULE_SCREEN_RELATION_CREATED','RULE_SCREEN_RELATION_ALREADY_EXISTS')
  OR op->>'rule_code' IS DISTINCT FROM code
  OR op->>'screen_code' IS DISTINCT FROM s.codigo
  OR op->>'rule_unchanged' IS DISTINCT FROM 'true'
  OR op->>'screen_unchanged' IS DISTINCT FROM 'true'
  OR op->>'no_delete' IS DISTINCT FROM 'true'
  OR op->>'relation_count' IS DISTINCT FROM '1'
  OR op->>'promotion_authorized' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'LINK_CHILD_EFFECT_INVALID'; END IF;
 PERFORM public.lf_skill_rule_link_step_v1(p_child,'relation_write',
  jsonb_build_object('rule_id',r.id,'pantalla_id',sid,'write_result',op->>'result'),ev||'/40');
 PERFORM public.lf_skill_rule_link_step_v1(p_child,'readback',
  jsonb_build_object('relation_row',op->'relation_row',
    'rule_unchanged',true,'screen_unchanged',true,'no_delete',true),ev||'/50');
 IF (SELECT count(*) FROM public.lf_operation_execution_steps
   WHERE execution_id=p_child AND status='PASS_CLEAN')<>5
  OR public.lf_asset_snapshot_sha_v1('REGLA',code) IS DISTINCT FROM sh
 THEN RAISE EXCEPTION 'LINK_CHILD_READBACK_FAIL'; END IF;
 UPDATE public.lf_operation_execution SET
  status='COMPLETED',completed_at=now(),updated_at=now(),updated_by_execution_id=p_child,
  manifest=manifest||jsonb_build_object(
    'link_verified',true,'operation_closed',true,'promotion_authorized',false,
    'rule_snapshot_sha256',sh,'relation_row',op->'relation_row',
    'write_result',op->>'result','profile_continuation_required',true)
 WHERE execution_id=p_child AND status='IN_PROGRESS';
 IF NOT FOUND THEN RAISE EXCEPTION 'LINK_CHILD_CLOSE_FAILED'; END IF;
 RETURN jsonb_build_object('status','APPLIED_VERIFIED','child_execution_id',p_child,
  'rule_code',code,'pantalla_id',sid,'promotion_authorized',false);
END $opener$;

-- The invoker will consume this exact readback in its existing receipt slot.
CREATE FUNCTION public.lf_skill_rule_link_child_readback_v1(
 p_parent text,p_run text,p_child text
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path='pg_catalog','public','lf_ops'
AS $receipt$
DECLARE e public.lf_operation_execution%ROWTYPE; code text; sid int;
 row_data jsonb; n int; clean int; unique_steps int;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.lf_skill_invocation_v1
  WHERE skill_run_id=p_run AND skill_code='RULE_LINK_APPLY'
   AND parent_execution_id=p_parent AND child_execution_id=p_child
   AND status='COMPLETED')
 THEN RETURN jsonb_build_object('status','BLOCKED','code','LINK_RECEIPT_INVOCATION'); END IF;
 SELECT * INTO e FROM public.lf_operation_execution
 WHERE execution_id=p_child AND operation_code='VINCULACION_REGLA_PANTALLA_LF'
  AND target_type='REGLA_PANTALLA_RELATION' AND created_by_execution_id=p_parent;
 IF NOT FOUND OR e.manifest#>>'{profile_handoff,source_execution_id}' IS DISTINCT FROM p_parent
  OR e.manifest#>>'{profile_handoff,skill_run_id}' IS DISTINCT FROM p_run
 THEN RETURN jsonb_build_object('status','BLOCKED','code','LINK_RECEIPT_CHILD_BIND'); END IF;
 IF e.status<>'COMPLETED'
 THEN RETURN jsonb_build_object('status','CHILD_IN_PROGRESS','effect_verified',false); END IF;
 IF e.manifest->>'link_verified' IS DISTINCT FROM 'true'
 OR e.manifest->>'promotion_authorized' IS DISTINCT FROM 'false'
 OR e.manifest->>'operation_closed' IS DISTINCT FROM 'true'
 THEN RETURN jsonb_build_object('status','BLOCKED','code','LINK_RECEIPT_NO_CLOSE_PROOF'); END IF;
 SELECT count(*),count(*) FILTER(WHERE status='PASS_CLEAN'),
  count(DISTINCT step_id) INTO n,clean,unique_steps
 FROM public.lf_operation_execution_steps WHERE execution_id=p_child;
 IF n<>5 OR clean<>5 OR unique_steps<>5
 THEN RETURN jsonb_build_object('status','BLOCKED','code','LINK_RECEIPT_STEPS'); END IF;
 IF e.target_code !~ '^[A-Z0-9_-]+@[1-9][0-9]*$'
 THEN RETURN jsonb_build_object('status','BLOCKED','code','LINK_RECEIPT_TARGET'); END IF;
 code:=split_part(e.target_code,'@',1);sid:=split_part(e.target_code,'@',2)::int;
 SELECT to_jsonb(x) INTO row_data FROM lf_ops.reglas_pantallas x
 JOIN lf_ops.reglas r ON r.id=x.regla_id
 WHERE r.codigo=code AND x.pantalla_id=sid;
 IF row_data IS NULL OR row_data IS DISTINCT FROM e.manifest->'relation_row'
 OR (SELECT count(*) FROM lf_ops.reglas_pantallas x JOIN lf_ops.reglas r
    ON x.regla_id=r.id WHERE r.codigo=code AND x.pantalla_id=sid)<>1
 OR NOT EXISTS(SELECT 1 FROM lf_ops.reglas r WHERE r.codigo=code
    AND r.estado='VIGENTE' AND NOT r.pendiente_decision)
 OR public.lf_asset_snapshot_sha_v1('REGLA',code)
    IS DISTINCT FROM e.manifest->>'rule_snapshot_sha256'
 THEN RETURN jsonb_build_object('status','BLOCKED','code','LINK_RECEIPT_CANONICAL_DRIFT'); END IF;
 RETURN jsonb_build_object('status','APPLIED_VERIFIED','effect_verified',true,
  'parent_execution_id',p_parent,'child_execution_id',p_child,
  'rule_code',code,'pantalla_id',sid,'required_steps_clean',5,
  'promotion_authorized',false,'profile_execution_complete',false);
END $receipt$;

REVOKE ALL ON FUNCTION public.lf_skill_rule_link_step_v1(text,text,jsonb,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_skill_o_rule_link_v1(text,jsonb,text,text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_skill_rule_link_child_readback_v1(text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_skill_rule_link_step_v1(text,text,jsonb,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_skill_o_rule_link_v1(text,jsonb,text,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_skill_rule_link_child_readback_v1(text,text,text) TO service_role;

-- Modify the existing invoker's two receipt slots, without changing routing.
DO $bind$
DECLARE src text; next_src text; old_replay text; new_replay text;
 old_fresh text; new_fresh text;
BEGIN
 src:=pg_get_functiondef('public.lf_skill_invoke_v1(text,text,jsonb)'::regprocedure);
 IF md5(src)<>'ac7e351e1834cbfb91aabf26e1a04a8d'
 THEN RAISE EXCEPTION 'LINK_INVOKER_SOURCE_CHANGED'; END IF;
 old_replay:=$o$IF p_skill='RULE_UPDATE_APPLY' AND v_prior.child_execution_id IS NOT NULL THEN
            v_rule_receipt:=public.lf_skill_rule_child_readback_v1(
              p_execution_id,v_prior.skill_run_id,v_prior.child_execution_id);$o$;
 new_replay:=$n$IF p_skill IN ('RULE_UPDATE_APPLY','RULE_LINK_APPLY') AND v_prior.child_execution_id IS NOT NULL THEN
            v_rule_receipt:=CASE p_skill
              WHEN 'RULE_UPDATE_APPLY' THEN public.lf_skill_rule_child_readback_v1(
                p_execution_id,v_prior.skill_run_id,v_prior.child_execution_id)
              ELSE public.lf_skill_rule_link_child_readback_v1(
                p_execution_id,v_prior.skill_run_id,v_prior.child_execution_id)
            END;$n$;
 old_fresh:=$o2$IF p_skill='RULE_UPDATE_APPLY' THEN
      v_rule_receipt:=public.lf_skill_rule_child_readback_v1(p_execution_id,v_run,v_child);$o2$;
 new_fresh:=$n2$IF p_skill IN ('RULE_UPDATE_APPLY','RULE_LINK_APPLY') THEN
      v_rule_receipt:=CASE p_skill
        WHEN 'RULE_UPDATE_APPLY' THEN public.lf_skill_rule_child_readback_v1(p_execution_id,v_run,v_child)
        ELSE public.lf_skill_rule_link_child_readback_v1(p_execution_id,v_run,v_child)
      END;$n2$;
 IF strpos(src,old_replay)=0 OR strpos(src,old_fresh)=0
 THEN RAISE EXCEPTION 'LINK_INVOKER_ANCHOR_MISSING'; END IF;
 next_src:=replace(replace(src,old_replay,new_replay),old_fresh,new_fresh);
 IF next_src=src THEN RAISE EXCEPTION 'LINK_INVOKER_PATCH_EMPTY'; END IF;
 EXECUTE next_src;
END $bind$;

UPDATE public.lf_skill_catalog_v1
 SET opener_fn='lf_skill_o_rule_link_v1',
  input_required=ARRAY['regla_codigo','pantalla_id','target_type','target_code',
    'decision_id','analysis_snapshot_sha256','link_intent'],
  description='Product Director: enlace de regla VIGENTE, child 5 pasos y recibo gobernado'
 WHERE skill_code='RULE_LINK_APPLY' AND opener_fn IS NULL AND status='READY'
  AND effect='WRITE_GOVERNED'
  AND required_operation='VINCULACION_REGLA_PANTALLA_LF';
DO $verify$
BEGIN
 IF (SELECT opener_fn FROM public.lf_skill_catalog_v1
   WHERE skill_code='RULE_LINK_APPLY') IS DISTINCT FROM 'lf_skill_o_rule_link_v1'
 OR to_regprocedure('public.lf_skill_rule_link_child_readback_v1(text,text,text)') IS NULL
 OR strpos(pg_get_functiondef('public.lf_skill_invoke_v1(text,text,jsonb)'::regprocedure),
  'lf_skill_rule_link_child_readback_v1')=0
 THEN RAISE EXCEPTION 'LINK_CHILD_INSTALL_READBACK_FAIL'; END IF;
END $verify$;
COMMIT;
