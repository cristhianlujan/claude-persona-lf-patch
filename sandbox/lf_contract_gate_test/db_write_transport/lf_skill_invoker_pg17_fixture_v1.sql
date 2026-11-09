-- PostgreSQL 17.6 isolated fixture. NO production credentials or connections.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE TABLE public.lf_operation_execution (
 execution_id text primary key, operation_code text not null, target_type text,
 target_code text, manifest jsonb default '{}'::jsonb, request_sha256 text,
 idempotency_key text, created_by_execution_id text, status text not null default 'IN_PROGRESS'
);
CREATE TABLE public.lf_skill_catalog_v1 (
 skill_code text primary key, required_operation text not null, effect text not null,
 status text not null, handler_fn text not null, opener_fn text, input_required text[] not null
);
CREATE TABLE public.lf_profile_write_authority_v1 (
 profile_code text not null, operation_code text not null, status text not null,
 primary key(profile_code,operation_code)
);
CREATE TABLE public.lf_skill_invocation_v1 (
 skill_run_id text primary key, skill_code text not null, parent_execution_id text not null,
 profile_code text, status text not null, blocking_code text, input_sha256 text,
 output jsonb, evidence_ref text, child_execution_id text, created_at timestamptz not null default now()
);
CREATE FUNCTION public.lf_skill_child_caller_manifest_v1(p_skill text) RETURNS jsonb
 LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;
CREATE FUNCTION public.lf_skill_h_rule_update_propose_v1(p_input jsonb) RETURNS jsonb
 LANGUAGE plpgsql AS $$ BEGIN PERFORM pg_sleep(0.55);
 RETURN jsonb_build_object('status','PROPOSED','rule',p_input->>'regla_codigo');
 END $$;
INSERT INTO public.lf_skill_catalog_v1
 (skill_code,required_operation,effect,status,handler_fn,opener_fn,input_required)
VALUES ('RULE_UPDATE_APPLY','ACTUALIZACION_REGLA_LF','WRITE_GOVERNED','READY',
 'lf_skill_h_rule_update_propose_v1',null,ARRAY['regla_codigo']);
INSERT INTO public.lf_profile_write_authority_v1
 (profile_code,operation_code,status)
VALUES ('PERFIL-PRODUCT-DIRECTOR-LF','ACTUALIZACION_REGLA_LF','ACTIVE');
INSERT INTO public.lf_operation_execution
 (execution_id,operation_code,target_code,status,request_sha256)
VALUES ('EXEC-PROFILE-GATE2-TEST12345678','EJECUCION_PERFIL_LF',
 'PERFIL-PRODUCT-DIRECTOR-LF','IN_PROGRESS','same-request-sha');
-- Fixture is the exact deployed, read-only inspected function; new migration
-- enforces MD5 on pg_get_functiondef prior to any candidate write.
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
end $function$

