-- S36 WP3 — Property / Stateful Assurance for governed asset lifecycle operations.
-- Read-only assurance only. No owner semantic mutation, Router activation, runtime, production or Golden promotion.
-- Reuses the one canonical LF Test Matrix/stores and the existing matrix runner.

create or replace function public.lf_s36_wp3_asset_lifecycle_probe_v1(
  p_operation_code text,
  p_case_code text
) returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog','public'
as $fn$
declare
  c public.lf_operation_contracts%rowtype;
  ok boolean := false;
  blocked_status text := null;
  reason text := null;
  details jsonb := '{}'::jsonb;
begin
  select * into c
  from public.lf_operation_contracts
  where operation_code=p_operation_code
    and status <> 'SUPERSEDED'
  order by updated_at desc
  limit 1;

  if c.operation_code is null then
    return jsonb_build_object('passed',false,'status_override','BLOCK','reason','OWNER_CONTRACT_MISSING','case_code',p_case_code);
  end if;

  case p_case_code
  when 'TRANSITION_SOURCE_STATE_GUARD' then
    ok := p_operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF'
      and jsonb_typeof(c.allowed->'from')='object'
      and c.blocked ? 'source_state_drift'
      and exists (
        select 1 from public.lf_operation_step_contracts s
        where s.operation_code=p_operation_code and s.step_id='source_state_read'
          and coalesce((s.block_condition->>'source_state_drift')::boolean,false)
          and s.status='CANDIDATO_READ_ONLY'
      )
      and exists (
        select 1 from public.lf_operation_judges j
        where j.operation_code=p_operation_code
          and j.judge_code='MINI_JUDGE_PROFILE_RUNTIME_TRANSITION_SOURCE_STATE_V1'
          and coalesce((j.fail_if->>'source_state_drift')::boolean,false)
          and j.status='CANDIDATO_READ_ONLY'
      );
    details := jsonb_build_object('from_state',c.allowed->'from','source_state_drift_blocked',c.blocked ? 'source_state_drift');

  when 'TRANSITION_SINGLE_TARGET_GUARD' then
    ok := p_operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF'
      and coalesce((c.allowed->>'single_target')::boolean,false)
      and c.blocked ? 'mass_transition'
      and exists (
        select 1 from public.lf_operation_step_contracts s
        where s.operation_code=p_operation_code and s.step_id='controlled_write'
          and coalesce((s.block_condition->>'mass_transition')::boolean,false)
          and s.status='CANDIDATO_READ_ONLY'
      );
    details := jsonb_build_object('single_target',c.allowed->'single_target','mass_transition_blocked',c.blocked ? 'mass_transition');

  when 'TRANSITION_ESCALATION_GUARD' then
    ok := p_operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF'
      and coalesce((c.allowed->>'automatic_impact')::boolean,true)=false
      and coalesce((c.allowed->>'production_enablement')::boolean,true)=false
      and c.blocked ? 'impact_change'
      and c.blocked ? 'production_enablement'
      and c.blocked ? 'automatic_promotion'
      and exists (
        select 1 from public.lf_operation_step_contracts s
        where s.operation_code=p_operation_code and s.step_id='controlled_write'
          and s.pass_condition->>'impacto_automatico'='BLOQUEADO'
          and coalesce((s.block_condition->>'impact_change')::boolean,false)
          and coalesce((s.block_condition->>'production_enablement')::boolean,false)
      );
    details := jsonb_build_object('automatic_impact',c.allowed->'automatic_impact','production_enablement',c.allowed->'production_enablement');

  when 'TRANSITION_SELF_ATTESTATION_GUARD' then
    ok := p_operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF' and c.blocked ? 'r4_self_attestation';
    details := jsonb_build_object('r4_self_attestation_blocked',c.blocked ? 'r4_self_attestation');

  when 'TRANSITION_READBACK_GUARD' then
    ok := p_operation_code='TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF'
      and c.required_after_write ? 'exact_state_readback'
      and c.required_after_write ? 'router_post_transition_readback'
      and c.required_after_write ? 'automatic_impact_still_blocked'
      and c.required_after_write ? 'no_production_promotion'
      and exists (
        select 1 from public.lf_operation_step_contracts s
        where s.operation_code=p_operation_code and s.step_id='readback'
          and s.required_evidence_keys ? 'exact_state_readback'
          and s.required_evidence_keys ? 'router_post_transition_readback'
          and s.required_evidence_keys ? 'automatic_impact_still_blocked'
      );
    details := jsonb_build_object('required_after_write',c.required_after_write);

  when 'TRANSITION_ROLLBACK_PROOF' then
    if p_operation_code<>'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF' then
      ok := false;
    elsif not coalesce((c.allowed->>'reversible')::boolean,false) then
      ok := false;
      reason := 'OWNER_CONTRACT_NOT_REVERSIBLE';
    else
      ok := false;
      blocked_status := 'BLOCK';
      reason := 'REVERSIBLE_DECLARED_BUT_AUTOMATED_ROLLBACK_PROOF_ABSENT';
    end if;
    details := jsonb_build_object('reversible',c.allowed->'reversible','owner_contract',c.contract_code);

  when 'TRANSITION_POSITIVE_EXECUTION' then
    if p_operation_code<>'TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF' then
      ok := false;
    elsif coalesce((c.allowed->>'persistent_write_executor')::boolean,false)=false then
      blocked_status := 'BLOCK';
      reason := 'OWNER_PERSISTENT_WRITE_EXECUTOR_NOT_AUTHORIZED';
      ok := false;
    else
      ok := true;
    end if;
    details := jsonb_build_object('persistent_write_executor',c.allowed->'persistent_write_executor');

  when 'RETIRE_CONSUMER_GUARD' then
    ok := p_operation_code='RETIRO_ACTIVO_LF'
      and c.required_before_write ? 'incoming_active_consumer_count_zero'
      and c.blocked ? 'archive_with_active_incoming_consumer'
      and c.allowed->>'consumer_guard' is not null
      and exists (
        select 1 from public.lf_operation_step_contracts s
        where s.operation_code=p_operation_code and s.step_id='dependency_consumer_check'
          and s.required_evidence_keys ? 'incoming_active_consumer_count'
          and s.required_evidence_keys ? 'consumer_guard_passed'
      );
    details := jsonb_build_object('consumer_guard',c.allowed->'consumer_guard');

  when 'RETIRE_REASON_REQUIRED' then
    ok := p_operation_code='RETIRO_ACTIVO_LF'
      and c.required_before_write ? 'retire_reason_nonempty'
      and c.blocked ? 'archive_without_reason'
      and c.required_after_write ? 'exact_archived_reason';
    details := jsonb_build_object('required_before_write',c.required_before_write,'required_after_write',c.required_after_write);

  when 'RETIRE_NO_HARD_DELETE' then
    ok := p_operation_code='RETIRO_ACTIVO_LF'
      and coalesce((c.allowed->>'hard_delete')::boolean,true)=false
      and c.blocked ? 'hard_delete'
      and c.required_after_write ? 'no_hard_delete'
      and c.allowed->'changed_fields' = '["archived_at","archived_reason","updated_at","updated_by_execution_id"]'::jsonb;
    details := jsonb_build_object('hard_delete',c.allowed->'hard_delete','changed_fields',c.allowed->'changed_fields');

  when 'RETIRE_LINEAGE_PRESERVATION' then
    ok := p_operation_code='RETIRO_ACTIVO_LF'
      and coalesce((c.allowed->>'relations_preserved')::boolean,false)
      and coalesce((c.allowed->>'evidence_preservation')::boolean,false)
      and c.blocked ? 'overwrite_lineage'
      and c.required_after_write ? 'relations_preserved';
    details := jsonb_build_object('relations_preserved',c.allowed->'relations_preserved','evidence_preservation',c.allowed->'evidence_preservation');

  when 'RETIRE_IDEMPOTENCY_GUARD' then
    ok := p_operation_code='RETIRO_ACTIVO_LF'
      and coalesce(c.allowed->>'idempotency_rule','')<>''
      and c.required_after_write ? 'second_effect_count_zero'
      and exists (
        select 1 from public.lf_operation_step_contracts s
        where s.operation_code=p_operation_code and s.step_id='idempotency_negative_validation'
          and s.required_evidence_keys ? 'second_effect_count'
          and s.required_evidence_keys ? 'idempotency_result'
      );
    details := jsonb_build_object('idempotency_rule',c.allowed->'idempotency_rule');

  when 'RETIRE_READBACK_GUARD' then
    ok := p_operation_code='RETIRO_ACTIVO_LF'
      and c.required_after_write ? 'archive_write_receipt'
      and c.required_after_write ? 'independent_archive_readback'
      and c.required_after_write ? 'execution_provenance_readback'
      and exists (
        select 1 from public.lf_operation_step_contracts s
        where s.operation_code=p_operation_code and s.step_id='archive_readback'
          and s.required_evidence_keys ? 'exact_archive_readback'
          and s.required_evidence_keys ? 'independent_readback'
      );
    details := jsonb_build_object('required_after_write',c.required_after_write);

  when 'RETIRE_EXECUTABLE_PATH' then
    if p_operation_code='RETIRO_ACTIVO_LF' and not exists (
      select 1 from public.lf_operation_step_contracts s
      where s.operation_code=p_operation_code and s.step_id='archive_write'
        and coalesce(s.execution_sql,'')<>''
    ) then
      blocked_status := 'BLOCK';
      reason := 'OWNER_ARCHIVE_WRITE_EXECUTOR_NOT_PRESENT';
      ok := false;
    else
      ok := true;
    end if;
    details := jsonb_build_object('archive_write_execution_sql_present',exists(select 1 from public.lf_operation_step_contracts s where s.operation_code=p_operation_code and s.step_id='archive_write' and coalesce(s.execution_sql,'')<>''));

  else
    return jsonb_build_object('passed',false,'status_override','FAIL','reason','UNKNOWN_WP3_CASE_CODE','case_code',p_case_code);
  end case;

  return jsonb_strip_nulls(jsonb_build_object(
    'passed',coalesce(ok,false),
    'status_override',blocked_status,
    'reason',reason,
    'case_code',p_case_code,
    'operation_code',p_operation_code,
    'contract_code',c.contract_code,
    'contract_status',c.status,
    'details',details
  ));
end
$fn$;

create or replace function public.lf_eval_strategy_matrix_probe_v1(p_probe jsonb, p_subject_type text, p_subject_code text, p_revision_sha256 text)
returns jsonb language plpgsql set search_path to 'pg_catalog','public' as $fn$
declare pc text:=p_probe->>'probe_code'; ok boolean:=false; actual jsonb:='{}'::jsonb; cnt int; sid bigint; def text; rp jsonb; expb boolean; actb boolean; st text; canary jsonb;
begin
 if p_subject_type='STRATEGY' then select id into sid from public.lf_strategy_snapshots where snapshot_code=p_subject_code order by id desc limit 1; end if;
 case pc
 when 'S36_WP3_ASSET_LIFECYCLE' then actual:=public.lf_s36_wp3_asset_lifecycle_probe_v1(p_subject_code,p_probe->>'case_code'); ok:=coalesce((actual->>'passed')::boolean,false);
 when 'OP_REGISTRY_STATE_VALID' then select exists(select 1 from public.lf_operation_registry r join lf_ops.estados_catalogo s on s.state_code=r.lifecycle_state_code and s.entity_type='OPERATION_LIFECYCLE' and s.status='VIGENTE' where r.operation_code=p_subject_code) into ok;
 when 'ROUTER_ACTIVE' then select exists(select 1 from public.lf_router_action_registry where operation_code=p_subject_code and status='ACTIVE') into ok;
 when 'ACTIVE_CONTRACT_PRESENT' then select exists(select 1 from public.lf_operation_contracts where operation_code=p_subject_code and status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')) into ok;
 when 'ACTIVE_STEPS_PRESENT' then select exists(select 1 from public.lf_operation_step_contracts where operation_code=p_subject_code and status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')) into ok;
 when 'ALL_ACTIVE_STEPS_JUDGED' then select not exists(select 1 from public.lf_operation_step_contracts s where s.operation_code=p_subject_code and s.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO') and (s.mini_judge_code is null or not exists(select 1 from public.lf_operation_judges j where j.operation_code=p_subject_code and j.judge_code=s.mini_judge_code and j.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')))) into ok;
 when 'STEP_PRESENT' then select exists(select 1 from public.lf_operation_step_contracts where operation_code=p_subject_code and step_id=p_probe->>'step_id' and status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')) into ok;
 when 'INITIAL_LIFECYCLE_TABLE_DRIVEN' then select count(*) into cnt from information_schema.columns where table_schema='public' and table_name=p_probe->>'table_name' and column_name='lifecycle_state_code' and column_default is null; ok:=(cnt=1 and public.lf_lifecycle_initial_state_v1(p_probe->>'entity_type') is not null and exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname=p_probe->>'table_name' and t.tgname like '%initial_lifecycle%' and not t.tgisinternal));
 when 'QUALIFICATION_BINDING_PRESENT' then select exists(select 1 from public.lf_test_requirement_bindings where subject_type='OPERATION' and subject_code=p_subject_code and status='ACTIVE') into ok;
 when 'ROUTER_NATURAL_ACTION' then rp:=public.lf_router_resolve_v1(p_probe->>'request',null,null,'STRATEGY','ROUTER'); ok:=((rp->>'status'='READY_TO_EXECUTE' and rp->>'action_code'=p_probe->>'expected_action' and rp->>'operation_code'=p_subject_code) or (rp->>'status'='BLOCKED' and rp->>'blocking_code'='BLOCK_OPERATION_QUALIFICATION_REQUIRED' and rp->>'operation_code'=p_subject_code and exists(select 1 from public.lf_router_action_registry a where a.operation_code=p_subject_code and a.action_code=p_probe->>'expected_action' and a.status='ACTIVE'))); actual:=rp;
 when 'FUNCTION_TABLE_DRIVEN' then select pg_get_functiondef(to_regprocedure('public.'||(p_probe->>'function_signature'))) into def; ok:=(def is not null and (strpos(def,'lf_lifecycle_resolve_transition_v1')>0 or strpos(def,'lf_lifecycle_transition_spec_v1')>0) and lower(def) !~ 'lifecycle_state_code\s*(=|in\s*\()\s*''strategy_(planned|active|closed|superseded)''');
 when 'FUNCTION_TERMINAL_HELPER' then select pg_get_functiondef(to_regprocedure('public.'||(p_probe->>'function_signature'))) into def; ok:=(def is not null and strpos(def,'lf_lifecycle_state_is_terminal_v1')>0);
 when 'TRIGGER_PRESENT' then select exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname=p_probe->>'table_name' and t.tgname=p_probe->>'trigger_name' and not t.tgisinternal) into ok;
 when 'OP_CONTRACT_BOOL' then expb:=(p_probe->>'expected')::boolean; select (c.allowed->>(p_probe->>'key'))::boolean into actb from public.lf_operation_contracts c where c.operation_code=p_subject_code and c.status='ACTIVE_ENFORCEMENT' order by c.updated_at desc limit 1; ok:=(actb is not distinct from expb); actual:=jsonb_build_object('actual',actb,'expected',expb);
 when 'STRATEGY_STATE_CATALOG_VALID' then select exists(select 1 from public.lf_strategy_snapshots s join lf_ops.estados_catalogo e on e.state_code=s.lifecycle_state_code and e.entity_type='STRATEGY_LIFECYCLE' and e.status='VIGENTE' where s.id=sid) into ok;
 when 'STRATEGY_NOT_TERMINAL' then select not public.lf_lifecycle_state_is_terminal_v1('STRATEGY_LIFECYCLE',lifecycle_state_code) into ok from public.lf_strategy_snapshots where id=sid;
 when 'STRATEGY_REVISION_MATCH' then ok:=(public.lf_strategy_revision_sha256_v1(sid)=p_revision_sha256); actual:=jsonb_build_object('actual_revision',public.lf_strategy_revision_sha256_v1(sid),'expected_revision',p_revision_sha256);
 when 'STRATEGY_CHARACTERISTICS_COMPLETE' then select not exists(select 1 from public.lf_strategy_test_characteristic_catalog k where k.status='ACTIVE' and not exists(select 1 from public.lf_strategy_test_characteristics c where c.snapshot_id=sid and c.characteristic_code=k.characteristic_code and c.enabled is not null)) into ok;
 when 'STRATEGY_CONDITIONAL_BINDINGS_RESOLVED' then select not exists(select 1 from public.lf_strategy_test_characteristics c where c.snapshot_id=sid and c.enabled is true and not exists(select 1 from public.lf_test_requirement_bindings b where b.subject_type='STRATEGY' and b.subject_code='*' and b.characteristic_code=c.characteristic_code and b.status='ACTIVE')) into ok;
 when 'EXECUTOR_OPERATIONAL' then select lifecycle_state_code into st from public.lf_operation_registry where operation_code='EJECUCION_ESTRATEGIA_LF'; ok:=(st=public.lf_lifecycle_action_target_state_v1('OPERATION_LIFECYCLE','PROMOTE_OPERATION'));
 when 'STRATEGY_POLICY_FINGERPRINT_PRESENT' then select coalesce(metadata->>'policy_set_fingerprint','')<>'' into ok from public.lf_strategy_snapshots where id=sid;
 when 'STRATEGY_UNIQUE_CODE_VERSION' then select count(*)=1 into ok from public.lf_strategy_snapshots s join public.lf_strategy_snapshots x on x.snapshot_code=s.snapshot_code and x.version=s.version where s.id=sid;
 when 'STRATEGY_START_TRANSITION_PRESENT' then begin perform public.lf_lifecycle_transition_spec_v1('STRATEGY_LIFECYCLE',(select lifecycle_state_code from public.lf_strategy_snapshots where id=sid),'START_EXECUTION'); ok:=true; exception when others then ok:=false; end;
 when 'STRATEGY_CURRENT_VERSION' then select id=(select max(id) from public.lf_strategy_snapshots x where x.snapshot_code=s.snapshot_code) into ok from public.lf_strategy_snapshots s where s.id=sid;
 when 'STRATEGY_ASSURANCE_DECLARATION' then select jsonb_typeof(metadata->'test_assurance'->(p_probe->>'assurance_key'))='object' into ok from public.lf_strategy_snapshots where id=sid;
 when 'STRATEGY_ASSURANCE_EVIDENCE' then select jsonb_typeof(metadata->'test_assurance'->(p_probe->>'assurance_key')->'evidence_refs')='array' and jsonb_array_length(metadata->'test_assurance'->(p_probe->>'assurance_key')->'evidence_refs')>0 into ok from public.lf_strategy_snapshots where id=sid;
 when 'STRATEGY_UNQUALIFIED_EXECUTION_BLOCK' then canary:=public.lf_canary_strategy_unqualified_execution_block_v1(sid); ok:=coalesce((canary->>'passed')::boolean,false); actual:=canary;
 when 'STRATEGY_QUALIFICATION_INVALIDATION' then canary:=public.lf_canary_strategy_material_change_invalidates_qualification_v1(sid); ok:=coalesce((canary->>'passed')::boolean,false); actual:=canary;
 else ok:=false; actual:=jsonb_build_object('error','UNKNOWN_PROBE_CODE','probe_code',pc);
 end case;
 return jsonb_build_object('passed',coalesce(ok,false),'probe_code',pc,'actual',actual,'status_override',actual->>'status_override');
end
$fn$;

create or replace function public.lf_run_strategy_matrix_suite_v1(p_suite_code text,p_subject_type text,p_subject_code text,p_revision_sha256 text,p_execution_id text)
returns jsonb language plpgsql set search_path to 'pg_catalog','public' as $fn$
declare sr uuid; c public.lf_test_suite_cases%rowtype; ev jsonb; st text; passed int:=0; failed int:=0; blocked int:=0; reviews int:=0; total int:=0; startv timestamptz:=clock_timestamp(); suite_rev text; ov text;
begin
 if not exists(select 1 from public.lf_test_suites where suite_code=p_suite_code) then raise exception 'LF_MATRIX_SUITE_MISSING:%',p_suite_code; end if;
 suite_rev:=public.lf_test_suite_revision_sha256_v1(p_suite_code);
 insert into public.lf_test_suite_runs(suite_code,execution_id,environment,application_version,rule_set_version,executor_type,executor_name,status,started_at,manifest,metadata,created_by_execution_id)
 values(p_suite_code,p_execution_id,'SUPABASE_LIVE','S36_WP3_ASSET_LIFECYCLE_V1','S36-WP3-v1','DETERMINISTIC_DB','lf_run_strategy_matrix_suite_v1','IN_PROGRESS',startv,jsonb_build_object('subject_type',p_subject_type,'subject_code',p_subject_code,'revision_sha256',p_revision_sha256,'suite_revision_sha256',suite_rev),jsonb_build_object('subject_type',p_subject_type,'subject_code',p_subject_code,'revision_sha256',p_revision_sha256,'suite_revision_sha256',suite_rev),p_execution_id) returning suite_run_id into sr;
 for c in select * from public.lf_test_suite_cases where suite_code=p_suite_code and status='CANDIDATO' order by test_order loop
   total:=total+1;
   if c.execution_mode='INDEPENDENT_REVIEW' then st:='REVIEW_REQUIRED'; reviews:=reviews+1; ev:=jsonb_build_object('passed',false,'review_required',true,'probe_code',c.input_payload->>'probe_code');
   else ev:=public.lf_eval_strategy_matrix_probe_v1(c.input_payload,p_subject_type,p_subject_code,p_revision_sha256); ov:=nullif(ev->>'status_override',''); if ov='BLOCK' then st:='BLOCKED'; blocked:=blocked+1; elsif ov='FAIL' then st:='FAIL'; failed:=failed+1; elsif coalesce((ev->>'passed')::boolean,false) then st:='PASS'; passed:=passed+1; else st:='FAIL'; failed:=failed+1; end if; end if;
   insert into public.lf_test_runs(suite_run_id,suite_code,test_code,execution_id,operation_code,environment,application_version,rule_set_version,executor_type,executor_name,status,input_payload,expected_output,actual_output,severity,started_at,completed_at,duration_ms,evidence_payload,metadata,created_by_execution_id)
   values(sr,p_suite_code,c.test_code,p_execution_id,case when p_subject_type='OPERATION' then p_subject_code else null end,'SUPABASE_LIVE','S36_WP3_ASSET_LIFECYCLE_V1','S36-WP3-v1','DETERMINISTIC_DB','lf_run_strategy_matrix_suite_v1',st,c.input_payload,c.expected_output,ev,c.severity,clock_timestamp(),clock_timestamp(),0,ev,jsonb_build_object('subject_type',p_subject_type,'subject_code',p_subject_code,'revision_sha256',p_revision_sha256,'suite_revision_sha256',suite_rev),p_execution_id);
 end loop;
 update public.lf_test_suite_runs set status=case when failed>0 then 'FAILED' when blocked>0 then 'BLOCKED' when reviews>0 then 'REVIEW_REQUIRED' else 'PASSED' end,completed_at=clock_timestamp(),duration_ms=(extract(epoch from (clock_timestamp()-startv))*1000)::bigint,tests_total=total,tests_passed=passed,tests_failed=failed,tests_blocked=blocked,tests_review_required=reviews,updated_at=clock_timestamp(),updated_by_execution_id=p_execution_id where suite_run_id=sr;
 return jsonb_build_object('suite_run_id',sr,'suite_code',p_suite_code,'suite_revision_sha256',suite_rev,'status',case when failed>0 then 'FAILED' when blocked>0 then 'BLOCKED' when reviews>0 then 'REVIEW_REQUIRED' else 'PASSED' end,'tests_total',total,'tests_passed',passed,'tests_failed',failed,'tests_blocked',blocked,'tests_review_required',reviews);
end
$fn$;

insert into public.lf_test_suites(suite_code,module_code,name,version,status,rule_set_code,execution_policy,metadata,created_by_execution_id,updated_by_execution_id)
values
('TS-S36-WP3-PROFILE-TRANSITION-V1','LF_TEST_ASSURANCE','S36 WP3 Profile runtime transition stateful assurance','v1','CANDIDATO',null,'{"deterministic_first":true,"false_pass_tolerance":0,"owner_execution_not_authorized_is_block":true,"runtime_write_allowed":false}'::jsonb,'{"canonical_matrix":"S36_CANONICAL_LF_TEST_MATRIX_V1","family":"PROFILES","process":"TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF","source_owner":"S26_PROFILE_RUNTIME","assurance_owner":"S36","dimension":"PROFUNDIDAD","no_owner_semantic_mutation":true,"no_runtime_change":true,"no_production_change":true,"no_golden_change":true}'::jsonb,'EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001'),
('TS-S36-WP3-ASSET-RETIRE-V1','LF_TEST_ASSURANCE','S36 WP3 governed asset retire stateful assurance','v1','CANDIDATO',null,'{"deterministic_first":true,"false_pass_tolerance":0,"owner_execution_not_authorized_is_block":true,"runtime_write_allowed":false}'::jsonb,'{"canonical_matrix":"S36_CANONICAL_LF_TEST_MATRIX_V1","family_binding_mode":"MULTI_FAMILY_EXPLICIT_OWNER_ASSET_TYPES","owner_asset_types":["PERFIL","CARD","ADAPTER","SKILL"],"formal_family_mapping_status":"PENDING_CANONICAL_MULTI_FAMILY_AUTHORITY","process":"RETIRO_ACTIVO_LF","source_owner":"S29_ASSET_LIFECYCLE_GOVERNANCE","assurance_owner":"S36","dimension":"PROFUNDIDAD","no_owner_semantic_mutation":true,"no_runtime_change":true,"no_production_change":true,"no_golden_change":true}'::jsonb,'EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001')
on conflict (suite_code) do update set module_code=excluded.module_code,name=excluded.name,version=excluded.version,status=excluded.status,execution_policy=excluded.execution_policy,metadata=excluded.metadata,updated_at=clock_timestamp(),updated_by_execution_id=excluded.updated_by_execution_id;

insert into public.lf_test_suite_cases(suite_code,test_code,test_order,story_code,rule_codes,title,test_type,execution_mode,severity,preconditions,input_payload,expected_output,prohibited_output,status,metadata,created_by_execution_id,updated_by_execution_id)
values
('TS-S36-WP3-PROFILE-TRANSITION-V1','WP3-TR-01',10,null,'{}','Exact source-state guard is enforced','DETERMINISTIC','AUTOMATED','CRITICAL','[]','{"probe_code":"S36_WP3_ASSET_LIFECYCLE","case_code":"TRANSITION_SOURCE_STATE_GUARD"}','{"passed":true}','{}','CANDIDATO','{"dimension":"PROFUNDIDAD","depth":["STATEFUL_SEQUENCE","NEGATIVE"]}','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001'),
('TS-S36-WP3-PROFILE-TRANSITION-V1','WP3-TR-02',20,null,'{}','Mass transition is fail-closed by single-target contract','DETERMINISTIC','AUTOMATED','CRITICAL','[]','{"probe_code":"S36_WP3_ASSET_LIFECYCLE","case_code":"TRANSITION_SINGLE_TARGET_GUARD"}','{"passed":true}','{}','CANDIDATO','{"dimension":"PROFUNDIDAD","depth":["NEGATIVE","EDGE"]}','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001'),
('TS-S36-WP3-PROFILE-TRANSITION-V1','WP3-TR-03',30,null,'{}','Impact and production escalation are prohibited','DETERMINISTIC','AUTOMATED','CRITICAL','[]','{"probe_code":"S36_WP3_ASSET_LIFECYCLE","case_code":"TRANSITION_ESCALATION_GUARD"}','{"passed":true}','{}','CANDIDATO','{"dimension":"PROFUNDIDAD","depth":["NEGATIVE","EDGE"]}','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001'),
('TS-S36-WP3-PROFILE-TRANSITION-V1','WP3-TR-04',40,null,'{}','R4 self-attestation cannot authorize transition','DETERMINISTIC','AUTOMATED','HIGH','[]','{"probe_code":"S36_WP3_ASSET_LIFECYCLE","case_code":"TRANSITION_SELF_ATTESTATION_GUARD"}','{"passed":true}','{}','CANDIDATO','{"dimension":"PROFUNDIDAD","depth":["NEGATIVE"]}','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001'),
('TS-S36-WP3-PROFILE-TRANSITION-V1','WP3-TR-05',50,null,'{}','Independent post-transition readback is mandatory','DETERMINISTIC','AUTOMATED','CRITICAL','[]','{"probe_code":"S36_WP3_ASSET_LIFECYCLE","case_code":"TRANSITION_READBACK_GUARD"}','{"passed":true}','{}','CANDIDATO','{"dimension":"PROFUNDIDAD","depth":["REQUIRED_STEP_REACHABILITY","PATH_TRAJECTORY"]}','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001'),
('TS-S36-WP3-PROFILE-TRANSITION-V1','WP3-TR-06',60,null,'{}','Declared reversible transition has automated rollback proof','DETERMINISTIC','AUTOMATED','CRITICAL','[]','{"probe_code":"S36_WP3_ASSET_LIFECYCLE","case_code":"TRANSITION_ROLLBACK_PROOF"}','{"passed":true}','{}','CANDIDATO','{"dimension":"PROFUNDIDAD","depth":["STATEFUL_SEQUENCE"],"expected_if_owner_gap":"BLOCK"}','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001'),
('TS-S36-WP3-PROFILE-TRANSITION-V1','WP3-TR-07',70,null,'{}','Valid transition positive path has an authorized persistent executor','DETERMINISTIC','AUTOMATED','CRITICAL','[]','{"probe_code":"S36_WP3_ASSET_LIFECYCLE","case_code":"TRANSITION_POSITIVE_EXECUTION"}','{"passed":true}','{}','CANDIDATO','{"dimension":"FUNCIONALIDAD","depth":["STATEFUL_SEQUENCE","PATH_TRAJECTORY"],"expected_if_owner_gap":"BLOCK"}','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001'),
('TS-S36-WP3-ASSET-RETIRE-V1','WP3-RT-01',10,null,'{}','Retire blocks active incoming consumers','DETERMINISTIC','AUTOMATED','CRITICAL','[]','{"probe_code":"S36_WP3_ASSET_LIFECYCLE","case_code":"RETIRE_CONSUMER_GUARD"}','{"passed":true}','{}','CANDIDATO','{"dimension":"PROFUNDIDAD","depth":["NEGATIVE","STATEFUL_SEQUENCE"]}','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001'),
('TS-S36-WP3-ASSET-RETIRE-V1','WP3-RT-02',20,null,'{}','Retire requires a nonempty reason','DETERMINISTIC','AUTOMATED','HIGH','[]','{"probe_code":"S36_WP3_ASSET_LIFECYCLE","case_code":"RETIRE_REASON_REQUIRED"}','{"passed":true}','{}','CANDIDATO','{"dimension":"PROFUNDIDAD","depth":["NEGATIVE"]}','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001'),
('TS-S36-WP3-ASSET-RETIRE-V1','WP3-RT-03',30,null,'{}','Retire forbids hard delete and bounds changed fields','DETERMINISTIC','AUTOMATED','CRITICAL','[]','{"probe_code":"S36_WP3_ASSET_LIFECYCLE","case_code":"RETIRE_NO_HARD_DELETE"}','{"passed":true}','{}','CANDIDATO','{"dimension":"PROFUNDIDAD","depth":["NEGATIVE","EDGE"]}','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001'),
('TS-S36-WP3-ASSET-RETIRE-V1','WP3-RT-04',40,null,'{}','Retire preserves relations lineage and historical evidence','DETERMINISTIC','AUTOMATED','CRITICAL','[]','{"probe_code":"S36_WP3_ASSET_LIFECYCLE","case_code":"RETIRE_LINEAGE_PRESERVATION"}','{"passed":true}','{}','CANDIDATO','{"dimension":"PROFUNDIDAD","depth":["STATEFUL_SEQUENCE","PATH_TRAJECTORY"]}','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001'),
('TS-S36-WP3-ASSET-RETIRE-V1','WP3-RT-05',50,null,'{}','Repeat retire is idempotent by contract and required validation step','DETERMINISTIC','AUTOMATED','CRITICAL','[]','{"probe_code":"S36_WP3_ASSET_LIFECYCLE","case_code":"RETIRE_IDEMPOTENCY_GUARD"}','{"passed":true}','{}','CANDIDATO','{"dimension":"PROFUNDIDAD","depth":["REPLAY_IDEMPOTENCY","NEGATIVE"]}','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001'),
('TS-S36-WP3-ASSET-RETIRE-V1','WP3-RT-06',60,null,'{}','Retire requires archive receipt provenance and independent readback','DETERMINISTIC','AUTOMATED','CRITICAL','[]','{"probe_code":"S36_WP3_ASSET_LIFECYCLE","case_code":"RETIRE_READBACK_GUARD"}','{"passed":true}','{}','CANDIDATO','{"dimension":"PROFUNDIDAD","depth":["REQUIRED_STEP_REACHABILITY","PATH_TRAJECTORY"]}','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001'),
('TS-S36-WP3-ASSET-RETIRE-V1','WP3-RT-07',70,null,'{}','Retire positive path has an owner-authorized archive writer','DETERMINISTIC','AUTOMATED','CRITICAL','[]','{"probe_code":"S36_WP3_ASSET_LIFECYCLE","case_code":"RETIRE_EXECUTABLE_PATH"}','{"passed":true}','{}','CANDIDATO','{"dimension":"FUNCIONALIDAD","depth":["STATEFUL_SEQUENCE","PATH_TRAJECTORY"],"expected_if_owner_gap":"BLOCK"}','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001')
on conflict (suite_code,test_code) do update set test_order=excluded.test_order,title=excluded.title,test_type=excluded.test_type,execution_mode=excluded.execution_mode,severity=excluded.severity,preconditions=excluded.preconditions,input_payload=excluded.input_payload,expected_output=excluded.expected_output,prohibited_output=excluded.prohibited_output,status=excluded.status,metadata=excluded.metadata,updated_at=clock_timestamp(),updated_by_execution_id=excluded.updated_by_execution_id;

insert into public.lf_test_requirement_bindings(binding_code,subject_type,subject_code,characteristic_code,suite_code,required,min_pass_rate,false_pass_tolerance,independent_review_required,rollback_required,currentness_mode,activation_condition,effective_from,status,created_by_execution_id,updated_by_execution_id)
values
('BIND-S36-WP3-PROFILE-TRANSITION-V1','OPERATION','TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF',null,'TS-S36-WP3-PROFILE-TRANSITION-V1',true,1.0,0,false,true,'EXACT_REVISION','{"type":"ALWAYS","assurance_only":true,"owner_execution_not_authorized_is_block":true}'::jsonb,clock_timestamp(),'ACTIVE','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001'),
('BIND-S36-WP3-ASSET-RETIRE-V1','OPERATION','RETIRO_ACTIVO_LF',null,'TS-S36-WP3-ASSET-RETIRE-V1',true,1.0,0,false,true,'EXACT_REVISION','{"type":"ALWAYS","assurance_only":true,"owner_execution_not_authorized_is_block":true}'::jsonb,clock_timestamp(),'ACTIVE','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001','EXEC-S36-WP03-ASSET-LIFECYCLE-AUTOMATION-20260914-001')
on conflict (binding_code) do update set suite_code=excluded.suite_code,required=excluded.required,min_pass_rate=excluded.min_pass_rate,false_pass_tolerance=excluded.false_pass_tolerance,independent_review_required=excluded.independent_review_required,rollback_required=excluded.rollback_required,currentness_mode=excluded.currentness_mode,activation_condition=excluded.activation_condition,status=excluded.status,updated_at=clock_timestamp(),updated_by_execution_id=excluded.updated_by_execution_id;

do $assert$
declare a jsonb; b jsonb;
begin
  if (select count(*) from public.lf_test_suites where suite_code in ('TS-S36-WP3-PROFILE-TRANSITION-V1','TS-S36-WP3-ASSET-RETIRE-V1'))<>2 then raise exception 'S36_WP3_SUITE_ASSERTION_FAILED'; end if;
  if (select count(*) from public.lf_test_suite_cases where suite_code='TS-S36-WP3-PROFILE-TRANSITION-V1')<>7 then raise exception 'S36_WP3_TRANSITION_CASE_COUNT_FAILED'; end if;
  if (select count(*) from public.lf_test_suite_cases where suite_code='TS-S36-WP3-ASSET-RETIRE-V1')<>7 then raise exception 'S36_WP3_RETIRE_CASE_COUNT_FAILED'; end if;
  if (select count(*) from public.lf_test_requirement_bindings where binding_code in ('BIND-S36-WP3-PROFILE-TRANSITION-V1','BIND-S36-WP3-ASSET-RETIRE-V1') and status='ACTIVE')<>2 then raise exception 'S36_WP3_BINDING_ASSERTION_FAILED'; end if;
  a:=public.lf_s36_wp3_asset_lifecycle_probe_v1('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','TRANSITION_SOURCE_STATE_GUARD');
  b:=public.lf_s36_wp3_asset_lifecycle_probe_v1('RETIRO_ACTIVO_LF','RETIRE_IDEMPOTENCY_GUARD');
  if not coalesce((a->>'passed')::boolean,false) then raise exception 'S36_WP3_TRANSITION_PROBE_ASSERTION_FAILED:%',a; end if;
  if not coalesce((b->>'passed')::boolean,false) then raise exception 'S36_WP3_RETIRE_PROBE_ASSERTION_FAILED:%',b; end if;
  if public.lf_s36_wp3_asset_lifecycle_probe_v1('TRANSICION_RUNTIME_PERFIL_READ_ONLY_LF','TRANSITION_ROLLBACK_PROOF')->>'status_override' <> 'BLOCK' then raise exception 'S36_WP3_ROLLBACK_BLOCK_ASSERTION_FAILED'; end if;
  if public.lf_s36_wp3_asset_lifecycle_probe_v1('RETIRO_ACTIVO_LF','RETIRE_EXECUTABLE_PATH')->>'status_override' <> 'BLOCK' then raise exception 'S36_WP3_RETIRE_EXECUTOR_BLOCK_ASSERTION_FAILED'; end if;
end
$assert$;