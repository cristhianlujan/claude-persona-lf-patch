-- S30_STRATEGY_ROUTE_GUARD_ASSURANCE_CLOSE_V1
-- Closes the structural gap left after PR #876 without creating a parallel Router,
-- assurance engine, test matrix, or workflow. Candidate/source only until governed apply.
-- Source execution: EXEC-S30-TRANSVERSAL-ROUTE-GUARD-ASSURANCE-20260917-001

create or replace function public.lf_canonical_route_guard_classify_v1(
  p_canonical_route text,
  p_selected_route text,
  p_explicit_exploration boolean default false
)
returns jsonb
language plpgsql
immutable
security invoker
set search_path to 'pg_catalog','public'
as $function$
declare
  v_canonical text := nullif(btrim(coalesce(p_canonical_route,'')),'');
  v_selected text := nullif(btrim(coalesce(p_selected_route,'')),'');
begin
  if v_canonical is null then
    return jsonb_build_object(
      'status','ROUTE_UNRESOLVED',
      'decision','RESOLVE_CANONICAL_ROUTE_FIRST',
      'canonical_route',null,
      'selected_route',v_selected,
      'ask_user',false,
      'exploratory',false,
      'canonical_effect_allowed',false,
      'merge_allowed',false,
      'production_effect_allowed',false,
      'canonical_close_allowed',false,
      'pass_claim_allowed',false,
      'effect_authorization','PENDING_ROUTE_RESOLUTION'
    );
  end if;

  if v_selected is not distinct from v_canonical then
    return jsonb_build_object(
      'status','CANONICAL_ROUTE',
      'decision','PROCEED_CANONICAL',
      'canonical_route',v_canonical,
      'selected_route',v_selected,
      'ask_user',false,
      'exploratory',false,
      'canonical_effect_allowed',true,
      'merge_allowed',null,
      'production_effect_allowed',null,
      'canonical_close_allowed',null,
      'pass_claim_allowed',null,
      'effect_authorization','DEFER_TO_GOVERNING_CONTRACT'
    );
  end if;

  if coalesce(p_explicit_exploration,false) then
    return jsonb_build_object(
      'status','EXPLORATORY_ROUTE',
      'decision','PROCEED_EXPLORATORY_NO_CANONICAL_EFFECT',
      'canonical_route',v_canonical,
      'selected_route',v_selected,
      'ask_user',false,
      'exploratory',true,
      'canonical_effect_allowed',false,
      'merge_allowed',false,
      'production_effect_allowed',false,
      'canonical_close_allowed',false,
      'pass_claim_allowed',false,
      'effect_authorization','DENIED_BY_EXPLORATORY_MODE'
    );
  end if;

  return jsonb_build_object(
    'status','ROUTE_DEVIATION',
    'decision','ASK_CANONICAL_OR_EXPLORATORY',
    'canonical_route',v_canonical,
    'selected_route',v_selected,
    'ask_user',true,
    'exploratory',false,
    'canonical_effect_allowed',false,
    'merge_allowed',false,
    'production_effect_allowed',false,
    'canonical_close_allowed',false,
    'pass_claim_allowed',false,
    'effect_authorization','PENDING_ROUTE_CHOICE'
  );
end;
$function$;

create or replace function public.lf_strategy_canonical_route_guard_v1(
  p_execution_id text,
  p_selected_route text,
  p_explicit_exploration boolean default false
)
returns jsonb
language plpgsql
stable
security invoker
set search_path to 'pg_catalog','public'
as $function$
declare
  v_execution public.lf_operation_execution%rowtype;
  v_snapshot public.lf_strategy_snapshots%rowtype;
  v_init public.lf_operation_execution_steps%rowtype;
  v_route_count integer := 0;
  v_canonical_route text;
  v_classification jsonb;
  v_target_revision text;
  v_bound_revision text;
  v_operation_revision text;
  v_checks jsonb;
  v_open_defeaters jsonb := '[]'::jsonb;
  v_closed_defeaters jsonb := '[]'::jsonb;
  v_valid boolean := false;
begin
  if btrim(coalesce(p_execution_id,''))='' then
    return public.lf_canonical_route_guard_classify_v1(null,p_selected_route,p_explicit_exploration)
      || jsonb_build_object('valid',false,'blocking_code','ROUTE_GUARD_EXECUTION_ID_MISSING');
  end if;

  select * into v_execution
  from public.lf_operation_execution
  where execution_id=p_execution_id;

  if not found then
    return public.lf_canonical_route_guard_classify_v1(null,p_selected_route,p_explicit_exploration)
      || jsonb_build_object('valid',false,'blocking_code','ROUTE_GUARD_EXECUTION_NOT_FOUND','execution_id',p_execution_id);
  end if;

  select count(*), min(operation_code)
    into v_route_count, v_canonical_route
  from public.lf_router_action_registry
  where asset_type='STRATEGY'
    and action_code='STRATEGY_EXECUTION'
    and status='ACTIVE';

  if v_route_count<>1 then
    return public.lf_canonical_route_guard_classify_v1(null,p_selected_route,p_explicit_exploration)
      || jsonb_build_object(
        'valid',false,
        'blocking_code','ROUTE_GUARD_CANONICAL_ROUTE_NOT_EXACT',
        'execution_id',v_execution.execution_id,
        'route_count',v_route_count
      );
  end if;

  v_classification:=public.lf_canonical_route_guard_classify_v1(
    v_canonical_route,p_selected_route,p_explicit_exploration
  );

  select * into v_snapshot
  from public.lf_strategy_snapshots
  where snapshot_code=v_execution.target_code
  order by id desc
  limit 1;

  select * into v_init
  from public.lf_operation_execution_steps
  where execution_id=v_execution.execution_id
    and step_id='init_execution'
  order by step_order
  limit 1;

  if v_snapshot.id is not null then
    v_target_revision:=public.lf_strategy_revision_sha256_v1(v_snapshot.id);
  end if;
  v_bound_revision:=v_init.evidence_payload->>'target_strategy_revision_sha256';
  v_operation_revision:=public.lf_operation_revision_sha256_v1(v_execution.operation_code);

  v_checks:=jsonb_build_object(
    'execution_binding',
      v_execution.execution_id=p_execution_id
      and v_execution.status='IN_PROGRESS'
      and btrim(coalesce(v_execution.idempotency_key,''))<>''
      and coalesce(v_execution.request_sha256,'') ~ '^[0-9a-f]{64}$',
    'operation_binding',
      v_execution.operation_code=v_canonical_route
      and v_execution.operation_code='EJECUCION_ESTRATEGIA_LF',
    'target_binding',
      v_execution.target_type='STRATEGY'
      and v_snapshot.id is not null
      and v_execution.target_path=format('supabase://public/lf_strategy_snapshots/%s',v_snapshot.id),
    'revision_binding',
      v_bound_revision is not null
      and v_bound_revision=v_target_revision,
    'producer_authority',
      v_route_count=1
      and v_canonical_route='EJECUCION_ESTRATEGIA_LF',
    'freshness',
      v_snapshot.id is not null
      and v_execution.target_path=format('supabase://public/lf_strategy_snapshots/%s',v_snapshot.id)
      and v_bound_revision=v_target_revision,
    'replay_resistance',
      btrim(coalesce(v_execution.idempotency_key,''))<>''
      and v_execution.lease_owner is not null
      and v_execution.lease_fence is not null
      and v_execution.lease_expires_at>statement_timestamp(),
    'spoof_resistance',
      v_classification->>'decision'='PROCEED_CANONICAL'
      and v_execution.operation_code=v_canonical_route,
    'toctou_resistance',
      v_bound_revision=v_target_revision
      and v_operation_revision is not null
      and v_execution.lease_expires_at>statement_timestamp(),
    'zero_effect_on_failure',true,
    'init_execution_binding',
      v_init.step_id='init_execution'
      and v_init.status='PASS_CLEAN'
      and v_init.evidence_ref=v_execution.target_path
  );

  select coalesce(jsonb_agg(key order by key),'[]'::jsonb)
    into v_open_defeaters
  from jsonb_each(v_checks)
  where value is distinct from 'true'::jsonb;

  select coalesce(jsonb_agg(key order by key),'[]'::jsonb)
    into v_closed_defeaters
  from jsonb_each(v_checks)
  where value is not distinct from 'true'::jsonb;

  v_valid :=
    v_classification->>'decision'='PROCEED_CANONICAL'
    and jsonb_array_length(v_open_defeaters)=0;

  return v_classification || jsonb_build_object(
    'valid',v_valid,
    'blocking_code',case when v_valid then null else 'CANONICAL_ROUTE_ASSURANCE_NOT_CLOSED' end,
    'receipt_type','LF_CANONICAL_ROUTE_GUARD_RECEIPT',
    'receipt_version','v1',
    'authority_ref','ACT-0001',
    'producer_ref','supabase://public/lf_router_action_registry+lf_operation_execution',
    'execution_id',v_execution.execution_id,
    'operation_code',v_execution.operation_code,
    'action_code','STRATEGY_EXECUTION',
    'target_type',v_execution.target_type,
    'target_code',v_execution.target_code,
    'target_path',v_execution.target_path,
    'target_revision_sha256',v_target_revision,
    'bound_target_revision_sha256',v_bound_revision,
    'operation_revision_sha256',v_operation_revision,
    'lease_owner',v_execution.lease_owner,
    'lease_fence',v_execution.lease_fence,
    'lease_expires_at',v_execution.lease_expires_at,
    'checks',v_checks,
    'open_defeaters',v_open_defeaters,
    'closed_defeaters',v_closed_defeaters,
    'observed_at',statement_timestamp()
  ) || case when v_valid then '{}'::jsonb else jsonb_build_object(
    'canonical_effect_allowed',false,
    'merge_allowed',false,
    'production_effect_allowed',false,
    'canonical_close_allowed',false,
    'pass_claim_allowed',false,
    'effect_authorization','DENIED_BY_ASSURANCE'
  ) end;
end;
$function$;

-- Patch the existing operation-neutral recorder at the canonical pre-write boundary.
-- The patch is fingerprint-pinned to the exact live source observed by the governed execution.
do $patch$
declare
  v_sig regprocedure := 'public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure;
  v_def text;
  v_new text;
  v_sha text;
  v_expected_sha constant text := 'c3cdc63b85689ba8c0f69c2f92cb0d2363524d08034483fe6db3764c70be1099';
begin
  select pg_get_functiondef(v_sig) into v_def;
  if v_def is null then raise exception 'S30_ROUTE_GUARD_CORE_MISSING'; end if;

  v_sha:=encode(extensions.digest(v_def,'sha256'),'hex');
  if v_sha is distinct from v_expected_sha then
    raise exception 'S30_ROUTE_GUARD_CORE_FINGERPRINT_MISMATCH expected=% actual=%',v_expected_sha,v_sha;
  end if;

  v_new:=replace(
    v_def,
    $old$  v_existing_retryable boolean := false;$old$,
    $new$  v_existing_retryable boolean := false;
  v_route_guard jsonb;$new$
  );
  if v_new is not distinct from v_def then raise exception 'S30_ROUTE_GUARD_CORE_DECLARATION_SHAPE_NOT_FOUND'; end if;
  v_def:=v_new;

  -- Server-derived receipt must not make clean replay depend on caller-supplied evidence.
  v_new:=replace(
    v_def,
    $old$'blocking_findings','blocking_codes','return_to_worker_reasons'$old$,
    $new$'blocking_findings','blocking_codes','return_to_worker_reasons','canonical_route_guard_receipt'$new$
  );
  if v_new is not distinct from v_def then raise exception 'S30_ROUTE_GUARD_CORE_REPLAY_EXISTING_SHAPE_NOT_FOUND'; end if;
  v_def:=v_new;

  v_new:=replace(
    v_def,
    $old$array['assertions_checked','hard_fails_checked','caller_assertions_ignored','blocking_codes']::text[]$old$,
    $new$array['assertions_checked','hard_fails_checked','caller_assertions_ignored','blocking_codes','canonical_route_guard_receipt']::text[]$new$
  );
  if v_new is not distinct from v_def then raise exception 'S30_ROUTE_GUARD_CORE_REPLAY_CALLER_SHAPE_NOT_FOUND'; end if;
  v_def:=v_new;

  v_new:=replace(
    v_def,
    $old$  if v_block_code is null and p_evidence_payload ? 'blocking_codes' then$old$,
    $new$  if v_block_code is null
     and v_execution.operation_code='EJECUCION_ESTRATEGIA_LF'
     and p_step_id='pre_write_execution_binding_gate' then
    v_route_guard:=public.lf_strategy_canonical_route_guard_v1(
      p_execution_id,v_execution.operation_code,false
    );
    if coalesce((v_route_guard->>'valid')::boolean,false) is not true then
      v_block_code:=coalesce(nullif(v_route_guard->>'blocking_code',''),'CANONICAL_ROUTE_GUARD_FAILED');
      v_block_details:=jsonb_build_object(
        'route_guard',v_route_guard,
        'execution_id',p_execution_id,
        'step_id',p_step_id
      );
    end if;
  end if;

  if v_block_code is null and p_evidence_payload ? 'blocking_codes' then$new$
  );
  if v_new is not distinct from v_def then raise exception 'S30_ROUTE_GUARD_CORE_PREWRITE_SHAPE_NOT_FOUND'; end if;
  v_def:=v_new;

  v_new:=replace(
    v_def,
    $old$  for v_key in select jsonb_array_elements_text(v_binding.required_evidence_keys) loop if not (v_payload ? v_key) then v_payload:=v_payload||jsonb_build_object(v_key,null); end if; end loop;$old$,
    $new$  if v_route_guard is not null then
    v_payload:=v_payload||jsonb_build_object('canonical_route_guard_receipt',v_route_guard);
  end if;
  for v_key in select jsonb_array_elements_text(v_binding.required_evidence_keys) loop if not (v_payload ? v_key) then v_payload:=v_payload||jsonb_build_object(v_key,null); end if; end loop;$new$
  );
  if v_new is not distinct from v_def then raise exception 'S30_ROUTE_GUARD_CORE_PERSISTENCE_SHAPE_NOT_FOUND'; end if;
  v_def:=v_new;

  execute v_def;
end;
$patch$;

revoke execute on function public.lf_canonical_route_guard_classify_v1(text,text,boolean) from public,anon,authenticated;
revoke execute on function public.lf_strategy_canonical_route_guard_v1(text,text,boolean) from public,anon,authenticated;
revoke execute on function public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text) from public,anon,authenticated;
grant execute on function public.lf_canonical_route_guard_classify_v1(text,text,boolean) to service_role;
grant execute on function public.lf_strategy_canonical_route_guard_v1(text,text,boolean) to service_role;
grant execute on function public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text) to service_role;

-- Extend the existing canonical S36 matrix evaluator; do not create another matrix/suite.
do $probe_patch$
declare
  v_sig regprocedure := 'public.lf_eval_strategy_matrix_probe_v1(jsonb,text,text,text)'::regprocedure;
  v_def text;
  v_new text;
  v_sha text;
  v_expected_sha constant text := 'dac89fa8fa022b4fa40ab8a7613e3ef9c444b76e66e19ac2a38ded03cf9d4489';
begin
  select pg_get_functiondef(v_sig) into v_def;
  if v_def is null then raise exception 'S30_ROUTE_GUARD_MATRIX_PROBE_MISSING'; end if;
  v_sha:=encode(extensions.digest(v_def,'sha256'),'hex');
  if v_sha is distinct from v_expected_sha then
    raise exception 'S30_ROUTE_GUARD_MATRIX_PROBE_FINGERPRINT_MISMATCH expected=% actual=%',v_expected_sha,v_sha;
  end if;

  v_new:=replace(
    v_def,
    $old$ when 'STRATEGY_QUALIFICATION_INVALIDATION' then canary:=public.lf_canary_strategy_material_change_invalidates_qualification_v1(sid); ok:=coalesce((canary->>'passed')::boolean,false); actual:=canary;
 else ok:=false; actual:=jsonb_build_object('error','UNKNOWN_PROBE_CODE','probe_code',pc);$old$,
    $new$ when 'STRATEGY_QUALIFICATION_INVALIDATION' then canary:=public.lf_canary_strategy_material_change_invalidates_qualification_v1(sid); ok:=coalesce((canary->>'passed')::boolean,false); actual:=canary;
 when 'ROUTE_GUARD_SERVER_BOUND' then
   select pg_get_functiondef('public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)'::regprocedure) into def;
   ok:=(
     to_regprocedure('public.lf_canonical_route_guard_classify_v1(text,text,boolean)') is not null
     and to_regprocedure('public.lf_strategy_canonical_route_guard_v1(text,text,boolean)') is not null
     and strpos(coalesce(def,''),'lf_strategy_canonical_route_guard_v1')>0
     and strpos(coalesce(def,''),'canonical_route_guard_receipt')>0
     and exists(
       select 1 from public.lf_operation_steps
       where operation_code=p_subject_code and step_id='pre_write_execution_binding_gate' and active=true
     )
     and exists(
       select 1 from public.lf_operation_step_judge_bindings
       where operation_code=p_subject_code and step_id='pre_write_execution_binding_gate' and status='ACTIVE_ENFORCEMENT'
     )
   );
   actual:=jsonb_build_object('server_enforced',ok,'operation_code',p_subject_code,'step_id','pre_write_execution_binding_gate');
 when 'ROUTE_GUARD_CLASSIFICATION' then
   actual:=public.lf_canonical_route_guard_classify_v1(
     p_probe->>'canonical_route',p_probe->>'selected_route',coalesce((p_probe->>'explicit_exploration')::boolean,false)
   );
   ok:=(
     actual->>'decision'=p_probe->>'expected_decision'
     and coalesce((actual->>'canonical_effect_allowed')::boolean,false)=coalesce((p_probe->>'expected_canonical_effect_allowed')::boolean,false)
     and coalesce((actual->>'ask_user')::boolean,false)=coalesce((p_probe->>'expected_ask_user')::boolean,false)
   );
 when 'ROUTE_GUARD_CLAIM_SURFACES' then
   select count(distinct obligation_code) into cnt
   from public.lf_assurance_obligation_catalog
   where claim_code='STRATEGY_ROUTER_AUTHENTIC_V1' and required=true;
   ok:=(
     exists(select 1 from public.lf_assurance_claim_catalog where claim_code='STRATEGY_ROUTER_AUTHENTIC_V1' and criticality='CRITICAL')
     and cnt=10
     and exists(
       select 1 from public.lf_assurance_subject_bindings
       where subject_code=p_subject_code and standard_claim_code='STRATEGY_ROUTER_AUTHENTIC_V1' and required=true
     )
   );
   actual:=jsonb_build_object('required_obligation_count',cnt,'claim_code','STRATEGY_ROUTER_AUTHENTIC_V1','subject_code',p_subject_code);
 else ok:=false; actual:=jsonb_build_object('error','UNKNOWN_PROBE_CODE','probe_code',pc);$new$
  );
  if v_new is not distinct from v_def then raise exception 'S30_ROUTE_GUARD_MATRIX_PROBE_SHAPE_NOT_FOUND'; end if;
  execute v_new;
end;
$probe_patch$;

-- Add PR876 semantics to the existing Strategy Execution qualification suite.
insert into public.lf_test_suite_cases(
  suite_code,test_code,test_order,story_code,rule_codes,title,test_type,execution_mode,severity,
  preconditions,input_payload,expected_output,prohibited_output,status,metadata,created_by_execution_id,updated_by_execution_id
)
values
('TS-STRATEGY-OP-EXECUTE-V1','E15',150,null,array['STRATEGY_ROUTER_AUTHENTIC_V1'],'Canonical route guard is server-bound at Strategy pre-write','CONTRACT','AUTOMATED','CRITICAL','[]'::jsonb,'{"probe_code":"ROUTE_GUARD_SERVER_BOUND"}'::jsonb,'{"passed":true}'::jsonb,'{}'::jsonb,'CANDIDATO','{"source_pr":876,"assurance_depth":"STRUCTURAL_PREWRITE"}'::jsonb,'EXEC-S30-TRANSVERSAL-ROUTE-GUARD-ASSURANCE-20260917-001','EXEC-S30-TRANSVERSAL-ROUTE-GUARD-ASSURANCE-20260917-001'),
('TS-STRATEGY-OP-EXECUTE-V1','E16',160,null,array['STRATEGY_ROUTER_AUTHENTIC_V1'],'Canonical route classifies as PROCEED_CANONICAL','DETERMINISTIC','AUTOMATED','CRITICAL','[]'::jsonb,'{"probe_code":"ROUTE_GUARD_CLASSIFICATION","canonical_route":"EJECUCION_ESTRATEGIA_LF","selected_route":"EJECUCION_ESTRATEGIA_LF","explicit_exploration":false,"expected_decision":"PROCEED_CANONICAL","expected_canonical_effect_allowed":true,"expected_ask_user":false}'::jsonb,'{"passed":true}'::jsonb,'{}'::jsonb,'CANDIDATO','{"source_pr":876,"assurance_depth":"POSITIVE"}'::jsonb,'EXEC-S30-TRANSVERSAL-ROUTE-GUARD-ASSURANCE-20260917-001','EXEC-S30-TRANSVERSAL-ROUTE-GUARD-ASSURANCE-20260917-001'),
('TS-STRATEGY-OP-EXECUTE-V1','E17',170,null,array['STRATEGY_ROUTER_AUTHENTIC_V1'],'Route deviation blocks canonical effect and asks once','ADVERSARIAL','AUTOMATED','CRITICAL','[]'::jsonb,'{"probe_code":"ROUTE_GUARD_CLASSIFICATION","canonical_route":"EJECUCION_ESTRATEGIA_LF","selected_route":"GIT_DIRECT","explicit_exploration":false,"expected_decision":"ASK_CANONICAL_OR_EXPLORATORY","expected_canonical_effect_allowed":false,"expected_ask_user":true}'::jsonb,'{"passed":true}'::jsonb,'{"canonical_effect_allowed":true}'::jsonb,'CANDIDATO','{"source_pr":876,"assurance_depth":"NEGATIVE_BYPASS"}'::jsonb,'EXEC-S30-TRANSVERSAL-ROUTE-GUARD-ASSURANCE-20260917-001','EXEC-S30-TRANSVERSAL-ROUTE-GUARD-ASSURANCE-20260917-001'),
('TS-STRATEGY-OP-EXECUTE-V1','E18',180,null,array['STRATEGY_ROUTER_AUTHENTIC_V1'],'Explicit exploration remains zero-canonical-effect','ADVERSARIAL','AUTOMATED','CRITICAL','[]'::jsonb,'{"probe_code":"ROUTE_GUARD_CLASSIFICATION","canonical_route":"EJECUCION_ESTRATEGIA_LF","selected_route":"GIT_DIRECT","explicit_exploration":true,"expected_decision":"PROCEED_EXPLORATORY_NO_CANONICAL_EFFECT","expected_canonical_effect_allowed":false,"expected_ask_user":false}'::jsonb,'{"passed":true}'::jsonb,'{"canonical_effect_allowed":true}'::jsonb,'CANDIDATO','{"source_pr":876,"assurance_depth":"EXPLORATORY_ZERO_EFFECT"}'::jsonb,'EXEC-S30-TRANSVERSAL-ROUTE-GUARD-ASSURANCE-20260917-001','EXEC-S30-TRANSVERSAL-ROUTE-GUARD-ASSURANCE-20260917-001'),
('TS-STRATEGY-OP-EXECUTE-V1','E19',190,null,array['STRATEGY_ROUTER_AUTHENTIC_V1'],'Unresolved canonical route fails safe before effect','ADVERSARIAL','AUTOMATED','CRITICAL','[]'::jsonb,'{"probe_code":"ROUTE_GUARD_CLASSIFICATION","canonical_route":null,"selected_route":"GIT_DIRECT","explicit_exploration":false,"expected_decision":"RESOLVE_CANONICAL_ROUTE_FIRST","expected_canonical_effect_allowed":false,"expected_ask_user":false}'::jsonb,'{"passed":true}'::jsonb,'{"canonical_effect_allowed":true}'::jsonb,'CANDIDATO','{"source_pr":876,"assurance_depth":"UNRESOLVED_FAIL_SAFE"}'::jsonb,'EXEC-S30-TRANSVERSAL-ROUTE-GUARD-ASSURANCE-20260917-001','EXEC-S30-TRANSVERSAL-ROUTE-GUARD-ASSURANCE-20260917-001'),
('TS-STRATEGY-OP-EXECUTE-V1','E20',200,null,array['STRATEGY_ROUTER_AUTHENTIC_V1'],'Route guard matrix is linked to the canonical Claim Assurance surfaces','CONTRACT','AUTOMATED','CRITICAL','[]'::jsonb,'{"probe_code":"ROUTE_GUARD_CLAIM_SURFACES"}'::jsonb,'{"passed":true}'::jsonb,'{}'::jsonb,'CANDIDATO','{"source_pr":876,"assurance_depth":"CLAIM_TRACEABILITY"}'::jsonb,'EXEC-S30-TRANSVERSAL-ROUTE-GUARD-ASSURANCE-20260917-001','EXEC-S30-TRANSVERSAL-ROUTE-GUARD-ASSURANCE-20260917-001')
on conflict (suite_code,test_code) do nothing;

-- Guard against an accidental second matrix/suite.
do $post$
declare
  v_count integer;
begin
  select count(*) into v_count from public.lf_test_suites where suite_code='TS-STRATEGY-OP-EXECUTE-V1';
  if v_count<>1 then raise exception 'S30_ROUTE_GUARD_CANONICAL_SUITE_NOT_EXACT:%',v_count; end if;
  if exists(select 1 from public.lf_test_suites where suite_code ilike '%ROUTE%GUARD%' and suite_code<>'TS-STRATEGY-OP-EXECUTE-V1') then
    raise exception 'S30_ROUTE_GUARD_PARALLEL_SUITE_FORBIDDEN';
  end if;
end;
$post$;
