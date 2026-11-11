-- Exact pg_get_functiondef copies from live Supabase 2026-11-11; isolated PG18 only.
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_apply_v1(p_promotion_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare p record;
begin
 select * into p from public.lf_rule_promotion_v1 where promotion_id=p_promotion_id for update;
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); end if;
 if p.status<>'APPROVED' then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_APPROVED','estado',p.status); end if;
 if public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code) is distinct from p.request_snapshot_sha256 then
  update public.lf_rule_promotion_v1 set status='STALE' where promotion_id=p_promotion_id;
  return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_STALE'); end if;
 update lf_ops.reglas set estado='VIGENTE' where codigo=p.rule_code and estado='CANDIDATO';
 update public.lf_rule_promotion_v1 set status='APPLIED', applied_at=now() where promotion_id=p_promotion_id;
 return jsonb_build_object('status','APPLIED','rule_code',p.rule_code);
end $function$
;
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_decide_v1(p_promotion_id text, p_decision text, p_decided_by text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare p record;
begin
 if p_decided_by is null or p_decided_by !~ '^HUMAN:.+' then return jsonb_build_object('status','BLOCKED','blocking_code','APPROVER_MUST_BE_HUMAN'); end if;
 if p_decision not in ('APPROVE','REJECT') then return jsonb_build_object('status','BLOCKED','blocking_code','DECISION_INVALID'); end if;
 select * into p from public.lf_rule_promotion_v1 where promotion_id=p_promotion_id for update;
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); end if;
 if p.status<>'PENDING' then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_PENDING','estado',p.status); end if;
 if p_decision='APPROVE' and public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code) is distinct from p.request_snapshot_sha256 then
  update public.lf_rule_promotion_v1 set status='STALE' where promotion_id=p_promotion_id;
  return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_STALE'); end if;
 update public.lf_rule_promotion_v1 set status=case p_decision when 'APPROVE' then 'APPROVED' else 'REJECTED' end, decided_by=p_decided_by, decided_at=now(), reason=coalesce(reason,'')||' | '||coalesce(p_note,'') where promotion_id=p_promotion_id;
 return jsonb_build_object('status',case p_decision when 'APPROVE' then 'APPROVED' else 'REJECTED' end,'promotion_id',p_promotion_id);
end $function$
;
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_guard_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
begin
 if NEW.estado='VIGENTE' and OLD.estado is distinct from 'VIGENTE' then
  if not exists(select 1 from public.lf_rule_promotion_v1 p where p.rule_code=OLD.codigo and p.status='APPROVED' and p.request_snapshot_sha256=public.lf_asset_snapshot_sha_v1('REGLA',OLD.codigo)) then
   raise exception 'LF_RULE_PROMOTION_REQUIRED:%',OLD.codigo; end if;
 end if;
 return NEW;
end $function$
;
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_request_v1(p_execution_id text, p_rule_code text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare par record; r record; v_sha text; v_id text;
begin
 select * into par from public.lf_operation_execution e where e.execution_id=p_execution_id and e.operation_code='EJECUCION_PERFIL_LF' and e.status='IN_PROGRESS';
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','PARENT_EXECUTION_NOT_ACTIVE'); end if;
 if not exists(select 1 from public.lf_profile_write_authority_v1 a where a.profile_code=par.target_code and a.operation_code='PROMOCION_REGLA_LF' and a.status='ACTIVE') then
  return jsonb_build_object('status','BLOCKED','blocking_code','PROFILE_NOT_AUTHORIZED_FOR_PROMOTION','profile',par.target_code); end if;
 select * into r from lf_ops.reglas where codigo=p_rule_code;
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','RULE_NOT_FOUND'); end if;
 if r.estado<>'CANDIDATO' then return jsonb_build_object('status','BLOCKED','blocking_code','RULE_NOT_CANDIDATE','estado',r.estado); end if;
 if exists(select 1 from public.lf_rule_promotion_v1 p where p.rule_code=p_rule_code and p.status in ('PENDING','APPROVED')) then
  return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_ALREADY_OPEN'); end if;
 if nullif(btrim(p_reason),'') is null then return jsonb_build_object('status','BLOCKED','blocking_code','REASON_REQUIRED'); end if;
 v_sha := public.lf_asset_snapshot_sha_v1('REGLA',p_rule_code);
 insert into public.lf_rule_promotion_v1(rule_code,request_execution_id,requested_by_profile,request_snapshot_sha256,reason) values(p_rule_code,p_execution_id,par.target_code,v_sha,p_reason) returning promotion_id into v_id;
 return jsonb_build_object('status','PENDING_HUMAN_APPROVAL','promotion_id',v_id,'snapshot_sha256',v_sha,'next_action','Una persona debe aprobar con lf_rule_promotion_decide_v1');
end $function$
;
