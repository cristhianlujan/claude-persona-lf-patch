create or replace function programacion.fn_guard_evaluation()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'programacion'
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

 -- PROG-ADR-AUTH-001: a boolean claim is never authority evidence.
 -- Historical true rows remain untouched; new/updated evaluations cannot assert it.
 if new.independencia_declarada then
   raise exception 'DECLARATIVE_INDEPENDENCE_DISABLED_BY_PROG_ADR_AUTH_001';
 end if;
 if v_independence_required then
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
   if not exists(select 1 from programacion.evidencias ev where ev.evaluacion_id=old.id) then raise exception 'PASS requires at least one evidence row for evaluation %',old.id; end if;
   if exists(select 1 from programacion.evidencias ev where ev.evaluacion_id=old.id and not exists(select 1 from programacion.evidence_verifications vv where vv.evidence_id=ev.id and vv.verification_status='VERIFIED' and vv.evidence_sha256=ev.sha256 and vv.source_system=ev.source_system and vv.source_ref=ev.source_ref)) then
     raise exception 'PASS requires VERIFIED receipt for every evidence row of evaluation %',old.id;
   end if;
 end if;
 return new;
end;
$function$;