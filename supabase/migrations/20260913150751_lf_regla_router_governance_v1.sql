insert into public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest,created_by_execution_id,updated_by_execution_id)
values
('EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001','VULNERABILITY_COVERAGE_REPAIR_LF','OPERATION_PROTOCOL_REPAIR','CREACION_REGLA_LF','IN_PROGRESS','{"mode":"REGLA_OPERATION_GOVERNANCE_BOOTSTRAP","governance_bootstrap":true,"bootstrap_operation_code":"CREACION_REGLA_LF","bootstrap_status_ceiling":"SANDBOX_ACTIVE","production_allowed":false}'::jsonb,'EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001','EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001'),
('EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001','VULNERABILITY_COVERAGE_REPAIR_LF','OPERATION_PROTOCOL_REPAIR','ACTUALIZACION_REGLA_LF','IN_PROGRESS','{"mode":"REGLA_OPERATION_GOVERNANCE_BOOTSTRAP","governance_bootstrap":true,"bootstrap_operation_code":"ACTUALIZACION_REGLA_LF","bootstrap_status_ceiling":"SANDBOX_ACTIVE","production_allowed":false}'::jsonb,'EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001','EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001');

with o(operation_code,op_type,bootstrap_id) as (values
('CREACION_REGLA_LF','CREATE_CANDIDATE','EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001'),
('ACTUALIZACION_REGLA_LF','UPDATE_CANDIDATE','EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001'))
insert into public.lf_operation_registry(operation_code,version,status,source_model,source_repo,source_paths,notes,operation_family,operation_domain,operation_type,applies_to_asset_type,created_by_execution_id)
select operation_code,'v0.1','SANDBOX_ACTIVE','GOVERNED_DB_OPERATION','cristhianlujan/claude-persona-lf-patch','["public.lf_router_resolve_v1","public.lf_router_action_registry","lf_ops.reglas","public.lf_regla_candidate_write_v1"]'::jsonb,'Lightweight governed rule candidate operation; no automatic promotion; VIGENTE direct update blocked.','RULE_OPERATIONS','RULE_GOVERNANCE',op_type,'REGLA',bootstrap_id from o;

with o(operation_code,bootstrap_id) as (values
('CREACION_REGLA_LF','EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001'),
('ACTUALIZACION_REGLA_LF','EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001'))
insert into public.lf_operation_contracts(operation_code,contract_code,contract_path,contract_sha,required_before_write,allowed,blocked,required_after_write,status,created_by_execution_id)
select operation_code,'CONTRACT-'||operation_code||'-v0.1','supabase://public/lf_operation_contracts/'||operation_code,null,
'["ekb_preflight","rule_classified","existing_checked","destination_validated","execution_bound"]'::jsonb,
'{"destination":"lf_ops.reglas","write_state":"CANDIDATO","single_rule":true,"automatic_promotion":false,"relation_mutation":false}'::jsonb,
'{"production_promotion":true,"vigente_direct_update":true,"duplicate_create":true,"missing_update_target":true,"relation_delete":true}'::jsonb,
'["exact_rule_readback","estado_CANDIDATO","execution_trace","no_promotion"]'::jsonb,'ACTIVE_ENFORCEMENT',bootstrap_id from o;

with o(operation_code,bootstrap_id) as (values
('CREACION_REGLA_LF','EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001'),
('ACTUALIZACION_REGLA_LF','EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001')),
s(step_order,step_id,evidence) as (values
(10,'ekb_preflight','ekb_refs,execution_binding'),
(20,'classify','rule_code,category,candidate_classification'),
(30,'existing_check','rule_code,existing_count,expected_existence'),
(40,'destination_validate','destination_schema,destination_table,unique_code_guard'),
(50,'candidate_write','execution_id,rule_code,write_result,estado'),
(60,'readback','rule_code,readback_row,estado'),
(70,'trace_close','execution_id,operation_code,trace_ref,no_promotion'))
insert into public.lf_operation_steps(operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,active,execution_order,created_by_execution_id)
select o.operation_code,s.step_order,s.step_id,true,s.evidence,'supabase://public/lf_operation_step_contracts/'||o.operation_code||'/'||s.step_id,null,true,s.step_order,o.bootstrap_id from o cross join s;

with o(operation_code,bootstrap_id) as (values
('CREACION_REGLA_LF','EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001'),
('ACTUALIZACION_REGLA_LF','EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001')),
s(step_order,step_id,keys,next_step) as (values
(10,'ekb_preflight','["ekb_refs","execution_binding"]'::jsonb,'classify'),
(20,'classify','["rule_code","category","candidate_classification"]'::jsonb,'existing_check'),
(30,'existing_check','["rule_code","existing_count","expected_existence"]'::jsonb,'destination_validate'),
(40,'destination_validate','["destination_schema","destination_table","unique_code_guard"]'::jsonb,'candidate_write'),
(50,'candidate_write','["execution_id","rule_code","write_result","estado"]'::jsonb,'readback'),
(60,'readback','["rule_code","readback_row","estado"]'::jsonb,'trace_close'),
(70,'trace_close','["execution_id","operation_code","trace_ref","no_promotion"]'::jsonb,null))
insert into public.lf_operation_step_contracts(operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,resolver_ref,output_payload,pass_condition,block_condition,blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,status,notes,execution_sql,fail_condition,created_by_execution_id)
select o.operation_code,s.step_id,s.step_order,s.step_order,'CONTRACT-'||o.operation_code||'-v0.1',s.step_id||' governed rule step.','{}'::jsonb,'RULE_OPERATION_DETERMINISTIC',s.keys,'{"required_evidence_present":true}'::jsonb,'{"missing_required_evidence":true}'::jsonb,'BLOCK_'||o.operation_code||'_'||upper(s.step_id),'MINI_JUDGE_'||o.operation_code||'_V1',s.keys,s.next_step,'trace_close','ACTIVE_ENFORCEMENT','Small fail-closed rule governance step.',null,'{}'::jsonb,o.bootstrap_id from o cross join s;

with o(operation_code,bootstrap_id) as (values
('CREACION_REGLA_LF','EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001'),
('ACTUALIZACION_REGLA_LF','EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001'))
insert into public.lf_operation_judges(operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,created_by_execution_id)
select operation_code,'MINI_JUDGE_'||operation_code||'_V1','supabase://public/lf_operation_judges/'||operation_code,null,'{"required_evidence_present":true}'::jsonb,'{"missing_required_evidence":true}'::jsonb,'["PASS_CLEAN","BLOCKED_BY_ENFORCEMENT","RETURN_TO_WORKER"]'::jsonb,'ACTIVE_ENFORCEMENT',bootstrap_id from o;

with o(operation_code,bootstrap_id) as (values
('CREACION_REGLA_LF','EXEC-BOOTSTRAP-CREACION-REGLA-LF-20260913-001'),
('ACTUALIZACION_REGLA_LF','EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001')),
s(step_order,step_id,keys) as (values
(10,'ekb_preflight','["ekb_refs","execution_binding"]'::jsonb),(20,'classify','["rule_code","category","candidate_classification"]'::jsonb),(30,'existing_check','["rule_code","existing_count","expected_existence"]'::jsonb),(40,'destination_validate','["destination_schema","destination_table","unique_code_guard"]'::jsonb),(50,'candidate_write','["execution_id","rule_code","write_result","estado"]'::jsonb),(60,'readback','["rule_code","readback_row","estado"]'::jsonb),(70,'trace_close','["execution_id","operation_code","trace_ref","no_promotion"]'::jsonb))
insert into public.lf_operation_step_judge_bindings(operation_code,step_order,step_id,judge_code,clean_result_value,blocked_result_value,return_result_value,required_evidence_keys,status,created_by_execution_id)
select o.operation_code,s.step_order,s.step_id,'MINI_JUDGE_'||o.operation_code||'_V1','PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER',s.keys,'ACTIVE_ENFORCEMENT',o.bootstrap_id from o cross join s;

insert into public.lf_router_action_registry(asset_type,action_code,operation_code,operation_resolution,requires_existing_target,requires_missing_target,write_allowed,status,notes,created_by_execution_id)
values
('REGLA','REGLA_CREATE','CREACION_REGLA_LF','STATIC',false,false,true,'ACTIVE','Existence resolved inside operation against lf_ops.reglas.codigo; most LF rules are not lf_activos.','EXEC-ACTUALIZACION-DB-REGLA-ROUTER-20260913-001'),
('REGLA','REGLA_UPDATE','ACTUALIZACION_REGLA_LF','STATIC',false,false,true,'ACTIVE','Existence and CANDIDATO state resolved inside operation against lf_ops.reglas.codigo.','EXEC-ACTUALIZACION-DB-REGLA-ROUTER-20260913-001');

create or replace function public.lf_regla_candidate_write_v1(p_execution_id text,p_action_code text,p_codigo text,p_categoria text,p_titulo text,p_descripcion text,p_razon text default null,p_valor_config jsonb default null,p_es_transversal boolean default false,p_origen text default null)
returns jsonb language plpgsql security invoker set search_path=pg_catalog,public,lf_ops as $fn$
declare v_exec public.lf_operation_execution%rowtype; v_expected text; v_before lf_ops.reglas%rowtype; v_after lf_ops.reglas%rowtype;
begin
 if upper(coalesce(p_action_code,'')) not in ('REGLA_CREATE','REGLA_UPDATE') then raise exception 'LF_REGLA_ACTION_INVALID:%',p_action_code; end if;
 if btrim(coalesce(p_execution_id,''))='' or btrim(coalesce(p_codigo,''))='' or btrim(coalesce(p_categoria,''))='' or btrim(coalesce(p_titulo,''))='' or btrim(coalesce(p_descripcion,''))='' then raise exception 'LF_REGLA_REQUIRED_INPUT_MISSING'; end if;
 v_expected:=case upper(p_action_code) when 'REGLA_CREATE' then 'CREACION_REGLA_LF' else 'ACTUALIZACION_REGLA_LF' end;
 select * into v_exec from public.lf_operation_execution where execution_id=p_execution_id;
 if not found then raise exception 'LF_REGLA_EXECUTION_NOT_FOUND:%',p_execution_id; end if;
 if v_exec.operation_code<>v_expected or v_exec.status<>'IN_PROGRESS' or v_exec.target_type<>'REGLA' or v_exec.target_code<>p_codigo then raise exception 'LF_REGLA_EXECUTION_BINDING_MISMATCH'; end if;
 select * into v_before from lf_ops.reglas where codigo=p_codigo;
 if upper(p_action_code)='REGLA_CREATE' then
  if found then raise exception 'LF_REGLA_CREATE_DUPLICATE:%',p_codigo; end if;
  insert into lf_ops.reglas(codigo,categoria,titulo,descripcion,razon,valor_config,es_transversal,estado,origen,pendiente_decision,pendiente_detalle,created_by)
  values(p_codigo,p_categoria,p_titulo,p_descripcion,p_razon,p_valor_config,coalesce(p_es_transversal,false),'CANDIDATO',p_origen,true,'GOVERNED_CANDIDATE_REQUIRES_REVIEW',p_execution_id) returning * into v_after;
 else
  if not found then raise exception 'LF_REGLA_UPDATE_NOT_FOUND:%',p_codigo; end if;
  if v_before.estado<>'CANDIDATO' then raise exception 'LF_REGLA_UPDATE_REQUIRES_CANDIDATO:%:%',p_codigo,v_before.estado; end if;
  update lf_ops.reglas set categoria=p_categoria,titulo=p_titulo,descripcion=p_descripcion,razon=p_razon,valor_config=p_valor_config,es_transversal=coalesce(p_es_transversal,false),estado='CANDIDATO',origen=coalesce(p_origen,origen),pendiente_decision=true,pendiente_detalle='GOVERNED_CANDIDATE_REQUIRES_REVIEW',updated_at=now() where codigo=p_codigo returning * into v_after;
 end if;
 return jsonb_build_object('result',case when upper(p_action_code)='REGLA_CREATE' then 'RULE_CANDIDATE_CREATED' else 'RULE_CANDIDATE_UPDATED' end,'operation_code',v_expected,'execution_id',p_execution_id,'before',case when upper(p_action_code)='REGLA_UPDATE' then to_jsonb(v_before) else null end,'after',to_jsonb(v_after));
end;$fn$;

revoke all on function public.lf_regla_candidate_write_v1(text,text,text,text,text,text,text,jsonb,boolean,text) from public,anon,authenticated;
grant execute on function public.lf_regla_candidate_write_v1(text,text,text,text,text,text,text,jsonb,boolean,text) to service_role;

do $patch$ declare v_def text; v_new text; p1 text:=$p$if v_type_hint='PERFIL' then v_action:='PROFILE_CREATE'; elsif v_type_hint='SKILL' then v_action:='SKILL_CREATE'; elsif v_type_hint='ADAPTER' then v_action:='ADAPTER_CREATE'; else v_action:='CREATE'; end if;$p$; r1 text:=$p$if v_type_hint='PERFIL' then v_action:='PROFILE_CREATE'; elsif v_type_hint='SKILL' then v_action:='SKILL_CREATE'; elsif v_type_hint='ADAPTER' then v_action:='ADAPTER_CREATE'; elsif v_type_hint='REGLA' then v_action:='REGLA_CREATE'; else v_action:='CREATE'; end if;$p$; p2 text:=$p$elsif v_type_hint='REGLA' then v_action:='RULE_UPDATE';$p$; r2 text:=$p$elsif v_type_hint='REGLA' then v_action:='REGLA_UPDATE';$p$; p3 text:=$p$if v_action in ('PROFILE_CREATE','SKILL_CREATE','ADAPTER_CREATE') and v_asset_found and v_target_norm='' then$p$; r3 text:=$p$if v_action in ('PROFILE_CREATE','SKILL_CREATE','ADAPTER_CREATE','REGLA_CREATE') and v_asset_found and v_target_norm='' then$p$; begin select pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) into v_def; if strpos(v_def,p1)=0 or strpos(v_def,p2)=0 or strpos(v_def,p3)=0 then raise exception 'LF_REGLA_ROUTER_SOURCE_DRIFT'; end if; v_new:=replace(replace(replace(v_def,p1,r1),p2,r2),p3,r3); execute v_new; end;$patch$;

do $post$ declare c int; v jsonb; begin
 select count(*) into c from public.lf_operation_registry where operation_code in ('CREACION_REGLA_LF','ACTUALIZACION_REGLA_LF'); if c<>2 then raise exception 'LF_REGLA_OPERATION_COUNT_FAIL:%',c; end if;
 select count(*) into c from public.lf_operation_steps where operation_code in ('CREACION_REGLA_LF','ACTUALIZACION_REGLA_LF'); if c<>14 then raise exception 'LF_REGLA_STEP_COUNT_FAIL:%',c; end if;
 select count(*) into c from public.lf_router_action_registry where asset_type='REGLA' and action_code in ('REGLA_CREATE','REGLA_UPDATE') and status='ACTIVE' and write_allowed; if c<>2 then raise exception 'LF_REGLA_ROUTER_COUNT_FAIL:%',c; end if;
 v:=public.lf_router_resolve_v1('crear nueva regla candidata para cobranza',null,null,'REGLA','ROUTER'); if v->>'status'<>'READY_TO_EXECUTE' or v->>'action_code'<>'REGLA_CREATE' or v->>'operation_code'<>'CREACION_REGLA_LF' then raise exception 'LF_REGLA_CREATE_ROUTE_POST_FAIL:%',v; end if;
 v:=public.lf_router_resolve_v1('actualizar regla candidata de cobranza',null,null,'REGLA','ROUTER'); if v->>'status'<>'READY_TO_EXECUTE' or v->>'action_code'<>'REGLA_UPDATE' or v->>'operation_code'<>'ACTUALIZACION_REGLA_LF' then raise exception 'LF_REGLA_UPDATE_ROUTE_POST_FAIL:%',v; end if;
end;$post$;