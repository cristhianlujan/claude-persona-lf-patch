-- LF / CHAT F: only sandbox rollout. Step 40 generic READ_ONLY skill hook.
-- Historical input_validate PASS rows are never modified; late evidence uses a separate ledger.
-- Requires exact deployed bridge/selector/invoker hashes verified by SELECT on 2026-11-14.
BEGIN;
DO $source_guard$
BEGIN
 IF md5(pg_get_functiondef('public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure))
    <> 'be58d7c3167964e9639df7c5f2a0ae7d' THEN
   RAISE EXCEPTION 'SOURCE_STATE_DRIFT:lf_profile_native_bridge_prepare_v1';
 END IF;
 IF md5(pg_get_functiondef('public.lf_profile_execution_plan_for_run_v1(text,jsonb)'::regprocedure))
    <> '2dd5b6570e5a4b5cc08b2905ef2dae57' THEN
   RAISE EXCEPTION 'SOURCE_STATE_DRIFT:lf_profile_execution_plan_for_run_v1';
 END IF;
 IF md5(pg_get_functiondef('public.lf_profile_skill_invoke_selected_v1(text,text,text,jsonb,jsonb)'::regprocedure))
    <> '5518b63ac3a1707ffeda5989a9f1d5c4' THEN
   RAISE EXCEPTION 'SOURCE_STATE_DRIFT:lf_profile_skill_invoke_selected_v1';
 END IF;
 IF md5(pg_get_functiondef('public.lf_profile_skill_selection_prepare_context_v1(text,text,jsonb,jsonb)'::regprocedure))
    <> '353a555c6c3a1666d36293dd6792ea9a' THEN
   RAISE EXCEPTION 'SOURCE_STATE_DRIFT:lf_profile_skill_selection_prepare_context_v1';
 END IF;
 IF NOT EXISTS (
   SELECT 1 FROM public.lf_operation_step_contracts
   WHERE operation_code='EJECUCION_PERFIL_LF' AND step_order=40
     AND step_id='input_validate' AND status='ACTIVE_ENFORCEMENT'
     AND resolver_ref='public.lf_profile_execution_input_validate_v1'
 ) THEN RAISE EXCEPTION 'SOURCE_STATE_DRIFT:generic_step40_contract'; END IF;
END $source_guard$;

CREATE TABLE IF NOT EXISTS public.lf_profile_skill_late_receipt_v1 (
 parent_execution_id text NOT NULL REFERENCES public.lf_operation_execution(execution_id),
 skill_code text NOT NULL,
 receipt_kind text NOT NULL CHECK (receipt_kind IN ('DISPATCH','TERMINAL')),
 finding_code text NOT NULL DEFAULT 'SKILL_SELECTION_LATE'
   CHECK (finding_code='SKILL_SELECTION_LATE'),
 cause text NOT NULL,
 selection_sha256 text NOT NULL CHECK (selection_sha256 ~ '^[0-9a-f]{64}$'),
 selection_receipt jsonb NOT NULL,
 invocation_status text NOT NULL,
 invocation_result jsonb NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY (parent_execution_id,skill_code,receipt_kind)
);
ALTER TABLE public.lf_profile_skill_late_receipt_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.lf_profile_skill_late_receipt_v1 FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.lf_profile_skill_late_receipt_v1 TO service_role;
-- Only SECURITY DEFINER function may append to the ledger.

CREATE OR REPLACE FUNCTION public.lf_profile_skill_reconcile_late_v1(p_execution_id text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $late$
DECLARE
 e public.lf_operation_execution%ROWTYPE;
 v_step jsonb;
 v_plan jsonb;
 v_skill jsonb;
 v_input jsonb;
 v_out jsonb;
 v_ticket jsonb;
 v_previous public.lf_profile_skill_late_receipt_v1%ROWTYPE;
 v_findings jsonb:='[]'::jsonb;
 v_receipts jsonb:='[]'::jsonb;
 v_finding jsonb;
 v_skill_code text;
 v_selection_digest text;
 v_terminal_status text;
 v_cause text:='Semantic skill selected for an existing Step40 PASS but not consumed by that Step40; preserve historical evidence';
BEGIN
 IF current_setting('request.jwt.claim.role',true)<>'service_role'
    AND session_user NOT IN ('postgres','service_role') THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_LATE_CALLER_NOT_AUTHORIZED');
 END IF;
 SELECT * INTO e FROM public.lf_operation_execution
 WHERE execution_id=p_execution_id FOR UPDATE;
 IF NOT FOUND OR e.operation_code<>'EJECUCION_PERFIL_LF'
    OR e.target_type<>'PERFIL' OR e.status<>'IN_PROGRESS' THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_LATE_PARENT_RUN_INVALID');
 END IF;
 SELECT evidence_payload INTO v_step
 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='input_validate'
   AND status='STEP_PASS_WITH_EVIDENCE';
 IF v_step IS NULL OR e.manifest->'skill_selection_decision' IS NULL THEN
   RETURN jsonb_build_object('status','READY','findings',v_findings,'receipts',v_receipts);
 END IF;
 IF jsonb_typeof(v_step->'skill_execution_receipts')<>'array' THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_LATE_STEP40_RECEIPTS_NOT_ARRAY');
 END IF;
 IF EXISTS(SELECT 1 FROM public.lf_operation_execution_steps
           WHERE execution_id=p_execution_id AND step_id='execute_profile') THEN
   RETURN jsonb_build_object('status','READY','findings',jsonb_build_array(
     jsonb_build_object('finding_code','SKILL_SELECTION_LATE_AFTER_STEP50',
       'cause','Step50 already exists; late invocation forbidden',
       'continuation_allowed',true,'production_authorized',false)),
     'receipts',v_receipts);
 END IF;
 v_plan:=public.lf_profile_execution_plan_for_run_v1(p_execution_id,NULL::jsonb);
 IF v_plan->>'status'<>'READY' OR jsonb_typeof(v_plan->'skills')<>'array' THEN
   RETURN jsonb_build_object('status','READY','findings',jsonb_build_array(
     jsonb_build_object('finding_code','SKILL_LATE_POLICY_PLAN_NOT_READY',
       'cause',coalesce(v_plan->>'blocking_code',v_plan->>'status','PLAN_UNREADABLE'),
       'remediation_action','VERIFY_SKILL_POLICY_IN_GOVERNED_FOLLOWUP',
       'continuation_allowed',true,'production_authorized',false)), 'receipts',v_receipts);
 END IF;
 v_selection_digest:=encode(extensions.digest(
   convert_to((e.manifest->'skill_selection_decision')::text,'UTF8'),'sha256'),'hex');
 FOR v_skill IN SELECT value FROM jsonb_array_elements(v_plan->'skills') LOOP
   v_skill_code:=v_skill->>'skill_code';
   IF v_skill->>'effect'<>'READ_ONLY' THEN CONTINUE; END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_step->'skill_execution_receipts') x
             WHERE x->>'skill_code'=v_skill_code) THEN CONTINUE; END IF;
   v_finding:=jsonb_build_object(
      'finding_code','SKILL_SELECTION_LATE',
      'skill_code',v_skill_code,'cause',v_cause,
      'historical_step_overwritten',false,'continuation_allowed',true,
      'production_authorized',false,
      'remediation_action','INVOKE_VIA_LF_PROFILE_SKILL_INVOKE_SELECTED_V1_BEFORE_STEP50');
   v_findings:=v_findings||jsonb_build_array(v_finding);
   SELECT * INTO v_previous FROM public.lf_profile_skill_late_receipt_v1
   WHERE parent_execution_id=p_execution_id AND skill_code=v_skill_code
     AND receipt_kind='TERMINAL';
   IF FOUND THEN
     IF v_previous.selection_sha256<>v_selection_digest THEN
       RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_LATE_RECEIPT_REPLAY_MISMATCH');
     END IF;
     v_receipts:=v_receipts||jsonb_build_array(jsonb_build_object(
       'skill_code',v_skill_code,'status',v_previous.invocation_status,
       'receipt_ref','supabase://public.lf_profile_skill_late_receipt_v1/'
         ||p_execution_id||'/'||v_skill_code||'/TERMINAL',
       'result',v_previous.invocation_result,'replay',true));
     CONTINUE;
   END IF;
   v_input:=jsonb_build_object('execution_id',p_execution_id,
      'request_text',e.manifest#>>'{router_profile_handoff,literal_request}',
      'profile_code',e.target_code,'scope',v_step->'resolved_scope',
      'consumer','CONTEXT_PACK',
      'pantalla_codigo',v_step#>>'{resolved_scope,resolved_screen_code}');
   BEGIN
     v_out:=public.lf_profile_skill_invoke_selected_v1(
       p_execution_id,e.manifest#>>'{router_profile_handoff,channel}',
       v_skill_code,v_input,e.manifest->'skill_selection_decision');
   EXCEPTION WHEN OTHERS THEN
     v_out:=jsonb_build_object('status','SKILL_FAILED_AS_FINDING',
       'blocking_code',SQLSTATE,'error_message',left(SQLERRM,500),
       'continuation_allowed',true);
   END;
   IF v_out->>'status'='RUNTIME_REQUIRED' THEN
     BEGIN
       v_ticket:=public.lf_profile_skill_runtime_ticket_issue_v1(
           p_execution_id,v_skill_code,v_input);
     EXCEPTION WHEN OTHERS THEN
       v_ticket:=jsonb_build_object('status','BLOCKED','code',SQLSTATE,
         'error_message',left(SQLERRM,500));
     END;
     IF v_ticket->>'status'='AUTHORIZED' THEN
       INSERT INTO public.lf_profile_skill_late_receipt_v1(
          parent_execution_id,skill_code,receipt_kind,cause,selection_sha256,
          selection_receipt,invocation_status,invocation_result)
       VALUES (p_execution_id,v_skill_code,'DISPATCH',v_cause,v_selection_digest,
          v_plan->'selection_receipt','RUNTIME_REQUIRED',v_out)
       ON CONFLICT(parent_execution_id,skill_code,receipt_kind) DO NOTHING;
       RETURN jsonb_build_object('status','SKILL_RUNTIME_REQUIRED',
         'execution_id',p_execution_id,'skill_code',v_skill_code,
         'late_skill_findings',v_findings,'late_skill_execution_receipts',v_receipts,
         'input_governance_runtime_request',jsonb_build_object(
           'transport','DIRECT_EDGE_INVOCATION',
           'runtime_orchestrator','SUPABASE_EDGE_FUNCTION:lf-profiles-governance-caller-v1',
           'runtime_slug',v_ticket->>'runtime_slug',
           'request_headers',jsonb_build_object('X-LF-Profile-Runtime-Ticket',v_ticket->>'ticket'),
           'request_body',jsonb_build_object('action','profile_skill_runtime_v1',
             'execution_id',p_execution_id,'skill_code',v_skill_code),
           'ticket_expires_at',v_ticket->'expires_at',
           'terminal_statuses',jsonb_build_array('READY','BLOCKED','HUMAN_DECISION_REQUIRED','FAILED'),
           'continuation_statuses',jsonb_build_array('VALIDATOR_RESUME_REQUIRED'),
           'queue_required',false,'polling_required',false),
         'next_action','INVOKE_SELECTED_SKILL_RUNTIME_AND_RETRY_SAME_BRIDGE',
         'router_reentry_required',false);
     END IF;
     v_out:=jsonb_build_object('status','SKILL_FAILED_AS_FINDING',
       'blocking_code',coalesce(v_ticket->>'code','SKILL_RUNTIME_TICKET_NOT_AUTHORIZED'),
       'attempt_count',v_ticket->'attempt_count','continuation_allowed',true,
       'remediation_action','REVIEW_RUNTIME_TICKET_AND_RETRY_GOVERNED');
   END IF;
   v_terminal_status:=CASE WHEN v_out->>'status' IN ('COMPLETED','READY','PASS','SKIPPED')
        THEN v_out->>'status' ELSE 'SKILL_FAILED_AS_FINDING' END;
   INSERT INTO public.lf_profile_skill_late_receipt_v1(
      parent_execution_id,skill_code,receipt_kind,cause,selection_sha256,
      selection_receipt,invocation_status,invocation_result)
   VALUES(p_execution_id,v_skill_code,'TERMINAL',v_cause,v_selection_digest,
      v_plan->'selection_receipt',v_terminal_status,v_out)
   ON CONFLICT(parent_execution_id,skill_code,receipt_kind) DO NOTHING;
   SELECT * INTO v_previous FROM public.lf_profile_skill_late_receipt_v1
   WHERE parent_execution_id=p_execution_id AND skill_code=v_skill_code
      AND receipt_kind='TERMINAL';
   IF v_previous.selection_sha256<>v_selection_digest
      OR v_previous.invocation_result IS DISTINCT FROM v_out THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_LATE_TERMINAL_READBACK_MISMATCH');
   END IF;
   IF v_terminal_status='COMPLETED' AND NOT EXISTS (
       SELECT 1 FROM public.lf_skill_invocation_v1 i
       JOIN public.lf_profile_skill_selection_receipt_v1 s USING(skill_run_id)
       WHERE i.parent_execution_id=p_execution_id AND s.parent_execution_id=p_execution_id
         AND i.skill_code=v_skill_code AND s.skill_code=v_skill_code
         AND i.skill_run_id=v_out->>'skill_run_id' AND i.status='COMPLETED') THEN
     RETURN jsonb_build_object('status','BLOCKED',
       'blocking_code','SKILL_LATE_CANONICAL_INVOCATION_RECEIPT_MISSING');
   END IF;
   v_receipts:=v_receipts||jsonb_build_array(jsonb_build_object(
     'skill_code',v_skill_code,'status',v_terminal_status,
     'receipt_ref','supabase://public.lf_profile_skill_late_receipt_v1/'
       ||p_execution_id||'/'||v_skill_code||'/TERMINAL',
     'result',v_out,'replay',false));
 END LOOP;
 RETURN jsonb_build_object('status','READY','findings',v_findings,'receipts',v_receipts,
   'historical_step_overwritten',false);
END
$late$;
REVOKE ALL ON FUNCTION public.lf_profile_skill_reconcile_late_v1(text)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_skill_reconcile_late_v1(text) TO service_role;

-- Surgical source-pinned rewrite of the *current* bridge only.
-- No update of public.lf_operation_execution_steps, historical PASS remains untouched.
DO $patch$
DECLARE d text; original text;
BEGIN
 d:=pg_get_functiondef('public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure);
 original:=d;
 IF strpos(d,'  v_skill_ig jsonb;')=0
   OR strpos(d,'    v_skill_plan:=public.lf_profile_execution_plan_for_run_v1(p_execution_id,NULL::jsonb);')=0
   OR strpos(d,E'  END IF;\n\n  SELECT evidence_payload INTO v_context')=0
   OR strpos(d,'''input_governance'',v_input->''input_governance'',')=0
 THEN RAISE EXCEPTION 'SOURCE_STATE_DRIFT:bridge_patch_anchors'; END IF;
 d:=replace(d,'  v_skill_ig jsonb;',
             E'  v_skill_ig jsonb;\n  v_selector_finding jsonb;\n  v_late jsonb;');
 d:=replace(d,
   '    v_skill_plan:=public.lf_profile_execution_plan_for_run_v1(p_execution_id,NULL::jsonb);',
   $insert$
    v_skill_plan:=public.lf_profile_execution_plan_for_run_v1(p_execution_id,NULL::jsonb);
    -- Content findings from the selector are part of Step40's evidence even
    -- when the plan is READY with zero skills. They are not a blocking gate.
    IF jsonb_typeof(v_skill_plan->'content_findings')='array' THEN
      FOR v_selector_finding IN
        SELECT value FROM jsonb_array_elements(v_skill_plan->'content_findings') LOOP
        v_skill_findings:=v_skill_findings||jsonb_build_array(
          v_selector_finding||jsonb_build_object(
            'skill_code','SKILL_SELECTION','status','SKILL_CONTENT_FINDING',
            'continuation_allowed',true,'production_authorized',false));
      END LOOP;
    END IF;$insert$);
 d:=replace(d,E'  END IF;\n\n  SELECT evidence_payload INTO v_context',
   $insert$
  END IF;

  -- Reconcile a semantic choice made after Step40 was persisted, before Step50.
  -- The old Step40 PASS is never rewritten. The new receipt is append-only.
  v_late:=public.lf_profile_skill_reconcile_late_v1(p_execution_id);
  IF v_late->>'status'='SKILL_RUNTIME_REQUIRED' THEN RETURN v_late; END IF;
  IF v_late->>'status'<>'READY' THEN
    RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code',coalesce(v_late->>'blocking_code','SKILL_LATE_RECONCILIATION_INVALID'),
      'late_skill_reconciliation',v_late);
  END IF;

  SELECT evidence_payload INTO v_context$insert$);
 d:=replace(d,'''input_governance'',v_input->''input_governance'',',
  $insert$'input_governance',v_input->'input_governance',
    'late_skill_findings',v_late->'findings',
    'late_skill_execution_receipts',v_late->'receipts',$insert$);
 IF d=original OR strpos(d,'v_selector_finding jsonb;')=0
    OR strpos(d,'lf_profile_skill_reconcile_late_v1(p_execution_id)')=0 THEN
   RAISE EXCEPTION 'SOURCE_STATE_DRIFT:bridge_patch_not_applied';
 END IF;
 EXECUTE d;
END $patch$;
COMMIT;
