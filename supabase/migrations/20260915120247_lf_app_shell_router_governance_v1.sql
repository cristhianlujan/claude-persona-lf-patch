-- Governed APP_SHELL lifecycle v1.
-- Candidate-only: creates/updates lf_ops.app_shells in CANDIDATO state; no promotion.
-- Source authorization: EXEC-ADMIN-APP-SHELL-LIFECYCLE-SANDBOX-20260915-001.

select public.fn_lf_operation_reserve_execution_v1(
  'EXEC-BOOTSTRAP-CREACION-APP-SHELL-LF-20260915-001','VULNERABILITY_COVERAGE_REPAIR_LF',
  'OPERATION_PROTOCOL_REPAIR','CREACION_APP_SHELL_LF','BOOTSTRAP:CREACION_APP_SHELL_LF:20260915:001',repeat('a',64),
  'EXEC-BOOTSTRAP-CREACION-APP-SHELL-LF-20260915-001','cristhianlujan/claude-persona-lf-patch',
  'supabase/migrations/20260915115500_lf_app_shell_router_governance_v1.sql',
  '{"mode":"APP_SHELL_OPERATION_GOVERNANCE_BOOTSTRAP","governance_bootstrap":true,"bootstrap_operation_code":"CREACION_APP_SHELL_LF","bootstrap_status_ceiling":"SANDBOX_ACTIVE","production_allowed":false}'::jsonb
);
select public.fn_lf_operation_reserve_execution_v1(
  'EXEC-BOOTSTRAP-ACTUALIZACION-APP-SHELL-LF-20260915-001','VULNERABILITY_COVERAGE_REPAIR_LF',
  'OPERATION_PROTOCOL_REPAIR','ACTUALIZACION_APP_SHELL_LF','BOOTSTRAP:ACTUALIZACION_APP_SHELL_LF:20260915:001',repeat('b',64),
  'EXEC-BOOTSTRAP-ACTUALIZACION-APP-SHELL-LF-20260915-001','cristhianlujan/claude-persona-lf-patch',
  'supabase/migrations/20260915115500_lf_app_shell_router_governance_v1.sql',
  '{"mode":"APP_SHELL_OPERATION_GOVERNANCE_BOOTSTRAP","governance_bootstrap":true,"bootstrap_operation_code":"ACTUALIZACION_APP_SHELL_LF","bootstrap_status_ceiling":"SANDBOX_ACTIVE","production_allowed":false}'::jsonb
);

with o(operation_code,op_type,bootstrap_id) as (values
  ('CREACION_APP_SHELL_LF','CREATE_CANDIDATE','EXEC-BOOTSTRAP-CREACION-APP-SHELL-LF-20260915-001'),
  ('ACTUALIZACION_APP_SHELL_LF','UPDATE_CANDIDATE','EXEC-BOOTSTRAP-ACTUALIZACION-APP-SHELL-LF-20260915-001')
)
insert into public.lf_operation_registry(
  operation_code,version,status,source_model,source_repo,source_paths,notes,
  operation_family,operation_domain,operation_type,applies_to_asset_type,
  created_by_execution_id,updated_by_execution_id
)
select operation_code,'v0.1','SANDBOX_ACTIVE','GOVERNED_DB_OPERATION','cristhianlujan/claude-persona-lf-patch',
  '["public.lf_router_resolve_v1","public.lf_router_action_registry","lf_ops.app_shells","lf_design.design_systems","public.lf_app_shell_candidate_write_v1"]'::jsonb,
  'Governed APP_SHELL candidate lifecycle. CANDIDATO only; exact execution binding; no automatic promotion.',
  'APP_SHELL_OPERATIONS','APP_SHELL_GOVERNANCE',op_type,'APP_SHELL',bootstrap_id,bootstrap_id
from o;

with o(operation_code,bootstrap_id) as (values
  ('CREACION_APP_SHELL_LF','EXEC-BOOTSTRAP-CREACION-APP-SHELL-LF-20260915-001'),
  ('ACTUALIZACION_APP_SHELL_LF','EXEC-BOOTSTRAP-ACTUALIZACION-APP-SHELL-LF-20260915-001')
)
insert into public.lf_operation_contracts(
  operation_code,contract_code,contract_path,contract_sha,required_before_write,allowed,blocked,required_after_write,status,
  created_by_execution_id,updated_by_execution_id
)
select operation_code,'CONTRACT-'||operation_code||'-v0.1','supabase://public/lf_operation_contracts/'||operation_code||'/v0.1',null,
  '["router_read","ekb_read","shell_inventory_read","design_system_resolved","execution_bound","rollback_plan"]'::jsonb,
  '{"destination":"lf_ops.app_shells","write_state":"CANDIDATO","single_shell":true,"visual_clone_allowed":true,"automatic_promotion":false,"production_allowed":false,"direct_write_allowed":false}'::jsonb,
  '["production_promotion","vigente_direct_update","duplicate_create","missing_update_target","direct_write_bypass","cross_shell_mutation"]'::jsonb,
  '["exact_shell_readback","status_CANDIDATO","execution_trace","no_promotion"]'::jsonb,
  'ACTIVE_ENFORCEMENT',bootstrap_id,bootstrap_id
from o;

with o(operation_code,bootstrap_id) as (values
  ('CREACION_APP_SHELL_LF','EXEC-BOOTSTRAP-CREACION-APP-SHELL-LF-20260915-001'),
  ('ACTUALIZACION_APP_SHELL_LF','EXEC-BOOTSTRAP-ACTUALIZACION-APP-SHELL-LF-20260915-001')
), s(step_order,step_id,evidence,next_step) as (values
  (10,'preflight','router_binding,ekb_refs,shell_inventory,rollback_plan','classify'),
  (20,'classify','app_shell_code,design_system_code,candidate_classification','existing_check'),
  (30,'existing_check','app_shell_code,existing_count,expected_existence','destination_validate'),
  (40,'destination_validate','destination_schema,destination_table,design_system_resolved','candidate_write'),
  (50,'candidate_write','execution_id,app_shell_code,write_result,status','readback'),
  (60,'readback','app_shell_code,readback_row,status','report_output'),
  (70,'report_output','execution_id,operation_code,trace_ref,no_promotion',null)
)
insert into public.lf_operation_steps(operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,active,execution_order,created_by_execution_id,updated_by_execution_id)
select o.operation_code,s.step_order,s.step_id,true,s.evidence,'supabase://public/lf_operation_step_contracts/'||o.operation_code||'/'||s.step_id,null,true,s.step_order,o.bootstrap_id,o.bootstrap_id
from o cross join s;

with o(operation_code,bootstrap_id) as (values
  ('CREACION_APP_SHELL_LF','EXEC-BOOTSTRAP-CREACION-APP-SHELL-LF-20260915-001'),
  ('ACTUALIZACION_APP_SHELL_LF','EXEC-BOOTSTRAP-ACTUALIZACION-APP-SHELL-LF-20260915-001')
), s(step_order,step_id,keys,next_step) as (values
  (10,'preflight','["router_binding","ekb_refs","shell_inventory","rollback_plan"]'::jsonb,'classify'),
  (20,'classify','["app_shell_code","design_system_code","candidate_classification"]'::jsonb,'existing_check'),
  (30,'existing_check','["app_shell_code","existing_count","expected_existence"]'::jsonb,'destination_validate'),
  (40,'destination_validate','["destination_schema","destination_table","design_system_resolved"]'::jsonb,'candidate_write'),
  (50,'candidate_write','["execution_id","app_shell_code","write_result","status"]'::jsonb,'readback'),
  (60,'readback','["app_shell_code","readback_row","status"]'::jsonb,'report_output'),
  (70,'report_output','["execution_id","operation_code","trace_ref","no_promotion"]'::jsonb,null)
)
insert into public.lf_operation_step_contracts(
  operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,resolver_ref,output_payload,
  pass_condition,block_condition,blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,status,notes,execution_sql,fail_condition,
  created_by_execution_id,updated_by_execution_id
)
select o.operation_code,s.step_id,s.step_order,s.step_order,'CONTRACT-'||o.operation_code||'-v0.1',s.step_id||' deterministic APP_SHELL governance step.',
  '{}'::jsonb,'APP_SHELL_OPERATION_DETERMINISTIC',s.keys,'{"required_evidence_present":true}'::jsonb,'{"missing_required_evidence":true}'::jsonb,
  'BLOCK_'||o.operation_code||'_'||upper(s.step_id),'MINI_JUDGE_'||o.operation_code||'_V1',s.keys,s.next_step,'report_output','ACTIVE_ENFORCEMENT',
  'Fail-closed governed APP_SHELL candidate step.',null,'{}'::jsonb,o.bootstrap_id,o.bootstrap_id
from o cross join s;

with o(operation_code,bootstrap_id) as (values
  ('CREACION_APP_SHELL_LF','EXEC-BOOTSTRAP-CREACION-APP-SHELL-LF-20260915-001'),
  ('ACTUALIZACION_APP_SHELL_LF','EXEC-BOOTSTRAP-ACTUALIZACION-APP-SHELL-LF-20260915-001')
)
insert into public.lf_operation_judges(operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,created_by_execution_id,updated_by_execution_id)
select operation_code,'MINI_JUDGE_'||operation_code||'_V1','supabase://public/lf_operation_judges/'||operation_code,null,
  '{"required_evidence_present":true}'::jsonb,'{"missing_required_evidence":true}'::jsonb,'["PASS_CLEAN","BLOCKED_BY_ENFORCEMENT","RETURN_TO_WORKER"]'::jsonb,
  'ACTIVE_ENFORCEMENT',bootstrap_id,bootstrap_id from o;

with o(operation_code,bootstrap_id) as (values
  ('CREACION_APP_SHELL_LF','EXEC-BOOTSTRAP-CREACION-APP-SHELL-LF-20260915-001'),
  ('ACTUALIZACION_APP_SHELL_LF','EXEC-BOOTSTRAP-ACTUALIZACION-APP-SHELL-LF-20260915-001')
), s(step_order,step_id,keys) as (values
  (10,'preflight','["router_binding","ekb_refs","shell_inventory","rollback_plan"]'::jsonb),
  (20,'classify','["app_shell_code","design_system_code","candidate_classification"]'::jsonb),
  (30,'existing_check','["app_shell_code","existing_count","expected_existence"]'::jsonb),
  (40,'destination_validate','["destination_schema","destination_table","design_system_resolved"]'::jsonb),
  (50,'candidate_write','["execution_id","app_shell_code","write_result","status"]'::jsonb),
  (60,'readback','["app_shell_code","readback_row","status"]'::jsonb),
  (70,'report_output','["execution_id","operation_code","trace_ref","no_promotion"]'::jsonb)
)
insert into public.lf_operation_step_judge_bindings(operation_code,step_order,step_id,judge_code,clean_result_value,blocked_result_value,return_result_value,required_evidence_keys,status,created_by_execution_id,updated_by_execution_id)
select o.operation_code,s.step_order,s.step_id,'MINI_JUDGE_'||o.operation_code||'_V1','PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER',s.keys,'ACTIVE_ENFORCEMENT',o.bootstrap_id,o.bootstrap_id
from o cross join s;

insert into public.lf_router_action_registry(asset_type,action_code,operation_code,operation_resolution,requires_existing_target,requires_missing_target,write_allowed,status,notes,created_by_execution_id,updated_by_execution_id)
values
('APP_SHELL','APP_SHELL_CREATE','CREACION_APP_SHELL_LF','STATIC',false,false,true,'ACTIVE','Existence resolved inside governed APP_SHELL operation; CANDIDATO only.','EXEC-BOOTSTRAP-CREACION-APP-SHELL-LF-20260915-001','EXEC-BOOTSTRAP-CREACION-APP-SHELL-LF-20260915-001'),
('APP_SHELL','APP_SHELL_UPDATE','ACTUALIZACION_APP_SHELL_LF','STATIC',false,false,true,'ACTIVE','Existing CANDIDATO APP_SHELL only; VIGENTE direct update blocked.','EXEC-BOOTSTRAP-ACTUALIZACION-APP-SHELL-LF-20260915-001','EXEC-BOOTSTRAP-ACTUALIZACION-APP-SHELL-LF-20260915-001');

create or replace function public.lf_app_shell_candidate_write_v1(
  p_execution_id text,p_action_code text,p_app_shell_code text,p_design_system_code text,p_name text,
  p_description text default null,p_version text default 'v0.1',p_source_decision_id text default null,
  p_source_decision_number bigint default null,p_clone_from_shell_code text default null
) returns jsonb language plpgsql security invoker set search_path=pg_catalog,public,lf_ops,lf_design as $fn$
declare
  v_exec public.lf_operation_execution%rowtype;
  v_expected text;
  v_before lf_ops.app_shells%rowtype;
  v_after lf_ops.app_shells%rowtype;
  v_clone lf_ops.app_shells%rowtype;
  v_ds_id bigint;
  v_next_id bigint;
begin
  if upper(coalesce(p_action_code,'')) not in ('APP_SHELL_CREATE','APP_SHELL_UPDATE') then raise exception 'LF_APP_SHELL_ACTION_INVALID:%',p_action_code; end if;
  if btrim(coalesce(p_execution_id,''))='' or btrim(coalesce(p_app_shell_code,''))='' or btrim(coalesce(p_design_system_code,''))='' or btrim(coalesce(p_name,''))='' then raise exception 'LF_APP_SHELL_REQUIRED_INPUT_MISSING'; end if;
  v_expected:=case upper(p_action_code) when 'APP_SHELL_CREATE' then 'CREACION_APP_SHELL_LF' else 'ACTUALIZACION_APP_SHELL_LF' end;
  select * into v_exec from public.lf_operation_execution where execution_id=p_execution_id;
  if not found then raise exception 'LF_APP_SHELL_EXECUTION_NOT_FOUND:%',p_execution_id; end if;
  if v_exec.operation_code<>v_expected or v_exec.status<>'IN_PROGRESS' or v_exec.target_type<>'APP_SHELL' or v_exec.target_code<>p_app_shell_code then raise exception 'LF_APP_SHELL_EXECUTION_BINDING_MISMATCH'; end if;
  select design_system_id into v_ds_id from lf_design.design_systems where design_system_code=p_design_system_code;
  if v_ds_id is null then raise exception 'LF_APP_SHELL_DESIGN_SYSTEM_NOT_FOUND:%',p_design_system_code; end if;
  if nullif(btrim(coalesce(p_clone_from_shell_code,'')),'') is not null then
    select * into v_clone from lf_ops.app_shells where app_shell_code=p_clone_from_shell_code;
    if not found then raise exception 'LF_APP_SHELL_CLONE_SOURCE_NOT_FOUND:%',p_clone_from_shell_code; end if;
    if v_clone.design_system_code<>p_design_system_code then raise exception 'LF_APP_SHELL_CLONE_DS_MISMATCH:%:%',v_clone.design_system_code,p_design_system_code; end if;
  end if;
  select * into v_before from lf_ops.app_shells where app_shell_code=p_app_shell_code;
  if upper(p_action_code)='APP_SHELL_CREATE' then
    if found then raise exception 'LF_APP_SHELL_CREATE_DUPLICATE:%',p_app_shell_code; end if;
    perform pg_advisory_xact_lock(hashtextextended('lf_ops.app_shells.app_shell_id',0));
    select coalesce(max(app_shell_id),0)+1 into v_next_id from lf_ops.app_shells;
    if v_clone.app_shell_code is not null then
      insert into lf_ops.app_shells(
        app_shell_id,app_shell_code,design_system_code,name,description,version,status,
        shell_component_token_code,sidebar_expanded_component_token_code,sidebar_collapsed_component_token_code,sidebar_mobile_component_token_code,
        topbar_component_token_code,breadcrumb_component_token_code,page_header_component_token_code,page_background_token_name,content_surface_token_name,
        divider_token_name,title_typography_token_name,body_typography_token_name,content_gap_token_name,logo_expanded_asset_code,logo_collapsed_asset_code,
        sidebar_collapsible,persist_user_preference,source_decision_id,source_decision_number,design_system_id,
        shell_component_token_id,sidebar_expanded_component_token_id,sidebar_collapsed_component_token_id,sidebar_mobile_component_token_id,topbar_component_token_id,
        breadcrumb_component_token_id,page_header_component_token_id,page_background_color_token_id,content_surface_color_token_id,divider_color_token_id,
        title_typography_token_id,body_typography_token_id,content_gap_spacing_token_id,logo_expanded_brand_asset_id,logo_collapsed_brand_asset_id
      ) values (
        v_next_id,p_app_shell_code,v_clone.design_system_code,p_name,p_description,coalesce(nullif(btrim(p_version),''),'v0.1'),'CANDIDATO',
        v_clone.shell_component_token_code,v_clone.sidebar_expanded_component_token_code,v_clone.sidebar_collapsed_component_token_code,v_clone.sidebar_mobile_component_token_code,
        v_clone.topbar_component_token_code,v_clone.breadcrumb_component_token_code,v_clone.page_header_component_token_code,v_clone.page_background_token_name,v_clone.content_surface_token_name,
        v_clone.divider_token_name,v_clone.title_typography_token_name,v_clone.body_typography_token_name,v_clone.content_gap_token_name,v_clone.logo_expanded_asset_code,v_clone.logo_collapsed_asset_code,
        v_clone.sidebar_collapsible,v_clone.persist_user_preference,p_source_decision_id,p_source_decision_number,v_clone.design_system_id,
        v_clone.shell_component_token_id,v_clone.sidebar_expanded_component_token_id,v_clone.sidebar_collapsed_component_token_id,v_clone.sidebar_mobile_component_token_id,v_clone.topbar_component_token_id,
        v_clone.breadcrumb_component_token_id,v_clone.page_header_component_token_id,v_clone.page_background_color_token_id,v_clone.content_surface_color_token_id,v_clone.divider_color_token_id,
        v_clone.title_typography_token_id,v_clone.body_typography_token_id,v_clone.content_gap_spacing_token_id,v_clone.logo_expanded_brand_asset_id,v_clone.logo_collapsed_brand_asset_id
      ) returning * into v_after;
    else
      insert into lf_ops.app_shells(app_shell_id,app_shell_code,design_system_code,design_system_id,name,description,version,status,source_decision_id,source_decision_number)
      values(v_next_id,p_app_shell_code,p_design_system_code,v_ds_id,p_name,p_description,coalesce(nullif(btrim(p_version),''),'v0.1'),'CANDIDATO',p_source_decision_id,p_source_decision_number)
      returning * into v_after;
    end if;
  else
    if not found then raise exception 'LF_APP_SHELL_UPDATE_NOT_FOUND:%',p_app_shell_code; end if;
    if v_before.status<>'CANDIDATO' then raise exception 'LF_APP_SHELL_UPDATE_REQUIRES_CANDIDATO:%:%',p_app_shell_code,v_before.status; end if;
    update lf_ops.app_shells set design_system_code=p_design_system_code,design_system_id=v_ds_id,name=p_name,description=p_description,
      version=coalesce(nullif(btrim(p_version),''),version),status='CANDIDATO',source_decision_id=coalesce(p_source_decision_id,source_decision_id),
      source_decision_number=coalesce(p_source_decision_number,source_decision_number),updated_at=now()
    where app_shell_code=p_app_shell_code returning * into v_after;
  end if;
  return jsonb_build_object('result',case when upper(p_action_code)='APP_SHELL_CREATE' then 'APP_SHELL_CANDIDATE_CREATED' else 'APP_SHELL_CANDIDATE_UPDATED' end,
    'operation_code',v_expected,'execution_id',p_execution_id,'clone_from_shell_code',p_clone_from_shell_code,
    'before',case when upper(p_action_code)='APP_SHELL_UPDATE' then to_jsonb(v_before) else null end,'after',to_jsonb(v_after));
end;$fn$;

revoke all on function public.lf_app_shell_candidate_write_v1(text,text,text,text,text,text,text,text,bigint,text) from public,anon,authenticated;
grant execute on function public.lf_app_shell_candidate_write_v1(text,text,text,text,text,text,text,text,bigint,text) to service_role;

do $post$
declare c integer; r jsonb;
begin
  select count(*) into c from public.lf_operation_registry where operation_code in ('CREACION_APP_SHELL_LF','ACTUALIZACION_APP_SHELL_LF') and status='SANDBOX_ACTIVE';
  if c<>2 then raise exception 'LF_APP_SHELL_OPERATION_COUNT_FAIL:%',c; end if;
  select count(*) into c from public.lf_operation_steps where operation_code in ('CREACION_APP_SHELL_LF','ACTUALIZACION_APP_SHELL_LF') and active;
  if c<>14 then raise exception 'LF_APP_SHELL_STEP_COUNT_FAIL:%',c; end if;
  select count(*) into c from public.lf_router_action_registry where asset_type='APP_SHELL' and action_code in ('APP_SHELL_CREATE','APP_SHELL_UPDATE') and status='ACTIVE' and write_allowed;
  if c<>2 then raise exception 'LF_APP_SHELL_ROUTER_COUNT_FAIL:%',c; end if;
  r:=public.lf_router_resolve_v1('create governed APP_SHELL candidate','ADMIN_APP_SHELL','APP_SHELL_CREATE','APP_SHELL','ROUTER');
  if r->>'status'<>'READY_TO_EXECUTE' or r->>'operation_code'<>'CREACION_APP_SHELL_LF' then raise exception 'LF_APP_SHELL_ROUTER_POSTCHECK_FAIL:%',r; end if;
  if not exists(select 1 from lf_ops.app_shells where app_shell_code='B2B_APP_SHELL') then raise exception 'LF_APP_SHELL_CLONE_SOURCE_MISSING'; end if;
end;$post$;
