-- Isolate rule exploration materialization from shared rule<->screen relation mutation.
-- Keeps historical migration 20260913184218 intact; this corrective migration removes the cross-domain write.
-- No production/runtime/Golden/VIGENTE promotion.

insert into public.lf_operation_execution(
 execution_id,operation_code,target_type,target_code,status,manifest,created_by_execution_id,updated_by_execution_id)
values(
 'EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-ISOLATION-20260913-001',
 'VULNERABILITY_COVERAGE_REPAIR_LF','OPERATION_PROTOCOL_REPAIR','MATERIALIZACION_REGLA_EXPLORADA_LF','IN_PROGRESS',
 '{"mode":"RULE_EXPLORATION_BRIDGE_ISOLATION","governance_bootstrap":true,"bootstrap_operation_code":"MATERIALIZACION_REGLA_EXPLORADA_LF","bootstrap_status_ceiling":"SANDBOX_ACTIVE","production_allowed":false,"runtime_activation":false}'::jsonb,
 'EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-ISOLATION-20260913-001',
 'EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-ISOLATION-20260913-001');

update public.lf_operation_registry
set source_paths='["public.lf_input_exploration_records","lf_ops.reglas","public.lf_rule_exploration_prepare_v1","public.lf_rule_exploration_materialize_candidate_v1"]'::jsonb,
    notes='Governed bridge from sparse exploration to canonical CANDIDATO through child rule operation. Screen relation mutation is intentionally excluded and must be handled by a separate governed capability.',
    updated_by_execution_id='EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-ISOLATION-20260913-001',
    updated_at=now()
where operation_code='MATERIALIZACION_REGLA_EXPLORADA_LF';

update public.lf_operation_contracts
set required_before_write='["ekb_preflight","consumer_allowlist","source_provenance","input_complete","exact_code_check","screen_governance_if_applicable","execution_bound"]'::jsonb,
    allowed='{"child_rule_operation":true,"candidate_state":"CANDIDATO","consume_exploration":true,"idempotent":true,"semantic_similarity_authority":false,"screen_relation_mutation":false}'::jsonb,
    blocked='{"vigente_direct_update":true,"automatic_promotion":true,"runtime_activation":true,"production_promotion":true,"screen_relation_mutation":true,"relation_delete":true,"invented_consumer":true}'::jsonb,
    required_after_write='["candidate_readback","exploration_CONSUMED","screen_relation_NOT_MUTATED","no_promotion","execution_trace"]'::jsonb,
    updated_by_execution_id='EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-ISOLATION-20260913-001',
    updated_at=now()
where operation_code='MATERIALIZACION_REGLA_EXPLORADA_LF';

update public.lf_operation_steps
set active=false,
    updated_by_execution_id='EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-ISOLATION-20260913-001',
    updated_at=now()
where operation_code='MATERIALIZACION_REGLA_EXPLORADA_LF'
  and step_id='relation_write';

update public.lf_operation_step_contracts
set status='SUPERSEDED_ISOLATION',
    notes='Superseded: rule<->screen relation mutation moved out of rule exploration bridge.',
    updated_by_execution_id='EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-ISOLATION-20260913-001',
    updated_at=now()
where operation_code='MATERIALIZACION_REGLA_EXPLORADA_LF'
  and step_id='relation_write';

update public.lf_operation_step_judge_bindings
set status='SUPERSEDED_ISOLATION',
    updated_by_execution_id='EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-ISOLATION-20260913-001',
    updated_at=now()
where operation_code='MATERIALIZACION_REGLA_EXPLORADA_LF'
  and step_id='relation_write';

update public.lf_operation_step_contracts
set required_evidence_keys='["candidate_row","exploration_status","screen_relation_status","no_promotion"]'::jsonb,
    output_payload='["candidate_row","exploration_status","screen_relation_status","no_promotion"]'::jsonb,
    notes='Final readback for rule-only exploration bridge. Shared screen relation is not mutated here.',
    updated_by_execution_id='EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-ISOLATION-20260913-001',
    updated_at=now()
where operation_code='MATERIALIZACION_REGLA_EXPLORADA_LF'
  and step_id='readback_consume';

update public.lf_operation_step_judge_bindings
set required_evidence_keys='["candidate_row","exploration_status","screen_relation_status","no_promotion"]'::jsonb,
    updated_by_execution_id='EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-ISOLATION-20260913-001',
    updated_at=now()
where operation_code='MATERIALIZACION_REGLA_EXPLORADA_LF'
  and step_id='readback_consume';

create or replace function public.lf_rule_exploration_materialize_candidate_v1(
 p_exploration_id uuid,p_completed_payload jsonb default '{}'::jsonb,p_consumer text default 'CONTEXT_PACK',p_actor_execution_id text default null)
returns jsonb language plpgsql security invoker set search_path=pg_catalog,public,programacion,lf_ops as $f$
declare
 r public.lf_input_exploration_records%rowtype; c jsonb; f jsonb; m jsonb; code text; n int:=0; st text;
 act text; op text; tm text; sg jsonb; modej jsonb; actor text; req jsonb; sha text; bx text; child text; idem text;
 base jsonb:=jsonb_build_object('assertions_checked',jsonb_build_array('required_evidence_present'),'hard_fails_checked','[]'::jsonb,'blocking_findings','[]'::jsonb,'return_to_worker_reasons','[]'::jsonb);
 wr jsonb; rr jsonb; rev int; trans boolean:=false; reason text; cfg jsonb; origin text; relation_status text;
begin
 if p_completed_payload is null or jsonb_typeof(p_completed_payload)<>'object' then raise exception 'LF_RULE_EXPLORATION_COMPLETED_PAYLOAD_INVALID'; end if;
 select * into r from public.lf_input_exploration_records where exploration_id=p_exploration_id for update;
 if not found or r.asset_type<>'REGLA' then raise exception 'LF_RULE_EXPLORATION_NOT_FOUND:%',p_exploration_id; end if;
 if r.governance_status='CONSUMED' then return jsonb_build_object('result','RULE_EXPLORATION_ALREADY_CONSUMED','exploration_id',r.exploration_id,'canonical_rule_code',r.canonical_rule_code,'revision',r.revision,'screen_relation_status',case when r.source_pantalla_id is null then 'NOT_APPLICABLE' else 'PENDING_SEPARATE_CAPABILITY' end); end if;
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
  jsonb_build_object('bridge_contract','LF_RULE_EXPLORATION_BRIDGE_V1','consumer',p_consumer,'production_allowed',false,'runtime_activation',false,'promotion_authorized',false,'screen_relation_mutation',false));
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
 relation_status:=case when r.source_pantalla_id is null then 'NOT_APPLICABLE' else 'PENDING_SEPARATE_CAPABILITY' end;
 rev:=r.revision+1;
 update public.lf_input_exploration_records set target_code=code,partial_payload=f,missing_fields='[]'::jsonb,governance_status='CONSUMED',canonical_rule_code=code,revision=rev,updated_by_execution_id=bx,updated_at=now() where exploration_id=r.exploration_id;
 insert into public.lf_input_exploration_events(exploration_id,revision,task_mode,delta_payload,snapshot_payload,source_context_delta,governance_status,created_by_execution_id)
 values(r.exploration_id,rev,r.task_mode,p_completed_payload,f,jsonb_build_object('screen_relation_status',relation_status),'CONSUMED',bx);
 insert into public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_ref,evidence_payload,created_by_execution_id)
 values(bx,50,'readback_consume','PASS_CLEAN','RULE_EXP/'||r.exploration_id||'/DONE',base||jsonb_build_object('candidate_row',rr,'exploration_status','CONSUMED','screen_relation_status',relation_status,'no_promotion',true),bx);
 update public.lf_operation_execution set status='COMPLETED',completed_at=now(),manifest=manifest||jsonb_build_object('result','RULE_EXPLORATION_BRIDGE_COMPLETED','canonical_rule_code',code,'child_execution_id',child,'screen_relation_status',relation_status),updated_by_execution_id=bx where execution_id=bx;
 return jsonb_build_object('result','RULE_EXPLORATION_MATERIALIZED_CANDIDATE','exploration_id',r.exploration_id,'canonical_rule_code',code,'bridge_execution_id',bx,'candidate_operation_execution_id',child,'screen_relation_status',relation_status,'governance_status','CONSUMED','production_authorized',false,'runtime_activation',false,'promotion_authorized',false);
end $f$;

revoke all on function public.lf_rule_exploration_materialize_candidate_v1(uuid,jsonb,text,text) from public,anon,authenticated;
grant execute on function public.lf_rule_exploration_materialize_candidate_v1(uuid,jsonb,text,text) to service_role;

do $p$
declare v_active_relation_steps integer; v_source_paths jsonb; v_allowed jsonb; v_blocked jsonb;
begin
 select count(*) into v_active_relation_steps
 from public.lf_operation_steps
 where operation_code='MATERIALIZACION_REGLA_EXPLORADA_LF' and step_id='relation_write' and active;
 if v_active_relation_steps<>0 then raise exception 'LF_RULE_BRIDGE_ISOLATION_RELATION_STEP_STILL_ACTIVE:%',v_active_relation_steps; end if;

 select source_paths into v_source_paths from public.lf_operation_registry where operation_code='MATERIALIZACION_REGLA_EXPLORADA_LF';
 if v_source_paths ? 'lf_ops.reglas_pantallas' then raise exception 'LF_RULE_BRIDGE_ISOLATION_SOURCE_PATH_STILL_SHARED'; end if;

 select allowed,blocked into v_allowed,v_blocked from public.lf_operation_contracts where operation_code='MATERIALIZACION_REGLA_EXPLORADA_LF';
 if coalesce((v_allowed->>'screen_relation_mutation')::boolean,true) is not false then raise exception 'LF_RULE_BRIDGE_ISOLATION_ALLOWED_RELATION_MUTATION'; end if;
 if coalesce((v_blocked->>'screen_relation_mutation')::boolean,false) is not true then raise exception 'LF_RULE_BRIDGE_ISOLATION_MISSING_BLOCK'; end if;
end $p$;

update public.lf_operation_execution
set status='COMPLETED',
    completed_at=now(),
    manifest=manifest||'{"result":"RULE_EXPLORATION_BRIDGE_ISOLATED","screen_relation_mutation":false}'::jsonb,
    updated_by_execution_id='EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-ISOLATION-20260913-001'
where execution_id='EXEC-BOOTSTRAP-MATERIALIZACION-REGLA-EXPLORADA-ISOLATION-20260913-001';
