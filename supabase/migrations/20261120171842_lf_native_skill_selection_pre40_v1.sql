BEGIN;
DO $migration$
DECLARE d text:=pg_get_functiondef('public.lf_profile_execution_plan_for_run_v1(text,jsonb)'::regprocedure);
BEGIN
 IF md5(d)<>'2aaecef34158d1b7da08ea34baab437f' THEN RAISE EXCEPTION 'Preimage drift: lf_profile_execution_plan_for_run_v1(text,jsonb)'; END IF;
 d:=replace(d,$old$ v_input:=jsonb_build_object('execution_id',p_execution_id,$old$,$new$ -- Rehydrate the same validated scope for both the selector and the binder.
 IF v_scope IS NULL AND e.manifest->>'executor_mode' IN ('GPT_NATIVE','CLAUDE_NATIVE') THEN
   SELECT public.lf_profile_execution_input_validate_v1(
     e.execution_id,v_handoff->>'literal_request',s.evidence_ref,v_handoff
   ) INTO v_screen_validation
   FROM public.lf_operation_execution_steps s WHERE s.execution_id=e.execution_id
     AND s.step_id='profile_source_read' AND s.status='STEP_PASS_WITH_EVIDENCE';
   IF v_screen_validation->>'status'='READY' THEN
     v_scope:=v_screen_validation->'resolved_scope';
   END IF;
 END IF;
 v_input:=jsonb_build_object('execution_id',p_execution_id,$new$);
 IF md5(d)<>'aad1da51ada01add2dba88b00b9635d6' THEN RAISE EXCEPTION 'Unexpected patched definition'; END IF;
 EXECUTE d;
END $migration$;
DO $migration$
DECLARE d text:=pg_get_functiondef('public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure);
BEGIN
 IF md5(d)<>'2350258a12e06bf4533f409a2a9c413c' THEN RAISE EXCEPTION 'Preimage drift: lf_profile_native_bridge_prepare_v1(text,text,text,text)'; END IF;
 d:=replace(d,$old$    v_input:=v_input||jsonb_build_object(
$old$,$new$    v_input:=v_input||jsonb_build_object(
      'skill_selection_closed',true,
      'skill_selection_status',v_skill_plan->>'skill_selection_status',
      'skill_selection_plan_sha256',encode(extensions.digest(convert_to(v_skill_plan::text,'UTF8'),'sha256'),'hex'),
$new$);
 d:=replace(d,$old$    v_skill_plan:=public.lf_profile_execution_plan_for_run_v1(p_execution_id,NULL::jsonb);
$old$,$new$    v_skill_plan:=public.lf_profile_execution_plan_for_run_v1(p_execution_id,NULL::jsonb);
    IF e.manifest->'skill_selection_decision' IS NULL
       AND v_skill_plan->>'skill_selection_status'='SKILL_SELECTION_PENDING_FINDING' THEN
      RETURN jsonb_build_object('status','SKILL_SELECTION_REQUIRED',
        'execution_id',p_execution_id,'operation_plan',v_skill_plan,
        'next_action','SUBMIT_SKILL_SELECTION','router_reentry_required',false);
    END IF;
$new$);
 d:=replace(d,$old$  WHERE execution_id=p_execution_id;
$old$,$new$  WHERE execution_id=p_execution_id FOR UPDATE;
$new$);
 IF md5(d)<>'ea7d74b10a02749368dfb636a58f1ad0' THEN RAISE EXCEPTION 'Unexpected patched definition'; END IF;
 EXECUTE d;
END $migration$;
DO $migration$
DECLARE d text:=pg_get_functiondef('public.lf_profile_skill_selection_run_bind_v1(text,jsonb,text)'::regprocedure);
BEGIN
 IF md5(d)<>'f5f55f4bbe9538cb7517241a6f8bfe9a' THEN RAISE EXCEPTION 'Preimage drift: lf_profile_skill_selection_run_bind_v1(text,jsonb,text)'; END IF;
 d:=replace(d,$old$   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_BIND_REPLAY_DIFFERENT_DECISION');
 END IF;
$old$,$new$   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_BIND_REPLAY_DIFFERENT_DECISION');
 END IF;
 -- Older Step40 receipts stay eligible for their existing reconciliation.
 IF EXISTS (SELECT 1 FROM public.lf_operation_execution_steps s
   WHERE s.execution_id=p_execution_id AND s.step_id='input_validate'
     AND s.status='STEP_PASS_WITH_EVIDENCE'
     AND s.evidence_payload->'skill_selection_closed'='true'::jsonb) THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_ALREADY_CLOSED');
 END IF;
$new$);
 IF md5(d)<>'5d1ad8fb94209b96f2bd17a2d4b87520' THEN RAISE EXCEPTION 'Unexpected patched definition'; END IF;
 EXECUTE d;
END $migration$;
COMMIT;
