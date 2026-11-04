-- LF skill invoker: caller identity of the child execution, declared per skill in the catalog.
-- Problem: a child execution opened by a WRITE_GOVERNED skill had no governed_caller_method /
-- caller_repository / caller_workflow_ref in its manifest, so the profile-operation runtime refused to
-- record its steps (STEP_EXECUTION_IDENTITY_MISMATCH). The identity is now declared once per skill
-- (lf_skill_catalog_v1.child_caller) and stamped at INSERT time by the generic invoker / shared helper.
-- No runtime control is relaxed: the identity is the same one a profile_update_init execution carries.

alter table public.lf_skill_catalog_v1 add column if not exists child_caller jsonb;
alter table public.lf_skill_catalog_v1 drop constraint if exists lf_skill_catalog_v1_child_caller_check;
alter table public.lf_skill_catalog_v1 add constraint lf_skill_catalog_v1_child_caller_check
  check (child_caller is null or (child_caller ? 'method' and child_caller ? 'repository' and child_caller ? 'workflow_ref'));

update public.lf_skill_catalog_v1
set child_caller = jsonb_build_object(
  'method','GITHUB_ACTIONS_OIDC_EXACT_PROFILE_UPDATE_V1',
  'repository','cristhianlujan/claude-persona-lf-patch',
  'workflow_ref','cristhianlujan/claude-persona-lf-patch/.github/workflows/lf-customer-profile-creator-governance-caller.yml@refs/heads/main')
where skill_code='PROFILE_UPDATE_APPLY' and child_caller is null;

create or replace function public.lf_skill_child_caller_manifest_v1(p_skill text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'pg_catalog', 'public'
as $function$
 select coalesce((select jsonb_build_object('governed_caller_method',c.child_caller->>'method','caller_repository',c.child_caller->>'repository','caller_workflow_ref',c.child_caller->>'workflow_ref')
                  from public.lf_skill_catalog_v1 c where c.skill_code=p_skill and c.child_caller is not null), '{}'::jsonb);
$function$;
revoke all on function public.lf_skill_child_caller_manifest_v1(text) from public, anon, authenticated;
grant execute on function public.lf_skill_child_caller_manifest_v1(text) to service_role;

CREATE OR REPLACE FUNCTION public.lf_skill_invoke_v1(p_skill text, p_execution_id text, p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare c record; par record; v_run text := 'RUN-'||upper(substr(md5(random()::text||clock_timestamp()::text),1,20)); v_in text; v_missing text[]; k text; v_out jsonb; v_code text; v_prof text; v_ev text; v_child text; v_status text;
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
    return jsonb_build_object('status','COMPLETED','skill_run_id',v_run,'output',v_out,'evidence_ref',v_ev,'child_execution_id',v_child,'next_action','CONTINUE_PROFILE');
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

CREATE OR REPLACE FUNCTION public.lf_skill_o_profile_update_v1(p_child text, p_input jsonb, p_parent text, p_run text, p_request_sha text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare par record; a record;
begin
 select * into par from public.lf_operation_execution e where e.execution_id=p_parent;
 if public.lf_profile_family_v1(par.target_code)=public.lf_profile_family_v1(p_input->>'target_code') and not exists(select 1 from public.lf_profile_write_authority_v1 w where w.profile_code=par.target_code and w.operation_code='ACTUALIZACION_PERFIL_LF' and w.status='ACTIVE' and w.self_update_allowed) then
  select * into a from public.lf_profile_self_update_approval_v1 x where x.profile_code=par.target_code and x.target_code=p_input->>'target_code' and x.target_path=p_input->>'target_path' and x.request_sha256=p_request_sha and x.status='APPROVED' order by x.created_at limit 1 for update;
  if not found then raise exception 'SELF_UPDATE_REQUIRES_HUMAN_APPROVAL: un perfil que se actualiza a si mismo necesita aprobacion humana. Pedirla con lf_profile_self_update_request_v1 y esperar la aprobacion'; end if;
  update public.lf_profile_self_update_approval_v1 set status='USED', used_at=now() where approval_id=a.approval_id;
 end if;
 return public.lf_profile_update_begin_v1(p_child, p_input->>'target_code', coalesce(p_input->>'target_repo','cristhianlujan/claude-persona-lf-patch'), p_input->>'target_path', p_request_sha, 'skill-child-v1:'||p_run, p_parent,
   jsonb_build_object('profile_handoff',jsonb_build_object('source_execution_id',p_parent,'skill_run_id',p_run,'via','SKILL_INVOKER')) || public.lf_skill_child_caller_manifest_v1('PROFILE_UPDATE_APPLY'));
end $function$;

revoke all on function public.lf_skill_invoke_v1(text,text,jsonb) from public, anon, authenticated;
grant execute on function public.lf_skill_invoke_v1(text,text,jsonb) to service_role;
revoke all on function public.lf_skill_o_profile_update_v1(text,jsonb,text,text,text) from public, anon, authenticated;
grant execute on function public.lf_skill_o_profile_update_v1(text,jsonb,text,text,text) to service_role;

-- General check: every skill that has a dedicated opener must declare its child caller identity.
do $chk$
declare gaps text;
begin
  select string_agg(skill_code, ',') into gaps from public.lf_skill_catalog_v1
   where effect='WRITE_GOVERNED' and opener_fn is not null and child_caller is null;
  if gaps is not null then raise exception 'LF_SKILL_CHILD_CALLER_IDENTITY_MISSING:%', gaps; end if;
end $chk$;
