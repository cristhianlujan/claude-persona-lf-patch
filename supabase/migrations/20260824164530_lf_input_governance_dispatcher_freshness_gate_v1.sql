-- Input Governance dispatcher: explicit source-freshness gate and role-specific fail-closed handoff.
update programacion.contratos
set especificacion=especificacion||jsonb_build_object(
 'current_run_freshness_gate','programacion.fn_input_freshness_delta(bigint)',
 'current_reuse_requires',jsonb_build_array('COMPLETED','RUN_CURRENT','FRESHNESS_DELTA_CURRENT','ZERO_CHANGED_SOURCES','VALIDATOR_FULL_PASS','STORY_GATE'))
where version_id=19 and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT' and estado='defined' and fail_closed;

create or replace function programacion.fn_input_governance_execute(p_pantalla_id integer,p_consumer text default 'STORY_CREATOR')
returns jsonb language plpgsql stable security definer
set search_path to 'pg_catalog','public','programacion','lf_ops' as $f$
declare
 v_contract jsonb; v_version bigint; v_code text; v_active boolean; v_run bigint; v_latest bigint; v_family integer;
 v_assessed integer; v_pass integer; v_bad integer; v_human integer; v_status text;
 v_pre jsonb; v_cur jsonb; v_val jsonb; v_story jsonb; v_ctx jsonb; v_close jsonb;
 v_stage jsonb; v_prop jsonb; v_manifest jsonb; v_payload jsonb; v_worker jsonb; v_fresh jsonb; v_summary jsonb;
begin
 select c.version_id,c.especificacion into v_version,v_contract
 from programacion.contratos c join programacion.versiones_agente v on v.id=c.version_id join programacion.agentes a on a.id=v.agente_id
 where a.agente_codigo='INPUT_GOVERNANCE_AGENT' and c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
   and c.estado='defined' and c.fail_closed order by c.version_id desc limit 1;
 if v_contract is null then raise exception 'INPUT_GOVERNANCE_EXECUTION_CONTRACT_NOT_RESOLVABLE'; end if;
 if not exists(select 1 from jsonb_array_elements_text(v_contract->'allowed_consumers') x(v) where x.v=p_consumer) then
   raise exception 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%',coalesce(p_consumer,'<NULL>');
 end if;
 select codigo,activa into v_code,v_active from lf_ops.pantallas where id=p_pantalla_id;
 if v_code is null then raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id; end if;
 if not v_active then raise exception 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%',v_code; end if;

 v_pre:=programacion.fn_input_governance_ekb_checkpoint('PRE_EXECUTION',p_pantalla_id,null);
 if not (v_pre->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_EXECUTION:%',v_pre->'unhandled_high_critical_codes'; end if;

 select id,family_count into v_run,v_family from programacion.input_readiness_runs r
 where r.version_id=v_version and r.pantalla_id=p_pantalla_id and r.status='COMPLETED' and r.invalidated_at is null
   and programacion.fn_input_readiness_run_is_current(r.id) order by r.id desc limit 1;

 if v_run is null then
   select id into v_latest from programacion.input_readiness_runs where version_id=v_version and pantalla_id=p_pantalla_id order by id desc limit 1;
   v_worker:=programacion.fn_input_governance_worker_spec(p_pantalla_id,p_consumer);
   v_close:=programacion.fn_input_governance_ekb_checkpoint('CLOSE_EKB',p_pantalla_id,v_latest);
   v_status:=case v_worker->>'required_role' when 'INPUT_VALIDATOR' then 'VALIDATOR_RUNTIME_REQUIRED' else 'CURATOR_RUNTIME_REQUIRED' end;
   v_payload:=jsonb_build_object(
    'schema_version',1,'execution_contract','INPUT_GOVERNANCE_EXECUTION_V1','execution_contract_revision',v_contract->>'contract_revision',
    'agent_code','INPUT_GOVERNANCE_AGENT','version_id',v_version,'pantalla_id',p_pantalla_id,'screen_code',v_code,'consumer',p_consumer,
    'status',v_status,'execution_mode','FAIL_CLOSED_ROLE_SPECIFIC_RUNTIME_REQUIRED','latest_run_id',v_latest,
    'blocker','UNBOUND_SEMANTIC_RUNTIME','worker_spec',v_worker,
    'checkpoints',jsonb_build_object('PRE_EXECUTION',v_pre,'CLOSE_EKB',v_close),
    'proposal_is_canonical_source',false,'promotion_authorized',false,'production_authorized',false,'generated_at',now());
   return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
 end if;

 v_fresh:=programacion.fn_input_freshness_delta(v_run); v_summary:=v_fresh->'summary';
 if v_fresh->>'run_state'<>'CURRENT' or coalesce((v_summary->>'changed_source_count')::integer,-1)<>0
    or coalesce((v_summary->>'affected_family_count')::integer,-1)<>0 then
   raise exception 'INPUT_GOVERNANCE_CURRENT_RUN_FRESHNESS_GATE_FAILED:run=% state=% summary=%',v_run,v_fresh->>'run_state',v_summary;
 end if;

 v_cur:=programacion.fn_input_governance_ekb_checkpoint('PRE_CURATOR',p_pantalla_id,v_run);
 if not (v_cur->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CURATOR:%',v_cur->'unhandled_high_critical_codes'; end if;
 select count(*) into v_assessed from programacion.input_family_assessments where run_id=v_run;
 if v_assessed<>v_family then raise exception 'INPUT_GOVERNANCE_CURATOR_UNIVERSE_INCOMPLETE:run=% expected=% actual=%',v_run,v_family,v_assessed; end if;

 v_val:=programacion.fn_input_governance_ekb_checkpoint('PRE_VALIDATOR',p_pantalla_id,v_run);
 if not (v_val->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_VALIDATOR:%',v_val->'unhandled_high_critical_codes'; end if;
 select count(*) filter(where a.validator_outcome='PASS'),
        count(*) filter(where a.validator_outcome<>'PASS' or a.validator_identity is null or not coalesce((a.validator_evidence->>'direct_source_readback')::boolean,false) or a.validator_evidence->>'source_snapshot_sha256' is distinct from r.source_snapshot_sha256)
 into v_pass,v_bad from programacion.input_family_assessments a join programacion.input_readiness_runs r on r.id=a.run_id where a.run_id=v_run;
 if v_pass<>v_family or v_bad<>0 then raise exception 'INPUT_GOVERNANCE_VALIDATOR_NOT_FULL_AUTHORIZED_PASS:run=% expected=% pass=% bad=%',v_run,v_family,v_pass,v_bad; end if;

 v_story:=programacion.fn_input_governance_ekb_checkpoint('PRE_STORY_GATE',p_pantalla_id,v_run);
 if not (v_story->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_STORY_GATE:%',v_story->'unhandled_high_critical_codes'; end if;
 v_stage:=programacion.fn_input_stage_gate_summary(v_run); v_prop:=programacion.fn_input_proposal_summary(v_run);
 select count(*) into v_human from programacion.input_gap_proposals where run_id=v_run and status='HUMAN_DECISION_REQUIRED' and validator_outcome='PASS';
 if coalesce((v_stage->>'canonical_story_gate_pass')::boolean,false) then
   v_ctx:=programacion.fn_input_governance_ekb_checkpoint('PRE_CONTEXT_MANIFEST',p_pantalla_id,v_run);
   if not (v_ctx->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:PRE_CONTEXT_MANIFEST:%',v_ctx->'unhandled_high_critical_codes'; end if;
   v_manifest:=programacion.fn_input_context_manifest(v_run); v_status:='READY';
 elsif v_human>0 then v_status:='HUMAN_DECISION_REQUIRED'; else v_status:='BLOCKED'; end if;

 v_close:=programacion.fn_input_governance_ekb_checkpoint('CLOSE_EKB',p_pantalla_id,v_run);
 if not (v_close->>'pass')::boolean then raise exception 'INPUT_GOVERNANCE_EKB_BLOCKED:CLOSE_EKB:%',v_close->'unhandled_high_critical_codes'; end if;
 v_worker:=programacion.fn_input_governance_worker_spec(p_pantalla_id,p_consumer);
 v_payload:=jsonb_build_object(
  'schema_version',1,'execution_contract','INPUT_GOVERNANCE_EXECUTION_V1','execution_contract_revision',v_contract->>'contract_revision',
  'agent_code','INPUT_GOVERNANCE_AGENT','version_id',v_version,'pantalla_id',p_pantalla_id,'screen_code',v_code,'consumer',p_consumer,
  'status',v_status,'execution_mode','REUSE_COMPLETED_CURRENT_RUN','run_id',v_run,'family_count',v_family,'validator_pass_count',v_pass,
  'human_decision_required_count',v_human,'freshness_delta_summary',v_summary,
  'stage_gate',v_stage,'proposal_summary',v_prop,'context_manifest',v_manifest,'worker_spec',v_worker,
  'checkpoints',jsonb_strip_nulls(jsonb_build_object('PRE_EXECUTION',v_pre,'PRE_CURATOR',v_cur,'PRE_VALIDATOR',v_val,'PRE_STORY_GATE',v_story,'PRE_CONTEXT_MANIFEST',v_ctx,'CLOSE_EKB',v_close)),
  'proposal_is_canonical_source',false,'promotion_authorized',false,'production_authorized',false,'generated_at',now());
 return v_payload||jsonb_build_object('output_sha256',programacion.fn_v09_sha256_jsonb(v_payload));
end;$f$;

revoke all on function programacion.fn_input_governance_execute(integer,text) from public,anon,authenticated;
grant execute on function programacion.fn_input_governance_execute(integer,text) to service_role;

do $check$ declare b bigint; a bigint; r jsonb; begin
 select count(*) into b from programacion.input_readiness_runs;
 r:=programacion.fn_input_governance_execute(51,'STORY_CREATOR');
 if r->>'status'<>'READY' or (r->>'run_id')::bigint<>183 or (r->'freshness_delta_summary'->>'changed_source_count')::integer<>0
    or r->'worker_spec'->>'required_role'<>'NONE' or coalesce((r->>'promotion_authorized')::boolean,true) then raise exception 'INPUT_GOV_DISPATCH_CURRENT_SELFTEST:%',r; end if;
 r:=programacion.fn_input_governance_execute(1,'STORY_CREATOR');
 if r->>'status'<>'CURATOR_RUNTIME_REQUIRED' or r->'worker_spec'->>'required_role'<>'INPUT_CURATOR' then raise exception 'INPUT_GOV_DISPATCH_NEW_SCREEN_SELFTEST:%',r; end if;
 begin perform programacion.fn_input_governance_execute(51,'UNAUTHORIZED_CONSUMER'); raise exception 'NEG_CONSUMER_NOT_REJECTED'; exception when others then if sqlerrm='NEG_CONSUMER_NOT_REJECTED' or sqlerrm not like 'INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED:%' then raise; end if; end;
 begin perform programacion.fn_input_governance_execute(55,'STORY_CREATOR'); raise exception 'NEG_INACTIVE_NOT_REJECTED'; exception when others then if sqlerrm='NEG_INACTIVE_NOT_REJECTED' or sqlerrm not like 'INPUT_GOVERNANCE_SCREEN_INACTIVE:%' then raise; end if; end;
 select count(*) into a from programacion.input_readiness_runs; if a<>b then raise exception 'INPUT_GOV_DISPATCH_SELFTEST_MUTATED_RUNS'; end if;
end;$check$;
