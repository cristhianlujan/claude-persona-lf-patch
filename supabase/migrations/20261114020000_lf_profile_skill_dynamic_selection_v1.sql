-- DRAFT/NO-GO: candidate-only; apply exclusively via LF Migration Merge Train.
-- Router selects PROFILE + Gate2; operation resolves skills deterministically/semantically.
-- This supersedes the incorrect lf_activo_relaciones/USA_SKILL selector.
-- Mirror existing lf_profile_selection_registry_v1 + lf_profile_selector_policy_v1.
BEGIN;

CREATE TABLE IF NOT EXISTS public.lf_skill_selection_registry_v1 (
  skill_code text PRIMARY KEY REFERENCES public.lf_skill_catalog_v1(skill_code),
  descriptor jsonb NOT NULL,
  source_kind text NOT NULL,
  source_ref text NOT NULL,
  source_revision text NOT NULL,
  descriptor_status text NOT NULL CHECK (descriptor_status IN ('CURRENT','STALE_SOURCE_CHANGED')),
  stale_reason text,
  synced_at timestamptz NOT NULL DEFAULT now(),
  CHECK (descriptor->>'schema_version'='LF_SKILL_SELECTION_DESCRIPTOR_V1'),
  CHECK (jsonb_typeof(descriptor->'selection_evidence')='array'),
  CHECK (jsonb_array_length(descriptor->'selection_evidence')>0)
);

CREATE TABLE IF NOT EXISTS public.lf_skill_selector_policy_v1 (
  profile_code text NOT NULL,
  skill_code text NOT NULL REFERENCES public.lf_skill_catalog_v1(skill_code),
  channels text[] NOT NULL,
  required_operation text NOT NULL,
  allowed_effects text[] NOT NULL,
  selection_mode text NOT NULL CHECK (selection_mode IN ('DETERMINISTIC_REQUIRED','SEMANTIC_OPTIONAL')),
  enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(profile_code,skill_code,required_operation),
  CHECK(cardinality(channels)>0 AND channels <@ ARRAY['PRODUCTO','PROGRAMACION','OPERACIONES']),
  CHECK(cardinality(allowed_effects)>0 AND allowed_effects <@ ARRAY['READ_ONLY','PROPOSE_ONLY','WRITE_GOVERNED'])
);

-- IG is a CANDIDATE, NOT a READY skill: its real handler/authority remains NO-GO.
INSERT INTO public.lf_skill_catalog_v1
(skill_code,description,required_operation,handler_fn,effect,input_required,status,opener_fn,child_caller)
VALUES ('INPUT_GOVERNANCE_CONTEXT_PACK',
        'Input Governance context readiness via profile-owned governed dependency (candidate; handler unverified)',
        'EJECUCION_PERFIL_LF','lf_skill_h_input_governance_context_pack_v1',
        'READ_ONLY',ARRAY['request_text','profile_code','scope','consumer'],'DRAFT',NULL,NULL)
ON CONFLICT (skill_code) DO NOTHING;

INSERT INTO public.lf_skill_selection_registry_v1
(skill_code,descriptor,source_kind,source_ref,source_revision,descriptor_status,stale_reason)
VALUES ('INPUT_GOVERNANCE_CONTEXT_PACK',
 jsonb_build_object(
   'schema_version','LF_SKILL_SELECTION_DESCRIPTOR_V1',
   'description','Resuelve preparación y evidencia de Input Governance solo cuando la política de perfil lo permite',
   'selection_evidence',jsonb_build_array(
      jsonb_build_object('kind','PURPOSE','value','context readiness y autoridad de entrada del perfil','source_section','INPUT_GOVERNANCE_EXECUTION_CONTRACT'),
      jsonb_build_object('kind','BOUNDARY','value','no crear segundo RUN de perfil, no escribir ni declarar CURRENT sin readback','source_section','EKB/7'))),
 'SUPABASE_CONTRACT','supabase://public.lf_activos/INPUT_GOVERNANCE_EXECUTION_CONTRACT',
 'CANDIDATE_SOURCE_NOT_ATTESTED','STALE_SOURCE_CHANGED','SOURCE_AND_HANDLER_NOT_ATTESTED')
ON CONFLICT (skill_code) DO NOTHING;

CREATE OR REPLACE FUNCTION public.lf_profile_skill_selection_prepare_v1(
 p_profile_code text, p_channel text, p_semantic_decision jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog','public'
AS $profile_skill_selector$
DECLARE
 v_n int;
 v_missing int;
 v_stale int;
 v_required jsonb:='[]'::jsonb;
 v_optional jsonb:='[]'::jsonb;
 v_selected jsonb:='[]'::jsonb;
 v_choice text;
 v_reason text;
 v_refs jsonb;
 v_revision text;
 v_row record;
 v_sem_n int;
BEGIN
 IF nullif(btrim(coalesce(p_profile_code,'')),'') IS NULL OR
    coalesce(p_channel,'') NOT IN ('PRODUCTO','PROGRAMACION','OPERACIONES')
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_PROFILE_CHANNEL_INVALID'); END IF;
 -- Follow the existing profile selector registry/policy: no unauthorized profile+channel.
 IF NOT EXISTS (
    SELECT 1 FROM public.lf_profile_selection_registry_v1 d
    JOIN public.lf_profile_selector_policy_v1 p USING(profile_code)
    WHERE d.profile_code=p_profile_code AND d.descriptor_status='CURRENT'
      AND p_channel=ANY(p.channels))
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_PROFILE_SOURCE_OR_CHANNEL_NOT_CURRENT'); END IF;

 SELECT count(*) INTO v_n FROM public.lf_skill_selector_policy_v1 p
 WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels);
 IF v_n=0 THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_POLICY_NOT_CONFIGURED');
 END IF;
 SELECT count(*) INTO v_missing
 FROM public.lf_skill_selector_policy_v1 p
 LEFT JOIN public.lf_skill_catalog_v1 c ON c.skill_code=p.skill_code
 WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels)
   AND (c.skill_code IS NULL OR c.status<>'READY' OR c.required_operation<>p.required_operation
        OR NOT(c.effect=ANY(p.allowed_effects))
        OR (c.effect='WRITE_GOVERNED' AND NOT EXISTS (
            SELECT 1 FROM public.lf_profile_write_authority_v1 a
            WHERE a.profile_code=p_profile_code AND a.operation_code=c.required_operation
              AND a.status='ACTIVE')));
 IF v_missing>0 THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_DETERMINISTIC_POLICY_OR_CATALOG_INVALID',
       'invalid_bindings',v_missing);
 END IF;
 SELECT count(*) INTO v_stale
 FROM public.lf_skill_selector_policy_v1 p
 LEFT JOIN public.lf_skill_selection_registry_v1 d ON d.skill_code=p.skill_code
 WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels)
   AND (d.skill_code IS NULL OR d.descriptor_status<>'CURRENT'
        OR d.descriptor->>'schema_version'<>'LF_SKILL_SELECTION_DESCRIPTOR_V1'
        OR coalesce(d.source_revision,'')='');
 IF v_stale>0 THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_DESCRIPTOR_STALE_OR_MISSING',
       'stale_count',v_stale);
 END IF;
 FOR v_row IN
   SELECT p.skill_code,p.selection_mode,c.handler_fn,c.required_operation,c.effect,
          c.input_required,d.descriptor,d.source_ref,d.source_revision
     FROM public.lf_skill_selector_policy_v1 p
     JOIN public.lf_skill_catalog_v1 c USING(skill_code)
     JOIN public.lf_skill_selection_registry_v1 d USING(skill_code)
    WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels)
    ORDER BY p.skill_code
 LOOP
   IF v_row.selection_mode='DETERMINISTIC_REQUIRED' THEN
     v_required:=v_required||jsonb_build_array(jsonb_build_object(
       'skill_code',v_row.skill_code,'handler_fn',v_row.handler_fn,
       'required_operation',v_row.required_operation,'effect',v_row.effect,
       'input_required',to_jsonb(v_row.input_required),'selection_mode','DETERMINISTIC_POLICY',
       'selection_evidence',jsonb_build_object('reason','MANDATORY_POLICY_FOR_PROFILE_AND_CHANNEL',
         'descriptor_revision',v_row.source_revision,'source_ref',v_row.source_ref),
       'invoker','public.lf_skill_invoke_v1'));
   ELSE
     v_optional:=v_optional||jsonb_build_array(jsonb_build_object(
       'skill_code',v_row.skill_code,'handler_fn',v_row.handler_fn,
       'required_operation',v_row.required_operation,'effect',v_row.effect,
       'input_required',to_jsonb(v_row.input_required),'descriptor',v_row.descriptor,
       'source_ref',v_row.source_ref,'source_revision',v_row.source_revision));
   END IF;
 END LOOP;
 IF jsonb_array_length(v_optional)=0 THEN
   IF p_semantic_decision IS NOT NULL THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_UNEXPECTED_SEMANTIC_DECISION');
   END IF;
   v_selected:=v_required;
 ELSE
   IF p_semantic_decision IS NULL THEN
     RETURN jsonb_build_object('status','SEMANTIC_SELECTION_REQUIRED',
       'blocking_code',null,'required_skills',v_required,
       'semantic_candidates',v_optional,'profile_code',p_profile_code,'channel',p_channel,
       'selection_mode','DETERMINISTIC_FILTER_THEN_NATIVE_SEMANTIC',
       'next_action','NATIVE_PROFILE_JUDGE_SKILL_AND_SUBMIT_SAME_EXECUTION');
   END IF;
   IF jsonb_typeof(p_semantic_decision)<>'object' OR
      p_semantic_decision ? 'selected_skill_codes' OR
      jsonb_typeof(p_semantic_decision->'selected_skill_code')<>'string'
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SEMANTIC_SELECTION_AMBIGUOUS'); END IF;
   v_choice:=nullif(btrim(p_semantic_decision->>'selected_skill_code'),'');
   v_reason:=nullif(btrim(p_semantic_decision->>'reason'),'');
   v_refs:=p_semantic_decision->'evidence_refs';
   v_revision:=p_semantic_decision->>'descriptor_revision';
   SELECT count(*) INTO v_sem_n FROM jsonb_array_elements(v_optional) x
   WHERE x->>'skill_code'=v_choice AND x->>'source_revision'=v_revision;
   IF v_sem_n<>1 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SEMANTIC_CHOICE_NOT_ALLOWED_OR_STALE'); END IF;
   IF v_reason IS NULL OR jsonb_typeof(v_refs)<>'array' OR jsonb_array_length(v_refs)=0
      OR coalesce(p_semantic_decision->>'review_mode','')<>'CURRENT_CONTEXT_REVIEW' THEN
      RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SEMANTIC_EVIDENCE_MISSING');
   END IF;
   SELECT coalesce(jsonb_agg(jsonb_build_object(
      'skill_code',x->>'skill_code','handler_fn',x->>'handler_fn',
      'required_operation',x->>'required_operation','effect',x->>'effect',
      'input_required',x->'input_required','selection_mode','SEMANTIC_DESCRIPTOR',
      'selection_evidence',jsonb_build_object('reason',v_reason,'evidence_refs',v_refs,
        'descriptor_revision',v_revision,'source_ref',x->>'source_ref',
        'review_mode','CURRENT_CONTEXT_REVIEW'),
      'invoker','public.lf_skill_invoke_v1')),'[]'::jsonb)
   INTO v_selected FROM jsonb_array_elements(v_optional) x
   WHERE x->>'skill_code'=v_choice;
   v_selected:=v_required||v_selected;
 END IF;
 RETURN jsonb_build_object('status','READY','skills',v_selected,
   'profile_code',p_profile_code,'channel',p_channel,
   'selection_mode','DETERMINISTIC_THEN_SEMANTIC',
   'source','lf_skill_selector_policy_v1+lf_skill_selection_registry_v1+lf_skill_catalog_v1',
   'independence_attested',false);
END;
$profile_skill_selector$;

CREATE OR REPLACE FUNCTION public.lf_profile_execution_plan_v1(
  p_profile_code text, p_channel text DEFAULT NULL, p_semantic_decision jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog','public'
AS $profile_plan_dynamic$
DECLARE v_steps jsonb; v_count int; v_invalid int; v_selected jsonb; v_out jsonb;
BEGIN
 SELECT count(*),count(*) FILTER(WHERE c.step_id IS NULL),
     coalesce(jsonb_agg(jsonb_build_object('step_order',s.step_order,'step_id',s.step_id,
       'resolver_ref',c.resolver_ref,'next_if_pass',c.next_if_pass,
       'next_if_blocked',c.next_if_blocked,'required_evidence_keys',c.required_evidence_keys)
       ORDER BY s.step_order),'[]'::jsonb)
 INTO v_count,v_invalid,v_steps
 FROM public.lf_operation_steps s
 LEFT JOIN public.lf_operation_step_contracts c
 ON c.operation_code=s.operation_code AND c.step_id=s.step_id AND c.status='ACTIVE_ENFORCEMENT'
 WHERE s.operation_code='EJECUCION_PERFIL_LF' AND s.active AND s.required;
 IF v_count<>11 OR v_invalid>0 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROFILE_OPERATION_STEP_CONTRACTS_INCOMPLETE');
 END IF;
 v_selected:=public.lf_profile_skill_selection_prepare_v1(p_profile_code,p_channel,p_semantic_decision);
 v_out:=jsonb_build_object('operation_code','EJECUCION_PERFIL_LF','profile_code',p_profile_code,
      'channel',p_channel,'status',v_selected->>'status',
      'steps',v_steps,'skills',coalesce(v_selected->'skills','[]'::jsonb),
      'selection_receipt',v_selected,'runtime_mode','GPT_NATIVE',
      'model_external_api',false,'step_source','lf_operation_steps+lf_operation_step_contracts');
 IF v_selected->>'status'='BLOCKED' THEN
    RETURN v_out||jsonb_build_object('blocking_code',v_selected->>'blocking_code');
 END IF;
 RETURN v_out;
END;
$profile_plan_dynamic$;

-- Selection receipt is bound to existing official skill_invocation ledger via skill_run_id.
-- This is a receipt, not a parallel skill invoker; existing lf_skill_invoke_v1 remains official.
CREATE TABLE IF NOT EXISTS public.lf_profile_skill_selection_receipt_v1 (
  skill_run_id text PRIMARY KEY REFERENCES public.lf_skill_invocation_v1(skill_run_id),
  parent_execution_id text NOT NULL,
  skill_code text NOT NULL,
  profile_code text NOT NULL,
  channel text NOT NULL,
  selection_mode text NOT NULL,
  selection_evidence jsonb NOT NULL,
  selection_sha256 text NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now()
);
CREATE OR REPLACE FUNCTION public.lf_profile_skill_invoke_selected_v1(
 p_execution_id text, p_channel text, p_skill_code text, p_input jsonb,
 p_semantic_decision jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $selected_invoker$
DECLARE e record; v_plan jsonb; v_skill jsonb; v_out jsonb; v_receipt jsonb;
BEGIN
 SELECT target_code,status,operation_code,manifest INTO e FROM public.lf_operation_execution
 WHERE execution_id=p_execution_id;
 IF NOT FOUND OR e.status<>'IN_PROGRESS' OR e.operation_code<>'EJECUCION_PERFIL_LF' THEN
  RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_PARENT_RUN_NOT_ACTIVE'); END IF;
 IF e.manifest#>>'{router_profile_handoff,channel}' IS DISTINCT FROM p_channel THEN
  RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_CHANNEL_NOT_BOUND_TO_PARENT_RUN'); END IF;
 v_plan:=public.lf_profile_execution_plan_v1(e.target_code,p_channel,p_semantic_decision);
 IF v_plan->>'status'<>'READY' THEN
  RETURN jsonb_build_object('status','BLOCKED',
    'blocking_code',coalesce(v_plan->>'blocking_code', 'SKILL_SEMANTIC_DECISION_PENDING')); END IF;
 SELECT x INTO v_skill FROM jsonb_array_elements(v_plan->'skills') x
 WHERE x->>'skill_code'=p_skill_code;
 IF v_skill IS NULL THEN
  RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_NOT_SELECTED_BY_DB_POLICY'); END IF;
 v_receipt:=jsonb_build_object('execution_id',p_execution_id,'skill_code',p_skill_code,
     'selection_mode',v_skill->>'selection_mode',
     'selection_evidence',v_skill->'selection_evidence','channel',p_channel);
 -- Source authority, input validation, dedupe, handler and child opener belong to official invoker.
 v_out:=public.lf_skill_invoke_v1(p_skill_code,p_execution_id,p_input);
 IF v_out->>'status'='COMPLETED' AND nullif(v_out->>'skill_run_id','') IS NOT NULL THEN
   INSERT INTO public.lf_profile_skill_selection_receipt_v1(
     skill_run_id,parent_execution_id,skill_code,profile_code,channel,
     selection_mode,selection_evidence,selection_sha256)
   VALUES (v_out->>'skill_run_id',p_execution_id,p_skill_code,e.target_code,p_channel,
       v_skill->>'selection_mode',v_receipt,
       encode(extensions.digest(convert_to(v_receipt::text,'UTF8'),'sha256'),'hex'))
   ON CONFLICT(skill_run_id) DO NOTHING;
   IF NOT EXISTS(SELECT 1 FROM public.lf_profile_skill_selection_receipt_v1 s
                 WHERE s.skill_run_id=v_out->>'skill_run_id'
                   AND s.parent_execution_id=p_execution_id AND s.skill_code=p_skill_code
                   AND s.selection_evidence=v_receipt) THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_REPLAY_RECEIPT_MISMATCH');
   END IF;
 END IF;
 RETURN v_out||jsonb_build_object('parent_execution_id',p_execution_id,
     'selection_mode',v_skill->>'selection_mode','selection_receipt',v_receipt);
END;
$selected_invoker$;
REVOKE ALL ON FUNCTION public.lf_profile_skill_invoke_selected_v1(text,text,text,jsonb,jsonb)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_skill_invoke_selected_v1(text,text,text,jsonb,jsonb) TO service_role;

COMMIT;
