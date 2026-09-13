-- LF governed bridge: rule exploration -> candidate. UI Architect is the sole mode-pattern reference.
-- No production/runtime/Golden/VIGENTE promotion.

insert into public.lf_operation_execution(
 execution_id,operation_code,target_type,target_code,status,manifest,created_by_execution_id,updated_by_execution_id)
values(
 'EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-LF-20260913-001',
 'VULNERABILITY_COVERAGE_REPAIR_LF','OPERATION_PROTOCOL_REPAIR','MATERIALIZACION_REGLA_EXPLORADA_LF','IN_PROGRESS',
 '{"governance_bootstrap":true,"bootstrap_operation_code":"MATERIALIZACION_REGLA_EXPLORADA_LF","bootstrap_status_ceiling":"SANDBOX_ACTIVE","production_allowed":false,"runtime_activation":false}'::jsonb,
 'EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-LF-20260913-001',
 'EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-LF-20260913-001');

insert into public.lf_operation_registry(
 operation_code,version,status,source_model,source_repo,source_paths,notes,operation_family,operation_domain,operation_type,applies_to_asset_type,created_by_execution_id)
values(
 'MATERIALIZACION_REGLA_EXPLORADA_LF','v0.1','SANDBOX_ACTIVE','GOVERNED_DB_OPERATION',
 'cristhianlujan/claude-persona-lf-patch',
 '["public.lf_input_exploration_records","lf_ops.reglas","lf_ops.reglas_pantallas","public.lf_rule_exploration_prepare_v1","public.lf_rule_exploration_materialize_candidate_v1"]'::jsonb,
 'Governed bridge from sparse exploration to canonical CANDIDATO through child rule operation; optional screen relation insert; no promotion/runtime.',
 'RULE_OPERATIONS','RULE_GOVERNANCE','MATERIALIZE_EXPLORATION','REGLA',
 'EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-LF-20260913-001');

insert into public.lf_operation_contracts(
 operation_code,contract_code,contract_path,contract_sha,required_before_write,allowed,blocked,required_after_write,status,created_by_execution_id)
values(
 'MATERIALIZACION_REGLA_EXPLORADA_LF','CONTRACT-MATERIALIZACION_REGLA_EXPLORADA_LF-v0.1',
 'supabase://public/lf_operation_contracts/MATERIALIZACION_REGLA_EXPLORADA_LF',null,
 '["ekb_preflight","consumer_allowlist","source_provenance","input_complete","exact_code_check","screen_governance_if_applicable","execution_bound"]'::jsonb,
 '{"child_rule_operation":true,"candidate_state":"CANDIDATO","screen_relation_insert":true,"consume_exploration":true,"idempotent":true,"semantic_similarity_authority":false}'::jsonb,
 '{"vigente_direct_update":true,"automatic_promotion":true,"runtime_activation":true,"production_promotion":true,"relation_delete":true,"invented_consumer":true}'::jsonb,
 '["candidate_readback","screen_relation_readback_if_applicable","exploration_CONSUMED","no_promotion","execution_trace"]'::jsonb,
 'ACTIVE_ENFORCEMENT','EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-LF-20260913-001');

with s(o,id,e,n) as (values
 (10,'preflight','ekb_refs,consumer,source_provenance,execution_binding','prepare'),
 (20,'prepare','rule_code,category,exact_code_existing_count,screen_gate,input_complete','candidate_child'),
 (30,'candidate_child','child_execution_id,write_result,estado','relation_write'),
 (40,'relation_write','screen_relation_applicable,relation_result,no_delete','readback_consume'),
 (50,'readback_consume','candidate_row,exploration_status,no_promotion','readback_consume'))
insert into public.lf_operation_steps(operation_code,step_order,step_id,required,evidence_required,source_path,source_sha,active,execution_order,created_by_execution_id)
select 'MATERIALIZACION_REGLA_EXPLORADA_LF',o,id,true,e,
 'supabase://public/lf_operation_step_contracts/MATERIALIZACION_REGLA_EXPLORADA_LF/'||id,null,true,o,
 'EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-LF-20260913-001' from s;

with s(o,id,k,n) as (values
 (10,'preflight','["ekb_refs","consumer","source_provenance","execution_binding"]'::jsonb,'prepare'),
 (20,'prepare','["rule_code","category","exact_code_existing_count","screen_gate","input_complete"]'::jsonb,'candidate_child'),
 (30,'candidate_child','["child_execution_id","write_result","estado"]'::jsonb,'relation_write'),
 (40,'relation_write','["screen_relation_applicable","relation_result","no_delete"]'::jsonb,'readback_consume'),
 (50,'readback_consume','["candidate_row","exploration_status","no_promotion"]'::jsonb,null))
insert into public.lf_operation_step_contracts(
 operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,resolver_ref,output_payload,
 pass_condition,block_condition,blocking_code,mini_judge_code,required_evidence_keys,next_if_pass,next_if_blocked,status,notes,execution_sql,fail_condition,created_by_execution_id)
select 'MATERIALIZACION_REGLA_EXPLORADA_LF',id,o,o,'CONTRACT-MATERIALIZACION_REGLA_EXPLORADA_LF-v0.1',
 id||' governed exploration bridge step.','{}'::jsonb,'RULE_EXPLORATION_BRIDGE_DETERMINISTIC',k,
 '{"required_evidence_present":true}'::jsonb,'{"missing_required_evidence":true}'::jsonb,
 'BLOCK_MATERIALIZACION_REGLA_EXPLORADA_'||upper(id),'MINI_JUDGE_MATERIALIZACION_REGLA_EXPLORADA_LF_V1',
 k,n,'readback_consume','ACTIVE_ENFORCEMENT','Fail closed.',null,'{}'::jsonb,
 'EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-LF-20260913-001' from s;

insert into public.lf_operation_judges(
 operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,created_by_execution_id)
values(
 'MATERIALIZACION_REGLA_EXPLORADA_LF','MINI_JUDGE_MATERIALIZACION_REGLA_EXPLORADA_LF_V1',
 'supabase://public/lf_operation_judges/MATERIALIZACION_REGLA_EXPLORADA_LF',null,
 '{"required_evidence_present":true}'::jsonb,'{"missing_required_evidence":true}'::jsonb,
 '["PASS_CLEAN","BLOCKED_BY_ENFORCEMENT","RETURN_TO_WORKER"]'::jsonb,'ACTIVE_ENFORCEMENT',
 'EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-LF-20260913-001');

with s(o,id,k) as (values
 (10,'preflight','["ekb_refs","consumer","source_provenance","execution_binding"]'::jsonb),
 (20,'prepare','["rule_code","category","exact_code_existing_count","screen_gate","input_complete"]'::jsonb),
 (30,'candidate_child','["child_execution_id","write_result","estado"]'::jsonb),
 (40,'relation_write','["screen_relation_applicable","relation_result","no_delete"]'::jsonb),
 (50,'readback_consume','["candidate_row","exploration_status","no_promotion"]'::jsonb))
insert into public.lf_operation_step_judge_bindings(
 operation_code,step_order,step_id,judge_code,clean_result_value,blocked_result_value,return_result_value,required_evidence_keys,status,created_by_execution_id)
select 'MATERIALIZACION_REGLA_EXPLORADA_LF',o,id,'MINI_JUDGE_MATERIALIZACION_REGLA_EXPLORADA_LF_V1',
 'PASS_CLEAN','BLOCKED_BY_ENFORCEMENT','RETURN_TO_WORKER',k,'ACTIVE_ENFORCEMENT',
 'EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-LF-20260913-001' from s;

create or replace function public.lf_rule_exploration_prepare_v1(p_exploration_id uuid,p_consumer text default 'CONTEXT_PACK')
returns jsonb language plpgsql stable security invoker set search_path=pg_catalog,public,programacion,lf_ops as $f$
declare r public.lf_input_exploration_records%rowtype; c jsonb; m jsonb; code text; n int:=0; st text; sg jsonb; src boolean;
begin
 select * into r from public.lf_input_exploration_records where exploration_id=p_exploration_id;
 if not found or r.asset_type<>'REGLA' then raise exception 'LF_RULE_EXPLORATION_NOT_FOUND:%',p_exploration_id; end if;
 select x.especificacion into c from programacion.contratos x join programacion.versiones_agente v on v.id=x.version_id join programacion.agentes a on a.id=v.agente_id
 where a.agente_codigo='INPUT_GOVERNANCE_AGENT' and x.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT' and x.estado='defined' and x.fail_closed order by x.version_id desc limit 1;
 if c is null then raise exception 'INPUT_GOVERNANCE_EXECUTION_CONTRACT_NOT_RESOLVABLE'; end if;
 if not exists(select 1 from jsonb_array_elements_text(c->'allowed_consumers') z(v) where z.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
 code:=coalesce(nullif(btrim(r.target_code),''),nullif(btrim(r.partial_payload->>'codigo'),''));
 select coalesce(jsonb_agg(k order by o),'[]'::jsonb) into m from (values(1,'codigo'),(2,'categoria'),(3,'titulo'),(4,'descripcion')) q(o,k) where nullif(btrim(coalesce(r.partial_payload->>k,'')),'') is null;
 src:=r.source_pantalla_id is not null or r.source_context<>'{}'::jsonb;
 if code is not null then select count(*),max(estado) into n,st from lf_ops.reglas where codigo=code; end if;
 sg:=case when r.source_pantalla_id is null then jsonb_build_object('status','NOT_APPLICABLE_NON_SCREEN_SOURCE') else public.fn_input_governance_execute(r.source_pantalla_id,p_consumer) end;
 return jsonb_build_object(
  'bridge_contract','LF_RULE_EXPLORATION_BRIDGE_V1','exploration_id',r.exploration_id,'consumer',p_consumer,'rule_code',code,
  'status',case
    when r.governance_status='CONSUMED' then 'ALREADY_CONSUMED'
    when r.governance_status<>'READY_FOR_INPUT_GOVERNANCE' then 'NOT_READY_FOR_INPUT_GOVERNANCE'
    when not src then 'SOURCE_PROVENANCE_REQUIRED'
    when jsonb_array_length(m)>0 then 'INPUT_GOVERNANCE_COMPLETION_REQUIRED'
    when r.source_pantalla_id is not null and sg->>'status' in ('CURATOR_RUNTIME_REQUIRED','VALIDATOR_RUNTIME_REQUIRED') then 'INPUT_GOVERNANCE_RUNTIME_REQUIRED'
    when r.source_pantalla_id is not null and sg->>'status'='HUMAN_DECISION_REQUIRED' then 'HUMAN_DECISION_REQUIRED'
    when r.source_pantalla_id is not null and sg->>'status'<>'READY' then 'SCREEN_INPUT_GOVERNANCE_BLOCKED'
    when n=1 and st<>'CANDIDATO' then 'EXISTING_RULE_NOT_CANDIDATO'
    else 'READY_FOR_CANDIDATE_MATERIALIZATION' end,
  'missing_fields',m,'source_provenance_present',src,'source_pantalla_id',r.source_pantalla_id,'screen_input_governance',sg,
  'exact_code_existing_count',n,'exact_code_existing_state',st,'semantic_similarity_is_authority',false,
  'canonical_write_performed',false,'promotion_authorized',false,'production_authorized',false,'runtime_activation',false);
end $f$;
revoke all on function public.lf_rule_exploration_prepare_v1(uuid,text) from public,anon,authenticated;
grant execute on function public.lf_rule_exploration_prepare_v1(uuid,text) to service_role;

create or replace function public.lf_rule_exploration_materialize_candidate_v1(
 p_exploration_id uuid,p_completed_payload jsonb default '{}'::jsonb,p_consumer text default 'CONTEXT_PACK',p_actor_execution_id text default null)
returns jsonb language plpgsql security invoker set search_path=pg_catalog,public,programacion,lf_ops as $f$
declare
 r public.lf_input_exploration_records%rowtype; c jsonb; f jsonb; m jsonb; code text; n int:=0; st text;
 act text; op text; tm text; sg jsonb; modej jsonb; actor text; req jsonb; sha text; bx text; child text; idem text;
 base jsonb:=jsonb_build_object('assertions_checked',jsonb_build_array('required_evidence_present'),'hard_fails_checked','[]'::jsonb,'blocking_findings','[]'::jsonb,'return_to_worker_reasons','[]'::jsonb);
 wr jsonb; rr jsonb; rel jsonb; rev int; trans boolean:=false; reason text; cfg jsonb; origin text;
begin
 if p_completed_payload is null or jsonb_typeof(p_completed_payload)<>'object' then raise exception 'LF_RULE_EXPLORATION_COMPLETED_PAYLOAD_INVALID'; end if;
 select * into r from public.lf_input_exploration_records where exploration_id=p_exploration_id for update;
 if not found or r.asset_type<>'REGLA' then raise exception 'LF_RULE_EXPLORATION_NOT_FOUND:%',p_exploration_id; end if;
 if r.governance_status='CONSUMED' then return jsonb_build_object('result','RULE_EXPLORATION_ALREADY_CONSUMED','exploration_id',r.exploration_id,'canonical_rule_code',r.canonical_rule_code,'revision',r.revision); end if;
 if r.governance_status<>'READY_FOR_INPUT_GOVERNANCE' then raise exception 'LF_RULE_EXPLORATION_NOT_READY:%',r.governance_status; end if;
 if r.source_pantalla_id is null and r.source_context='{}'::jsonb then raise exception 'LF_RULE_EXPLORATION_SOURCE_PROVENANCE_REQUIRED'; end if;
 select x.especificacion into c from programacion.contratos x join programacion.versiones_agente v on v.id=x.version_id join programacion.agentes a on a.id=v.agente_id
 where a.agente_codigo='INPUT_GOVERNANCE_AGENT' and x.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT' and x.estado='defined' and x.fail_closed order by x.version_id desc limit 1;
 if c is null then raise exception 'INPUT_GOVERNANCE_EXECUTION_CONTRACT_NOT_RESOLVABLE'; end if;
 if not exists(select 1 from jsonb_array_elements_text(c->'allowed_consumers') z(v) where z.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
 f:=r.partial_payload||p_completed_payload; code:=coalesce(nullif(btrim(r.target_code),''),nullif(btrim(f->>'codigo'),''));
 select coalesce(jsonb_agg(k order by o),'[]'::jsonb) into m from (values(1,'codigo'),(2,'categoria'),(3,'titulo'),(4,'descripcion')) q(o,k) where nullif(btrim(coalesce(f->>k,'')),'') is null;
 if jsonb_array_length(m)>0 then raise exception 'LF_RULE_EXPLORATION_COMPLETION_REQUIRED:%',m; end if;
 if r.source_pantalla_id is not null then sg:=public.fn_input_governance_execute(r.source_pantalla_id,p_consumer); if sg->>'status'<>'READY' then raise exception 'LF_RULE_EXPLORATION_SCREEN_GOVERNANCE_NOT_READY:%',sg->>'status'; end if; else sg:=jsonb_build_object('status','NOT_APPLICABLE_NON_SCREEN_SOURCE'); end if;
 select count(*),max(estado) into n,st from lf_ops.reglas where codigo=code;
 if n=0 then act:='REGLA_CREATE';op:='CREACION_REGLA_LF';tm:='CREATE_NEW';
 elsif n=1 and st='CANDIDATO' then act:='REGLA_UPDATE';op:='ACTUALIZACION_REGLA_LF';tm:='REMEDIATE_EXISTING';
 elsif n=1 then raise exception 'LF_RULE_EXPLORATION_EXISTING_RULE_NOT_CANDIDATO:%:%',code,st;
 else raise exception 'LF_RULE_EXPLORATION_EXACT_CODE_DUPLICATE_STATE:%:%',code,n; end if;
 modej:=public.lf_resolve_operation_mode_v1(op,tm,'GOVERNED');
 if modej->>'status'<>'READY' or coalesce((modej->>'write_allowed')::boolean,false) is not true or modej->>'destination_kind'<>'CANONICAL_CANDIDATE' then raise exception 'LF_RULE_EXPLORATION_GOVERNED_MODE_NOT_READY:%',modej; end if;
 actor:=coalesce(nullif(btrim(p_actor_execution_id),''),r.updated_by_execution_id,r.created_by_execution_id);
 if not exists(select 1 from public.lf_operation_execution where execution_id=actor) then raise exception 'LF_RULE_EXPLORATION_ACTOR_EXECUTION_NOT_FOUND:%',coalesce(actor,'<NULL>'); end if;
 bx:='EXEC-REG-BRIDGE-'||replace(r.exploration_id::text,'-','')||'-R'||r.revision;
 req:=jsonb_build_object('exploration_id',r.exploration_id,'revision',r.revision,'consumer',p_consumer,'rule_code',code,'screen',r.source_pantalla_id,'payload',f);
 sha:=encode(extensions.digest(convert_to(req::text,'UTF8'),'sha256'),'hex');
 perform public.fn_lf_operation_reserve_execution_v1(bx,'MATERIALIZACION_REGLA_EXPLORADA_LF','REGLA_EXPLORATION',r.exploration_id::text,
  'RULE_EXPLORATION_BRIDGE:'||r.exploration_id||':R'||r.revision,sha,actor,null,null,
  jsonb_build_object('bridge_contract','LF_RULE_EXPLORATION_BRIDGE_V1','consumer',p_consumer,'production_allowed',false,'runtime_activation',false,'promotion_authorized',false));
 insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,created_by_execution_id) values
 (bx,10,'preflight','PASS_CLEAN','RULE_EXP/'||r.exploration_id||'/PRE',base||jsonb_build_object('ekb_refs',jsonb_build_array('INPUT-GOV-CONSUMER-BINDING-001','AUD-018','GOV-024'),'consumer',p_consumer,'source_provenance',coalesce(r.source_context,'{}'::jsonb)||jsonb_build_object('pantalla_id',r.source_pantalla_id),'execution_binding',bx),bx),
 (bx,20,'prepare','PASS_CLEAN','RULE_EXP/'||r.exploration_id||'/PREP',base||jsonb_build_object('rule_code',code,'category',f->>'categoria','exact_code_existing_count',n,'screen_gate',sg,'input_complete',true),bx);
 child:='EXEC-REG-EXP-'||replace(r.exploration_id::text,'-','')||'-R'||r.revision; idem:='RULE_EXPLORATION:'||r.exploration_id||':R'||r.revision||':CANDIDATE_V1';
 perform public.fn_lf_operation_reserve_execution_v1(child,op,'REGLA',code,idem,sha,bx,null,null,
  jsonb_build_object('mode','RULE_EXPLORATION_TO_CANDIDATE','bridge_execution_id',bx,'exploration_id',r.exploration_id,'production_allowed',false,'runtime_activation',false,'promotion_authorized',false));
 insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,created_by_execution_id) values
 (child,10,'ekb_preflight','PASS_CLEAN','RULE_EXP/'||r.exploration_id||'/EKB',base||jsonb_build_object('ekb_refs',jsonb_build_array('INPUT-GOV-CONSUMER-BINDING-001','AUD-018','GOV-024'),'execution_binding',child),child),
 (child,20,'classify','PASS_CLEAN','RULE_EXP/'||r.exploration_id||'/CLASS',base||jsonb_build_object('rule_code',code,'category',f->>'categoria','candidate_classification',act),child),
 (child,30,'existing_check','PASS_CLEAN','RULE_EXP/'||r.exploration_id||'/EXISTS',base||jsonb_build_object('rule_code',code,'existing_count',n,'expected_existence',case when n=0 then 'MISSING' else 'ONE_CANDIDATO' end),child),
 (child,40,'destination_validate','PASS_CLEAN','RULE_EXP/'||r.exploration_id||'/DEST',base||jsonb_build_object('destination_schema','lf_ops','destination_table','reglas','unique_code_guard',true),child);
 if f ? 'es_transversal' then begin trans:=(f->>'es_transversal')::boolean; exception when invalid_text_representation then raise exception 'LF_RULE_EXPLORATION_ES_TRANSVERSAL_INVALID:%',f->>'es_transversal'; end; end if;
 reason:=nullif(btrim(f->>'razon'),''); cfg:=case when f?'valor_config' then f->'valor_config' else null end; origin:=coalesce(nullif(btrim(f->>'origen'),''),case when r.source_pantalla_id is null then 'GOVERNED_EXPLORATION' else 'SCREEN_EXPLORATION' end);
 wr:=public.lf_regla_candidate_write_v1(child,act,code,f->>'categoria',f->>'titulo',f->>'descripcion',reason,cfg,trans,origin);
 insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,created_by_execution_id) values
 (child,50,'candidate_write','PASS_CLEAN','RULE_EXP/'||r.exploration_id||'/WRITE',base||jsonb_build_object('execution_id',child,'rule_code',code,'write_result',wr->>'result','estado','CANDIDATO'),child);
 select to_jsonb(x) into rr from lf_ops.reglas x where x.codigo=code;
 if rr is null or rr->>'estado'<>'CANDIDATO' then raise exception 'LF_RULE_EXPLORATION_CANDIDATE_READBACK_FAILED:%',code; end if;
 insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,created_by_execution_id) values
 (child,60,'readback','PASS_CLEAN','RULE_EXP/'||r.exploration_id||'/READ',base||jsonb_build_object('rule_code',code,'readback_row',rr,'estado','CANDIDATO'),child),
 (child,70,'trace_close','PASS_CLEAN','RULE_EXP/'||r.exploration_id||'/CLOSE',base||jsonb_build_object('execution_id',child,'operation_code',op,'trace_ref','exploration:'||r.exploration_id,'no_promotion',true),child);
 update public.lf_operation_execution set status='COMPLETED',completed_at=now(),manifest=manifest||jsonb_build_object('result','RULE_EXPLORATION_MATERIALIZED_CANDIDATE','canonical_rule_code',code),updated_by_execution_id=child where execution_id=child;
 insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,created_by_execution_id)
 values(bx,30,'candidate_child','PASS_CLEAN','RULE_EXP/'||r.exploration_id||'/CHILD',base||jsonb_build_object('child_execution_id',child,'write_result',wr->>'result','estado','CANDIDATO'),bx);
 if r.source_pantalla_id is not null then
   insert into lf_ops.reglas_pantallas(regla_id,pantalla_id,nota) values((rr->>'id')::int,r.source_pantalla_id,'Origen exploración gobernada '||r.exploration_id)
   on conflict(regla_id,pantalla_id) do nothing;
   select to_jsonb(rp) into rel from lf_ops.reglas_pantallas rp where rp.regla_id=(rr->>'id')::int and rp.pantalla_id=r.source_pantalla_id;
   if rel is null then raise exception 'LF_RULE_EXPLORATION_RELATION_READBACK_FAILED'; end if;
 else rel:=null; end if;
 insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,created_by_execution_id)
 values(bx,40,'relation_write','PASS_CLEAN','RULE_EXP/'||r.exploration_id||'/REL',base||jsonb_build_object('screen_relation_applicable',r.source_pantalla_id is not null,'relation_result',coalesce(rel,'{}'::jsonb),'no_delete',true),bx);
 rev:=r.revision+1;
 update public.lf_input_exploration_records set target_code=code,partial_payload=f,missing_fields='[]'::jsonb,governance_status='CONSUMED',canonical_rule_code=code,revision=rev,updated_by_execution_id=bx,updated_at=now() where exploration_id=r.exploration_id;
 insert into public.lf_input_exploration_events(exploration_id,revision,task_mode,delta_payload,snapshot_payload,source_context_delta,governance_status,created_by_execution_id)
 values(r.exploration_id,rev,r.task_mode,p_completed_payload,f,'{}'::jsonb,'CONSUMED',bx);
 insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,created_by_execution_id)
 values(bx,50,'readback_consume','PASS_CLEAN','RULE_EXP/'||r.exploration_id||'/DONE',base||jsonb_build_object('candidate_row',rr,'exploration_status','CONSUMED','no_promotion',true),bx);
 update public.lf_operation_execution set status='COMPLETED',completed_at=now(),manifest=manifest||jsonb_build_object('result','RULE_EXPLORATION_BRIDGE_COMPLETED','canonical_rule_code',code,'child_execution_id',child,'screen_relation',rel),updated_by_execution_id=bx where execution_id=bx;
 return jsonb_build_object('result','RULE_EXPLORATION_MATERIALIZED_CANDIDATE','exploration_id',r.exploration_id,'canonical_rule_code',code,'bridge_execution_id',bx,'candidate_operation_execution_id',child,'screen_relation',rel,'governance_status','CONSUMED','production_authorized',false,'runtime_activation',false,'promotion_authorized',false);
end $f$;
revoke all on function public.lf_rule_exploration_materialize_candidate_v1(uuid,jsonb,text,text) from public,anon,authenticated;
grant execute on function public.lf_rule_exploration_materialize_candidate_v1(uuid,jsonb,text,text) to service_role;

create or replace view public.v_lf_rule_exploration_input_queue with(security_invoker=true) as
select e.exploration_id,e.governance_status,e.task_mode,e.target_code,e.source_pantalla_id,p.codigo source_screen_code,e.partial_payload,e.missing_fields,e.source_context,e.revision,e.created_at,e.updated_at
from public.lf_input_exploration_records e left join lf_ops.pantallas p on p.id=e.source_pantalla_id
where e.asset_type='REGLA' and e.governance_status in('OPEN','READY_FOR_INPUT_GOVERNANCE');
revoke all on public.v_lf_rule_exploration_input_queue from public,anon,authenticated;
grant select on public.v_lf_rule_exploration_input_queue to service_role;

do $p$ declare n int; begin
 select count(*) into n from public.lf_operation_steps where operation_code='MATERIALIZACION_REGLA_EXPLORADA_LF' and active;
 if n<>5 then raise exception 'LF_RULE_EXPLORATION_BRIDGE_STEP_COUNT:%',n; end if;
 if to_regprocedure('public.lf_rule_exploration_prepare_v1(uuid,text)') is null or to_regprocedure('public.lf_rule_exploration_materialize_candidate_v1(uuid,jsonb,text,text)') is null then raise exception 'LF_RULE_EXPLORATION_BRIDGE_FUNCTION_MISSING'; end if;
end $p$;
