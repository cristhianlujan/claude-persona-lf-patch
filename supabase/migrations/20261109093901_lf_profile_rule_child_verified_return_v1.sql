-- LF Skill rule child: verified return receipt without new dispatcher.
-- Does NOT close the parent or promote any rule. Same skill invoker/ACL.
DO $preflight$
BEGIN
 IF md5(pg_get_functiondef('public.lf_skill_invoke_v1(text,text,jsonb)'::regprocedure))
    IS DISTINCT FROM '884b551f9dd11919c6c8488ee34f197f' THEN
  RAISE EXCEPTION 'BLOCK_RULE_RECEIPT_SKILL_INVOKER_SOURCE_DRIFT';
 END IF;
 IF to_regprocedure('public.lf_skill_rule_child_readback_v1(text,text,text)') IS NOT NULL
    THEN RAISE EXCEPTION 'BLOCK_RULE_RECEIPT_ALREADY_EXISTS'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_skill_catalog_v1
    WHERE skill_code='RULE_UPDATE_APPLY' AND status='READY'
      AND opener_fn='lf_skill_o_rule_update_v1'
      AND required_operation='ACTUALIZACION_REGLA_LF')
    THEN RAISE EXCEPTION 'BLOCK_RULE_RECEIPT_OPENER_NOT_INSTALLED'; END IF;
END $preflight$;

CREATE FUNCTION public.lf_skill_rule_child_readback_v1(
 p_parent text,p_run text,p_child text
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog','public','lf_ops'
AS $readback$
DECLARE e public.lf_operation_execution%ROWTYPE;
 v_code text; v_sha text; v_count integer; v_clean integer; v_names integer;
BEGIN
 IF coalesce(p_parent,'')='' OR coalesce(p_run,'')='' OR coalesce(p_child,'')='' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_READBACK_INPUT_INVALID'); END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_skill_invocation_v1 i
   WHERE i.skill_run_id=p_run AND i.skill_code='RULE_UPDATE_APPLY'
     AND i.parent_execution_id=p_parent AND i.child_execution_id=p_child
     AND i.status='COMPLETED') THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_INVOCATION_MISMATCH'); END IF;
 SELECT * INTO e FROM public.lf_operation_execution
 WHERE execution_id=p_child
   AND operation_code='ACTUALIZACION_REGLA_LF'
   AND target_type='REGLA'
   AND created_by_execution_id=p_parent;
 IF NOT FOUND THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_OPERATION_BINDING_INVALID'); END IF;
 IF e.manifest#>>'{profile_handoff,source_execution_id}' IS DISTINCT FROM p_parent
    OR e.manifest#>>'{profile_handoff,skill_run_id}' IS DISTINCT FROM p_run THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_HANDOFF_MISMATCH'); END IF;
 IF e.status<>'COMPLETED' THEN
   RETURN jsonb_build_object('status','CHILD_IN_PROGRESS','child_execution_id',p_child,
     'effect_verified',false,'profile_execution_complete',false); END IF;
 IF e.manifest->>'candidate_write_verified' IS DISTINCT FROM 'true'
    OR e.manifest->>'rule_state' IS DISTINCT FROM 'CANDIDATO'
    OR e.manifest->>'promotion_authorized' IS DISTINCT FROM 'false'
    OR coalesce(e.manifest->>'result_snapshot_sha256','') !~ '^[0-9a-f]{64}$' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_COMPLETION_UNATTESTED'); END IF;
 SELECT count(*),count(*) FILTER (WHERE status='PASS_CLEAN'),
        count(DISTINCT step_id) FILTER(WHERE step_id IN (
          'ekb_preflight','classify','existing_check','destination_validate',
          'candidate_write','readback','trace_close'))
 INTO v_count,v_clean,v_names
 FROM public.lf_operation_execution_steps WHERE execution_id=p_child;
 IF v_count<>7 OR v_clean<>7 OR v_names<>7 THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_REQUIRED_STEPS_NOT_CLEAN',
     'observed_steps',v_count,'clean_steps',v_clean); END IF;
 v_code:=e.target_code;
 IF NOT EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo=v_code AND estado='CANDIDATO'
   AND pendiente_decision=true) THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_CANONICAL_STATE_DRIFT'); END IF;
 v_sha:=public.lf_asset_snapshot_sha_v1('REGLA',v_code);
 IF v_sha IS DISTINCT FROM e.manifest->>'result_snapshot_sha256' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','RULE_CHILD_CANONICAL_SNAPSHOT_DRIFT'); END IF;
 RETURN jsonb_build_object('status','APPLIED_VERIFIED','effect_verified',true,
   'parent_execution_id',p_parent,'child_execution_id',p_child,
   'skill_run_id',p_run,'operation_code','ACTUALIZACION_REGLA_LF',
   'rule_code',v_code,'rule_state','CANDIDATO','result_snapshot_sha256',v_sha,
   'canonical_readback',true,'required_steps_clean',7,
   'promotion_authorized',false,'profile_execution_complete',false,
   'next_action','CONTINUE_SAME_PARENT_PROFILE');
END
$readback$;

REVOKE ALL ON FUNCTION public.lf_skill_rule_child_readback_v1(text,text,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_skill_rule_child_readback_v1(text,text,text)
  TO service_role;

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
    elsif not exists(select 1 from public.lf_profile_write_authority_v1 a where a.profile_code=v_prof and a.operation_code=c.required_operation and a.status='ACTIVE') then v_code:='SKILL_NOT_AUTHORIZED_FOR_PROFILE';
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

DO $verify$
BEGIN
 IF pg_get_functiondef('public.lf_skill_invoke_v1(text,text,jsonb)'::regprocedure)
    NOT LIKE '%RULE_CHILD_CANONICAL_SNAPSHOT_DRIFT%' THEN
   -- This condition deliberately checks the helper independently below.
   IF pg_get_functiondef('public.lf_skill_invoke_v1(text,text,jsonb)'::regprocedure)
      NOT LIKE '%lf_skill_rule_child_readback_v1%' THEN
     RAISE EXCEPTION 'BLOCK_RULE_RECEIPT_INVOKER_NOT_UPDATED';
   END IF;
 END IF;
 IF pg_get_functiondef('public.lf_skill_rule_child_readback_v1(text,text,text)'::regprocedure)
    NOT LIKE '%RULE_CHILD_CANONICAL_SNAPSHOT_DRIFT%'
    OR pg_get_functiondef('public.lf_skill_invoke_v1(text,text,jsonb)'::regprocedure)
       NOT LIKE '%v_rule_receipt%' THEN
   RAISE EXCEPTION 'BLOCK_RULE_RECEIPT_READBACK_NOT_BOUND';
 END IF;
END $verify$;
