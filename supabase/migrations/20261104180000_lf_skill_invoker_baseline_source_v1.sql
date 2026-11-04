-- LF skill invoker baseline (source parity).
-- These objects already exist in LF_SUPABASE_SANDBOX but had no migration in the repo.
-- This migration is idempotent and reproduces their CURRENT definitions exactly:
-- no behaviour change. It registers them in the ledger and in source control.
-- Operational data (lf_profile_write_authority_v1 rows) is intentionally not seeded here.

create table if not exists public.lf_skill_catalog_v1 (
  skill_code text not null,
  description text not null,
  required_operation text not null,
  handler_fn text not null,
  effect text not null,
  input_required text[] not null default '{}'::text[],
  status text not null,
  created_at timestamp with time zone not null default now(),
  opener_fn text,
  constraint lf_skill_catalog_v1_pkey primary key (skill_code),
  constraint lf_skill_catalog_v1_effect_check check (effect = any (array['READ_ONLY'::text, 'PROPOSE_ONLY'::text, 'WRITE_GOVERNED'::text])),
  constraint lf_skill_catalog_v1_handler_fn_check check (handler_fn ~ '^lf_skill_h_[a-z0-9_]+$'::text),
  constraint lf_skill_catalog_v1_opener_fn_check check (opener_fn is null or opener_fn ~ '^lf_skill_o_[a-z0-9_]+$'::text),
  constraint lf_skill_catalog_v1_skill_code_check check (skill_code ~ '^[A-Z][A-Z0-9_]{2,63}$'::text),
  constraint lf_skill_catalog_v1_status_check check (status = any (array['DRAFT'::text, 'READY'::text, 'DISABLED'::text]))
);
alter table public.lf_skill_catalog_v1 enable row level security;

create table if not exists public.lf_skill_invocation_v1 (
  skill_run_id text not null,
  skill_code text not null,
  parent_execution_id text not null,
  profile_code text,
  status text not null,
  blocking_code text,
  input_sha256 text,
  output jsonb,
  evidence_ref text,
  child_execution_id text,
  created_at timestamp with time zone not null default now(),
  constraint lf_skill_invocation_v1_pkey primary key (skill_run_id)
);
alter table public.lf_skill_invocation_v1 enable row level security;

create table if not exists public.lf_profile_write_authority_v1 (
  profile_code text not null,
  operation_code text not null,
  status text not null default 'PROPOSED'::text,
  basis text,
  self_update_allowed boolean not null default false,
  constraint lf_profile_write_authority_v1_pkey primary key (profile_code, operation_code),
  constraint lf_profile_write_authority_v1_status_check check (status = any (array['ACTIVE'::text, 'PROPOSED'::text, 'RETIRED'::text]))
);
alter table public.lf_profile_write_authority_v1 enable row level security;

create table if not exists public.lf_profile_self_update_approval_v1 (
  approval_id text not null default ('SELFUPD-'::text || upper(substr(md5(((random())::text || (clock_timestamp())::text)), 1, 14))),
  profile_code text not null,
  target_code text not null,
  target_path text not null,
  request_sha256 text not null,
  reason text not null,
  status text not null default 'PENDING'::text,
  requested_by_execution_id text not null,
  decided_by text,
  decided_at timestamp with time zone,
  used_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  constraint lf_profile_self_update_approval_v1_pkey primary key (approval_id),
  constraint lf_profile_self_update_approval_v1_status_check check (status = any (array['PENDING'::text, 'APPROVED'::text, 'REJECTED'::text, 'USED'::text]))
);
alter table public.lf_profile_self_update_approval_v1 enable row level security;

CREATE OR REPLACE FUNCTION public.lf_profile_family_v1(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$ select regexp_replace(coalesce(p,''),'-LF(-V[0-9]+.*)?(-CANDIDATE)?$','') $function$;

CREATE OR REPLACE FUNCTION public.lf_profile_self_update_decide_v1(p_approval_id text, p_decision text, p_decided_by text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare a record;
begin
 if p_decided_by is null or p_decided_by !~ '^HUMAN:.+' then return jsonb_build_object('status','BLOCKED','blocking_code','APPROVER_MUST_BE_HUMAN'); end if;
 if p_decision not in ('APPROVE','REJECT') then return jsonb_build_object('status','BLOCKED','blocking_code','DECISION_INVALID'); end if;
 select * into a from public.lf_profile_self_update_approval_v1 where approval_id=p_approval_id for update;
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','APPROVAL_NOT_FOUND'); end if;
 if a.status<>'PENDING' then return jsonb_build_object('status','BLOCKED','blocking_code','APPROVAL_NOT_PENDING','estado',a.status); end if;
 update public.lf_profile_self_update_approval_v1 set status=case p_decision when 'APPROVE' then 'APPROVED' else 'REJECTED' end, decided_by=p_decided_by, decided_at=now(), reason=reason||' | '||coalesce(p_note,'') where approval_id=p_approval_id;
 return jsonb_build_object('status',case p_decision when 'APPROVE' then 'APPROVED' else 'REJECTED' end,'approval_id',p_approval_id);
end $function$;

CREATE OR REPLACE FUNCTION public.lf_profile_self_update_pending_text_v1()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare t text := ''; r record; i int := 0;
begin
 for r in select * from public.lf_profile_self_update_approval_v1 where status='PENDING' order by created_at loop
  i := i+1;
  t := t||i||'. El perfil '||r.profile_code||' pide actualizarse a si mismo'||E'\n   Archivo: '||r.target_path||E'\n   Motivo: '||r.reason||E'\n   Codigo de aprobacion: '||r.approval_id||E'\n';
 end loop;
 return case when i=0 then 'No hay autoactualizaciones pendientes de tu aprobacion.' else 'AUTOACTUALIZACIONES DE PERFIL PENDIENTES: '||i||E'\n'||t end;
end $function$;

CREATE OR REPLACE FUNCTION public.lf_profile_self_update_request_v1(p_execution_id text, p_target_code text, p_target_path text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare par record; v_id text;
begin
 select * into par from public.lf_operation_execution e where e.execution_id=p_execution_id and e.operation_code='EJECUCION_PERFIL_LF' and e.status='IN_PROGRESS';
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','PARENT_EXECUTION_NOT_ACTIVE'); end if;
 if public.lf_profile_family_v1(par.target_code) is distinct from public.lf_profile_family_v1(p_target_code) or exists(select 1 from public.lf_profile_write_authority_v1 w where w.profile_code=par.target_code and w.operation_code='ACTUALIZACION_PERFIL_LF' and w.status='ACTIVE' and w.self_update_allowed) then
  return jsonb_build_object('status','NOT_NEEDED','detail','El perfil no se actualiza a si mismo: no requiere aprobacion humana'); end if;
 if nullif(btrim(p_reason),'') is null then return jsonb_build_object('status','BLOCKED','blocking_code','REASON_REQUIRED'); end if;
 if exists(select 1 from public.lf_profile_self_update_approval_v1 a where a.profile_code=par.target_code and a.target_code=p_target_code and a.target_path=p_target_path and a.request_sha256=par.request_sha256 and a.status in ('PENDING','APPROVED')) then
  return jsonb_build_object('status','BLOCKED','blocking_code','SELF_UPDATE_APPROVAL_ALREADY_OPEN'); end if;
 insert into public.lf_profile_self_update_approval_v1(profile_code,target_code,target_path,request_sha256,reason,requested_by_execution_id) values(par.target_code,p_target_code,p_target_path,par.request_sha256,p_reason,p_execution_id) returning approval_id into v_id;
 return jsonb_build_object('status','PENDING_HUMAN_APPROVAL','approval_id',v_id);
end $function$;

CREATE OR REPLACE FUNCTION public.lf_skill_h_profile_update_propose_v1(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
 if p_input->>'target_code' !~ '^PERFIL-[A-Z0-9-]+$' then raise exception 'PROFILE_TARGET_INVALID:%', p_input->>'target_code'; end if;
 return jsonb_build_object('target_code',p_input->>'target_code','target_path',p_input->>'target_path','operacion_requerida','ACTUALIZACION_PERFIL_LF','escribe',false);
end $function$;

CREATE OR REPLACE FUNCTION public.lf_skill_h_rule_create_propose_v1(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
 if exists(select 1 from lf_ops.reglas r where r.codigo=p_input->>'regla_codigo') then raise exception 'RULE_ALREADY_EXISTS:%', p_input->>'regla_codigo'; end if;
 return jsonb_build_object('regla_codigo',p_input->>'regla_codigo','existe',false,'operacion_requerida','CREACION_REGLA_LF','escribe',false);
end $function$;

CREATE OR REPLACE FUNCTION public.lf_skill_h_rule_link_propose_v1(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
 if p_input->>'target_type'<>'REGLA_PANTALLA_RELATION' or p_input->>'target_code' is distinct from (p_input->>'regla_codigo')||'@'||(p_input->>'pantalla_id') then raise exception 'LINK_TARGET_INVALID: target_code debe ser regla@pantalla_id'; end if;
 if not exists(select 1 from lf_ops.reglas r where r.codigo=p_input->>'regla_codigo' and r.estado in ('CANDIDATO','VIGENTE')) then raise exception 'RULE_NOT_LINKABLE:%', p_input->>'regla_codigo'; end if;
 if not exists(select 1 from lf_ops.pantallas p where p.id=(p_input->>'pantalla_id')::int) then raise exception 'SCREEN_NOT_FOUND:%', p_input->>'pantalla_id'; end if;
 return jsonb_build_object('regla_codigo',p_input->>'regla_codigo','pantalla_id',p_input->>'pantalla_id','operacion_requerida','VINCULACION_REGLA_PANTALLA_LF','escribe',false);
end $function$;

CREATE OR REPLACE FUNCTION public.lf_skill_h_rule_update_propose_v1(p_input jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 select jsonb_build_object('regla_codigo',p_input->>'regla_codigo','existe',exists(select 1 from lf_ops.reglas r where r.codigo=p_input->>'regla_codigo'),
  'operacion_requerida','ACTUALIZACION_REGLA_LF','escribe',false,'analysis_snapshot_sha256',public.lf_asset_snapshot_sha_v1('REGLA',p_input->>'regla_codigo'));
$function$;

CREATE OR REPLACE FUNCTION public.lf_skill_h_screen_rules_snapshot_v1(p_input jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 select jsonb_build_object('pantalla_codigo',p_input->>'pantalla_codigo',
  'n_reglas',(select count(*) from lf_ops.pantallas p join lf_ops.reglas_pantallas rp on rp.pantalla_id=p.id where p.codigo=p_input->>'pantalla_codigo'),
  'estados',(select coalesce(jsonb_object_agg(z.e,z.c),'{}'::jsonb) from (select r.estado e,count(*) c from lf_ops.pantallas p join lf_ops.reglas_pantallas rp on rp.pantalla_id=p.id join lf_ops.reglas r on r.id=rp.regla_id where p.codigo=p_input->>'pantalla_codigo' group by 1) z),
  'analysis_snapshot_sha256',public.lf_asset_snapshot_sha_v1('PANTALLA',p_input->>'pantalla_codigo'));
$function$;

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
        jsonb_build_object('profile_handoff',jsonb_build_object('source_execution_id',p_execution_id,'skill_run_id',v_run,'analysis_snapshot_sha256',p_input->>'analysis_snapshot_sha256','via','SKILL_INVOKER')),
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
   jsonb_build_object('profile_handoff',jsonb_build_object('source_execution_id',p_parent,'skill_run_id',p_run,'via','SKILL_INVOKER')));
end $function$;

-- Function ACLs as currently deployed: service_role only.
do $acl$
declare f text;
begin
  foreach f in array array[
    'lf_profile_family_v1(text)',
    'lf_profile_self_update_decide_v1(text,text,text,text)',
    'lf_profile_self_update_pending_text_v1()',
    'lf_profile_self_update_request_v1(text,text,text,text)',
    'lf_skill_h_profile_update_propose_v1(jsonb)',
    'lf_skill_h_rule_create_propose_v1(jsonb)',
    'lf_skill_h_rule_link_propose_v1(jsonb)',
    'lf_skill_h_rule_update_propose_v1(jsonb)',
    'lf_skill_h_screen_rules_snapshot_v1(jsonb)',
    'lf_skill_invoke_v1(text,text,jsonb)',
    'lf_skill_o_profile_update_v1(text,jsonb,text,text,text)'
  ] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
end $acl$;

-- Catalog seed: current rows; never overwrite existing ones.
insert into public.lf_skill_catalog_v1(skill_code,description,required_operation,handler_fn,effect,input_required,status,opener_fn) values
('PROFILE_UPDATE_APPLY','Abre la operacion gobernada ACTUALIZACION_PERFIL_LF desde un perfil (reemplaza la entrada directa de actualizacion de perfiles)','ACTUALIZACION_PERFIL_LF','lf_skill_h_profile_update_propose_v1','WRITE_GOVERNED','{target_code,target_path}','READY','lf_skill_o_profile_update_v1'),
('RULE_CREATE_APPLY','Abre la operacion gobernada CREACION_REGLA_LF desde el perfil (la escritura la hacen sus 7 pasos)','CREACION_REGLA_LF','lf_skill_h_rule_create_propose_v1','WRITE_GOVERNED','{regla_codigo}','READY',null),
('RULE_LINK_APPLY','Abre la operacion gobernada VINCULACION_REGLA_PANTALLA_LF desde el perfil (vincula una regla a una pantalla)','VINCULACION_REGLA_PANTALLA_LF','lf_skill_h_rule_link_propose_v1','WRITE_GOVERNED','{regla_codigo,pantalla_id,target_type,target_code}','READY',null),
('RULE_UPDATE_APPLY','Abre operacion gobernada ACTUALIZACION_REGLA_LF desde el perfil (la escritura la hacen sus 7 pasos)','ACTUALIZACION_REGLA_LF','lf_skill_h_rule_update_propose_v1','WRITE_GOVERNED','{regla_codigo,analysis_snapshot_sha256}','READY',null),
('RULE_UPDATE_PROPOSE','Prepara propuesta de cambio de una regla (no escribe)','ACTUALIZACION_REGLA_LF','lf_skill_h_rule_update_propose_v1','PROPOSE_ONLY','{regla_codigo}','READY',null),
('SCREEN_RULES_SNAPSHOT','Lee reglas de una pantalla y devuelve huella del analisis','EJECUCION_PERFIL_LF','lf_skill_h_screen_rules_snapshot_v1','READ_ONLY','{pantalla_codigo}','READY',null)
on conflict (skill_code) do nothing;
