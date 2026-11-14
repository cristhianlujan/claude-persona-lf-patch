-- PR A DRAFT / SOURCE_FIRST: profile-selected Step40 skills, no Router IG applicability.
-- Preimages inspected by pg_proc; no direct production execution.
BEGIN;
DO $pre$
BEGIN
 IF md5(pg_get_functiondef('public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)'::regprocedure)) <> '9293aa23cb29f3bb984a37799b6e5ff3' THEN
   RAISE EXCEPTION 'SOURCE_STATE_DRIFT:public.lf_profile_execution_input_validate_v1';
 END IF;
 IF md5(pg_get_functiondef('public.lf_skill_invoke_v1(text,text,jsonb)'::regprocedure)) <> 'ac7e351e1834cbfb91aabf26e1a04a8d' THEN
   RAISE EXCEPTION 'SOURCE_STATE_DRIFT:public.lf_skill_invoke_v1';
 END IF;
 IF md5(pg_get_functiondef('public.lf_profile_skill_invoke_selected_v1(text,text,text,jsonb,jsonb)'::regprocedure)) <> '802cfb1f0ca1b0c1d481b5e5395bc855' THEN
   RAISE EXCEPTION 'SOURCE_STATE_DRIFT:public.lf_profile_skill_invoke_selected_v1';
 END IF;
END $pre$;
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



  v_screen_request jsonb;
  v_screen_result jsonb;
  v_screen_validation jsonb;
  v_resolved_scope jsonb;


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

  -- Step40 validates scope and semantic screen; skill applicability belongs to
  -- the profile's live skill policy, NEVER to Router task binding metadata.
  IF upper(coalesce(p_handoff#>>'{scope,target_type}',''))='PANTALLA' THEN
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

  END IF;
  RETURN jsonb_build_object(
     'status','READY','blocking_code',null,'server_validated',true,
     'input_scope','ROUTER_AUTHORIZED_PROFILE_EXECUTION',
     'activation_trigger_match',true,
     'scope_authority_packet',v_scope->'scope_authority_packet',
     'scope_authority_packet_sha256',v_scope->>'scope_packet_sha256',
     'resolved_scope',coalesce(v_resolved_scope,p_handoff->'scope','{}'::jsonb),
     'analysis_scope','READ_ONLY_PROFILE_VALIDATION',
     'production_authorized',false,'promotion_authorized',false,
     'mutation_authorized',false,
     'allowed_actions',jsonb_build_array('ANALYZE','PROPOSE','VALIDATE','REPORT'),
     'router_handoff_fingerprint',p_handoff->>'fingerprint_sha256',
     'router_reentry_required',false
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.lf_skill_h_input_governance_context_pack_v1(p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','programacion'
AS $handler$
DECLARE
 v_exec public.lf_operation_execution%rowtype;
 v_ig jsonb; v_runtime text; v_slug text; v_screen integer;
 v_first_ticket_expires timestamptz;
BEGIN
 IF jsonb_typeof(p_input)<>'object' OR
    coalesce(p_input->>'consumer','')<>'CONTEXT_PACK' OR
    coalesce(p_input#>>'{scope,resolution_status}','')<>'RESOLVED' OR
    nullif(p_input->>'execution_id','') IS NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_IG_PROFILE_SCOPE_INVALID');
 END IF;
 SELECT * INTO v_exec FROM public.lf_operation_execution
 WHERE execution_id=p_input->>'execution_id'
   AND operation_code='EJECUCION_PERFIL_LF'
   AND target_type='PERFIL' AND status='IN_PROGRESS';
 IF NOT FOUND OR v_exec.target_code IS DISTINCT FROM p_input->>'profile_code' THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_IG_PARENT_NOT_CURRENT');
 END IF;
 v_ig:=programacion.fn_lf_profile_input_governance_resolve_v1(
   p_input->>'request_text',v_exec.target_code,p_input->'scope','CONTEXT_PACK');
 IF v_ig->>'status'='INPUT_GOVERNANCE_REQUIRED' THEN
   -- The existing profile-owned ticket TTL is the DB-authoritative wait bound,
   -- not a caller-provided timeout. Future tickets cannot extend the first TTL.
   SELECT min(t.expires_at) INTO v_first_ticket_expires
   FROM private.lf_profile_skill_runtime_ticket_v1 t
   WHERE t.execution_id=p_input->>'execution_id'
     AND t.consumer='CONTEXT_PACK';
   IF v_first_ticket_expires IS NOT NULL AND clock_timestamp()>v_first_ticket_expires THEN
     RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','SKILL_IG_RUNTIME_TIMEOUT_AS_FINDING',
        'skill_code','INPUT_GOVERNANCE_CONTEXT_PACK',
        'input_governance',v_ig||jsonb_build_object(
          'status','BLOCKED','decision','BLOCKED',
          'blocking_code','SKILL_IG_RUNTIME_TIMEOUT_AS_FINDING',
          'analysis_scope','READ_ONLY_WITH_IG_FINDINGS',
          'production_authorized',false,'promotion_authorized',false),
        'findings',jsonb_build_array(jsonb_build_object(
           'finding_type','SKILL_RUNTIME_TIMEOUT',
           'skill_code','INPUT_GOVERNANCE_CONTEXT_PACK',
           'source_run_status',v_ig->>'status',
           'first_ticket_expiry',v_first_ticket_expires)),
        'production_authorized',false,'promotion_authorized',false);
   END IF;
   SELECT c.especificacion->>'runtime_orchestrator' INTO v_runtime
   FROM programacion.contratos c JOIN programacion.versiones_agente v ON v.id=c.version_id
   JOIN programacion.agentes a ON a.id=v.agente_id
   WHERE a.agente_codigo='INPUT_GOVERNANCE_AGENT'
     AND c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
     AND c.estado='defined' AND c.fail_closed
   ORDER BY c.version_id DESC LIMIT 1;
   v_slug:=split_part(coalesce(v_runtime,''),':',2);
   v_screen:=(v_ig->>'pantalla_id')::integer;
   IF coalesce(v_runtime,'') NOT LIKE 'SUPABASE_EDGE_FUNCTION:%'
     OR v_slug !~ '^[a-z0-9][a-z0-9-]{0,62}$'
     OR v_screen IS NULL OR v_screen<1 THEN
       RETURN jsonb_build_object('status','BLOCKED',
         'blocking_code','SKILL_IG_RUNTIME_CONTRACT_INVALID','findings',jsonb_build_array(v_ig));
   END IF;
   RETURN jsonb_build_object('status','RUNTIME_REQUIRED','skill_code','INPUT_GOVERNANCE_CONTEXT_PACK',
     'runtime_request',jsonb_build_object(
       'transport','DIRECT_EDGE_INVOCATION','runtime_slug',v_slug,
       'legacy_ticket_adapter','INPUT_GOVERNANCE_CONTEXT_PACK_V1',
       'request_body',jsonb_build_object('pantalla_id',v_screen,'consumer','CONTEXT_PACK'),
       'terminal_statuses',jsonb_build_array('READY','BLOCKED','HUMAN_DECISION_REQUIRED'),
       'continuation_statuses',jsonb_build_array('VALIDATOR_RESUME_REQUIRED'),
       'queue_required',false,'polling_required',false),
     'input_governance',v_ig,'production_authorized',false);
 END IF;
 RETURN jsonb_build_object('status',coalesce(v_ig->>'status','BLOCKED'),
   'blocking_code',v_ig->>'blocking_code',
   'input_governance',v_ig,
   'findings',CASE WHEN v_ig->>'status'='BLOCKED' THEN jsonb_build_array(v_ig)
       ELSE '[]'::jsonb END,
   'production_authorized',false,'promotion_authorized',false);
END
$handler$;

CREATE OR REPLACE FUNCTION public.lf_skill_invoke_v1(p_skill text, p_execution_id text, p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare c record; par record; v_run text := 'RUN-'||upper(substr(md5(random()::text||clock_timestamp()::text),1,20)); v_in text; v_missing text[]; k text; v_out jsonb; v_code text; v_prof text; v_ev text; v_child text; v_status text; v_prior public.lf_skill_invocation_v1%ROWTYPE; v_prior_count integer; v_rule_receipt jsonb;
begin
  v_in := encode(extensions.digest(convert_to(coalesce(p_input,'{}'::jsonb)::text,'UTF8'),'sha256'),'hex');
  select * into par from public.lf_operation_execution e where e.execution_id=p_execution_id and e.operation_code='EJECUCION_PERFIL_LF' and e.status='IN_PROGRESS';
  v_prof := par.target_code;
  if not found then v_code:='PARENT_EXECUTION_NOT_ACTIVE';
  else
    select * into c from public.lf_skill_catalog_v1 s where s.skill_code=p_skill;
    if not found then v_code:='SKILL_NOT_FOUND';
    elsif c.status<>'READY' then v_code:='SKILL_NOT_READY';
    elsif c.effect='WRITE_GOVERNED' and not exists(select 1 from public.lf_profile_write_authority_v1 a where a.profile_code=v_prof and a.operation_code=c.required_operation and a.status='ACTIVE') then v_code:='SKILL_NOT_AUTHORIZED_FOR_PROFILE';
    else
      v_missing := array[]::text[];
      foreach k in array c.input_required loop if nullif(p_input->>k,'') is null then v_missing:=v_missing||k; end if; end loop;
      if array_length(v_missing,1) is not null then v_code:='SKILL_INPUT_INVALID';
      elsif not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=c.handler_fn) then v_code:='SKILL_HANDLER_MISSING';
      else
        -- One parent+skill+input may open only one invocation/child.
        -- Advisory transaction lock serializes two concurrent calls before the effect.
        perform pg_catalog.pg_advisory_xact_lock(
          pg_catalog.hashtextextended(p_execution_id||':'||p_skill||':'||v_in,0)
        );
        select count(*) into v_prior_count
          from public.lf_skill_invocation_v1 i
         where i.parent_execution_id=p_execution_id and i.skill_code=p_skill
           and i.input_sha256=v_in;
        if v_prior_count>1 then
          return jsonb_build_object('status','BLOCKED',
            'blocking_code','SKILL_REPLAY_AMBIGUOUS_HISTORY','replay',false,
            'next_action','RECONCILE_HISTORICAL_DUPLICATES_WITHOUT_DELETE');
        elsif v_prior_count=1 then
          select * into v_prior from public.lf_skill_invocation_v1 i
           where i.parent_execution_id=p_execution_id and i.skill_code=p_skill
             and i.input_sha256=v_in;
          if v_prior.profile_code is distinct from v_prof then
            return jsonb_build_object('status','BLOCKED',
              'blocking_code','SKILL_REPLAY_PROFILE_MISMATCH','replay',false);
          end if;
          if v_prior.child_execution_id is not null and
             not exists(
               select 1 from public.lf_operation_execution e
                where e.execution_id=v_prior.child_execution_id
                  and e.operation_code=c.required_operation
                  and e.created_by_execution_id=p_execution_id
             ) then
            return jsonb_build_object('status','BLOCKED',
              'blocking_code','SKILL_REPLAY_CHILD_BINDING_MISMATCH','replay',false);
          end if;
          IF p_skill='RULE_UPDATE_APPLY' AND v_prior.child_execution_id IS NOT NULL THEN
            v_rule_receipt:=public.lf_skill_rule_child_readback_v1(
              p_execution_id,v_prior.skill_run_id,v_prior.child_execution_id);
          ELSE
            v_rule_receipt:=NULL;
          END IF;
          return jsonb_build_object(
            'status',v_prior.status,
            'skill_run_id',v_prior.skill_run_id,
            'output',coalesce(v_prior.output,'{}'::jsonb),
            'evidence_ref',v_prior.evidence_ref,
            'child_execution_id',v_prior.child_execution_id,
            'blocking_code',v_prior.blocking_code,
            'replay',true,
            'effect_verified',coalesce(v_rule_receipt->>'status','')='APPLIED_VERIFIED',
            'child_receipt',v_rule_receipt,
            'next_action',case
              when v_rule_receipt->>'status'='APPLIED_VERIFIED' then 'CONTINUE_PROFILE'
              when v_prior.child_execution_id is not null then 'VERIFY_CHILD_OPERATION_BEFORE_PROFILE_CLOSE'
              when v_prior.status='COMPLETED' then 'CONTINUE_PROFILE'
              else 'FIX_REQUEST_AND_RETRY' end
          );
        end if;
        begin
          execute format('select public.%I($1)',c.handler_fn) into v_out using p_input;
        exception when others then
          v_code:='SKILL_HANDLER_ERROR';
        end;
      end if;
    end if;
  end if;
  -- A runtime request is NOT a completed invocation; retry from the same RUN.
  IF v_code IS NULL AND v_out->>'status' IN ('RUNTIME_REQUIRED','INPUT_GOVERNANCE_REQUIRED') THEN
    RETURN jsonb_build_object('status','RUNTIME_REQUIRED','skill_code',p_skill,
      'parent_execution_id',p_execution_id,'output',v_out,
      'runtime_request',v_out->'runtime_request',
      'next_action','DISPATCH_SELECTED_SKILL_RUNTIME_THROUGH_PROFILE');
  END IF;
  IF v_code IS NULL AND v_out->>'status' IN ('BLOCKED','FAILED','HUMAN_DECISION_REQUIRED') THEN
    v_ev:='SKILLRUN:'||v_run||':'||encode(extensions.digest(convert_to(v_out::text,'UTF8'),'sha256'),'hex');
    INSERT INTO public.lf_skill_invocation_v1(
      skill_run_id,skill_code,parent_execution_id,profile_code,status,
      blocking_code,input_sha256,output,evidence_ref
    ) VALUES(v_run,p_skill,p_execution_id,v_prof,'BLOCKED',
      coalesce(v_out->>'blocking_code','SKILL_RUNTIME_OR_EVIDENCE_BLOCKED'),
      v_in,v_out,v_ev);
    RETURN jsonb_build_object('status','BLOCKED','skill_run_id',v_run,
      'output',v_out,'evidence_ref',v_ev,'skill_code',p_skill,
      'blocking_code',coalesce(v_out->>'blocking_code','SKILL_BLOCKED_AS_FINDING'));
  END IF;
  if v_code is null and exists(select 1 from public.lf_skill_catalog_v1 s2 where s2.skill_code=p_skill and s2.effect='WRITE_GOVERNED') then
    v_child := 'EXEC-SKILL-'||substr(v_run,5,16);
    v_ev := 'SKILLRUN:'||v_run||':'||encode(extensions.digest(convert_to(v_out::text,'UTF8'),'sha256'),'hex');
    insert into public.lf_skill_invocation_v1(skill_run_id,skill_code,parent_execution_id,profile_code,status,input_sha256,output,evidence_ref,child_execution_id) values(v_run,p_skill,p_execution_id,v_prof,'COMPLETED',v_in,v_out,v_ev,v_child);
    begin
      if c.opener_fn is null then
      insert into public.lf_operation_execution(execution_id,operation_code,target_type,target_code,manifest,request_sha256,idempotency_key,created_by_execution_id)
      values(v_child,c.required_operation,coalesce(p_input->>'target_type','REGLA'),coalesce(p_input->>'target_code',p_input->>'regla_codigo'),
        jsonb_build_object('profile_handoff',jsonb_build_object('source_execution_id',p_execution_id,'skill_run_id',v_run,'analysis_snapshot_sha256',p_input->>'analysis_snapshot_sha256','via','SKILL_INVOKER')) || public.lf_skill_child_caller_manifest_v1(p_skill),
        par.request_sha256,'skill-child-v1:'||v_run,p_execution_id);
      else
        execute format('select public.%I($1,$2,$3,$4,$5)',c.opener_fn) using v_child,p_input,p_execution_id,v_run,par.request_sha256;
      end if;
    exception when others then
      v_code := coalesce(nullif(split_part(sqlerrm,':',1),''),'SKILL_CHILD_EXECUTION_BLOCKED');
      update public.lf_skill_invocation_v1 set status='BLOCKED', blocking_code=v_code, child_execution_id=null where skill_run_id=v_run;
      return jsonb_build_object('status','BLOCKED','skill_run_id',v_run,'output','{}'::jsonb,'evidence_ref',null,'blocking_code',v_code,'detail',left(sqlerrm,220),'next_action','FIX_REQUEST_AND_RETRY');
    end;
    IF p_skill='RULE_UPDATE_APPLY' THEN
      v_rule_receipt:=public.lf_skill_rule_child_readback_v1(p_execution_id,v_run,v_child);
    ELSE
      v_rule_receipt:=NULL;
    END IF;
    return jsonb_build_object('status','COMPLETED','skill_run_id',v_run,
      'output',v_out,'evidence_ref',v_ev,'child_execution_id',v_child,
      'effect_verified',coalesce(v_rule_receipt->>'status','')='APPLIED_VERIFIED',
      'child_receipt',v_rule_receipt,
      'next_action',case when v_rule_receipt->>'status'='APPLIED_VERIFIED'
        then 'CONTINUE_PROFILE' else 'VERIFY_CHILD_OPERATION_BEFORE_PROFILE_CLOSE' end);
  end if;
  if v_code is not null then
    v_status := case when v_code='SKILL_HANDLER_ERROR' then 'FAILED' else 'BLOCKED' end;
    insert into public.lf_skill_invocation_v1(skill_run_id,skill_code,parent_execution_id,profile_code,status,blocking_code,input_sha256) values(v_run,p_skill,p_execution_id,v_prof,v_status,v_code,v_in);
    return jsonb_build_object('status',v_status,'skill_run_id',v_run,'output','{}'::jsonb,'evidence_ref',null,'blocking_code',v_code,'missing_inputs',to_jsonb(v_missing),'next_action','FIX_REQUEST_AND_RETRY');
  end if;
  v_ev := 'SKILLRUN:'||v_run||':'||encode(extensions.digest(convert_to(v_out::text,'UTF8'),'sha256'),'hex');
  insert into public.lf_skill_invocation_v1(skill_run_id,skill_code,parent_execution_id,profile_code,status,input_sha256,output,evidence_ref) values(v_run,p_skill,p_execution_id,v_prof,'COMPLETED',v_in,v_out,v_ev);
  return jsonb_build_object('status','COMPLETED','skill_run_id',v_run,'output',v_out,'evidence_ref',v_ev,'next_action','CONTINUE_PROFILE');
end $function$;


CREATE OR REPLACE FUNCTION public.lf_profile_skill_invoke_selected_v1(p_execution_id text, p_channel text, p_skill_code text, p_input jsonb, p_semantic_decision jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE e record; v_plan jsonb; v_skill jsonb; v_out jsonb; v_receipt jsonb;
 v_app_contract jsonb; v_app_evidence jsonb; v_app_path text[];
 v_app_value text;
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
 -- Generic, policy-bound applicability; no skill/IG/profile name is encoded
 -- in the invoker or in the Step40/50 operation contract. A legacy NOT_REQUIRED
 -- receipt MUST NOT trigger a skill invocation.
 SELECT applicability_contract INTO v_app_contract
 FROM public.lf_skill_selector_policy_v1
 WHERE profile_code=e.target_code AND skill_code=p_skill_code
   AND required_operation=v_skill->>'required_operation'
   AND enabled AND p_channel=ANY(channels);
 IF v_app_contract IS NULL THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_APPLICABILITY_POLICY_NOT_FOUND');
 END IF;
 IF coalesce((v_app_contract->>'only_if_applicable')::boolean,false) THEN
   IF v_app_contract->>'evaluation'<>'EVIDENCE_PAYLOAD' OR
      coalesce(v_app_contract->>'evidence_step_id','')='' OR
      jsonb_typeof(v_app_contract->'evidence_json_path')<>'array' THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_APPLICABILITY_POLICY_INVALID');
   END IF;
   SELECT array_agg(path_element ORDER BY ord) INTO v_app_path
   FROM jsonb_array_elements_text(v_app_contract->'evidence_json_path')
       WITH ORDINALITY AS path(path_element,ord);
   IF v_app_path IS NULL OR cardinality(v_app_path)<1 THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_APPLICABILITY_PATH_INVALID');
   END IF;
   SELECT evidence_payload INTO v_app_evidence
   FROM public.lf_operation_execution_steps
   WHERE execution_id=p_execution_id
     AND step_id=v_app_contract->>'evidence_step_id'
     AND status='STEP_PASS_WITH_EVIDENCE';
   IF v_app_evidence IS NULL THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_APPLICABILITY_EVIDENCE_NOT_READY');
   END IF;
   v_app_value:=jsonb_extract_path_text(v_app_evidence,VARIADIC v_app_path);
   IF v_app_value IS DISTINCT FROM v_app_contract->>'positive_literal' THEN
     RETURN jsonb_build_object('status','BLOCKED',
       'blocking_code',case when v_app_value='false'
             then 'SKILL_NOT_REQUIRED_BY_INPUT_VALIDATE'
             else 'SKILL_APPLICABILITY_NOT_ATTESTED' end);
   END IF;
 END IF;
 v_receipt:=jsonb_build_object('execution_id',p_execution_id,'skill_code',p_skill_code,
     'selection_mode',v_skill->>'selection_mode',
     'selection_evidence',v_skill->'selection_evidence','channel',p_channel);
 -- Source authority, input validation, dedupe, handler and child opener belong to official invoker.
 BEGIN
   v_out:=public.lf_skill_invoke_v1(p_skill_code,p_execution_id,p_input);
 EXCEPTION WHEN OTHERS THEN
   RETURN jsonb_build_object('status','SKILL_FAILED_AS_FINDING',
     'parent_execution_id',p_execution_id,'skill_code',p_skill_code,
     'blocking_code',SQLSTATE,'error_message',left(SQLERRM,500),
     'selection_receipt',v_receipt,'effect_authorized',false,
     'next_action','CONTINUE_PROFILE_READ_ONLY_WITH_SKILL_FINDINGS');
 END;
 IF v_out->>'status' IN ('BLOCKED','FAILED','SKILL_FAILED_AS_FINDING') THEN
   RETURN v_out||jsonb_build_object('status','SKILL_FAILED_AS_FINDING',
     'parent_execution_id',p_execution_id,'selection_receipt',v_receipt,
     'effect_authorized',false,
     'next_action','CONTINUE_PROFILE_READ_ONLY_WITH_SKILL_FINDINGS');
 END IF;
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
$function$;


-- Source-first selection: only 4 profiles actually GOBERNADOS_POR IG today,
-- never enable unrelated candidate policies. Owner authorization 2026-11-14.
DO $governed$
DECLARE v_bind integer; v_count integer;
BEGIN
 SELECT count(*) INTO v_bind FROM public.lf_skill_selector_policy_v1 p
 WHERE p.skill_code='INPUT_GOVERNANCE_CONTEXT_PACK'
 AND EXISTS(SELECT 1 FROM public.lf_activo_relaciones r
      WHERE r.codigo_activo=p.profile_code
        AND r.relacionado_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
        AND r.relacion_tipo='GOBERNADO_POR');
 IF v_bind<>4 THEN RAISE EXCEPTION 'GOVERNED_SKILL_POLICY_BINDING_DRIFT:%',v_bind; END IF;
 IF (SELECT status FROM public.lf_skill_catalog_v1
     WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK')<>'DRAFT' THEN
   RAISE EXCEPTION 'IG_SKILL_CATALOG_PREIMAGE_DRIFT';
 END IF;
 UPDATE public.lf_skill_catalog_v1 SET status='READY'
 WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK'
   AND handler_fn='lf_skill_h_input_governance_context_pack_v1' AND effect='READ_ONLY';
 GET DIAGNOSTICS v_count = ROW_COUNT;
 IF v_count<>1 THEN RAISE EXCEPTION 'IG_SKILL_CATALOG_ACTIVATION_NOT_EXACT:%',v_count; END IF;
 UPDATE public.lf_skill_selection_registry_v1
 SET descriptor_status='CURRENT',
     source_revision='sha256:'||encode(extensions.digest(convert_to(
       pg_get_functiondef('public.lf_skill_h_input_governance_context_pack_v1(jsonb)'::regprocedure),
       'UTF8'),'sha256'),'hex'),
     source_ref='supabase://public.lf_skill_h_input_governance_context_pack_v1',
     synced_at=clock_timestamp()
 WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK'
   AND descriptor_status='STALE_SOURCE_CHANGED'
   AND source_revision='CANDIDATE_SOURCE_NOT_ATTESTED';
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count<>1 THEN RAISE EXCEPTION 'IG_SKILL_DESCRIPTOR_CURRENTNESS_DRIFT:%',v_count; END IF;
 UPDATE public.lf_skill_selector_policy_v1 p
 SET enabled=true,owner_decision_required=false,
     applicability_contract=jsonb_build_object('only_if_applicable',false,
          'source','PROFILE_CURRENT_POLICY','owner_instruction','2026-11-14'),
     policy_evidence_ref='owner://lf/2026-11-14/skill-policy-active-by-design',
     updated_at=clock_timestamp()
 WHERE p.skill_code='INPUT_GOVERNANCE_CONTEXT_PACK'
   AND p.enabled=false AND p.owner_decision_required=true
   AND p.selection_mode='DETERMINISTIC_REQUIRED'
   AND EXISTS(SELECT 1 FROM public.lf_activo_relaciones r
      WHERE r.codigo_activo=p.profile_code
        AND r.relacionado_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
        AND r.relacion_tipo='GOBERNADO_POR');
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count<>4 THEN RAISE EXCEPTION 'IG_SKILL_POLICY_ACTIVATION_NOT_EXACT:%',v_count; END IF;
END $governed$;
DO $bridgepre$
BEGIN
 IF md5(pg_get_functiondef('public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure))
   <> '92f52f23e0f8cbfb96c2e0ebad58a5be' THEN RAISE EXCEPTION 'SOURCE_STATE_DRIFT:bridge'; END IF;
 IF md5(pg_get_functiondef('public.lf_profile_input_governance_runtime_ticket_issue_v1(text,text,text,jsonb)'::regprocedure))
   <> '7945acf4d72bc1d7b85a0f646405a16a' THEN RAISE EXCEPTION 'SOURCE_STATE_DRIFT:ticket'; END IF;
END $bridgepre$;

CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_prepare_v1(p_execution_id text, p_source_revision text, p_source_digest text, p_actor_execution_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
  v_policy_selection jsonb;
  v_ig_ticket jsonb;
  v_skill_plan jsonb;
  v_skill_item jsonb;
  v_skill_result jsonb;
  v_skill_findings jsonb:='[]'::jsonb;
  v_skill_receipts jsonb:='[]'::jsonb;
  v_skill_input jsonb;
  v_skill_code text;
  v_skill_ig jsonb;
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
     OR NOT COALESCE(
       (e.manifest->>'executor_mode'='GPT_NATIVE'
        AND e.manifest->>'executor_provider'='OPENAI_CHATGPT_NATIVE')
       OR (e.manifest->>'executor_mode'='CLAUDE_NATIVE'
        AND e.manifest->>'executor_provider'='ANTHROPIC_CLAUDE_NATIVE'),
       false) THEN
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
      IF v_input->>'status'='SCREEN_SELECTION_REQUIRED'
         AND v_input->>'next_action'='RUN_SCREEN_SEMANTIC_SELECTION_AND_SUBMIT'
         AND jsonb_typeof(v_input->'screen_selection_request')='object'
      THEN
        RETURN jsonb_build_object(
          'status','SCREEN_SELECTION_REQUIRED',
          'blocking_code',null,
          'execution_id',p_execution_id,
          'screen_selection_request',v_input->'screen_selection_request',
          'selection_mode','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC',
          'semantic_selection_required',true,
          'submit_entrypoint','public.lf_profile_screen_selector_semantic_submit_v1',
          'submit_raw_entrypoint','public.lf_profile_screen_selector_semantic_submit_raw_v1',
          'next_action','SUBMIT_SCREEN_SELECTION_AND_RETRY_SAME_NATIVE_BRIDGE_PREPARE',
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false
        );
      END IF;


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


    -- Step40 executes all policy-selected READ_ONLY skills; never Router-owned.
    v_skill_plan:=public.lf_profile_execution_plan_v1(e.target_code,v_handoff->>'channel',null::jsonb);
    IF v_skill_plan->>'status'<>'READY' THEN
      RETURN jsonb_build_object('status',v_skill_plan->>'status',
        'blocking_code',coalesce(v_skill_plan->>'blocking_code','SKILL_POLICY_NOT_READY'),
        'skill_plan',v_skill_plan,'execution_id',p_execution_id);
    END IF;
    FOR v_skill_item IN SELECT x FROM jsonb_array_elements(v_skill_plan->'skills') x LOOP
      v_skill_code:=v_skill_item->>'skill_code';
      IF v_skill_item->>'effect'<>'READ_ONLY' THEN
        v_skill_receipts:=v_skill_receipts||jsonb_build_array(
          jsonb_build_object('skill_code',v_skill_code,'status','DEFERRED_NOT_STEP40',
             'effect_authorized',false));
        CONTINUE;
      END IF;
      v_skill_input:=jsonb_build_object(
        'execution_id',p_execution_id,
        'request_text',v_handoff->>'literal_request',
        'profile_code',e.target_code,
        'scope',v_input->'resolved_scope',
        'consumer','CONTEXT_PACK',
        'pantalla_codigo',v_input#>>'{resolved_scope,resolved_screen_code}'
      );
      v_skill_result:=public.lf_profile_skill_invoke_selected_v1(
        p_execution_id,v_handoff->>'channel',v_skill_code,v_skill_input,null
      );
      IF v_skill_result->>'status'='RUNTIME_REQUIRED' THEN
        v_ig_ticket:=public.lf_profile_skill_runtime_ticket_issue_v1(
          p_execution_id,v_skill_code,v_skill_input);
        IF v_ig_ticket->>'status'='AUTHORIZED' THEN
          RETURN jsonb_build_object(
            'status','SKILL_RUNTIME_REQUIRED','skill_code',v_skill_code,
            'execution_id',p_execution_id,'input_validate',v_input,
            'input_governance_runtime_request',jsonb_build_object(
              'transport','DIRECT_EDGE_INVOCATION',
              'runtime_orchestrator','SUPABASE_EDGE_FUNCTION:lf-profiles-governance-caller-v1',
              'runtime_slug',v_ig_ticket->>'runtime_slug',
              'request_headers',jsonb_build_object(
                'X-LF-Profile-Runtime-Ticket',v_ig_ticket->>'ticket'),
              'request_body',jsonb_build_object(
                'action','profile_skill_runtime_v1','execution_id',p_execution_id,
                'skill_code',v_skill_code),
              'terminal_statuses',jsonb_build_array('READY','BLOCKED','HUMAN_DECISION_REQUIRED','FAILED'),
              'continuation_statuses',jsonb_build_array('VALIDATOR_RESUME_REQUIRED'),
              'ticket_expires_at',v_ig_ticket->'expires_at',
              'queue_required',false,'polling_required',false),
            'next_action','INVOKE_SELECTED_SKILL_RUNTIME_AND_RETRY_SAME_BRIDGE',
            'router_reentry_required',false);
        END IF;
        v_skill_result:=jsonb_build_object('status','SKILL_FAILED_AS_FINDING',
          'blocking_code','SKILL_RUNTIME_TICKET_NOT_AUTHORIZED',
          'ticket_status',v_ig_ticket->>'status','skill_code',v_skill_code);
      END IF;
      v_skill_receipts:=v_skill_receipts||jsonb_build_array(jsonb_build_object(
        'skill_code',v_skill_code,'result',v_skill_result));
      IF v_skill_code='INPUT_GOVERNANCE_CONTEXT_PACK' THEN
        v_skill_ig:=coalesce(v_skill_result#>'{output,input_governance}',
          v_skill_result->'input_governance','{}'::jsonb);
      END IF;
      IF v_skill_result->>'status' IN ('BLOCKED','FAILED','SKILL_FAILED_AS_FINDING') THEN
        v_skill_findings:=v_skill_findings||jsonb_build_array(jsonb_build_object(
           'skill_code',v_skill_code,'status','SKILL_FAILED_AS_FINDING',
           'blocking_code',coalesce(v_skill_result->>'blocking_code','SKILL_FAILED'),
           'evidence_ref',v_skill_result->>'evidence_ref',
           'receipt',v_skill_result));
      END IF;
    END LOOP;
    v_input:=v_input||jsonb_build_object(
      'skill_execution_receipts',v_skill_receipts,
      'skill_findings',v_skill_findings,
      'analysis_scope',case when jsonb_array_length(v_skill_findings)>0
        then 'READ_ONLY_WITH_IG_FINDINGS' else 'READ_ONLY_PROFILE_VALIDATION' end,
      'input_governance',coalesce(v_skill_ig,'{}'::jsonb)
          ||jsonb_build_object('analysis_scope',
              case when jsonb_array_length(v_skill_findings)>0
                then 'READ_ONLY_WITH_IG_FINDINGS' else 'READ_ONLY_PROFILE_VALIDATION' end,
              'production_authorized',false,'promotion_authorized',false),
      'production_authorized',false,'promotion_authorized',false,
      'mutation_authorized',false,
      'allowed_actions',jsonb_build_array('ANALYZE','PROPOSE','VALIDATE','REPORT')
    );
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

  v_policy_selection:=public.lf_profile_policy_selection_prepare_v1(p_execution_id);

  IF v_policy_selection->>'status'<>'READY' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code',coalesce(v_policy_selection->>'blocking_code','BLOCK_PROFILE_POLICY_SELECTION_PREPARE_FAILED'),
      'policy_selection',v_policy_selection
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
    'ig_open_work',public.lf_profile_ig_open_work_v1(p_execution_id),
    'ig_open_work_count',jsonb_array_length(public.lf_profile_ig_open_work_v1(p_execution_id)),
    'ig_open_work_response_contract',jsonb_build_object(
      'required',jsonb_array_length(public.lf_profile_ig_open_work_v1(p_execution_id))>0,
      'output_field','traceability.ig_open_work_resolution',
      'coverage','EXACT_ONE_RESPONSE_PER_FAMILY',
      'allowed_statuses',jsonb_build_array(
        'RESUELTA','NO_CORRESPONDE','DEPENDENCIA','DECISIÓN_REQUERIDA'
      ),
      'resolved_requires_evidence',true,
      'dependency_or_decision_requires_next_action',true
    ),
    'context_receipt_ref',v_context->>'context_receipt_ref',
    'context_receipt_digest',v_context->>'context_receipt_digest',
    'context_capsule',v_context->'context_capsule',
    'research_baseline',v_baseline,
    'policy_resolution_mode','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC',
    'policy_selection_request',v_policy_selection,
    'repair_execution_authority',
      e.manifest->'repair_execution_authority',
    'execution_write_mode',
      case
        when coalesce((e.manifest->>'governed_repair_write')::boolean,false)
          then 'GOVERNED_REPAIR_WRITE'
        else 'READ_ONLY'
      end,
    'clean_step_count',v_clean,
    'next_step','execute_profile',
    'next_action',CASE e.manifest->>'executor_mode' WHEN 'CLAUDE_NATIVE' THEN 'EXECUTE_PROFILE_IN_CURRENT_CLAUDE_NATIVE_CONTEXT' ELSE 'EXECUTE_PROFILE_IN_CURRENT_GPT_NATIVE_CONTEXT' END,
    'semantic_judge_after_output','INDEPENDENT_CONTEXT_REQUIRED',
    'router_reentry_required',false
  );
END
$function$;



-- Runtime slug only from authoritative skill catalog.
ALTER TABLE public.lf_skill_catalog_v1 ADD COLUMN IF NOT EXISTS runtime_slug text;
UPDATE public.lf_skill_catalog_v1 SET runtime_slug='input-governance-agent-v1'
 WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK' AND status='READY'
 AND effect='READ_ONLY' AND runtime_slug IS NULL;
-- Generic skill runtime ticket, selected by the current profile policy.
-- Existing IG token remains a backward-compatible worker adapter only.
CREATE TABLE private.lf_profile_skill_runtime_ticket_v1 (
 ticket_id uuid PRIMARY KEY,
 execution_id text NOT NULL,
 skill_code text NOT NULL,
 runtime_slug text NOT NULL,
 request_body jsonb NOT NULL,
 request_sha256 text NOT NULL,
 issued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 expires_at timestamptz NOT NULL,
 consumed_at timestamptz,
 consumed_by text,
 CONSTRAINT lf_profile_skill_rt_expiry CHECK(expires_at>issued_at),
 CONSTRAINT lf_profile_skill_rt_consumed CHECK (
   (consumed_at IS NULL AND consumed_by IS NULL) OR
   (consumed_at IS NOT NULL AND consumed_by='LF_PROFILES_GOVERNANCE_CALLER_V1')
 )
);
REVOKE ALL ON private.lf_profile_skill_runtime_ticket_v1 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.lf_profile_skill_runtime_ticket_issue_v1(
 p_execution_id text,p_skill_code text,p_input jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private','extensions'
AS $issue$
DECLARE
 v_e public.lf_operation_execution%rowtype;
 v_plan jsonb;v_invoked jsonb;v_req jsonb;
 v_catalog_runtime_slug text;
 v_id uuid:=extensions.gen_random_uuid();
 v_exp timestamptz:=clock_timestamp()+interval '5 minutes';
 v_screen integer;
BEGIN
 IF jsonb_typeof(p_input)<>'object'
   OR p_input->>'execution_id' IS DISTINCT FROM p_execution_id THEN
  RETURN jsonb_build_object('status','BLOCKED','code','SKILL_TICKET_INPUT_INVALID');
 END IF;
 SELECT * INTO v_e FROM public.lf_operation_execution e
 WHERE e.execution_id=p_execution_id AND e.operation_code='EJECUCION_PERFIL_LF'
   AND e.target_type='PERFIL' AND e.status='IN_PROGRESS';
 IF NOT FOUND OR p_input->>'profile_code' IS DISTINCT FROM v_e.target_code THEN
  RETURN jsonb_build_object('status','BLOCKED','code','SKILL_TICKET_PARENT_INVALID');
 END IF;
 v_plan:=public.lf_profile_execution_plan_v1(v_e.target_code,
   v_e.manifest#>>'{router_profile_handoff,channel}',NULL);
 IF v_plan->>'status'<>'READY' OR NOT EXISTS(
    SELECT 1 FROM jsonb_array_elements(v_plan->'skills') sk
    WHERE sk->>'skill_code'=p_skill_code AND sk->>'effect'='READ_ONLY'
 ) THEN RETURN jsonb_build_object(
   'status','BLOCKED','code','SKILL_TICKET_NOT_POLICY_SELECTED'); END IF;
 v_invoked:=public.lf_profile_skill_invoke_selected_v1(
    p_execution_id,v_e.manifest#>>'{router_profile_handoff,channel}',
    p_skill_code,p_input,NULL);
 v_req:=v_invoked->'runtime_request';
 SELECT c.runtime_slug INTO v_catalog_runtime_slug FROM public.lf_skill_catalog_v1 c
 WHERE c.skill_code=p_skill_code AND c.status='READY' AND c.effect='READ_ONLY';
 IF coalesce(v_catalog_runtime_slug,'') !~ '^[a-z0-9][a-z0-9-]{0,62}$'
 OR v_catalog_runtime_slug IS DISTINCT FROM v_req->>'runtime_slug' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','SKILL_RUNTIME_CATALOG_SLUG_MISMATCH');
 END IF;
 IF v_invoked->>'status'<>'RUNTIME_REQUIRED'
    OR v_req->>'transport'<>'DIRECT_EDGE_INVOCATION'
    OR coalesce(v_req->>'runtime_slug','') !~ '^[a-z0-9][a-z0-9-]{0,62}$'
    OR jsonb_typeof(v_req->'request_body')<>'object' THEN
    RETURN jsonb_build_object('status','BLOCKED','code','SKILL_TICKET_RUNTIME_NOT_ATTESTED',
      'skill_status',v_invoked->>'status');
 END IF;
 INSERT INTO private.lf_profile_skill_runtime_ticket_v1(
   ticket_id,execution_id,skill_code,runtime_slug,request_body,
   request_sha256,expires_at
 ) VALUES (
   v_id,p_execution_id,p_skill_code,v_req->>'runtime_slug',v_req->'request_body',
   encode(extensions.digest(convert_to(p_input::text,'UTF8'),'sha256'),'hex'),v_exp
 );
 IF v_req->>'legacy_ticket_adapter'='INPUT_GOVERNANCE_CONTEXT_PACK_V1' THEN
   v_screen:=nullif(v_req#>>'{request_body,pantalla_id}','')::integer;
   IF p_skill_code<>'INPUT_GOVERNANCE_CONTEXT_PACK'
     OR v_screen IS NULL OR v_screen<1
     OR v_req#>>'{request_body,consumer}'<>'CONTEXT_PACK' THEN
     RAISE EXCEPTION 'SKILL_IG_ADAPTER_SCOPE_INVALID';
   END IF;
   INSERT INTO private.lf_profile_input_governance_runtime_ticket_v1(
     ticket_id,execution_id,pantalla_id,consumer,
     router_handoff_fingerprint,expires_at
   ) VALUES(
     v_id,p_execution_id,v_screen,'CONTEXT_PACK',
     v_e.manifest#>>'{router_profile_handoff,fingerprint_sha256}',v_exp
   );
 END IF;
 RETURN jsonb_build_object('status','AUTHORIZED','ticket',v_id::text,
   'execution_id',p_execution_id,'skill_code',p_skill_code,
   'runtime_slug',v_req->>'runtime_slug',
   'expires_at',v_exp,'transport','DIRECT_EDGE_INVOCATION');
END
$issue$;
REVOKE ALL ON FUNCTION public.lf_profile_skill_runtime_ticket_issue_v1(text,text,jsonb)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_skill_runtime_ticket_issue_v1(text,text,jsonb)
 TO service_role;

CREATE OR REPLACE FUNCTION public.lf_profile_skill_runtime_ticket_consume_v1(
 p_ticket uuid,p_execution_id text,p_skill_code text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','private'
AS $consume$
DECLARE
 v_r private.lf_profile_skill_runtime_ticket_v1%rowtype;
 v_old jsonb;v_plan jsonb;v_profile text;v_channel text;
BEGIN
 SELECT e.target_code,e.manifest#>>'{router_profile_handoff,channel}'
 INTO v_profile,v_channel FROM public.lf_operation_execution e
 WHERE e.execution_id=p_execution_id AND e.operation_code='EJECUCION_PERFIL_LF'
  AND e.target_type='PERFIL' AND e.status='IN_PROGRESS';
 IF v_profile IS NULL THEN RETURN jsonb_build_object(
    'authorized',false,'code','SKILL_TICKET_PARENT_NOT_ACTIVE'); END IF;
 v_plan:=public.lf_profile_execution_plan_v1(v_profile,v_channel,NULL);
 IF v_plan->>'status'<>'READY' OR NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_plan->'skills') sk
    WHERE sk->>'skill_code'=p_skill_code AND sk->>'effect'='READ_ONLY'
 ) THEN RETURN jsonb_build_object(
    'authorized',false,'code','SKILL_TICKET_POLICY_NOT_CURRENT'); END IF;
 UPDATE private.lf_profile_skill_runtime_ticket_v1 r
 SET consumed_at=clock_timestamp(),consumed_by='LF_PROFILES_GOVERNANCE_CALLER_V1'
 WHERE r.ticket_id=p_ticket AND r.execution_id=p_execution_id
   AND r.skill_code=p_skill_code AND r.consumed_at IS NULL
   AND r.expires_at>clock_timestamp()
 RETURNING r.* INTO v_r;
 IF NOT FOUND THEN RETURN jsonb_build_object(
    'authorized',false,'code','SKILL_TICKET_EXPIRED_INVALID_OR_REPLAY'); END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_skill_catalog_v1 c
   WHERE c.skill_code=v_r.skill_code AND c.status='READY'
     AND c.effect='READ_ONLY' AND c.runtime_slug=v_r.runtime_slug)
 THEN RAISE EXCEPTION 'SKILL_RUNTIME_CATALOG_SOURCE_DRIFT'; END IF;
 IF v_r.skill_code='INPUT_GOVERNANCE_CONTEXT_PACK'
   AND v_r.request_body->>'consumer'='CONTEXT_PACK' THEN
   v_old:=public.lf_profile_input_governance_runtime_ticket_consume_v1(
     p_ticket,p_execution_id,(v_r.request_body->>'pantalla_id')::integer,'CONTEXT_PACK');
   IF coalesce((v_old->>'authorized')::boolean,false) IS NOT TRUE THEN
     RAISE EXCEPTION 'SKILL_LEGACY_IG_TICKET_NOT_AUTHORIZED';
   END IF;
 END IF;
 RETURN jsonb_build_object('authorized',true,
   'execution_id',v_r.execution_id,'skill_code',v_r.skill_code,
   'runtime_slug',v_r.runtime_slug,'request_body',v_r.request_body,
   'expires_at',v_r.expires_at);
END
$consume$;
REVOKE ALL ON FUNCTION public.lf_profile_skill_runtime_ticket_consume_v1(uuid,text,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_skill_runtime_ticket_consume_v1(uuid,text,text)
 TO service_role;

COMMIT;
