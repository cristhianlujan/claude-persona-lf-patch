-- Generated via read-only SELECT pg_get_functiondef on sandbox, for PG17/18 ROLLBACK fixture.
-- public.lf_rule_promotion_request_v1(text,text,text)
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
 -- Reuse existing Step70; bind reviewed source, raw and scope SHA to rule.
 IF NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s
 WHERE s.execution_id=p_execution_id AND s.step_order=70
 AND s.step_id='semantic_judge' AND s.status='STEP_PASS_WITH_EVIDENCE'
 AND s.evidence_payload#>>'{semantic_judge_result,verdict}'='PASS_INDEPENDENT_SEMANTIC'
 AND s.evidence_payload#>>'{semantic_judge_result,producer_independence_proven}'='true'
 AND s.evidence_payload#>>'{semantic_judge_result,model_call_count}' ~ '^[1-9][0-9]{0,5}$'
 AND s.evidence_payload#>>'{semantic_judge_result,judge_v3_evidence,judge_invocation_kind}'='NEW_INDEPENDENT_CURRENT_CHAT_GPT_NATIVE'
 AND s.evidence_payload#>>'{semantic_judge_result,judge_v3_evidence,judge_role}' LIKE 'INDEPENDENT_REVIEWER_%'
 AND s.evidence_payload#>>'{semantic_judge_result,candidate_sha256}' ~ '^[0-9a-f]{64}$'
 AND s.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}' ~ '^[0-9a-f]{64}$'
 AND jsonb_typeof(s.evidence_payload#>'{semantic_judge_result,judge_v3_evidence,unsupported_claims}')='array'
 AND jsonb_array_length(s.evidence_payload#>'{semantic_judge_result,judge_v3_evidence,unsupported_claims}')=0
 AND EXISTS(SELECT 1 FROM public.lf_operation_execution_steps f
 WHERE f.execution_id=p_execution_id AND f.step_order=50
 AND f.step_id='execute_profile' AND f.status='STEP_PASS_WITH_EVIDENCE'
 AND f.evidence_payload->>'raw_output_sha256'=s.evidence_payload#>>'{semantic_judge_result,candidate_sha256}'
 AND jsonb_typeof(f.evidence_payload#>'{profile_output,deliverable_created,product_decision,source_refs}')='array'
 AND EXISTS(SELECT 1 FROM jsonb_array_elements(f.evidence_payload#>'{profile_output,deliverable_created,product_decision,source_refs}') z
 WHERE z->>'source_ref'='supabase://lf_ops.reglas/'||p_rule_code))
 AND EXISTS(SELECT 1 FROM public.lf_operation_execution_steps v
 WHERE v.execution_id=p_execution_id AND v.step_order=60
 AND v.step_id='output_validate' AND v.status='STEP_PASS_WITH_EVIDENCE'
 AND v.evidence_payload->>'raw_output_sha256'=s.evidence_payload#>>'{semantic_judge_result,candidate_sha256}')
 AND EXISTS(SELECT 1 FROM public.lf_operation_execution_steps c
 WHERE c.execution_id=p_execution_id AND c.step_order=40
 AND c.step_id='input_validate' AND c.status='STEP_PASS_WITH_EVIDENCE'
 AND c.evidence_payload->>'scope_authority_packet_sha256'='sha256:'||(s.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}'))
 ) THEN RETURN jsonb_build_object('status','BLOCKED',
 'blocking_code','PROMOTION_INDEPENDENT_STEP70_NOT_ATTESTED',
 'requirement','INDEPENDENT_STEP40_50_60_70_RULE_SOURCE_SHA_BOUND');
 END IF;
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

-- public.lf_rule_promotion_decide_v1(text,text,text,text)
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

-- public.lf_rule_promotion_apply_v1(text)
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

-- public.lf_rule_promotion_decide_batch_v1(text[],text,text,text)
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_decide_batch_v1(p_ids text[], p_decision text, p_decided_by text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare x text; o jsonb; res jsonb := '[]'::jsonb; ok int := 0; bad int := 0;
begin
 foreach x in array coalesce(p_ids,array[]::text[]) loop
  o := public.lf_rule_promotion_decide_v1(x,p_decision,p_decided_by,p_note);
  if o->>'status' in ('APPROVED','REJECTED') then ok:=ok+1; else bad:=bad+1; end if;
  res := res||jsonb_build_array(jsonb_build_object('id',x,'status',o->>'status','code',o->>'blocking_code'));
 end loop;
 return jsonb_build_object('ok',ok,'blocked',bad,'detail',res);
end $function$
;

-- public.lf_rule_promotion_apply_batch_v1(text[])
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_apply_batch_v1(p_ids text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare x text; o jsonb; res jsonb := '[]'::jsonb; ok int := 0; bad int := 0;
begin
 foreach x in array coalesce(p_ids,array[]::text[]) loop
  o := public.lf_rule_promotion_apply_v1(x);
  if o->>'status'='APPLIED' then ok:=ok+1; else bad:=bad+1; end if;
  res := res||jsonb_build_array(jsonb_build_object('id',x,'status',o->>'status','code',o->>'blocking_code'));
 end loop;
 return jsonb_build_object('applied',ok,'blocked',bad,'detail',res);
end $function$
;

-- public.lf_rule_promotion_guard_v1()
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
