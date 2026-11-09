-- LF capability 3: execute the existing RULE_UPDATE_APPLY child, then return evidence.
-- No Router mutation, no new orchestrator, no promotion, no security-policy edits.
-- The parent profile remains READ_ONLY; a separate ACTIVE governed rule operation
-- owns the candidate write. The child cannot write unless the exact parent RAW
-- patch was structurally validated and semantically judged in this same RUN.
DO $preflight$
BEGIN
 IF md5(pg_get_functiondef('public.lf_skill_invoke_v1(text,text,jsonb)'::regprocedure))
    <> '884b551f9dd11919c6c8488ee34f197f' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_SKILL_INVOKER_SOURCE_DRIFT';
 END IF;
 IF md5(pg_get_functiondef('public.lf_regla_candidate_write_v1(text,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure))
    <> 'c311087befe49afb2affa668231c9dd1' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_WRITER_SOURCE_DRIFT';
 END IF;
 IF md5(pg_get_functiondef('public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure))
    <> 'fe08a25c8e3c023d7181194d2dfdee0d' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_STEP_RECORDER_SOURCE_DRIFT';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_skill_catalog_v1
     WHERE skill_code='RULE_UPDATE_APPLY' AND required_operation='ACTUALIZACION_REGLA_LF'
       AND effect='WRITE_GOVERNED' AND status='READY' AND opener_fn IS NULL
       AND handler_fn='lf_skill_h_rule_update_propose_v1') THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_CATALOG_DRIFT';
 END IF;
 IF to_regprocedure('public.lf_skill_o_rule_update_v1(text,jsonb,text,text,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_OPENER_ALREADY_EXISTS';
 END IF;
END $preflight$;

-- This is a skill opener INSIDE the already-authorized lf_skill_invoke_v1.
-- No direct public writer, no new execution route. Atomic under the invoker's
-- exception subtransaction: any failed step rolls back every child/write effect.
CREATE FUNCTION public.lf_skill_o_rule_update_v1(
 p_child text, p_input jsonb, p_parent text, p_run text, p_request_sha text
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO 'pg_catalog','public','lf_ops','extensions'
AS $opener$
DECLARE
 v_par public.lf_operation_execution%ROWTYPE;
 v_inv public.lf_skill_invocation_v1%ROWTYPE;
 v_before lf_ops.reglas%ROWTYPE;
 v_after jsonb;
 v_profile_output jsonb;
 v_patch jsonb;
 v_changes jsonb;
 v_source_refs jsonb;
 v_semantic jsonb;
 v_decision text;
 v_rule text;
 v_screen text;
 v_snapshot text;
 v_out_sha text;
 v_step_payload jsonb;
 v_trust jsonb;
 v_rec jsonb;
 v_written jsonb;
 v_mode jsonb;
 v_reservation jsonb;
 v_field text;
 v_current text;
 v_next text;
 v_old_title text;
 v_old_desc text;
 v_old_reason text;
 v_new_title text;
 v_new_desc text;
 v_new_reason text;
 v_changed integer := 0;
 v_n integer;
 v_after_sha text;
 v_evidence text;
 v_steps text[] := ARRAY[
  'ekb_preflight','classify','existing_check','destination_validate',
  'candidate_write','readback','trace_close'
 ];
 v_status text;
BEGIN
 IF p_input IS NULL OR jsonb_typeof(p_input)<>'object'
    OR coalesce(p_input->>'regla_codigo','') !~ '^[A-Z0-9][A-Z0-9_-]{3,159}$'
    OR coalesce(p_input->>'analysis_snapshot_sha256','') !~ '^[0-9a-f]{64}$'
    OR coalesce(p_input->>'decision_id','')=''
    OR jsonb_typeof(p_input->'candidate_patch') IS DISTINCT FROM 'object'
    OR p_input->'candidate_patch'->>'rule_code' IS DISTINCT FROM p_input->>'regla_codigo'
    OR p_input->'candidate_patch'->>'change_kind' IS DISTINCT FROM 'DOCUMENTARY_ONLY'
    OR jsonb_typeof(p_input->'candidate_patch'->'changes') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_INPUT_OR_PATCH_CONTRACT';
 END IF;
 v_rule := p_input->>'regla_codigo';
 v_patch := p_input->'candidate_patch';
 v_changes := v_patch->'changes';
 IF (SELECT count(*) FROM jsonb_object_keys(v_patch))<>3
    OR jsonb_object_length(v_changes) NOT BETWEEN 1 AND 3 THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_PATCH_KEYS';
 END IF;
 FOR v_field IN SELECT jsonb_object_keys(v_changes) LOOP
    IF v_field NOT IN ('titulo','descripcion','razon')
       OR jsonb_typeof(v_changes->v_field)<>'string'
       OR length(btrim(v_changes->>v_field))<8
       OR length(v_changes->>v_field)>8000 THEN
       RAISE EXCEPTION 'BLOCK_RULE_CHILD_PROTECTED_OR_INVALID_FIELD:%',v_field;
    END IF;
 END LOOP;

 SELECT * INTO v_par FROM public.lf_operation_execution
 WHERE execution_id=p_parent AND operation_code='EJECUCION_PERFIL_LF'
   AND status='IN_PROGRESS' FOR UPDATE;
 IF NOT FOUND OR v_par.target_type<>'PERFIL'
    OR v_par.manifest->>'read_only'<>'true'
    OR v_par.manifest->>'no_write'<>'true'
    OR v_par.manifest->>'no_promotion'<>'true'
    OR v_par.manifest->'router_profile_handoff'->'router_authorization_receipt'->>'profile_execution_allowed'<>'true'
 THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_PARENT_NOT_AUTHORIZED'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_profile_write_authority_v1
    WHERE profile_code=v_par.target_code
      AND operation_code='ACTUALIZACION_REGLA_LF' AND status='ACTIVE') THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_PROFILE_OPERATION_AUTHORITY'; END IF;
 SELECT * INTO v_inv FROM public.lf_skill_invocation_v1
 WHERE skill_run_id=p_run AND skill_code='RULE_UPDATE_APPLY'
   AND child_execution_id=p_child AND parent_execution_id=p_parent
   AND profile_code=v_par.target_code AND status='COMPLETED'
   AND input_sha256=encode(extensions.digest(convert_to(p_input::text,'UTF8'),'sha256'),'hex')
 FOR UPDATE;
 IF NOT FOUND OR p_request_sha IS DISTINCT FROM v_par.request_sha256 THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_INVOCATION_OR_REQUEST_BINDING'; END IF;
 -- Profile output is the ONLY authority for exact patch bytes. The caller may
 -- echo that patch but cannot choose new values or target independently.
 IF NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps
    WHERE execution_id=p_parent AND step_id='output_validate'
      AND status='STEP_PASS_WITH_EVIDENCE'
      AND evidence_payload->>'output_contract_result'='PASS') THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_PROFILE_OUTPUT_NOT_VALIDATED'; END IF;
 SELECT evidence_payload->'semantic_judge_result' INTO v_semantic
 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_parent AND step_id='semantic_judge'
   AND status='STEP_PASS_WITH_EVIDENCE'
   AND evidence_payload->'blocking_codes'='[]'::jsonb;
 IF v_semantic IS NULL OR v_semantic->>'verdict'
      NOT IN ('PASS_INDEPENDENT_SEMANTIC','PASS_REVIEWED_CURRENT_CONTEXT') THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_SEMANTIC_JUDGE_NOT_CLEAN'; END IF;
 SELECT evidence_payload->'profile_output' INTO v_profile_output
 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_parent AND step_id='execute_profile'
   AND status='STEP_PASS_WITH_EVIDENCE';
 IF v_profile_output IS NULL OR v_profile_output->>'worker'<>'product_director_lf'
    OR v_profile_output->>'output_type'<>'PRODUCT_DIRECTION_SPEC'
    OR v_profile_output->>'self_verdict'<>'PASS'
    OR v_profile_output->'deliverable_created'->>'authority_status'
          NOT IN ('SUPPORTED','CONFLICT_RESOLVED') THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_PRODUCT_DECISION_NOT_FOUND'; END IF;
 v_out_sha := encode(extensions.digest(convert_to(v_profile_output::text,'UTF8'),'sha256'),'hex');
 IF v_profile_output->'deliverable_created'->'governed_rule_patch'
       IS DISTINCT FROM v_patch
    OR v_profile_output->'deliverable_created'->'product_decision'->>'decision_id'
       IS DISTINCT FROM p_input->>'decision_id' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_PATCH_NOT_IN_JUDGED_OUTPUT'; END IF;
 v_source_refs := v_profile_output->'deliverable_created'->'product_decision'->'source_refs';
 IF jsonb_typeof(v_source_refs)<>'array'
    OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_source_refs) ref
      WHERE ref->>'authority' IN ('AUTHORITATIVE','CONSTRAINT')
        AND ref->>'current'='true'
        AND nullif(btrim(ref->>'source_ref'),'') IS NOT NULL) THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_AUTHORITATIVE_SOURCE_ABSENT'; END IF;
 -- A screen task cannot mutate rules unrelated to the screen actually
 -- selected by the SAME parent. No caller-provided pantalla_id is trusted.
 v_screen := v_par.manifest->'screen_selection_result'->>'selected_screen_code';
 IF nullif(btrim(v_screen),'') IS NULL OR NOT EXISTS (
   SELECT 1 FROM lf_ops.pantallas s
   JOIN lf_ops.reglas_pantallas rel ON rel.pantalla_id=s.id
   JOIN lf_ops.reglas r ON r.id=rel.regla_id
   WHERE s.codigo=v_screen AND r.codigo=v_rule
 ) THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_RULE_NOT_IN_SELECTED_SCREEN'; END IF;
 SELECT count(*) INTO v_n FROM lf_ops.reglas WHERE codigo=v_rule;
 IF v_n<>1 THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_EXACT_RULE_CARDINALITY:%',v_n; END IF;
 SELECT * INTO v_before FROM lf_ops.reglas WHERE codigo=v_rule FOR UPDATE;
 IF v_before.estado<>'CANDIDATO' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_REQUIRES_CANDIDATO:%',v_before.estado;
 END IF;
 v_snapshot := public.lf_asset_snapshot_sha_v1('REGLA',v_rule);
 IF v_snapshot IS DISTINCT FROM p_input->>'analysis_snapshot_sha256' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_SOURCE_SNAPSHOT_STALE';
 END IF;
 v_old_title:=v_before.titulo;
 v_old_desc:=v_before.descripcion;
 v_old_reason:=v_before.razon;
 v_new_title:=COALESCE(v_changes->>'titulo',v_old_title);
 v_new_desc:=COALESCE(v_changes->>'descripcion',v_old_desc);
 v_new_reason:=COALESCE(v_changes->>'razon',v_old_reason);
 IF v_new_title IS DISTINCT FROM v_old_title THEN v_changed:=v_changed+1; END IF;
 IF v_new_desc IS DISTINCT FROM v_old_desc THEN v_changed:=v_changed+1; END IF;
 IF v_new_reason IS DISTINCT FROM v_old_reason THEN v_changed:=v_changed+1; END IF;
 IF v_changed=0 THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_NO_MATERIAL_CHANGE'; END IF;
 v_mode:=public.lf_resolve_operation_mode_v1('ACTUALIZACION_REGLA_LF','REMEDIATE_EXISTING','GOVERNED');
 IF v_mode->>'status'<>'READY' OR v_mode->>'destination_kind'<>'CANONICAL_CANDIDATE'
    OR v_mode->>'write_allowed'<>'true' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_GOVERNED_MODE_NOT_READY'; END IF;
 v_reservation:=public.fn_lf_operation_reserve_execution_v1(
   p_child,'ACTUALIZACION_REGLA_LF','REGLA',v_rule,
   'skill-child-v1:'||p_run,p_request_sha,p_parent,NULL,NULL,
   jsonb_build_object(
     'profile_handoff',jsonb_build_object(
       'source_execution_id',p_parent,'skill_run_id',p_run,'via','SKILL_INVOKER'),
     'analysis_snapshot_sha256',v_snapshot,'profile_decision_sha256',v_out_sha,
     'production_allowed',false,'promotion_authorized',false,
     'candidate_patch_scope','DOCUMENTARY_ONLY')
 );
 IF v_reservation->>'result'<>'RESERVED_NEW_EXECUTION'
    OR v_reservation->>'execution_id'<>p_child THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_RESERVATION_NOT_NEW'; END IF;
 v_evidence:='SKILLRUN:'||p_run;
 v_trust:=jsonb_build_object('valid',true,'code','LF_RULE_CHILD_SERVER_VALIDATED_V1',
   'server_assertions',jsonb_build_array('required_evidence_present'),
   'server_hard_fails','[]'::jsonb);
 -- Each record uses the existing canonical judge/core. No raw PASS inserts.
 v_step_payload:=jsonb_build_object(
    'ekb_refs',jsonb_build_array('INPUT_GOVERNANCE_LF_V1_4'),
    'execution_binding',p_child,'parent_execution_id',p_parent,
    'profile_decision_sha256',v_out_sha);
 PERFORM public.lf_skill_rule_step_record_v1(p_child,'ekb_preflight',v_evidence||'/10',v_step_payload,v_trust);
 v_step_payload:=jsonb_build_object(
    'rule_code',v_rule,'category',v_before.categoria,
    'candidate_classification','REGLA_UPDATE','analysis_snapshot_sha256',v_snapshot);
 PERFORM public.lf_skill_rule_step_record_v1(p_child,'classify',v_evidence||'/20',v_step_payload,v_trust);
 v_step_payload:=jsonb_build_object(
    'rule_code',v_rule,'existing_count',1,'expected_existence','ONE_CANDIDATO');
 PERFORM public.lf_skill_rule_step_record_v1(p_child,'existing_check',v_evidence||'/30',v_step_payload,v_trust);
 v_step_payload:=jsonb_build_object(
    'destination_schema','lf_ops','destination_table','reglas','unique_code_guard',true);
 PERFORM public.lf_skill_rule_step_record_v1(p_child,'destination_validate',v_evidence||'/40',v_step_payload,v_trust);

 v_written:=public.lf_regla_candidate_write_v1(
    p_child,'REGLA_UPDATE',v_rule,v_before.categoria,v_new_title,
    v_new_desc,v_new_reason,v_before.valor_config,
    v_before.es_transversal,v_before.origen
 );
 IF v_written->>'result'<>'RULE_CANDIDATE_UPDATED'
    OR v_written->'before'->>'estado'<>'CANDIDATO'
    OR v_written->'after'->>'estado'<>'CANDIDATO' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_WRITER_RESULT_MISMATCH'; END IF;
 v_step_payload:=jsonb_build_object(
    'execution_id',p_child,'rule_code',v_rule,
    'write_result',v_written->>'result','estado','CANDIDATO',
    'writer','lf_regla_candidate_write_v1');
 PERFORM public.lf_skill_rule_step_record_v1(p_child,'candidate_write',v_evidence||'/50',v_step_payload,v_trust);
 SELECT to_jsonb(r) INTO v_after FROM lf_ops.reglas r WHERE r.codigo=v_rule;
 IF v_after IS NULL OR v_after->>'estado'<>'CANDIDATO'
    OR v_after->>'titulo' IS DISTINCT FROM v_new_title
    OR v_after->>'descripcion' IS DISTINCT FROM v_new_desc
    OR v_after->>'razon' IS DISTINCT FROM v_new_reason
    OR v_after->'valor_config' IS DISTINCT FROM to_jsonb(v_before.valor_config)
    OR v_after->>'categoria' IS DISTINCT FROM v_before.categoria
    OR v_after->>'es_transversal' IS DISTINCT FROM v_before.es_transversal::text
    OR v_after->>'pendiente_decision'<>'true'
 THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_CANONICAL_READBACK_MISMATCH'; END IF;
 v_after_sha:=public.lf_asset_snapshot_sha_v1('REGLA',v_rule);
 IF v_after_sha IS NULL OR v_after_sha=v_snapshot THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_CANONICAL_HASH_NOT_CHANGED'; END IF;
 v_step_payload:=jsonb_build_object(
    'rule_code',v_rule,'readback_row',v_after,'estado','CANDIDATO',
    'source_snapshot_sha256',v_snapshot,'result_snapshot_sha256',v_after_sha);
 PERFORM public.lf_skill_rule_step_record_v1(p_child,'readback',v_evidence||'/60',v_step_payload,v_trust);
 v_step_payload:=jsonb_build_object(
    'execution_id',p_child,'operation_code','ACTUALIZACION_REGLA_LF',
    'trace_ref',v_evidence,'no_promotion',true,'result_snapshot_sha256',v_after_sha);
 PERFORM public.lf_skill_rule_step_record_v1(p_child,'trace_close',v_evidence||'/70',v_step_payload,v_trust);
 IF (SELECT count(*) FROM public.lf_operation_execution_steps
      WHERE execution_id=p_child AND step_id=ANY(v_steps)
      AND status='PASS_CLEAN')<>7 THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_7_STEPS_NOT_CLEAN'; END IF;
 UPDATE public.lf_operation_execution SET
    status='COMPLETED',completed_at=now(),
    manifest=manifest||jsonb_build_object(
      'operation_closed',true,'candidate_write_verified',true,
      'result_snapshot_sha256',v_after_sha,'rule_state','CANDIDATO',
      'promotion_authorized',false,'profile_continuation_required',true),
    updated_by_execution_id=p_child,updated_at=now()
 WHERE execution_id=p_child AND status='IN_PROGRESS';
 IF NOT FOUND THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_TERMINAL_WRITE_FAILED'; END IF;
 RETURN jsonb_build_object('status','APPLIED_VERIFIED','child_execution_id',p_child,
   'parent_execution_id',p_parent,'rule_code',v_rule,
   'result_snapshot_sha256',v_after_sha,'promotion_authorized',false);
END
$opener$;

-- Thin same-operation step wrapper over the shared registered core. It never
-- trusts a client-supplied judge result and supplies only server-built context.
CREATE FUNCTION public.lf_skill_rule_step_record_v1(
 p_child text,p_step text,p_ref text,p_evidence jsonb,p_trust jsonb
) RETURNS void LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO 'pg_catalog','public'
AS $rec$
DECLARE v jsonb;
BEGIN
 v:=public.lf_record_operation_step_core_v1(
  p_child,p_step,p_ref,p_evidence,p_child,
  'ACTUALIZACION_REGLA_LF','REGLA',
  'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',
  p_trust,false,'lf_skill_rule_step_record_v1');
 IF v->>'outcome'<>'STEP_RECORDED' OR v->>'status'<>'PASS_CLEAN' THEN
    RAISE EXCEPTION 'BLOCK_RULE_CHILD_STEP_RECORD_FAILED:%:%',p_step,coalesce(v->>'code',v->>'status','UNKNOWN');
 END IF;
END
$rec$;

-- Refuse direct invocations outside the service-role governed transport.
REVOKE ALL ON FUNCTION public.lf_skill_o_rule_update_v1(text,jsonb,text,text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_skill_rule_step_record_v1(text,text,text,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_skill_o_rule_update_v1(text,jsonb,text,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_skill_rule_step_record_v1(text,text,text,jsonb,jsonb) TO service_role;

UPDATE public.lf_skill_catalog_v1
SET opener_fn='lf_skill_o_rule_update_v1',
    input_required=ARRAY['regla_codigo','analysis_snapshot_sha256','decision_id','candidate_patch'],
    description='Ejecuta ACTUALIZACION_REGLA_LF solo para parche documental exacto validado por el mismo Product Director RUN; 7 pasos registrados y readback CANDIDATO, nunca promocion'
WHERE skill_code='RULE_UPDATE_APPLY' AND opener_fn IS NULL
  AND required_operation='ACTUALIZACION_REGLA_LF'
  AND effect='WRITE_GOVERNED' AND status='READY';
DO $readback$
BEGIN
 IF (SELECT opener_fn FROM public.lf_skill_catalog_v1 WHERE skill_code='RULE_UPDATE_APPLY')
       IS DISTINCT FROM 'lf_skill_o_rule_update_v1'
    OR to_regprocedure('public.lf_skill_rule_step_record_v1(text,text,text,jsonb,jsonb)') IS NULL
    OR to_regprocedure('public.lf_skill_o_rule_update_v1(text,jsonb,text,text,text)') IS NULL
    THEN RAISE EXCEPTION 'BLOCK_RULE_CHILD_INSTALL_READBACK'; END IF;
END $readback$;
