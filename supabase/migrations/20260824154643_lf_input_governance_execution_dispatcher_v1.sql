-- LF Input Governance single-call dispatcher. Separate from readiness contract 5.12.
insert into programacion.contratos(version_id,contrato_codigo,tipo,nombre,descripcion,productor_componente_id,consumidor_componente_id,especificacion,fail_closed,estado)
select 19,'INPUT_GOVERNANCE_EXECUTION_CONTRACT','EXECUTION_INTERFACE','Input Governance single-call execution contract',
'Fail-closed entrypoint. Reuses only COMPLETED/current runs; stale or absent runs require Curator/Validator materialization. EKB checkpoints are mandatory. No auto-canon, promotion or production.',
(select id from programacion.componentes where version_id=19 and componente_codigo='INPUT_CURATOR'),null,
jsonb_build_object(
 'schema_version',1,'contract_revision','1.0','execution_contract','INPUT_GOVERNANCE_EXECUTION_V1',
 'decision_authority','DEC-INPUT-GOV-EXEC-EKB-001','entrypoint','programacion.fn_input_governance_execute(integer,text)',
 'allowed_consumers',jsonb_build_array('STORY_CREATOR','CONTEXT_PACK','MANUAL'),
 'current_run_policy','REUSE_COMPLETED_CURRENT_ONLY','stale_or_absent_policy','MATERIALIZATION_REQUIRED_FAIL_CLOSED',
 'new_run_materialization','CURATOR_VALIDATOR_WORKER_REQUIRED','ekb_checkpoints',jsonb_build_array('PRE_EXECUTION','PRE_CURATOR','PRE_VALIDATOR','PRE_STORY_GATE','PRE_CONTEXT_MANIFEST','CLOSE_EKB'),
 'ekb_occurrence_policy',jsonb_build_object('new_verified_error','GOVERNED_EKB_INSERT','verified_recurrence','UPDATE_EXISTING','unverified_suspicion','PROPOSAL_OR_BLOCKER','no_error','NO_WRITE','high_critical_without_control','BLOCK_PHASE'),
 'proposal_is_canonical_source',false,'auto_canonicalization','DENY','promotion_authorized',false,'production_authorized',false),
true,'defined'
where exists(select 1 from programacion.versiones_agente v join programacion.agentes a on a.id=v.agente_id where v.id=19 and a.agente_codigo='INPUT_GOVERNANCE_AGENT')
on conflict(version_id,contrato_codigo) do update set tipo=excluded.tipo,nombre=excluded.nombre,descripcion=excluded.descripcion,productor_componente_id=excluded.productor_componente_id,especificacion=excluded.especificacion,fail_closed=excluded.fail_closed,estado=excluded.estado;

create or replace function programacion.fn_input_governance_ekb_checkpoint(p_phase text,p_pantalla_id integer,p_run_id bigint default null)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','public','programacion','lf_ops' as $f$
declare v_codes text[]; v_errors jsonb; v_rules jsonb; v_unhandled jsonb; v_receipt jsonb;
begin
 if not exists(select 1 from programacion.contratos where version_id=19 and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT' and estado='defined' and fail_closed) then raise exception 'INPUT_GOVERNANCE_EXECUTION_CONTRACT_NOT_RESOLVABLE'; end if;
 if not exists(select 1 from lf_ops.pantallas where id=p_pantalla_id) then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;
 v_codes:=case p_phase
  when 'PRE_EXECUTION' then array['GOV-010','DB-001','ARC-006','GOV-007','SRC-001','SRC-006','CI-MIG-001']
  when 'PRE_CURATOR' then array['GOV-010','DB-001','AUD-019','AUD-038','AUD-039','GOV-012','GOV-013','GOV-014','ARC-011','SQL-013']
  when 'PRE_VALIDATOR' then array['GOV-010','AUD-001','AUD-019','AUD-038','AUD-039','GOV-012','GOV-013','GOV-014','ARC-006']
  when 'PRE_STORY_GATE' then array['GOV-010','GOV-012','GOV-013','GOV-014','ARC-011']
  when 'PRE_CONTEXT_MANIFEST' then array['GOV-010','ARC-006','GOV-007','SRC-001','SRC-006']
  when 'CLOSE_EKB' then array['GOV-010','ARC-006','GOV-007','SRC-001','SRC-006','AUD-001']
  else null end;
 if v_codes is null then raise exception 'INPUT_GOVERNANCE_EKB_PHASE_NOT_DEFINED:%',coalesce(p_phase,'<NULL>'); end if;
 select coalesce(jsonb_agg(jsonb_build_object('codigo',e.codigo,'severidad',e.severidad,'frecuencia',e.frecuencia,'prevencion',e.prevencion,'validacion',e.validacion) order by e.codigo),'[]'::jsonb) into v_errors from public.lf_error_knowledge e where e.estado='activo' and e.codigo=any(v_codes);
 select coalesce(jsonb_agg(jsonb_build_object('regla_codigo',r.regla_codigo,'error_codigo',r.error_codigo,'regla',r.regla,'prioridad',r.prioridad) order by r.error_codigo,r.prioridad,r.regla_codigo),'[]'::jsonb) into v_rules from public.lf_prevention_rules r where r.activa and r.error_codigo=any(v_codes);
 select coalesce(jsonb_agg(e.codigo order by e.codigo),'[]'::jsonb) into v_unhandled from public.lf_error_knowledge e where e.estado='activo' and e.codigo=any(v_codes) and lower(e.severidad) in ('high','critical') and nullif(btrim(coalesce(e.prevencion,'')),'') is null and not exists(select 1 from public.lf_prevention_rules r where r.error_codigo=e.codigo and r.activa);
 v_receipt:=jsonb_build_object('schema_version',1,'phase',p_phase,'pantalla_id',p_pantalla_id,'run_id',p_run_id,'decision_authority','DEC-INPUT-GOV-EXEC-EKB-001','ekb_read',true,'active_errors',v_errors,'active_prevention_rules',v_rules,'unhandled_high_critical_codes',v_unhandled,'pass',jsonb_array_length(v_unhandled)=0,'observed_at',now());
 return v_receipt||jsonb_build_object('receipt_sha256',programacion.fn_v09_sha256_jsonb(v_receipt));
end;$f$;

create or replace function programacion.fn_input_governance_execute(p_pantalla_id integer,p_consumer text default 'STORY_CREATOR')
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','public','programacion','lf_ops' as $f$
declare v_contract jsonb; v_version bigint; v_code text; v_active boolean; v_run bigint; v_latest bigint; v_family integer; v_assessed integer; v_pass integer; v_bad integer; v_human integer; v_status text; v_pre jsonb; v_cur jsonb; v_val jsonb; v_story jsonb; v_ctx jsonb; v_close jsonb; v_stage jsonb; v_prop jsonb; v_manifest jsonb; v_payload jsonb;
begin
 select c.version_id,c.especificacion into v_version,v_contract from programacion.contratos c join programacion.versiones_agente v on v.id=c.version_id join programacion.agentes a on a.id=v.agente_id where a.agente_codigo='INPUT_GOVERNANCE_AGENT' and c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT' and c.estado='defined' and c.fail_closed order by c.version_id desc limit 1;
 if v_contract is null then raise exception 'INPUT_GOVERNANCE_EXECUTION_CONTRACT_NOT_RESOLVABLE'; end if;
 if not exists(select 1 from jsonb_array_elements_text(v_contract->'allowed_consumers') x(v) where x.v=p_consumer) then raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>'); end if;
 select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id;
 if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;
 if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;
 v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_EXECUTION',p_pantalla_id,null); if not (v_pre->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_EXECUTION:%',v_pre->'unhandled_high_critical_codes'; end if;
 select id,family_count into v_run,v_family from programacion.input_readiness_runs r where r.version_id=v_version and r.pantalla_id=p_pantalla_id and r.status='COMPLETED' and r.invalidated_at is null and programacion.fn_input_readiness_run_is_current(r.id) order by r.id desc limit 1;
 if v_run is null then
  select id into v_latest from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
  v_close:=programacion.fn_input_governance_ekb_checkpoint('CLOSE_EKB',p_pantalla_id,v_latest);
  v_payload:=jsonb_build_object('schema_version',1,'execution_contract','INPUT_GOVERNANCE_EXECUTION_V1','agent_code','INPUT_GOVERNANCE_AGENT','version_id',v_version,'pantalla_id',p_pantalla_id,'screen_code',v_code,'consumer',p_consumer,'status','MATERIALIZATION_REQUIRED','execution_mode','FAIL_CLOSED_NO_CURRENT_RUN','latest_run_id',v_latest,'blocker','CURATOR_VALIDATOR_MATERIALIZATION_REQUIRED','next_action','RUN_CURATOR_VALIDATOR_WORKER_THEN_RECALL_ENTRYPOINT','checkpoints',jsonb_build_object('PRE_EXECUTION',v_pre,'CLOSE_EKB',v_close),'ekb_close_classification','NO_ARTIFICIAL_WRITE','proposal_is_canonical_source',false,'promotion_authorized',false,'production_authorized',false,'generated_at',now());
  return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
 end if;
 v_cur:=programacion.fn_input_governance_ekb_checkpoint('PRE_CURATOR',p_pantalla_id,v_run); if not (v_cur->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CURATOR:%',v_cur->'unhandled_high_critical_codes'; end if;
 select count(*) into v_assessed from programacion.input_family_assessments where run_id=v_run; if v_assessed<>v_family then raise exception 'INPUT_GOVERNANCE_CURATOR_UNIVERSE_INCOMPLETE:run=% expected=% actual=%',v_run,v_family,v_assessed; end if;
 v_val:=programacion.fn_input_governance_ekb_checkpoint('PRE_VALIDATOR',p_pantalla_id,v_run); if not (v_val->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_VALIDATOR:%',v_val->'unhandled_high_critical_codes'; end if;
 select count(*) filter(where a.validator_outcome='PASS'),count(*) filter(where a.validator_outcome<>'PASS' or a.validator_identity is null or not coalesce((a.validator_evidence->>'direct_source_readback')::boolean,false) or a.validator_evidence->>'source_snapshot_sha256' is distinct from r.source_snapshot_sha256) into v_pass,v_bad from programacion.input_family_assessments a join programacion.input_readiness_runs r on r.id=a.run_id where a.run_id=v_run;
 if v_pass<>v_family or v_bad<>0 then raise exception 'INPUT_GOVERNANCE_VALIDATOR_NOT_FULL_AUTHORIZED_PASS:run=% expected=% pass=% bad=%',v_run,v_family,v_pass,v_bad; end if;
 v_story:=programacion.fn_input_governance_ekb_checkpoint('PRE_STORY_GATE',p_pantalla_id,v_run); if not (v_story->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_STORY_GATE:%',v_story->'unhandled_high_critical_codes'; end if;
 v_stage:=programacion.fn_input_stage_gate_summary(v_run); v_prop:=programacion.fn_input_proposal_summary(v_run);
 select count(*) into v_human from programacion.input_gap_proposals where run_id=v_run and status='HUMAN_DECISION_REQUIRED' and validator_outcome='PASS';
 if coalesce((v_stage->>'canonical_story_gate_pass')::boolean,false) then v_ctx:=programacion.fn_input_governance_ekb_checkpoint('PRE_CONTEXT_MANIFEST',p_pantalla_id,v_run); if not (v_ctx->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CONTEXT_MANIFEST:%',v_ctx->'unhandled_high_critical_codes'; end if; v_manifest:=programacion.fn_input_context_manifest(v_run); v_status:='READY'; elsif v_human>0 then v_status:='HUMAN_DECISION_REQUIRED'; else v_status:='BLOCKED'; end if;
 v_close:=programacion.fn_input_governance_ekb_checkpoint('CLOSE_EKB',p_pantalla_id,v_run); if not (v_close->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:CLOSE_EKB:%',v_close->'unhandled_high_critical_codes'; end if;
 v_payload:=jsonb_build_object('schema_version',1,'execution_contract','INPUT_GOVERNANCE_EXECUTION_V1','agent_code','INPUT_GOVERNANCE_AGENT','version_id',v_version,'pantalla_id',p_pantalla_id,'screen_code',v_code,'consumer',p_consumer,'status',v_status,'execution_mode','REUSE_COMPLETED_CURRENT_RUN','run_id',v_run,'family_count',v_family,'validator_pass_count',v_pass,'human_decision_required_count',v_human,'stage_gate',v_stage,'proposal_summary',v_prop,'context_manifest',v_manifest,'checkpoints',jsonb_strip_nulls(jsonb_build_object('PRE_EXECUTION',v_pre,'PRE_CURATOR',v_cur,'PRE_VALIDATOR',v_val,'PRE_STORY_GATE',v_story,'PRE_CONTEXT_MANIFEST',v_ctx,'CLOSE_EKB',v_close)),'ekb_close_classification','NO_ERROR_NO_ARTIFICIAL_WRITE','proposal_is_canonical_source',false,'promotion_authorized',false,'production_authorized',false,'generated_at',now());
 return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;$f$;

revoke all on function programacion.fn_input_governance_ekb_checkpoint(text,integer,bigint) from public,anon,authenticated;
revoke all on function programacion.fn_input_governance_execute(integer,text) from public,anon,authenticated;
grant execute on function programacion.fn_input_governance_ekb_checkpoint(text,integer,bigint) to service_role;
grant execute on function programacion.fn_input_governance_execute(integer,text) to service_role;
comment on function programacion.fn_input_governance_execute(integer,text) is 'Single-call fail-closed INPUT_GOVERNANCE_AGENT entrypoint. Current runs are reused; stale/absent runs require Curator/Validator materialization. EKB checkpoints mandatory. No promotion/production.';

do $check$ declare b bigint; a bigint; r jsonb; begin
 select count(*) into b from programacion.input_readiness_runs;
 r:=programacion.fn_input_governance_execute(51,'STORY_CREATOR');
 if r->>'status'<>'READY' or (r->>'run_id')::bigint<>183 or coalesce((r->>'promotion_authorized')::boolean,true) or coalesce((r->>'production_authorized')::boolean,true) or (select count(*) from jsonb_object_keys(r->'checkpoints'))<>6 then raise exception 'INPUT_GOVERNANCE_EXECUTION_POSITIVE_SELFTEST_FAILED:%',r; end if;
 begin perform programacion.fn_input_governance_execute(51,'UNAUTHORIZED_CONSUMER'); raise exception 'NEG_CONSUMER_NOT_REJECTED'; exception when others then if sqlerrm='NEG_CONSUMER_NOT_REJECTED' or sqlerrm not like 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%' then raise; end if; end;
 begin perform programacion.fn_input_governance_execute(55,'STORY_CREATOR'); raise exception 'NEG_INACTIVE_NOT_REJECTED'; exception when others then if sqlerrm='NEG_INACTIVE_NOT_REJECTED' or sqlerrm not like 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%' then raise; end if; end;
 select count(*) into a from programacion.input_readiness_runs; if a<>b then raise exception 'INPUT_GOVERNANCE_EXECUTION_SELFTEST_MUTATED_READINESS_RUNS'; end if;
end;$check$;
