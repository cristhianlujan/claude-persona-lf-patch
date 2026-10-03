-- Bounded rollback for T-INDEP / INDEPENDENT_ASSURANCE subject extension v2.
-- This is a recovery artifact, not a forward migration.
-- It restores the pre-extension Strategy-only operation revision exactly and leaves
-- historical evidence immutable. Capability v2 is retired/detached, not erased.

-- Fail closed if a Story review is currently executing.
do $pre$
declare
  v_current text;
  v_active integer;
begin
  select count(*) into v_active
  from public.lf_operation_execution
  where operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
    and target_type='STORY_IMPLEMENTATION_PACKAGE'
    and status='IN_PROGRESS';
  if v_active<>0 then
    raise exception 'BLOCK_T_INDEP_ROLLBACK_ACTIVE_STORY_REVIEWS:%',v_active;
  end if;

  select version into v_current
  from public.lf_capability_current
  where capability_code='INDEPENDENT_ASSURANCE';
  if v_current is not null and v_current not in ('1.0.0','2.0.0') then
    raise exception 'BLOCK_T_INDEP_ROLLBACK_UNEXPECTED_CURRENT_VERSION:%',v_current;
  end if;
end
$pre$;

-- Remove active v2 pointer first so new generic entries fail closed during rollback.
delete from public.lf_capability_current
where capability_code='INDEPENDENT_ASSURANCE' and version='2.0.0';

insert into public.lf_capability_current(
  capability_code,version,manifest_sha256,previous_version,promoted_at,promoted_by_execution_id,promotion_reason
)
select 'INDEPENDENT_ASSURANCE','1.0.0',v.manifest_sha256,null,clock_timestamp(),
       'CHATGPT-T-INDEP-ROLLBACK-20261003','Restore exact preextension current v1.0.0'
from public.lf_capability_version_registry v
where v.capability_code='INDEPENDENT_ASSURANCE' and v.version='1.0.0'
on conflict(capability_code) do update set
  version=excluded.version,manifest_sha256=excluded.manifest_sha256,previous_version=null,
  promoted_at=excluded.promoted_at,promoted_by_execution_id=excluded.promoted_by_execution_id,
  promotion_reason=excluded.promotion_reason;

-- Generic v2 entrypoints no longer accept new work.
drop function if exists public.lf_independent_review_begin_v2(text,text,text,text,text,uuid,text,text,text,uuid,text,text,text,jsonb);
drop function if exists public.lf_record_independent_review_step_v2(text,text,text,jsonb,text,text);

-- Restore exact pre-extension operation registry boundary.
update public.lf_operation_registry
set applies_to_asset_type='STRATEGY',
    notes='Transversal independent review for Strategy qualification REVIEW_REQUIRED cases. Reviewer identity is its own governed operation execution; it does not require another Strategy to be qualification_current.',
    updated_at=clock_timestamp(),
    updated_by_execution_id='CHATGPT-T-INDEP-ROLLBACK-20261003'
where operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF';

update public.lf_operation_contracts
set required_before_write=jsonb_build_array(
      'router_receipt','operation_qualification_current','qualification_bound','exact_strategy_revision',
      'exact_suite_fingerprint','review_required_test','independent_reviewer_execution','evidence_refs'
    ),
    allowed=jsonb_build_object(
      'runtime_activation',false,
      'scheduler_activation',false,
      'production_activation',false,
      'orchestrator_activation',false,
      'independent_review_required',true,
      'direct_business_write_allowed',false,
      'strategy_snapshot_mutation_allowed',false,
      'qualification_evidence_write_allowed',true,
      'reviewer_must_be_operation_execution',true,
      'reviewer_must_complete_before_finalizer',true
    ),
    blocked=jsonb_build_array(
      'direct_strategy_snapshot_write','runtime_enable','production_enable','scheduler_enable','orchestrator_enable',
      'stale_revision','stale_suite_fingerprint','reviewer_equals_producer','judge_without_evidence',
      'finalize_before_reviewer_completed','unrouted_execution'
    ),
    required_after_write=jsonb_build_array(
      'judge_receipt','reviewer_execution_completed','qualification_finalizer_receipt','qualification_readback'
    ),
    updated_at=clock_timestamp(),
    updated_by_execution_id='CHATGPT-T-INDEP-ROLLBACK-20261003'
where operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
  and contract_code='CONTRACT-REVISION-INDEPENDIENTE-ESTRATEGIA-LF-v1'
  and status='ACTIVE_ENFORCEMENT';

update public.lf_operation_step_contracts
set purpose=case step_id
      when 'route_bind' then 'Bind ACT-0001 route and exact independent-review operation.'
      when 'target_currentness' then 'Bind current Strategy qualification, revision, fingerprint, suite and REVIEW_REQUIRED test.'
      when 'semantic_review' then 'Persist independent semantic verdict rationale and evidence references before judge recording.'
      when 'judge_record' then 'Prove canonical judge result was recorded by this reviewer execution.'
      when 'reviewer_readback' then 'Re-read judge and target currentness before reviewer completion.'
      when 'report_output' then 'Close reviewer execution only after all required review steps are clean.'
      else purpose end,
    required_evidence_keys=case step_id
      when 'route_bind' then jsonb_build_array('router_receipt','operation_code')
      when 'target_currentness' then jsonb_build_array('qualification_id','snapshot_id','revision_sha256','suite_set_fingerprint','suite_run_id','test_run_id')
      when 'semantic_review' then jsonb_build_array('verdict','review_type','review_context','rationale_summary','evidence_refs')
      when 'judge_record' then jsonb_build_array('judge_result_id','verdict','test_run_id')
      when 'reviewer_readback' then jsonb_build_array('judge_result_id','qualification_id','revision_sha256','suite_set_fingerprint')
      when 'report_output' then jsonb_build_array('review_receipt','evidence_refs','next_gate')
      else required_evidence_keys end,
    output_payload=case step_id
      when 'route_bind' then jsonb_build_array('router_receipt','operation_code')
      when 'target_currentness' then jsonb_build_array('qualification_id','snapshot_id','revision_sha256','suite_set_fingerprint','suite_run_id','test_run_id')
      when 'semantic_review' then jsonb_build_array('verdict','review_type','review_context','rationale_summary','evidence_refs')
      when 'judge_record' then jsonb_build_array('judge_result_id','verdict','test_run_id')
      when 'reviewer_readback' then jsonb_build_array('judge_result_id','qualification_id','revision_sha256','suite_set_fingerprint')
      when 'report_output' then jsonb_build_array('review_receipt','evidence_refs','next_gate')
      else output_payload end,
    updated_at=clock_timestamp(),
    updated_by_execution_id='CHATGPT-T-INDEP-ROLLBACK-20261003'
where operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
  and step_id in ('route_bind','target_currentness','semantic_review','judge_record','reviewer_readback','report_output')
  and status='ACTIVE_ENFORCEMENT';

update public.lf_operation_step_judge_bindings
set required_evidence_keys=case step_id
      when 'route_bind' then jsonb_build_array('router_receipt','operation_code')
      when 'target_currentness' then jsonb_build_array('qualification_id','snapshot_id','revision_sha256','suite_set_fingerprint','suite_run_id','test_run_id')
      when 'semantic_review' then jsonb_build_array('verdict','review_type','review_context','rationale_summary','evidence_refs')
      when 'judge_record' then jsonb_build_array('judge_result_id','verdict','test_run_id')
      when 'reviewer_readback' then jsonb_build_array('judge_result_id','qualification_id','revision_sha256','suite_set_fingerprint')
      when 'report_output' then jsonb_build_array('review_receipt','evidence_refs','next_gate')
      else required_evidence_keys end,
    updated_at=clock_timestamp(),
    updated_by_execution_id='CHATGPT-T-INDEP-ROLLBACK-20261003'
where operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
  and step_id in ('route_bind','target_currentness','semantic_review','judge_record','reviewer_readback','report_output')
  and status='ACTIVE_ENFORCEMENT';

update public.lf_operation_judges
set pass_if=case judge_code
      when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-ROUTE-v1' then jsonb_build_array('router_ready','operation_exact')
      when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-CURRENTNESS-v1' then jsonb_build_array('qualification_bound','revision_current','suite_fingerprint_current','test_review_required')
      when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-SEMANTIC-v1' then jsonb_build_array('review_receipt_shape_valid','review_context_independent','evidence_refs_present','verdict_allowed')
      when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-JUDGE-v1' then jsonb_build_array('judge_persisted','judge_bound','judge_verdict_matches')
      when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-READBACK-v1' then jsonb_build_array('judge_readback','target_still_current','test_still_review_required')
      when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-REPORT-v1' then jsonb_build_array('all_prior_clean','reviewer_ready_to_complete','target_still_current')
      else pass_if end,
    fail_if=case judge_code
      when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-ROUTE-v1' then jsonb_build_array('route_invalid')
      when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-CURRENTNESS-v1' then jsonb_build_array('target_stale')
      when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-SEMANTIC-v1' then jsonb_build_array('review_receipt_invalid')
      when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-JUDGE-v1' then jsonb_build_array('judge_invalid')
      when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-READBACK-v1' then jsonb_build_array('readback_invalid')
      when 'JUDGE-INDEPENDENT-STRATEGY-REVIEW-REPORT-v1' then jsonb_build_array('completion_invalid')
      else fail_if end,
    updated_at=clock_timestamp(),
    updated_by_execution_id='CHATGPT-T-INDEP-ROLLBACK-20261003'
where operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF'
  and status='ACTIVE_ENFORCEMENT';

-- Restore the exact Strategy-only recorder implementation that is live before T-INDEP.
create or replace function public.lf_record_independent_strategy_review_step_v1(
  p_execution_id text,p_step_id text,p_evidence_ref text,p_evidence_payload jsonb,p_actor_execution_id text
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $function$
declare
  x public.lf_operation_execution%rowtype;
  q public.lf_qualification_receipts%rowtype;
  tr public.lf_test_runs%rowtype;
  jr public.lf_test_judge_results%rowtype;
  route jsonb;
  rev text;
  fp text;
  qid uuid;
  trid uuid;
  jrid uuid;
  sid bigint;
  assertions jsonb:='[]'::jsonb;
  hard_fails jsonb:='[]'::jsonb;
  valid boolean:=true;
  code text:='OK';
  trust jsonb;
  verdict text;
begin
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload)<>'object' then
    return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_PAYLOAD_INVALID','durable',false);
  end if;
  select * into x from public.lf_operation_execution where execution_id=p_execution_id;
  if not found or x.operation_code<>'REVISION_INDEPENDIENTE_ESTRATEGIA_LF' or x.target_type<>'STRATEGY' or x.status<>'IN_PROGRESS' then
    return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_IDENTITY_INVALID','durable',false);
  end if;
  begin
    qid:=(x.manifest->>'qualification_id')::uuid;
    trid:=(x.manifest->>'test_run_id')::uuid;
    sid:=(x.manifest->>'snapshot_id')::bigint;
  exception when others then
    return jsonb_build_object('outcome','BLOCKED','code','EXECUTION_MANIFEST_BINDING_INVALID','durable',false);
  end;
  rev:=public.lf_strategy_revision_sha256_v1(sid);
  fp:=public.lf_required_test_suite_fingerprint_v1('STRATEGY',x.target_code);
  select * into q from public.lf_qualification_receipts where qualification_id=qid;
  select * into tr from public.lf_test_runs where test_run_id=trid;

  if p_step_id='route_bind' then
    route:=public.lf_router_resolve_v1('revision independiente de qualification de estrategia',null,'STRATEGY_INDEPENDENT_REVIEW','STRATEGY','ROUTER');
    if route->>'status'='READY_TO_EXECUTE' then assertions:=assertions||'"router_ready"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"route_invalid"'::jsonb; code:='ROUTE_INVALID'; end if;
    if route->>'operation_code'='REVISION_INDEPENDIENTE_ESTRATEGIA_LF' then assertions:=assertions||'"operation_exact"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"route_invalid"'::jsonb; code:='OPERATION_MISMATCH'; end if;
  elsif p_step_id='target_currentness' then
    if q.qualification_id=qid and q.subject_code=x.target_code and q.lifecycle_state_code='QUAL_QUALIFYING' then assertions:=assertions||'"qualification_bound"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"target_stale"'::jsonb; code:='QUALIFICATION_NOT_BOUND'; end if;
    if rev=x.manifest->>'revision_sha256' and q.revision_sha256=rev then assertions:=assertions||'"revision_current"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"target_stale"'::jsonb; code:='REVISION_STALE'; end if;
    if fp=x.manifest->>'suite_set_fingerprint' and q.suite_set_fingerprint=fp then assertions:=assertions||'"suite_fingerprint_current"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"target_stale"'::jsonb; code:='SUITE_FINGERPRINT_STALE'; end if;
    if tr.test_run_id=trid and tr.status='REVIEW_REQUIRED' and tr.test_code='A03' and tr.input_payload->>'probe_code'='INDEPENDENT_REVIEW' and tr.suite_run_id=any(q.suite_run_ids) then assertions:=assertions||'"test_review_required"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"target_stale"'::jsonb; code:='TEST_NOT_REVIEW_REQUIRED'; end if;
  elsif p_step_id='semantic_review' then
    verdict:=upper(coalesce(p_evidence_payload->>'verdict',''));
    if verdict in ('PASS','FAIL') and nullif(btrim(coalesce(p_evidence_payload->>'rationale_summary','')),'') is not null
       and p_evidence_payload->>'review_type' in ('INDEPENDENT_REVIEW','INDEPENDENT_HOLDOUT') then assertions:=assertions||'"review_receipt_shape_valid"'::jsonb||'"verdict_allowed"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"review_receipt_invalid"'::jsonb; code:='REVIEW_RECEIPT_INVALID'; end if;
    if p_evidence_payload->>'review_context'='INDEPENDENT_OPERATION_CONTEXT' then assertions:=assertions||'"review_context_independent"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"review_receipt_invalid"'::jsonb; code:='REVIEW_CONTEXT_INVALID'; end if;
    if jsonb_typeof(p_evidence_payload->'evidence_refs')='array' and jsonb_array_length(p_evidence_payload->'evidence_refs')>0 then assertions:=assertions||'"evidence_refs_present"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"review_receipt_invalid"'::jsonb; code:='REVIEW_EVIDENCE_MISSING'; end if;
  elsif p_step_id in ('judge_record','reviewer_readback','report_output') then
    begin jrid:=coalesce(nullif(p_evidence_payload->>'judge_result_id',''),x.checkpoint_payload->>'judge_result_id')::uuid; exception when others then jrid:=null; end;
    if jrid is not null then select * into jr from public.lf_test_judge_results where judge_result_id=jrid; end if;
    if p_step_id='judge_record' then
      if jr.judge_result_id=jrid then assertions:=assertions||'"judge_persisted"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"judge_invalid"'::jsonb; code:='JUDGE_NOT_FOUND'; end if;
      if jr.test_run_id=trid and jr.created_by_execution_id=p_execution_id and jr.metadata->>'reviewer_execution_id'=p_execution_id then assertions:=assertions||'"judge_bound"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"judge_invalid"'::jsonb; code:='JUDGE_BINDING_INVALID'; end if;
      if jr.verdict=upper(coalesce(x.checkpoint_payload->>'verdict','')) then assertions:=assertions||'"judge_verdict_matches"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"judge_invalid"'::jsonb; code:='JUDGE_VERDICT_MISMATCH'; end if;
    elsif p_step_id='reviewer_readback' then
      if jr.judge_result_id=jrid and jr.test_run_id=trid and jr.created_by_execution_id=p_execution_id then assertions:=assertions||'"judge_readback"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='JUDGE_READBACK_INVALID'; end if;
      if rev=x.manifest->>'revision_sha256' and fp=x.manifest->>'suite_set_fingerprint' and q.lifecycle_state_code='QUAL_QUALIFYING' then assertions:=assertions||'"target_still_current"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='TARGET_STALE_AT_READBACK'; end if;
      if tr.status='REVIEW_REQUIRED' then assertions:=assertions||'"test_still_review_required"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"readback_invalid"'::jsonb; code:='TEST_STATE_CHANGED_BEFORE_FINALIZE'; end if;
    else
      if not exists (
        select 1 from public.lf_operation_steps s
        left join public.lf_operation_execution_steps es on es.execution_id=p_execution_id and es.step_order=s.step_order and es.step_id=s.step_id
        left join public.lf_operation_step_judge_bindings b on b.operation_code=s.operation_code and b.step_order=s.step_order and b.step_id=s.step_id and b.status='ACTIVE_ENFORCEMENT'
        where s.operation_code='REVISION_INDEPENDIENTE_ESTRATEGIA_LF' and s.required and s.active and s.step_id<>'report_output'
          and (es.step_id is null or b.clean_result_value is null or es.status<>b.clean_result_value)
      ) then assertions:=assertions||'"all_prior_clean"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='PRIOR_STEPS_NOT_CLEAN'; end if;
      if jr.judge_result_id=jrid and jr.created_by_execution_id=p_execution_id then assertions:=assertions||'"reviewer_ready_to_complete"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='JUDGE_NOT_BOUND_AT_COMPLETION'; end if;
      if rev=x.manifest->>'revision_sha256' and fp=x.manifest->>'suite_set_fingerprint' and q.lifecycle_state_code='QUAL_QUALIFYING' and tr.status='REVIEW_REQUIRED' then assertions:=assertions||'"target_still_current"'::jsonb; else valid:=false; hard_fails:=hard_fails||'"completion_invalid"'::jsonb; code:='TARGET_STALE_AT_COMPLETION'; end if;
    end if;
  else
    return jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_SUPPORTED','durable',false);
  end if;

  trust:=jsonb_build_object('valid',valid,'code',code,'server_assertions',assertions,'server_hard_fails',hard_fails,
    'details',jsonb_build_object('qualification_id',qid,'test_run_id',trid,'snapshot_id',sid,'current_revision',rev,'current_fingerprint',fp));
  return public.lf_record_operation_step_core_v1(
    p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id,
    'REVISION_INDEPENDIENTE_ESTRATEGIA_LF','STRATEGY',
    'ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT','ACTIVE_ENFORCEMENT',trust,true,'lf_record_independent_strategy_review_step_v1'
  );
end
$function$;

-- Restore the pre-extension requalification bootstrap helper (no residual helper change).
create or replace function public.lf_operation_requalification_bootstrap_v1(
  p_execution_id text,
  p_operation_code text,
  p_route_action_code text,
  p_request_sha256 text,
  p_idempotency_key text,
  p_actor_execution_id text,
  p_exact_source_head text
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $function$
declare
  r public.lf_operation_registry%rowtype;
  x public.lf_operation_execution%rowtype;
  reserve_result jsonb;
  qualification_result jsonb;
  rev text;
  fp text;
  target_path text;
  current_after boolean;
  binding_kind text;
begin
  if btrim(coalesce(p_execution_id,''))=''
     or btrim(coalesce(p_operation_code,''))=''
     or btrim(coalesce(p_route_action_code,''))=''
     or coalesce(p_request_sha256,'') !~ '^[0-9a-f]{64}$'
     or btrim(coalesce(p_idempotency_key,''))=''
     or btrim(coalesce(p_actor_execution_id,''))=''
     or coalesce(p_exact_source_head,'') !~ '^[0-9a-f]{40}$' then
    raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_INPUT_INVALID';
  end if;

  select * into r from public.lf_operation_registry where operation_code=p_operation_code;
  if not found or r.lifecycle_state_code not in ('OP_OPERATIONAL','OP_CANDIDATE') then
    raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_TARGET_INVALID:%',p_operation_code;
  end if;
  if btrim(coalesce(r.applies_to_asset_type,''))='' then
    raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_ROUTE_SCOPE_MISSING:%',p_operation_code;
  end if;

  if r.lifecycle_state_code='OP_OPERATIONAL' then
    binding_kind:='ACTIVE_ROUTER';
    if not exists (
      select 1 from public.lf_router_action_registry a
      where a.asset_type=r.applies_to_asset_type
        and a.action_code=p_route_action_code
        and a.operation_code=p_operation_code
        and a.status='ACTIVE'
    ) then
      raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_ROUTE_INVALID:%:%',p_operation_code,p_route_action_code;
    end if;
  else
    binding_kind:='PREPROMOTION_LIFECYCLE_QUALIFICATION';
    if exists (select 1 from public.lf_router_action_registry a where a.operation_code=p_operation_code and a.status='ACTIVE') then
      raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_CANDIDATE_ROUTER_ALREADY_ACTIVE:%',p_operation_code;
    end if;
    if not exists (
      select 1 from lf_ops.estados_transiciones t
      where t.entity_type='OPERATION_LIFECYCLE'
        and t.from_state_code='OP_CANDIDATE'
        and t.to_state_code='OP_OPERATIONAL'
        and t.action_code=p_route_action_code
        and t.status='VIGENTE'
        and coalesce((t.condition_config->>'requires_qualification')::boolean,false)=true
        and t.condition_config->>'qualification_scope'='OPERATION'
    ) then
      raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_CANDIDATE_PREPROMOTION_AUTHORITY_INVALID:%:%',p_operation_code,p_route_action_code;
    end if;
  end if;

  rev:=public.lf_operation_revision_sha256_v1(p_operation_code);
  fp:=public.lf_required_test_suite_fingerprint_v1('OPERATION',p_operation_code);
  if public.lf_qualification_current_v1('OPERATION',p_operation_code,rev) then
    raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_NOT_NEEDED:%',p_operation_code;
  end if;

  target_path:='supabase://public/lf_operation_registry/'||p_operation_code;
  reserve_result:=public.fn_lf_operation_reserve_execution_v1(
    p_execution_id,p_operation_code,'OPERATION',p_operation_code,
    p_idempotency_key,p_request_sha256,p_actor_execution_id,null,target_path,
    jsonb_build_object(
      'mode','OPERATION_REQUALIFICATION_BOOTSTRAP_ONLY',
      'operation_requalification_bootstrap_only',true,
      'qualification_target_operation',p_operation_code,
      'qualification_target_revision_sha256',rev,
      'qualification_target_suite_fingerprint',fp,
      'route_binding',jsonb_build_object(
        'binding_kind',binding_kind,
        'asset_type',r.applies_to_asset_type,
        'action_code',p_route_action_code,
        'operation_code',p_operation_code,
        'operation_lifecycle_state',r.lifecycle_state_code,
        'router_activation_authorized',false
      ),
      'exact_source_head',p_exact_source_head,
      'runtime_activation',false,
      'production_activation',false,
      'promotion_authorized',false,
      'router_activation_authorized',false
    )
  );

  select * into x from public.lf_operation_execution
  where execution_id=reserve_result->>'execution_id' for update;
  if not found or x.status<>'IN_PROGRESS'
     or x.operation_code is distinct from p_operation_code
     or x.target_type is distinct from 'OPERATION'
     or x.target_code is distinct from p_operation_code
     or x.target_path is distinct from target_path then
    raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_EXECUTION_BINDING_INVALID';
  end if;
  if coalesce(x.manifest->>'operation_policy_source','')<>'SUPABASE'
     or jsonb_typeof(x.manifest->'operation_policy_snapshots') is distinct from 'object' then
    raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_POLICY_SNAPSHOT_MISSING';
  end if;
  if rev is distinct from public.lf_operation_revision_sha256_v1(p_operation_code)
     or fp is distinct from public.lf_required_test_suite_fingerprint_v1('OPERATION',p_operation_code) then
    raise exception 'LF_OPERATION_REQUALIFICATION_BOOTSTRAP_TARGET_CHANGED:%',p_operation_code;
  end if;

  qualification_result:=public.lf_run_operation_qualification_v1(p_operation_code,x.execution_id);
  current_after:=public.lf_qualification_current_v1('OPERATION',p_operation_code,rev);

  update public.lf_operation_execution
     set status='COMPLETED',completed_at=clock_timestamp(),updated_by_execution_id=p_actor_execution_id,
         manifest=manifest||jsonb_build_object(
           'qualification_bootstrap_result',qualification_result,
           'qualification_current_after_runner',current_after,
           'qualification_bootstrap_closed',true,
           'runtime_activation',false,
           'production_activation',false,
           'promotion_authorized',false,
           'router_activation_authorized',false
         )
   where execution_id=x.execution_id;

  return jsonb_build_object(
    'execution_id',x.execution_id,
    'operation_code',p_operation_code,
    'operation_lifecycle_state',r.lifecycle_state_code,
    'route_binding_kind',binding_kind,
    'revision_sha256',rev,
    'suite_set_fingerprint',fp,
    'qualification',qualification_result,
    'qualification_current',current_after,
    'exact_source_head',p_exact_source_head,
    'runtime_activation',false,
    'production_activation',false,
    'promotion_authorized',false,
    'router_activation_authorized',false,
    'bootstrap_execution_status','COMPLETED'
  );
end
$function$;

-- Retire v2 manifest instead of deleting audit history.
update public.lf_capability_version_registry
set release_state='RETIRED'
where capability_code='INDEPENDENT_ASSURANCE' and version='2.0.0';

-- Post-rollback invariants: exact old operation revision/current qualification restored.
do $post$
declare
  v_revision text;
  v_count integer;
begin
  v_revision:=public.lf_operation_revision_sha256_v1('REVISION_INDEPENDIENTE_ESTRATEGIA_LF');
  if v_revision<>'fb59333049740f13332d68b07d38493dff0732545e856facea817f6d3ad34811' then
    raise exception 'BLOCK_T_INDEP_ROLLBACK_REVISION_MISMATCH:%',v_revision;
  end if;
  if not public.lf_qualification_current_v1('OPERATION','REVISION_INDEPENDIENTE_ESTRATEGIA_LF',v_revision) then
    raise exception 'BLOCK_T_INDEP_ROLLBACK_OLD_QUALIFICATION_NOT_CURRENT';
  end if;
  select count(*) into v_count from public.lf_operation_registry where operation_type='INDEPENDENT_REVIEW';
  if v_count<>1 then raise exception 'BLOCK_T_INDEP_ROLLBACK_OPERATION_COUNT:%',v_count; end if;
  if exists(select 1 from public.lf_capability_current where capability_code='INDEPENDENT_ASSURANCE') then
    raise exception 'BLOCK_T_INDEP_ROLLBACK_CURRENT_POINTER_RESIDUE';
  end if;
end
$post$;
