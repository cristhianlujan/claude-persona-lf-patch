-- LF #3774 / RULE_CREATE_APPLY. Stacked on PR #3775 link child.
-- No new skill/profile/Router. Parent stays read-only; governed child writes CANDIDATO only.
BEGIN;
DO $pre$
BEGIN
 IF md5(pg_get_functiondef('public.lf_regla_candidate_write_v1(text,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure)) <> 'c311087befe49afb2affa668231c9dd1'
 OR md5(pg_get_functiondef('public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure)) <> 'fe08a25c8e3c023d7181194d2dfdee0d'
 THEN RAISE EXCEPTION 'BLOCK_CREATE_SOURCE_DRIFT'; END IF;
 IF to_regprocedure('public.lf_skill_o_rule_create_v1(text,jsonb,text,text,text)') IS NOT NULL
 THEN RAISE EXCEPTION 'BLOCK_CREATE_ALREADY_INSTALLED'; END IF;
 IF (SELECT count(*) FROM public.lf_skill_catalog_v1 WHERE skill_code='RULE_CREATE_APPLY'
 AND status='READY' AND effect='WRITE_GOVERNED' AND opener_fn IS NULL
 AND handler_fn='lf_skill_h_rule_create_propose_v1'
 AND required_operation='CREACION_REGLA_LF')<>1
 OR (SELECT count(*) FROM public.lf_operation_registry WHERE operation_code='CREACION_REGLA_LF'
 AND status='SANDBOX_ACTIVE')<>1
 OR (SELECT count(*) FROM public.lf_operation_contracts WHERE operation_code='CREACION_REGLA_LF'
 AND contract_code='CONTRACT-CREACION_REGLA_LF-v0.1' AND status='ACTIVE_ENFORCEMENT')<>1
 THEN RAISE EXCEPTION 'BLOCK_CREATE_CATALOG_DRIFT'; END IF;
 IF strpos(pg_get_functiondef('public.lf_skill_invoke_v1(text,text,jsonb)'::regprocedure),
 'lf_skill_rule_link_child_readback_v1')=0
 THEN RAISE EXCEPTION 'BLOCK_CREATE_LINK_DEPENDENCY_MISSING'; END IF;
END $pre$;

CREATE FUNCTION public.lf_skill_rule_create_step_v1(
 p_child text,p_step text,p_payload jsonb,p_ref text
) RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path='pg_catalog','public'
AS $step$
DECLARE result jsonb;
BEGIN
 result:=public.lf_record_operation_step_core_v1(
 p_child,p_step,p_ref,p_payload,p_child,
 'CREACION_REGLA_LF','REGLA','ACTIVE_ENFORCEMENT',
 'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
 jsonb_build_object('valid',true,'code','CREATE_SERVER_VERIFIED',
 'server_assertions',jsonb_build_array('required_evidence_present'),
 'server_hard_fails','[]'::jsonb),false,'lf_skill_rule_create_step_v1');
 IF result->>'outcome'<>'STEP_RECORDED' OR result->>'status'<>'PASS_CLEAN'
 THEN RAISE EXCEPTION 'BLOCK_CREATE_STEP:%',p_step; END IF;
END $step$;

CREATE FUNCTION public.lf_skill_o_rule_create_v1(
 p_child text,p_input jsonb,p_parent text,p_run text,p_request_sha text
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER
SET search_path='pg_catalog','public','lf_ops','extensions'
AS $open$
DECLARE par public.lf_operation_execution%ROWTYPE;
 inv public.lf_skill_invocation_v1%ROWTYPE;
 scr lf_ops.pantallas%ROWTYPE;
 spec jsonb;outp jsonb;val jsonb;jud jsonb;refs jsonb;
 mode jsonb;reserved jsonb;wr jsonb;rowdata jsonb;
 code text;ref text;outsha text;rowsha text; n int;
BEGIN
 IF p_input IS NULL OR jsonb_typeof(p_input)<>'object'
 OR coalesce(p_input->>'regla_codigo','') !~ '^[A-Z0-9][A-Z0-9_-]{3,159}$'
 OR p_input->>'target_type' IS DISTINCT FROM 'REGLA'
 OR p_input->>'target_code' IS DISTINCT FROM p_input->>'regla_codigo'
 OR coalesce(p_input->>'decision_id','')=''
 OR jsonb_typeof(p_input->'candidate_create') IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'BLOCK_CREATE_INPUT'; END IF;
 code:=p_input->>'regla_codigo';spec:=p_input->'candidate_create';
 IF (SELECT count(*) FROM jsonb_object_keys(spec))<>10
 OR spec->>'change_kind' IS DISTINCT FROM 'CREATE_CANDIDATE'
 OR spec->>'rule_code' IS DISTINCT FROM code
 OR coalesce(spec->>'category','') !~ '^[A-Z][A-Z0-9_-]{1,63}$'
 OR length(btrim(coalesce(spec->>'title','')))<8
 OR length(btrim(coalesce(spec->>'description','')))<12
 OR length(btrim(coalesce(spec->>'reason','')))<8
 OR length(coalesce(spec->>'title',''))>400
 OR length(coalesce(spec->>'description',''))>8000
 OR jsonb_typeof(spec->'config') IS DISTINCT FROM 'object'
 OR jsonb_typeof(spec->'transversal') IS DISTINCT FROM 'boolean'
 OR coalesce(spec->>'source_decision_ref','') !~ '^(supabase://|github://|drive://)'
 OR length(coalesce(spec->>'source_decision_ref',''))>1000
 OR coalesce(spec->>'screen_code','')=''
 THEN RAISE EXCEPTION 'BLOCK_CREATE_SPEC'; END IF;
 SELECT * INTO par FROM public.lf_operation_execution
 WHERE execution_id=p_parent AND operation_code='EJECUCION_PERFIL_LF'
 AND target_type='PERFIL' AND target_code='PERFIL-PRODUCT-DIRECTOR-LF'
 AND status='IN_PROGRESS' FOR UPDATE;
 IF NOT FOUND OR par.request_sha256 IS DISTINCT FROM p_request_sha
 OR par.manifest->>'read_only' IS DISTINCT FROM 'true'
 OR par.manifest->>'no_write' IS DISTINCT FROM 'true'
 OR par.manifest->>'no_promotion' IS DISTINCT FROM 'true'
 OR par.manifest#>>'{router_profile_handoff,router_authorization_receipt,profile_execution_allowed}' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'BLOCK_CREATE_PARENT_AUTHORITY'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_profile_write_authority_v1
 WHERE profile_code=par.target_code AND operation_code='CREACION_REGLA_LF' AND status='ACTIVE')
 THEN RAISE EXCEPTION 'BLOCK_CREATE_PROFILE_AUTHORITY'; END IF;
 SELECT * INTO inv FROM public.lf_skill_invocation_v1 WHERE skill_run_id=p_run
 AND skill_code='RULE_CREATE_APPLY' AND parent_execution_id=p_parent
 AND child_execution_id=p_child AND profile_code=par.target_code
 AND status='COMPLETED'
 AND input_sha256=encode(extensions.digest(convert_to(p_input::text,'UTF8'),'sha256'),'hex')
 FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'BLOCK_CREATE_INVOCATION'; END IF;
 SELECT * INTO scr FROM lf_ops.pantallas WHERE codigo=spec->>'screen_code' FOR SHARE;
 IF NOT FOUND OR scr.codigo IS DISTINCT FROM
 par.manifest#>>'{screen_selection_result,selected_screen_code}'
 THEN RAISE EXCEPTION 'BLOCK_CREATE_SCREEN'; END IF;
 SELECT count(*) INTO n FROM lf_ops.reglas WHERE codigo=code;
 IF n<>0 THEN RAISE EXCEPTION 'BLOCK_CREATE_DUPLICATE'; END IF;
 SELECT evidence_payload->'profile_output' INTO outp FROM public.lf_operation_execution_steps
 WHERE execution_id=p_parent AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT evidence_payload INTO val FROM public.lf_operation_execution_steps
 WHERE execution_id=p_parent AND step_id='output_validate' AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT evidence_payload INTO jud FROM public.lf_operation_execution_steps
 WHERE execution_id=p_parent AND step_id='semantic_judge' AND status='STEP_PASS_WITH_EVIDENCE';
 IF outp IS NULL OR val IS NULL OR jud IS NULL
 OR val->>'output_contract_result' IS DISTINCT FROM 'PASS'
 OR coalesce(val->>'raw_output_sha256','') !~ '^[0-9a-f]{64}$'
 OR jud->'unsupported_claims' IS DISTINCT FROM '[]'::jsonb
 OR jud->'blocking_codes' IS DISTINCT FROM '[]'::jsonb
 OR jud#>>'{semantic_judge_result,status}' IS DISTINCT FROM 'PASS'
 OR jud#>'{semantic_judge_result,result,unsupported_claims}' IS DISTINCT FROM '[]'::jsonb
 OR jud#>'{semantic_judge_result,result,blocking_codes}' IS DISTINCT FROM '[]'::jsonb
 OR coalesce(jud#>>'{semantic_judge_result,verdict}','') NOT IN
 ('PASS_INDEPENDENT_SEMANTIC','PASS_REVIEWED_CURRENT_CONTEXT')
 OR jud#>>'{semantic_judge_result,candidate_sha256}' IS DISTINCT FROM val->>'raw_output_sha256'
 THEN RAISE EXCEPTION 'BLOCK_CREATE_JUDGE'; END IF;
 IF outp->>'worker' IS DISTINCT FROM 'product_director_lf'
 OR outp->>'output_type' IS DISTINCT FROM 'PRODUCT_DIRECTION_SPEC'
 OR outp->>'self_verdict' IS DISTINCT FROM 'PASS'
 OR coalesce(outp#>>'{deliverable_created,authority_status}','') NOT IN
 ('SUPPORTED','CONFLICT_RESOLVED')
 OR outp#>'{deliverable_created,governed_rule_create}' IS DISTINCT FROM spec
 OR outp#>>'{deliverable_created,product_decision,decision_id}'
 IS DISTINCT FROM p_input->>'decision_id'
 THEN RAISE EXCEPTION 'BLOCK_CREATE_PRODUCT_SPEC'; END IF;
 refs:=outp#>'{deliverable_created,product_decision,source_refs}';
 IF jsonb_typeof(refs) IS DISTINCT FROM 'array'
 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(refs) x
 WHERE x->>'authority'='AUTHORITATIVE' AND x->>'current'='true'
 AND x->>'source_ref'=spec->>'source_decision_ref')
 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(refs) x
 WHERE x->>'authority' IN ('AUTHORITATIVE','CONSTRAINT') AND x->>'current'='true'
 AND x->>'source_ref'='supabase://lf_ops.pantallas/'||scr.id::text)
 THEN RAISE EXCEPTION 'BLOCK_CREATE_SOURCE_REFS'; END IF;
 mode:=public.lf_resolve_operation_mode_v1('CREACION_REGLA_LF','CREATE_NEW','GOVERNED');
 IF mode->>'status' IS DISTINCT FROM 'READY'
 OR mode->>'destination_kind' IS DISTINCT FROM 'CANONICAL_CANDIDATE'
 OR mode->>'write_allowed' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'BLOCK_CREATE_MODE'; END IF;
 outsha:=encode(extensions.digest(convert_to(outp::text,'UTF8'),'sha256'),'hex');
 reserved:=public.fn_lf_operation_reserve_execution_v1(
 p_child,'CREACION_REGLA_LF','REGLA',code,'skill-child-v1:'||p_run,
 p_request_sha,p_parent,NULL,NULL,jsonb_build_object(
 'profile_handoff',jsonb_build_object('source_execution_id',p_parent,
 'skill_run_id',p_run,'via','SKILL_INVOKER'),
 'profile_output_sha256',outsha,'source_decision_ref',spec->>'source_decision_ref',
 'production_allowed',false,'promotion_authorized',false));
 IF reserved->>'result' IS DISTINCT FROM 'RESERVED_NEW_EXECUTION'
 OR reserved->>'execution_id' IS DISTINCT FROM p_child
 THEN RAISE EXCEPTION 'BLOCK_CREATE_RESERVE'; END IF;
 ref:='SKILLRUN:'||p_run;
 PERFORM public.lf_skill_rule_create_step_v1(p_child,'ekb_preflight',
 jsonb_build_object('ekb_refs',jsonb_build_array('INPUT-GOV-DECISION-RULE-PROVENANCE-PARITY-001'),
 'execution_binding',p_child),ref||'/10');
 PERFORM public.lf_skill_rule_create_step_v1(p_child,'classify',
 jsonb_build_object('rule_code',code,'category',spec->>'category',
 'candidate_classification','REGLA_CREATE'),ref||'/20');
 PERFORM public.lf_skill_rule_create_step_v1(p_child,'existing_check',
 jsonb_build_object('rule_code',code,'existing_count',0,'expected_existence','ABSENT'),ref||'/30');
 PERFORM public.lf_skill_rule_create_step_v1(p_child,'destination_validate',
 jsonb_build_object('destination_schema','lf_ops','destination_table','reglas',
 'unique_code_guard',true),ref||'/40');
 wr:=public.lf_regla_candidate_write_v1(p_child,'REGLA_CREATE',code,
 spec->>'category',spec->>'title',spec->>'description',spec->>'reason',
 spec->'config',(spec->>'transversal')::boolean,spec->>'source_decision_ref');
 IF wr->>'result' IS DISTINCT FROM 'RULE_CANDIDATE_CREATED'
 OR wr->>'before' IS NOT NULL
 OR wr->'after'->>'estado' IS DISTINCT FROM 'CANDIDATO'
 OR wr->'after'->>'pendiente_decision' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'BLOCK_CREATE_WRITER'; END IF;
 PERFORM public.lf_skill_rule_create_step_v1(p_child,'candidate_write',
 jsonb_build_object('execution_id',p_child,'rule_code',code,
 'write_result',wr->>'result','estado','CANDIDATO'),ref||'/50');
 SELECT to_jsonb(r) INTO rowdata FROM lf_ops.reglas r WHERE r.codigo=code;
 IF rowdata IS NULL OR (SELECT count(*) FROM lf_ops.reglas WHERE codigo=code)<>1
 OR rowdata->>'estado' IS DISTINCT FROM 'CANDIDATO'
 OR rowdata->>'pendiente_decision' IS DISTINCT FROM 'true'
 OR rowdata->>'categoria' IS DISTINCT FROM spec->>'category'
 OR rowdata->>'titulo' IS DISTINCT FROM spec->>'title'
 OR rowdata->>'descripcion' IS DISTINCT FROM spec->>'description'
 OR rowdata->>'razon' IS DISTINCT FROM spec->>'reason'
 OR rowdata->'valor_config' IS DISTINCT FROM spec->'config'
 OR rowdata->>'es_transversal' IS DISTINCT FROM spec->>'transversal'
 OR rowdata->>'origen' IS DISTINCT FROM spec->>'source_decision_ref'
 THEN RAISE EXCEPTION 'BLOCK_CREATE_CANONICAL_READBACK'; END IF;
 rowsha:=public.lf_asset_snapshot_sha_v1('REGLA',code);
 IF coalesce(rowsha,'') !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'BLOCK_CREATE_HASH'; END IF;
 PERFORM public.lf_skill_rule_create_step_v1(p_child,'readback',
 jsonb_build_object('rule_code',code,'readback_row',rowdata,'estado','CANDIDATO'),ref||'/60');
 PERFORM public.lf_skill_rule_create_step_v1(p_child,'trace_close',
 jsonb_build_object('execution_id',p_child,'operation_code','CREACION_REGLA_LF',
 'trace_ref',ref,'no_promotion',true),ref||'/70');
 IF (SELECT count(*) FROM public.lf_operation_execution_steps
 WHERE execution_id=p_child AND status='PASS_CLEAN')<>7
 THEN RAISE EXCEPTION 'BLOCK_CREATE_7_STEPS'; END IF;
 UPDATE public.lf_operation_execution SET status='COMPLETED',
 completed_at=now(),updated_at=now(),updated_by_execution_id=p_child,
 manifest=manifest||jsonb_build_object('operation_closed',true,
 'candidate_write_verified',true,'result_snapshot_sha256',rowsha,
 'rule_state','CANDIDATO','pending_decision',true,
 'source_decision_ref',spec->>'source_decision_ref',
 'promotion_authorized',false,'profile_continuation_required',true)
 WHERE execution_id=p_child AND status='IN_PROGRESS';
 IF NOT FOUND THEN RAISE EXCEPTION 'BLOCK_CREATE_CLOSE'; END IF;
 RETURN jsonb_build_object('status','APPLIED_VERIFIED','child_execution_id',p_child,
 'rule_code',code,'result_snapshot_sha256',rowsha,
 'pending_decision',true,'promotion_authorized',false);
END $open$;

CREATE FUNCTION public.lf_skill_rule_create_child_readback_v1(
 p_parent text,p_run text,p_child text
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path='pg_catalog','public','lf_ops'
AS $receipt$
DECLARE e public.lf_operation_execution%ROWTYPE;
 rule lf_ops.reglas%ROWTYPE; n int; clean int; dist int;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.lf_skill_invocation_v1
 WHERE skill_run_id=p_run AND skill_code='RULE_CREATE_APPLY'
 AND parent_execution_id=p_parent AND child_execution_id=p_child
 AND status='COMPLETED') THEN
 RETURN jsonb_build_object('status','BLOCKED','code','CREATE_RECEIPT_INVOCATION'); END IF;
 SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_child
 AND operation_code='CREACION_REGLA_LF' AND target_type='REGLA'
 AND created_by_execution_id=p_parent;
 IF NOT FOUND OR e.manifest#>>'{profile_handoff,source_execution_id}' IS DISTINCT FROM p_parent
 OR e.manifest#>>'{profile_handoff,skill_run_id}' IS DISTINCT FROM p_run
 THEN RETURN jsonb_build_object('status','BLOCKED','code','CREATE_RECEIPT_BIND'); END IF;
 IF e.status<>'COMPLETED' THEN
 RETURN jsonb_build_object('status','CHILD_IN_PROGRESS','effect_verified',false); END IF;
 IF e.manifest->>'operation_closed' IS DISTINCT FROM 'true'
 OR e.manifest->>'candidate_write_verified' IS DISTINCT FROM 'true'
 OR e.manifest->>'promotion_authorized' IS DISTINCT FROM 'false'
 OR e.manifest->>'rule_state' IS DISTINCT FROM 'CANDIDATO'
 OR e.manifest->>'pending_decision' IS DISTINCT FROM 'true'
 THEN RETURN jsonb_build_object('status','BLOCKED','code','CREATE_RECEIPT_CLOSE'); END IF;
 SELECT count(*),count(*) FILTER(WHERE status='PASS_CLEAN'),
 count(DISTINCT step_id) INTO n,clean,dist
 FROM public.lf_operation_execution_steps WHERE execution_id=p_child;
 IF n<>7 OR clean<>7 OR dist<>7 THEN
 RETURN jsonb_build_object('status','BLOCKED','code','CREATE_RECEIPT_STEPS'); END IF;
 SELECT * INTO rule FROM lf_ops.reglas WHERE codigo=e.target_code;
 IF NOT FOUND OR (SELECT count(*) FROM lf_ops.reglas WHERE codigo=e.target_code)<>1
 OR rule.estado IS DISTINCT FROM 'CANDIDATO'
 OR rule.pendiente_decision IS DISTINCT FROM true
 OR rule.origen IS DISTINCT FROM e.manifest->>'source_decision_ref'
 OR public.lf_asset_snapshot_sha_v1('REGLA',e.target_code)
 IS DISTINCT FROM e.manifest->>'result_snapshot_sha256'
 THEN RETURN jsonb_build_object('status','BLOCKED','code','CREATE_RECEIPT_CANONICAL_DRIFT'); END IF;
 RETURN jsonb_build_object('status','APPLIED_VERIFIED','effect_verified',true,
 'child_execution_id',p_child,'parent_execution_id',p_parent,
 'rule_code',e.target_code,'required_steps_clean',7,
 'rule_state','CANDIDATO','pending_decision',true,
 'promotion_authorized',false,'profile_execution_complete',false);
END $receipt$;

REVOKE ALL ON FUNCTION public.lf_skill_rule_create_step_v1(text,text,jsonb,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_skill_o_rule_create_v1(text,jsonb,text,text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_skill_rule_create_child_readback_v1(text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_skill_rule_create_step_v1(text,text,jsonb,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_skill_o_rule_create_v1(text,jsonb,text,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_skill_rule_create_child_readback_v1(text,text,text) TO service_role;

DO $patch$
DECLARE source text;patched text;a text;b text;c text;d text;
BEGIN
 source:=pg_get_functiondef('public.lf_skill_invoke_v1(text,text,jsonb)'::regprocedure);
 a:=$a$IF p_skill IN ('RULE_UPDATE_APPLY','RULE_LINK_APPLY') AND v_prior.child_execution_id IS NOT NULL THEN
            v_rule_receipt:=CASE p_skill
              WHEN 'RULE_UPDATE_APPLY' THEN public.lf_skill_rule_child_readback_v1(
                p_execution_id,v_prior.skill_run_id,v_prior.child_execution_id)
              ELSE public.lf_skill_rule_link_child_readback_v1(
                p_execution_id,v_prior.skill_run_id,v_prior.child_execution_id)
            END;$a$;
 b:=$b$IF p_skill IN ('RULE_UPDATE_APPLY','RULE_LINK_APPLY','RULE_CREATE_APPLY') AND v_prior.child_execution_id IS NOT NULL THEN
            v_rule_receipt:=CASE p_skill
              WHEN 'RULE_UPDATE_APPLY' THEN public.lf_skill_rule_child_readback_v1(
                p_execution_id,v_prior.skill_run_id,v_prior.child_execution_id)
              WHEN 'RULE_LINK_APPLY' THEN public.lf_skill_rule_link_child_readback_v1(
                p_execution_id,v_prior.skill_run_id,v_prior.child_execution_id)
              ELSE public.lf_skill_rule_create_child_readback_v1(
                p_execution_id,v_prior.skill_run_id,v_prior.child_execution_id)
            END;$b$;
 c:=$c$IF p_skill IN ('RULE_UPDATE_APPLY','RULE_LINK_APPLY') THEN
      v_rule_receipt:=CASE p_skill
        WHEN 'RULE_UPDATE_APPLY' THEN public.lf_skill_rule_child_readback_v1(p_execution_id,v_run,v_child)
        ELSE public.lf_skill_rule_link_child_readback_v1(p_execution_id,v_run,v_child)
      END;$c$;
 d:=$d$IF p_skill IN ('RULE_UPDATE_APPLY','RULE_LINK_APPLY','RULE_CREATE_APPLY') THEN
      v_rule_receipt:=CASE p_skill
        WHEN 'RULE_UPDATE_APPLY' THEN public.lf_skill_rule_child_readback_v1(p_execution_id,v_run,v_child)
        WHEN 'RULE_LINK_APPLY' THEN public.lf_skill_rule_link_child_readback_v1(p_execution_id,v_run,v_child)
        ELSE public.lf_skill_rule_create_child_readback_v1(p_execution_id,v_run,v_child)
      END;$d$;
 IF strpos(source,a)=0 OR strpos(source,c)=0 THEN
 RAISE EXCEPTION 'BLOCK_CREATE_INVOKER_ANCHOR'; END IF;
 patched:=replace(replace(source,a,b),c,d);
 IF patched=source OR strpos(patched,a)>0 OR strpos(patched,c)>0 THEN
 RAISE EXCEPTION 'BLOCK_CREATE_INVOKER_PATCH'; END IF;
 EXECUTE patched;
END $patch$;
UPDATE public.lf_skill_catalog_v1
SET opener_fn='lf_skill_o_rule_create_v1',
 input_required=ARRAY['regla_codigo','target_type','target_code',
 'decision_id','candidate_create'],
 description='Regla CANDIDATO: 7 pasos/recibo; sin promoción'
WHERE skill_code='RULE_CREATE_APPLY' AND status='READY' AND opener_fn IS NULL
AND effect='WRITE_GOVERNED' AND required_operation='CREACION_REGLA_LF'
AND handler_fn='lf_skill_h_rule_create_propose_v1';
DO $verify$
BEGIN
 IF (SELECT opener_fn FROM public.lf_skill_catalog_v1 WHERE skill_code='RULE_CREATE_APPLY')
 IS DISTINCT FROM 'lf_skill_o_rule_create_v1'
 OR strpos(pg_get_functiondef('public.lf_skill_invoke_v1(text,text,jsonb)'::regprocedure),
 'lf_skill_rule_create_child_readback_v1')=0
 THEN RAISE EXCEPTION 'BLOCK_CREATE_INSTALL'; END IF;
END $verify$;
COMMIT;
