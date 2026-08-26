create or replace function programacion.fn_worker_machine_proof_contract_v2_ok(
  p_worker_receipt jsonb,
  p_expected_head_sha text,
  p_expected_source_ref text
)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
begin
  perform programacion.fn_assert_worker_machine_proof_contract_v2(
    p_worker_receipt,p_expected_head_sha,p_expected_source_ref
  );
  return true;
exception when others then
  return false;
end;
$function$;
revoke all on function programacion.fn_worker_machine_proof_contract_v2_ok(jsonb,text,text) from public,anon,authenticated,service_role;
grant execute on function programacion.fn_worker_machine_proof_contract_v2_ok(jsonb,text,text) to postgres;

create or replace function programacion.fn_evidence_pass_compatible_v1(p_evidence_id bigint)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
declare
  v_ev programacion.evidencias%rowtype;
  v_latest_id bigint;
  v_latest_status text;
  v_latest_authority_id bigint;
  v_source_id bigint;
  v_source_verification_id bigint;
  v_source_authority_id bigint;
  v_source_latest_id bigint;
  v_source_latest_status text;
  v_source_latest_authority_id bigint;
  v_proof_value text;
begin
  select * into v_ev from programacion.evidencias where id=p_evidence_id;
  if v_ev.id is null then return false; end if;

  select vv.id,vv.verification_status,vv.authority_receipt_id
    into v_latest_id,v_latest_status,v_latest_authority_id
  from programacion.evidence_verifications vv
  where vv.evidence_id=v_ev.id
    and vv.evidence_sha256=v_ev.sha256
    and vv.source_system=v_ev.source_system
    and vv.source_ref=v_ev.source_ref
  order by vv.id desc
  limit 1;

  if v_latest_id is null or v_latest_status is distinct from 'VERIFIED' or v_latest_authority_id is null then
    return false;
  end if;

  if upper(coalesce(v_ev.metadata->>'status','')) in ('FAIL','BLOCKED','REJECTED','ERROR','FINDING')
     or upper(coalesce(v_ev.metadata->>'result','')) in ('FAIL','BLOCKED','REJECTED','ERROR','FINDING')
     or upper(coalesce(v_ev.metadata->>'outcome','')) in ('FAIL','BLOCKED','REJECTED','ERROR','FINDING')
     or upper(coalesce(v_ev.metadata->>'verdict','')) in ('FAIL','BLOCKED','REJECTED','ERROR','FINDING') then
    return false;
  end if;

  if v_ev.tipo='VERIFIED_WORKER_RECEIPT' and v_ev.source_system='PROGRAMMING_AGENT_WORKER' then
    if v_ev.metadata#>>'{worker_receipt,status}' is distinct from 'PASS' then return false; end if;
    if programacion.fn_worker_machine_proof_contract_v2_ok(
         v_ev.metadata->'worker_receipt',v_ev.head_sha,v_ev.source_ref
       ) is not true then
      return false;
    end if;
  end if;

  if v_ev.tipo='MACHINE_GATE_DERIVED_RECEIPT'
     and v_ev.source_system='VERIFIED_WORKER_RECEIPT_DERIVATION_V1' then
    begin
      v_source_id:=(v_ev.metadata->>'source_worker_evidence_id')::bigint;
      v_source_verification_id:=(v_ev.metadata->>'source_worker_verification_id')::bigint;
      v_source_authority_id:=(v_ev.metadata->>'source_worker_authority_receipt_id')::bigint;
    exception when others then
      return false;
    end;
    if v_source_id is null or v_source_id<1 or v_source_id>=v_ev.id
       or v_source_verification_id is null or v_source_verification_id<1
       or v_source_authority_id is null or v_source_authority_id<1 then
      return false;
    end if;

    select vv.id,vv.verification_status,vv.authority_receipt_id
      into v_source_latest_id,v_source_latest_status,v_source_latest_authority_id
    from programacion.evidence_verifications vv
    join programacion.evidencias sev on sev.id=vv.evidence_id
    where sev.id=v_source_id
      and vv.evidence_sha256=sev.sha256
      and vv.source_system=sev.source_system
      and vv.source_ref=sev.source_ref
    order by vv.id desc
    limit 1;

    if v_source_latest_id is distinct from v_source_verification_id
       or v_source_latest_status is distinct from 'VERIFIED'
       or v_source_latest_authority_id is distinct from v_source_authority_id then
      return false;
    end if;

    v_proof_value:=v_ev.metadata->>'proof_value';
    if v_proof_value is distinct from 'PASS' then
      if coalesce(v_proof_value,'') !~ '^[1-9][0-9]*/[1-9][0-9]* PASS$'
         or split_part(split_part(v_proof_value,' ',1),'/',1)
            <> split_part(split_part(v_proof_value,' ',1),'/',2) then
        return false;
      end if;
    end if;

    if programacion.fn_evidence_pass_compatible_v1(v_source_id) is not true then
      return false;
    end if;
  end if;

  return true;
end;
$function$;
revoke all on function programacion.fn_evidence_pass_compatible_v1(bigint) from public,anon,authenticated,service_role;
grant execute on function programacion.fn_evidence_pass_compatible_v1(bigint) to postgres;

create or replace function programacion.fn_evaluation_pass_evidence_valid_v1(p_evaluation_id bigint)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
  select exists(
    select 1
    from programacion.evaluaciones eva
    where eva.id=p_evaluation_id
      and exists(
        select 1 from programacion.evidencias ev
        where ev.evaluacion_id=eva.id
      )
      and not exists(
        select 1
        from programacion.evidencias ev
        where ev.evaluacion_id=eva.id
          and (
            ev.head_sha is distinct from eva.head_sha
            or programacion.fn_evidence_pass_compatible_v1(ev.id) is not true
          )
      )
  );
$function$;
revoke all on function programacion.fn_evaluation_pass_evidence_valid_v1(bigint) from public,anon,authenticated,service_role;
grant execute on function programacion.fn_evaluation_pass_evidence_valid_v1(bigint) to postgres;

create or replace function programacion.fn_guard_evaluation()
returns trigger
language plpgsql
set search_path to 'pg_catalog','programacion'
as $function$
declare
 v_head text; v_app text; v_exec_estado text; v_independence_required boolean:=false; v_previous_id bigint;
begin
 select ex.head_sha,o.aplicabilidad,ex.estado,coalesce(comp_direct.independencia_requerida,comp_control.independencia_requerida,false)
 into v_head,v_app,v_exec_estado,v_independence_required
 from programacion.objetivos_ejecucion o join programacion.ejecuciones ex on ex.id=o.execution_id
 left join programacion.gates g_direct on g_direct.id=o.gate_id
 left join programacion.componentes comp_direct on comp_direct.id=g_direct.ejecutor_componente_id
 left join programacion.controles_calidad cq on cq.id=o.control_calidad_id
 left join programacion.gates g_control on g_control.id=cq.gate_id
 left join programacion.componentes comp_control on comp_control.id=g_control.ejecutor_componente_id
 where o.id=new.objetivo_id;
 if v_head is null then raise exception 'objective % has no execution',new.objetivo_id; end if;
 if v_exec_estado<>'RUNNING' then raise exception 'evaluations are allowed only while execution is RUNNING'; end if;
 if new.head_sha<>v_head then raise exception 'evaluation HEAD % does not match execution HEAD %',new.head_sha,v_head; end if;
 if v_app<>'REQUIRED' then raise exception 'objective % applicability is %, so it must not be evaluated as REQUIRED',new.objetivo_id,v_app; end if;

 if tg_op='INSERT' then
   new.db_principal:=current_user;
   new.session_principal:=session_user;
 else
   new.db_principal:=old.db_principal;
   new.session_principal:=old.session_principal;
 end if;

 if new.independencia_declarada then
   raise exception 'DECLARATIVE_INDEPENDENCE_DISABLED_BY_PROG_ADR_AUTH_001';
 end if;
 if v_independence_required and not exists(
     select 1
     from programacion.objetivos_ejecucion o_worker
     join programacion.gates g_worker on g_worker.id=o_worker.gate_id
     where o_worker.id=new.objetivo_id
       and g_worker.gate_codigo in('G_WORKER_SOURCE_IDENTITY','G_WORKER_PATCH_POLICY','G_WORKER_ACCEPTANCE','G_WORKER_DELIVERY_BOUNDARY')
   ) then
   if new.evaluador_tipo not in('auditor','human') then
     raise exception 'objective % requires auditor/human evaluator role; authority is verified separately by receipt-backed gates',new.objetivo_id;
   end if;
   if length(btrim(coalesce(new.evaluador_identidad,'')))=0 then
     raise exception 'independent-role evaluation requires evaluador_identidad';
   end if;
   if length(btrim(coalesce(new.evaluador_canal,'')))=0 then
     raise exception 'independent-role evaluation requires evaluador_canal';
   end if;
 end if;

 if tg_op='INSERT' and new.intento>1 then
   if length(btrim(coalesce(new.detalles->>'retry_justification','')))=0 or not(new.detalles?'previous_evaluation_id') then
     raise exception 'retry attempt >1 requires retry_justification and previous_evaluation_id';
   end if;
   begin v_previous_id:=(new.detalles->>'previous_evaluation_id')::bigint;
   exception when others then raise exception 'previous_evaluation_id must be bigint'; end;
   if not exists(select 1 from programacion.evaluaciones p where p.id=v_previous_id and p.objetivo_id=new.objetivo_id and p.intento=new.intento-1 and p.resultado in('FAIL','BLOCKED')) then
     raise exception 'retry must reference immediately preceding FAIL/BLOCKED evaluation';
   end if;
 end if;

 if tg_op='UPDATE' and old.resultado<>'PENDING' then raise exception 'final evaluation % is immutable; create a new attempt',old.id; end if;
 if new.resultado='PASS' then
   if tg_op='INSERT' then raise exception 'insert evaluation as PENDING, attach evidence, verify evidence, then finalize PASS'; end if;
   if programacion.fn_evaluation_pass_evidence_valid_v1(old.id) is not true then
     raise exception 'PASS_REQUIRES_CURRENT_COMPATIBLE_EVIDENCE:%',old.id;
   end if;
 end if;
 return new;
end;
$function$;

create or replace function programacion.fn_agent_task_worker_context_receipt_ok(p_execution_id bigint)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','programacion'
as $function$
  select exists(
    select 1
    from programacion.ejecuciones ex
    join programacion.context_packs cp on cp.execution_id=ex.id and cp.estado='COMPLETE' and cp.digest_version=2
    join programacion.objetivos_ejecucion obj on obj.execution_id=ex.id
    join programacion.evaluaciones eva on eva.objetivo_id=obj.id and eva.resultado='PASS'
    join programacion.evidencias ev on ev.evaluacion_id=eva.id
    where ex.id=p_execution_id
      and ex.request_ref~'^agent-task://[1-9][0-9]*$'
      and programacion.fn_evaluation_pass_evidence_valid_v1(eva.id)
      and ev.tipo='VERIFIED_WORKER_RECEIPT'
      and ev.source_system='PROGRAMMING_AGENT_WORKER'
      and ev.sha256=ev.metadata->>'receipt_sha256'
      and ev.metadata#>>'{worker_receipt,status}'='PASS'
      and ev.metadata#>>'{worker_receipt,execution_id}'=ex.id::text
      and ev.metadata#>>'{worker_receipt,context_pack_id}'=cp.id::text
      and ev.metadata#>>'{worker_receipt,context_pack_sha256}'=cp.context_sha256
      and programacion.fn_evidence_pass_compatible_v1(ev.id)
  );
$function$;
revoke all on function programacion.fn_agent_task_worker_context_receipt_ok(bigint) from public,anon,authenticated,service_role;
grant execute on function programacion.fn_agent_task_worker_context_receipt_ok(bigint) to postgres,programacion_builder,programacion_auditor,programacion_human_authority,programacion_promoter;

create or replace view programacion.v_ejecucion_cierre as
with recursive version_chain as (
  select ex.id as execution_id,v.id as version_id,v.supersedes_version_id,0 as depth
  from programacion.ejecuciones ex
  join programacion.versiones_agente v on v.id=ex.version_id
  union all
  select vc.execution_id,p.id,p.supersedes_version_id,vc.depth+1
  from version_chain vc
  join programacion.versiones_agente p on p.id=vc.supersedes_version_id
), effective_gates as (
  select distinct on (vc.execution_id,g.gate_codigo)
    vc.execution_id,g.gate_codigo,g.id as gate_id
  from version_chain vc
  join programacion.gates g on g.version_id=vc.version_id
  where g.bloqueante=true and g.estado=any(array['defined'::text,'active'::text])
  order by vc.execution_id,g.gate_codigo,vc.depth,g.id desc
), latest as (
  select o.id as objetivo_id,o.execution_id,o.aplicabilidad,
         e.id as evaluacion_id,
         case
           when e.resultado='PASS' and programacion.fn_evaluation_pass_evidence_valid_v1(e.id) is not true then 'BLOCKED'::text
           else e.resultado
         end as resultado,
         e.intento
  from programacion.objetivos_ejecucion o
  left join effective_gates eg on eg.execution_id=o.execution_id and eg.gate_id=o.gate_id
  left join lateral (
    select ev.id,ev.resultado,ev.intento
    from programacion.evaluaciones ev
    where ev.objetivo_id=o.id
    order by ev.intento desc
    limit 1
  ) e on true
  where o.control_calidad_id is not null or o.gate_id is null or eg.gate_id is not null
), agg as (
  select latest.execution_id,
    count(*) as objetivos_total,
    count(*) filter(where latest.aplicabilidad='REQUIRED') as required_total,
    count(*) filter(where latest.aplicabilidad='NOT_APPLICABLE') as not_applicable_total,
    count(*) filter(where latest.aplicabilidad='BLOCKED') as blocked_by_applicability,
    count(*) filter(where latest.aplicabilidad='REQUIRED' and latest.resultado='PASS') as required_pass,
    count(*) filter(where latest.aplicabilidad='REQUIRED' and latest.resultado=any(array['FAIL'::text,'FINDING'::text,'ERROR'::text])) as required_fail,
    count(*) filter(where latest.aplicabilidad='REQUIRED' and latest.resultado='BLOCKED') as required_blocked,
    count(*) filter(where latest.aplicabilidad='REQUIRED' and (latest.resultado is null or latest.resultado='PENDING')) as required_pending
  from latest
  group by latest.execution_id
)
select ex.id as execution_id,ex.version_id,ex.repo_full_name,ex.branch_name,ex.head_sha,ex.estado,
  case when exists(select 1 from programacion.execution_invalidations inv where inv.execution_id=ex.id) then 'INVALIDATED' else ex.veredicto end as veredicto,
  coalesce(a.objetivos_total,0) as objetivos_total,
  coalesce(a.required_total,0) as required_total,
  coalesce(a.not_applicable_total,0) as not_applicable_total,
  coalesce(a.blocked_by_applicability,0) as blocked_by_applicability,
  coalesce(a.required_pass,0) as required_pass,
  coalesce(a.required_fail,0) as required_fail,
  coalesce(a.required_blocked,0) as required_blocked,
  coalesce(a.required_pending,0) as required_pending,
  case
    when exists(select 1 from programacion.execution_invalidations inv where inv.execution_id=ex.id) then 'INVALIDATED'
    when not exists(select 1 from programacion.context_packs cp where cp.execution_id=ex.id and cp.estado='COMPLETE') then 'BLOCKED_CONTEXT'
    when ex.request_ref~'^agent-task://[1-9][0-9]*$' and not programacion.fn_agent_task_worker_context_receipt_ok(ex.id) then 'BLOCKED_WORKER_CONTEXT_RECEIPT'
    when coalesce(a.objetivos_total,0)=0 then 'BLOCKED_EMPTY_UNIVERSE'
    when coalesce(a.blocked_by_applicability,0)>0 or coalesce(a.required_blocked,0)>0 then 'BLOCKED'
    when coalesce(a.required_fail,0)>0 then 'FAIL'
    when coalesce(a.required_pending,0)>0 then 'PENDING'
    when coalesce(a.required_total,0)=coalesce(a.required_pass,0) then 'ELIGIBLE_PASS'
    else 'PENDING'
  end as derived_status
from programacion.ejecuciones ex
left join agg a on a.execution_id=ex.id;

comment on function programacion.fn_evidence_pass_compatible_v1(bigint)
is 'AUD-023/ARC-006 fail-closed evidence consumer: PASS compatibility uses the latest exact authoritative verification; later REJECTED degrades prior VERIFIED. Worker PASS also requires machine proof contract v2. Derived gate evidence cannot launder a stale/rejected source verification.';
comment on function programacion.fn_evaluation_pass_evidence_valid_v1(bigint)
is 'AUD-023/ARC-006 dynamic PASS-evidence validity for guards and closure. Every attached evidence must remain exact-head and effectively VERIFIED with no explicit FAIL/BLOCKED/REJECTED contradiction.';
comment on view programacion.v_ejecucion_cierre
is 'Derived execution closure. Stored PASS is counted only while its evidence remains currently compatible; later authoritative evidence degradation converts the effective objective result to BLOCKED.';
