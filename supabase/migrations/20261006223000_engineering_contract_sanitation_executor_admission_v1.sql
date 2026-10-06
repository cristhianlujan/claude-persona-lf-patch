-- ENGINEERING contract sanitation + executor admission v1
-- Scope:
-- 1) fail closed on material/complex checkpoint semantics inferred from title/recipe;
-- 2) keep only bounded read-only generic compilation;
-- 3) enforce exact RUN_TEST contracts;
-- 4) admit units before consuming a scheduler lane;
-- 5) normalize T-EQUIV transversal identity so it is consumer-parameterized;
-- 6) expose a one-call dispatch bundle for host-side concurrent lane workers.

create or replace function programacion.fn_engineering_action_spec_sanitize_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_spec jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_meta jsonb;
  v_explicit boolean := false;
  v_tx jsonb;
  v_kind text := coalesce(p_spec->>'action_kind','');
  v_material boolean := coalesce((p_spec->>'requires_material_execution')::boolean,false);
  v_verification_count int := coalesce(jsonb_array_length(coalesce(p_spec->'verification_queries','[]'::jsonb)),0);
  v_structural_transversal boolean := false;
  v_safe_generic boolean := false;
  v_complex_semantics boolean := false;
  v_seed text;
  v_digest text;
  v_prefix text;
  v_query text;
  v_out jsonb := p_spec;
begin
  if p_spec is null then
    return null;
  end if;

  select pu.unit_metadata
    into v_meta
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code;

  v_explicit :=
    coalesce(v_meta#>array['action_specs_v1',p_checkpoint_code],'null'::jsonb) <> 'null'::jsonb;

  v_tx := v_meta#>array['transversal_execution_v1',p_checkpoint_code];

  v_structural_transversal :=
    v_tx is not null
    and coalesce(v_tx->>'activation','ACTIVE') <> 'DECLARED_ONLY'
    and coalesce(v_tx->>'mode','') in ('EXPLICIT','SELECT');

  if v_explicit then
    return p_spec || jsonb_build_object(
      'contract_source','EXPLICIT_ACTION_SPEC'
    );
  end if;

  if v_structural_transversal then
    v_out := p_spec || jsonb_build_object(
      'contract_source','STRUCTURAL_TRANSVERSAL'
    );

    -- CONTROL_EQUIVALENCE_JUDGE is transversal. Never leak M3.9 identity into
    -- another consumer such as M4.10 or M9.3.
    if coalesce(v_out->>'transversal_capability_code','')='CONTROL_EQUIVALENCE_JUDGE'
       and coalesce(v_out->>'action_kind','')='DECLARED_CAPABILITY_TEST_EXECUTION' then
      v_seed := p_plan_code||':'||p_unit_code||'|CONTROL_EQUIVALENCE_JUDGE|EXACT_ONLY';
      v_digest := encode(
        extensions.digest(convert_to(v_seed,'UTF8'),'sha256'),
        'hex'
      );
      v_prefix := replace(replace(upper(p_unit_code),'.','-'),'_','-');

      v_query := $q$
with v as (
  select public.fn_lf_version_compatibility_current_version_id_v1(
    'PROGRAMACION_CONTRACT',
    'INPUT_READINESS_CONTRACT',
    'INPUT_GOVERNANCE_AGENT'
  ) as version_id
), s(id) as (
  values (1),(43),(58)
), x as materialized (
  select
    s.id,
    v.version_id,
    programacion.fn_input_governance_shadow_evaluate_v2(s.id,v.version_id) as shadow
  from s cross join v
)
select jsonb_build_object(
  'shadow_contract','ENGINEERING_T_EQUIV_CORPUS_V1',
  'version_id',max(version_id),
  'screen_count',count(*),
  'screens',jsonb_agg(
    jsonb_build_object(
      'pantalla_id',id,
      'summary',shadow->'summary',
      'shadow_sha256',shadow->>'shadow_sha256'
    ) order by id
  )
)
from x$q$;

      v_out := jsonb_set(
        v_out,
        '{capability_execution}',
        coalesce(v_out->'capability_execution','{}'::jsonb)
        || jsonb_build_object(
          'target_code',p_plan_code||':'||p_unit_code,
          'plan_digest',v_digest,
          'plan_digest_seed',v_seed,
          'execution_id_prefix','T-EQUIV-IG-'||v_prefix||'-',
          'orchestrator_execution_id_prefix','T-EQUIV-ORCH-IG-'||v_prefix||'-',
          'result_contract',jsonb_build_object(
            'suite_code','INPUT_GOVERNANCE_REGRESSION',
            'test_code','ENGINEERING_T_EQUIV_SHADOW_CORPUS',
            'pass_when',jsonb_build_object(
              'shadow_contract','ENGINEERING_T_EQUIV_CORPUS_V1',
              'screen_count',3,
              'fresh_t_equiv_binding_receipt',true,
              'domain_mutation',false,
              'diff_adjudication','NEXT_CHECKPOINT'
            )
          )
        ),
        true
      );

      v_out := jsonb_set(
        v_out,
        '{verification_queries}',
        jsonb_build_array(v_query),
        true
      );
    end if;

    return v_out;
  end if;

  -- Heuristics may make admission stricter, never looser. Any checkpoint that
  -- signals negative/parity/repro/concurrency/test semantics must have an
  -- explicit or structural-transversal contract even when the legacy compiler
  -- reduced it to a read-only query.
  v_complex_semantics :=
    coalesce(p_checkpoint_code,'') ~* '(^NEG_|NEGATIVE|FALSE_PASS|MUTATION|PARITY|REPRO|DRILL|CONCURRENCY|EQUIVALENCE|TEST)'
    or lower(coalesce(p_spec->>'checkpoint_title','')) ~
      '(negativ|false pass|mutaci|paridad|reproduc|drill|concurren|equivalen|inyect)';

  -- Generic compilation is allowed only for bounded read-only evidence that
  -- does not carry complex semantic obligations.
  v_safe_generic :=
    not v_material
    and not v_complex_semantics
    and (
      v_kind in ('READBACK_ONCE','OBSERVE_ONCE')
      or (
        v_kind='VERIFY_QUERY_ONCE'
        and v_verification_count>0
      )
    );

  if v_safe_generic then
    return p_spec || jsonb_build_object(
      'contract_source','GENERIC_SAFE_READ',
      'heuristic_scope','READ_ONLY_EXACT_EVIDENCE'
    );
  end if;

  return p_spec || jsonb_build_object(
    'status','BLOCK_EXPLICIT_ACTION_SPEC_REQUIRED',
    'precision','SANITIZED_FAIL_CLOSED',
    'contract_source','HEURISTIC_BLOCKED',
    'requires_explicit_contract',true,
    'sanitation_reason','MATERIAL_OR_COMPLEX_SEMANTICS_MUST_NOT_BE_INFERRED_FROM_TITLE_OR_RECIPE',
    'blocking_codes',
      coalesce(p_spec->'blocking_codes','[]'::jsonb)
      || jsonb_build_array('EXPLICIT_ACTION_SPEC_REQUIRED')
  );
end;
$function$;

comment on function programacion.fn_engineering_action_spec_sanitize_v1(text,text,text,jsonb)
is 'Fail-closed sanitation boundary. Only bounded read-only generic specs may remain inferred; material/complex semantics require explicit or structural-transversal authority.';

create or replace function programacion.fn_engineering_checkpoint_action_spec_v3(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text default null
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_base jsonb;
  v_tx jsonb;
  v_cp text;
  v_state jsonb;
  v_item jsonb;
  v_spec jsonb;
begin
  v_base:=programacion.fn_engineering_checkpoint_action_spec_v3_legacy(
    p_plan_code,p_unit_code,p_checkpoint_code
  );
  if v_base is null then
    return null;
  end if;

  v_cp:=coalesce(p_checkpoint_code,v_base->>'checkpoint_code');
  v_base:=programacion.fn_engineering_action_spec_apply_git_migration_guard_v1(v_base);

  select pu.unit_metadata#>array['transversal_execution_v1',v_cp]
    into v_tx
  from programacion.engineering_plan_units pu
  where pu.plan_code=p_plan_code
    and pu.unit_code=p_unit_code;

  if v_tx is null then
    return programacion.fn_engineering_action_spec_sanitize_v1(
      p_plan_code,p_unit_code,v_cp,v_base
    );
  end if;

  if coalesce(v_tx->>'activation','ACTIVE')='DECLARED_ONLY' then
    return programacion.fn_engineering_action_spec_sanitize_v1(
      p_plan_code,p_unit_code,v_cp,
      v_base || jsonb_build_object(
        'transversal_execution',v_tx,
        'transversal_gate','DECLARED_NOT_ACTIVATED',
        'transversal_routing_changed',false
      )
    );
  end if;

  if coalesce(v_tx->>'mode','')='SELECT' then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_SELECTOR_RUNTIME_REQUIRED',
      'precision','STRUCTURAL_TRANSVERSAL_SELECT',
      'transversal_execution',v_tx,
      'transversal_gate','SELECTOR_REQUIRED',
      'contract_source','STRUCTURAL_TRANSVERSAL'
    );
  end if;

  if coalesce(v_tx->>'mode','')<>'EXPLICIT' then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_MODE_INVALID',
      'transversal_execution',v_tx,
      'contract_source','STRUCTURAL_TRANSVERSAL'
    );
  end if;

  v_state:=programacion.fn_engineering_transversal_sequence_state_v1(
    p_plan_code,p_unit_code,v_cp
  );

  if coalesce((v_state->>'total')::int,0)=0 then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_CAPABILITIES_MISSING',
      'transversal_execution',v_tx,
      'contract_source','STRUCTURAL_TRANSVERSAL'
    );
  end if;

  if coalesce((v_state->>'all_done')::boolean,false) then
    return v_base || jsonb_build_object(
      'status','BLOCK_TRANSVERSAL_SEQUENCE_ALREADY_COMPLETE_REQUIRES_CHECKPOINT_TRANSITION',
      'transversal_execution',v_tx,
      'transversal_sequence',v_state,
      'contract_source','STRUCTURAL_TRANSVERSAL'
    );
  end if;

  v_item:=v_state->'current_item';

  v_spec:=programacion.fn_engineering_transversal_capability_action_spec_v2(
    p_plan_code,p_unit_code,v_cp,v_item,v_base
  );

  v_spec:=programacion.fn_engineering_action_spec_apply_git_migration_guard_v1(v_spec);

  return programacion.fn_engineering_action_spec_sanitize_v1(
    p_plan_code,p_unit_code,v_cp,
    v_spec || jsonb_build_object(
      'transversal_execution',v_tx,
      'transversal_sequence',v_state,
      'transversal_gate',
        case when v_spec->>'status'='READY'
          then 'PASS_CURRENT_ITEM'
          else 'BLOCK_CURRENT_ITEM'
        end,
      'forbidden',
        coalesce(v_spec->'forbidden','[]'::jsonb)
        || jsonb_build_array('FALLBACK_TO_TITLE_HEURISTIC_WHEN_EXPLICIT_DECLARED')
    )
  );
end;
$function$;

create or replace function programacion.fn_engineering_packet_apply_test_contract_guard_v1(
  p_packet jsonb,
  p_action_spec jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_kind text := coalesce(p_action_spec->>'action_kind','');
  v_test_code text;
  v_valid boolean := false;
begin
  if coalesce(p_packet->>'status','')<>'READY'
     or coalesce(p_packet->>'execution_capability','')<>'RUN_TEST' then
    return p_packet;
  end if;

  if p_packet->'explicit_test_case_set' is not null then
    return p_packet || jsonb_build_object(
      'test_contract_guard',jsonb_build_object(
        'status','PASS',
        'mode','EXPLICIT_TEST_CODES',
        'fallback_case_discovery','FORBIDDEN'
      )
    );
  end if;

  if v_kind='DECLARED_CAPABILITY_TEST_EXECUTION' then
    v_test_code:=
      nullif(btrim(coalesce(
        p_action_spec#>>'{capability_execution,result_contract,test_code}',''
      )),'');
    v_valid:=
      v_test_code is not null
      and coalesce(
        jsonb_array_length(coalesce(p_action_spec->'verification_queries','[]'::jsonb)),
        0
      )>0;

  elsif v_kind='DECLARED_TEST_PERSISTENCE_EXECUTION' then
    v_test_code:='CAPABILITY_OWNED_TEST_PERSISTENCE';
    v_valid:=true;

  elsif jsonb_typeof(p_action_spec->'test_execution_contract')='object' then
    v_test_code:=
      nullif(btrim(coalesce(
        p_action_spec#>>'{test_execution_contract,test_code}',''
      )),'');
    v_valid:=
      coalesce(p_action_spec#>>'{test_execution_contract,mode}','')
        in ('AUTHORED_NEGATIVE','EXPLICIT_VERIFICATION_QUERY')
      and v_test_code is not null
      and coalesce(
        jsonb_array_length(coalesce(p_action_spec->'verification_queries','[]'::jsonb)),
        0
      )>0;
  end if;

  if v_valid then
    return p_packet || jsonb_build_object(
      'test_contract_guard',jsonb_build_object(
        'status','PASS',
        'mode',case
          when v_kind='DECLARED_CAPABILITY_TEST_EXECUTION'
            then 'CAPABILITY_OWNED_EXACT_TEST'
          when v_kind='DECLARED_TEST_PERSISTENCE_EXECUTION'
            then 'CAPABILITY_OWNED_TEST_PERSISTENCE'
          else coalesce(
            p_action_spec#>>'{test_execution_contract,mode}',
            'AUTHORED_NEGATIVE'
          )
        end,
        'test_code',v_test_code,
        'fallback_case_discovery','FORBIDDEN'
      )
    );
  end if;

  return (
    p_packet || jsonb_build_object(
      'status','BLOCK_TEST_EXECUTION_CONTRACT_MISSING',
      'execution_allowed',false,
      'test_contract_guard',jsonb_build_object(
        'status','BLOCK',
        'reason','RUN_TEST_REQUIRES_EXPLICIT_TEST_CODES_OR_EXACT_AUTHORED_TEST_CONTRACT',
        'fallback_case_discovery','FORBIDDEN'
      ),
      'block_reasons',
        coalesce(p_packet->'block_reasons','[]'::jsonb)
        || jsonb_build_array('TEST_EXECUTION_CONTRACT_MISSING')
    )
  ) - 'connector_plan'
    || jsonb_build_object('connector_plan','[]'::jsonb);
end;
$function$;

comment on function programacion.fn_engineering_packet_apply_test_contract_guard_v1(jsonb,jsonb)
is 'RUN_TEST fail-closed guard. Requires explicit catalog cases, a capability-owned exact test, or an exact authored test contract. Implicit case discovery is forbidden.';

create or replace function programacion.fn_engineering_execution_packet_from_spec_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_action_spec jsonb,
  p_execution_input jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_packet jsonb;
  v_budget int;
  v_spec jsonb := coalesce(p_action_spec,'{}'::jsonb);
  v_material boolean := coalesce((p_action_spec->>'requires_material_execution')::boolean,false);
  v_kind text := coalesce(p_action_spec->>'action_kind','');
  v_title text := coalesce(p_action_spec->>'checkpoint_title','');
begin
  if v_material
     and v_kind not in ('READBACK_ONCE','OBSERVE_ONCE','DECISION_GATE','TERMINAL_RECONCILE') then
    v_spec := jsonb_set(
      v_spec,
      '{checkpoint_title}',
      to_jsonb('execute material: ' || v_title),
      true
    );
  end if;

  v_packet:=programacion.fn_engineering_execution_packet_from_spec_core_v1(
    p_plan_code,p_unit_code,p_checkpoint_code,v_spec,p_execution_input
  );

  v_packet:=programacion.fn_engineering_execution_packet_apply_transversal_adapter_v1(
    v_packet,p_plan_code,p_unit_code,p_checkpoint_code,p_action_spec
  );

  v_packet:=programacion.fn_engineering_packet_apply_test_contract_guard_v1(
    v_packet,p_action_spec
  );

  v_budget:=nullif(p_action_spec#>>'{read_budget,checkpoint_queries_max}','')::int;

  if v_budget is null then
    select nullif(
      coalesce(
        pu.unit_metadata#>>'{source_fast_path_v2,read_budget,checkpoint_queries_max}',
        pu.unit_metadata#>>'{source_fast_path_v1,preferred_queries_max}'
      ),''
    )::int
    into v_budget
    from programacion.engineering_plan_units pu
    where pu.plan_code=p_plan_code
      and pu.unit_code=p_unit_code;
  end if;

  v_packet:=programacion.fn_engineering_packet_apply_read_budget_v1(
    v_packet,v_budget
  );

  v_packet:=programacion.fn_engineering_packet_apply_governed_merge_v1(v_packet);

  return v_packet || jsonb_build_object(
    'readonly_policy',jsonb_build_object(
      'scope','EXPLICIT_READ_ACTIONS_ONLY',
      'materiality_authority','ACTION_SPEC_REQUIRES_MATERIAL_EXECUTION',
      'title_based_materiality_downgrade','FORBIDDEN',
      'material_actions_allowed',jsonb_build_array('WRITE_DB','WRITE_GIT','RUN_TEST')
    )
  );
end;
$function$;

create or replace function programacion.fn_engineering_unit_bootstrap_v3(
  p_plan_code text,
  p_unit_code text
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_fast jsonb;
  v_payload jsonb;
  v_cp text;
  v_readiness jsonb;
  v_terminal text;
  v_continuation jsonb;
  v_execution_contract jsonb;
  v_packet jsonb;
  v_action_spec jsonb;
  v_execution_input jsonb;
begin
  v_fast:=programacion.fn_engineering_unit_bootstrap_snapshot_v2(
    p_plan_code,p_unit_code
  );

  if coalesce((v_fast->>'snapshot_fast_path_supported')::boolean,false) then
    v_payload:=v_fast;
  else
    v_payload:=programacion.fn_engineering_unit_bootstrap_v3_legacy(
      p_plan_code,p_unit_code
    ) || jsonb_build_object(
      'engine_variant','LEGACY_FALLBACK_V3',
      'snapshot_fast_path_supported',false
    );
  end if;

  v_cp:=v_payload#>>'{current_checkpoint,checkpoint_code}';

  -- Snapshot context may be reused, but execution authority is always freshly
  -- compiled for the current checkpoint. This prevents stale READY packets from
  -- bypassing newly tightened contract sanitation.
  if v_cp is not null then
    v_action_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
      p_plan_code,p_unit_code,v_cp
    );

    v_execution_input:=coalesce(
      v_payload#>'{execution_packet,execution_input}',
      v_payload->'execution_input',
      '{}'::jsonb
    );

    v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
      p_plan_code,
      p_unit_code,
      v_cp,
      coalesce(v_action_spec,'{}'::jsonb),
      v_execution_input
    );

    v_payload:=jsonb_set(
      v_payload,
      '{action_spec}',
      coalesce(v_action_spec,'null'::jsonb),
      true
    );

    v_payload:=jsonb_set(
      v_payload,
      '{execution_packet}',
      v_packet,
      true
    );

    if v_payload#>'{context_snapshot,unit_metadata}' is not null then
      v_readiness:=programacion.fn_engineering_checkpoint_execution_readiness_from_context_v1(
        v_cp,
        coalesce(v_action_spec,'{}'::jsonb),
        coalesce(v_packet,'{}'::jsonb),
        v_payload#>'{context_snapshot,unit_metadata}'
      );
    else
      v_readiness:=programacion.fn_engineering_checkpoint_execution_readiness_from_payload_v1(
        p_plan_code,
        p_unit_code,
        v_cp,
        coalesce(v_action_spec,'{}'::jsonb),
        coalesce(v_packet,'{}'::jsonb)
      );
    end if;

    v_payload:=v_payload||jsonb_build_object(
      'execution_readiness',v_readiness
    );

    if coalesce(v_payload->>'terminal_action','')='CONTINUE_CURRENT_CHECKPOINT'
       and coalesce((v_readiness->>'execution_ready')::boolean,false)=false then
      v_payload:=v_payload
        || jsonb_build_object(
          'terminal_action','STOP_EXECUTION_PREFLIGHT',
          'execution_allowed',false,
          'preflight_block',jsonb_build_object(
            'status','NOT_READY',
            'checkpoint_code',v_cp,
            'reasons',v_readiness->'reasons',
            'gates',v_readiness->'gates',
            'next_action','FIX_PREFLIGHT_CONTRACT_BEFORE_CONNECTOR_EXECUTION'
          )
        );
    elsif coalesce((v_readiness->>'execution_ready')::boolean,false)=true then
      v_payload:=v_payload || jsonb_build_object(
        'execution_allowed',true
      );
    end if;
  end if;

  v_terminal:=coalesce(v_payload->>'terminal_action','');
  v_continuation:=jsonb_build_object(
    'terminal_scope',case
      when v_terminal='CONTINUE_CURRENT_CHECKPOINT' then 'CURRENT_UNIT'
      else 'CURRENT_UNIT_ONLY'
    end,
    'global_stop',false,
    'orchestrator_action',case
      when v_terminal='CONTINUE_CURRENT_CHECKPOINT' then 'EXECUTE_CURRENT_UNIT'
      else 'YIELD_CURRENT_UNIT_CONTINUE_AVAILABLE_WORK'
    end,
    'selection_owner','ENGINEERING_SCHEDULER',
    'rule','NON_CONTINUE_TERMINAL_ACTION_STOPS_ONLY_CURRENT_UNIT; SCHEDULER MAY CONTINUE OTHER ELIGIBLE WORK'
  );

  v_execution_contract:=coalesce(v_payload->'execution_contract','{}'::jsonb)
    || jsonb_build_object(
      'terminal_action_scope','CURRENT_UNIT_ONLY_UNLESS_EXPLICIT_GLOBAL_STOP',
      'non_continue_terminal_behavior','YIELD_CURRENT_UNIT_CONTINUE_AVAILABLE_WORK',
      'scheduler_continuation_owner','ENGINEERING_SCHEDULER',
      'global_stop_requires_explicit_flag',true,
      'current_checkpoint_compilation','ALWAYS_FRESH'
    );

  return v_payload || jsonb_build_object(
    'continuation_contract',v_continuation,
    'execution_contract',v_execution_contract
  );
end;
$function$;

comment on function programacion.fn_engineering_unit_bootstrap_v3(text,text)
is 'Canonical bootstrap v3: reuses snapshot context but always recompiles current Action Spec, execution packet and readiness so stale READY state cannot bypass contract sanitation.';

create or replace function programacion.fn_engineering_unit_execution_admission_v1(
  p_plan_code text,
  p_unit_code text
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_boot jsonb;
  v_admitted boolean;
begin
  v_boot:=programacion.fn_engineering_unit_bootstrap_v3(
    p_plan_code,p_unit_code
  );

  v_admitted :=
    v_boot#>>'{current_checkpoint,checkpoint_code}' is not null
    and coalesce(v_boot#>>'{action_spec,status}','')='READY'
    and coalesce(v_boot#>>'{execution_packet,status}','')='READY'
    and coalesce(
      (v_boot#>>'{execution_readiness,execution_ready}')::boolean,
      false
    )
    and coalesce(v_boot->>'terminal_action','')='CONTINUE_CURRENT_CHECKPOINT'
    and coalesce((v_boot->>'execution_allowed')::boolean,true);

  return jsonb_build_object(
    'schema_version','ENGINEERING_UNIT_EXECUTION_ADMISSION_V1',
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'checkpoint_code',v_boot#>>'{current_checkpoint,checkpoint_code}',
    'admitted',v_admitted,
    'action_spec_status',v_boot#>>'{action_spec,status}',
    'contract_source',v_boot#>>'{action_spec,contract_source}',
    'packet_status',v_boot#>>'{execution_packet,status}',
    'execution_ready',
      coalesce(
        (v_boot#>>'{execution_readiness,execution_ready}')::boolean,
        false
      ),
    'terminal_action',v_boot->>'terminal_action',
    'reasons',
      coalesce(
        v_boot#>'{execution_readiness,reasons}',
        v_boot#>'{execution_packet,block_reasons}',
        '[]'::jsonb
      )
  );
end;
$function$;

comment on function programacion.fn_engineering_unit_execution_admission_v1(text,text)
is 'Cheap scheduler admission contract built on canonical BOOTSTRAP_V3. A unit may claim a lane only when Action Spec, packet and execution readiness are all READY.';

create or replace function programacion.fn_engineering_parallel_pilot_pick_unit_v1(
  p_plan_code text,
  p_run_id bigint
)
returns text
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  r record;
  v_admission jsonb;
begin
  update programacion.engineering_parallel_pilot_lane_runs
     set status='ERROR',
         finished_at=coalesce(finished_at,now()),
         result_summary=coalesce(result_summary,'LEASE_EXPIRED')
   where status='RUNNING'
     and lease_expires_at < now();

  for r in
    select pu.unit_code
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_items w
      on w.id=pu.work_item_id
    where pu.plan_code=p_plan_code
      and pu.disposition='ASSIGNED'
      and w.status in ('BACKLOG','READY','IN_PROGRESS')
      and programacion.fn_engineering_effective_open_blocker_count_v1(w.id)=0
      and not exists (
        select 1
        from programacion.fn_engineering_effective_dependencies_v1(w.id) d
        where d.is_unmet
      )
      and not exists (
        select 1
        from programacion.engineering_parallel_pilot_lane_runs lr
        where lr.plan_code=p_plan_code
          and lr.unit_code=pu.unit_code
          and lr.status='RUNNING'
      )
      and not exists (
        select 1
        from programacion.engineering_parallel_pilot_lane_runs lr
        where lr.run_id=p_run_id
          and lr.unit_code=pu.unit_code
      )
    order by
      case w.priority
        when 'P0' then 0
        when 'P1' then 1
        when 'P2' then 2
        when 'P3' then 3
        else 9
      end,
      pu.id
  loop
    v_admission:=programacion.fn_engineering_unit_execution_admission_v1(
      p_plan_code,r.unit_code
    );

    if coalesce((v_admission->>'admitted')::boolean,false) then
      return r.unit_code;
    end if;
  end loop;

  return null;
end;
$function$;

comment on function programacion.fn_engineering_parallel_pilot_pick_unit_v1(text,bigint)
is 'Selector used by ENGINEERING_PARALLEL_EXECUTOR_V1. Dependency/state eligibility is necessary but not sufficient: canonical unit execution admission must PASS before consuming a lane.';

create or replace function programacion.fn_engineering_plan_contract_sanitation_v1(
  p_plan_code text
)
returns jsonb
language sql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
with open_cp as materialized (
  select
    pu.unit_code,
    c.checkpoint_code,
    (
      coalesce(pu.unit_metadata->'action_specs_v1','{}'::jsonb)
      ? c.checkpoint_code
    ) as has_explicit,
    (
      pu.unit_metadata#>array['transversal_execution_v1',c.checkpoint_code]
      is not null
    ) as has_transversal
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_checkpoints c
    on c.work_item_id=pu.work_item_id
  where pu.plan_code=p_plan_code
    and pu.disposition='ASSIGNED'
    and c.required
    and c.status not in ('DONE','NOT_APPLICABLE')
), specs as materialized (
  select
    o.*,
    programacion.fn_engineering_checkpoint_action_spec_v3(
      p_plan_code,o.unit_code,o.checkpoint_code
    ) as spec
  from open_cp o
)
select jsonb_build_object(
  'schema_version','ENGINEERING_PLAN_CONTRACT_SANITATION_V1',
  'plan_code',p_plan_code,
  'open_required_checkpoints',count(*),
  'explicit_contracts',count(*) filter(where has_explicit),
  'structural_transversal_contracts',
    count(*) filter(where not has_explicit and has_transversal),
  'generic_safe_reads',
    count(*) filter(where spec->>'contract_source'='GENERIC_SAFE_READ'),
  'heuristic_blocked',
    count(*) filter(where spec->>'status'='BLOCK_EXPLICIT_ACTION_SPEC_REQUIRED'),
  'other_legitimate_blocks',
    count(*) filter(
      where coalesce(spec->>'status','')<>'READY'
        and spec->>'status'<>'BLOCK_EXPLICIT_ACTION_SPEC_REQUIRED'
    ),
  'ready_after_sanitation',
    count(*) filter(where spec->>'status'='READY')
)
from specs;
$function$;

comment on function programacion.fn_engineering_plan_contract_sanitation_v1(text)
is 'Read-only plan-wide sanitation report. Classifies every open required checkpoint after canonical Action Spec sanitation; does not mutate plan metadata.';

create or replace function programacion.fn_engineering_parallel_executor_dispatch_bundle_v1(
  p_run_id bigint
)
returns jsonb
language sql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
with r as (
  select id,plan_code,status,max_lanes,max_turns_per_lane
  from programacion.engineering_parallel_pilot_runs
  where id=p_run_id
), lanes as materialized (
  select
    lr.lane_no,
    lr.turn_no,
    lr.unit_code,
    lr.status,
    programacion.fn_engineering_unit_bootstrap_v3(
      lr.plan_code,lr.unit_code
    ) as bootstrap
  from programacion.engineering_parallel_pilot_lane_runs lr
  join r on r.id=lr.run_id
  where lr.status='RUNNING'
  order by lr.lane_no,lr.turn_no
)
select jsonb_build_object(
  'schema_version','ENGINEERING_PARALLEL_DISPATCH_BUNDLE_V1',
  'run_id',r.id,
  'plan_code',r.plan_code,
  'run_status',r.status,
  'dispatch_policy','CONCURRENT_ACTIVE_LANES',
  'worker_contract','ONE_WORKER_PER_ACTIVE_LANE',
  'lane_count',(select count(*) from lanes),
  'lanes',coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'lane_no',lane_no,
          'turn_no',turn_no,
          'unit_code',unit_code,
          'status',status,
          'bootstrap',bootstrap
        )
        order by lane_no,turn_no
      )
      from lanes
    ),
    '[]'::jsonb
  )
)
from r;
$function$;

comment on function programacion.fn_engineering_parallel_executor_dispatch_bundle_v1(bigint)
is 'Returns all active lane bootstrap packets in one DB round trip so the host can execute independent lane workers concurrently. It does not fake DB-side parallel execution.';

create or replace function programacion.fn_engineering_parallel_executor_start_v1(
  p_plan_code text,
  p_actor text default 'ENGINEERING_PARALLEL_EXECUTOR_V1'
)
returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_storage jsonb;
begin
  v_storage := programacion.fn_engineering_parallel_scheduler_storage_start_v1(
    p_plan_code,
    coalesce(nullif(p_actor,''),'ENGINEERING_PARALLEL_EXECUTOR_V1')
  );

  return v_storage
    || jsonb_build_object(
      'executor_contract','ENGINEERING_PARALLEL_EXECUTOR_V1',
      'execution_scope','UNIT_TO_TERMINAL',
      'selection_policy','DEPENDENCIES_CLEAR_AND_EXECUTION_ADMISSION_PASS',
      'contract_preflight','PER_CANDIDATE_CANONICAL_ADMISSION',
      'parallel_execution_contract',jsonb_build_object(
        'db_scheduler_role','CLAIM_REFILL_AND_STATE_ONLY',
        'lane_worker_model','EXTERNAL_CONCURRENT_WORKERS',
        'dispatch_entrypoint','programacion.fn_engineering_parallel_executor_dispatch_bundle_v1',
        'claim_before_worker','ADMISSION_REQUIRED',
        'same_unit_double_claim','FORBIDDEN',
        'real_parallelism_condition','ACTIVE_LANES_MUST_BE_EXECUTED_CONCURRENTLY_BY_HOST'
      ),
      'unit_loop',jsonb_build_array(
        'BOOTSTRAP_V3',
        'EXECUTE_CURRENT_PACKET',
        'HEARTBEAT_WHEN_REQUIRED',
        'CHECKPOINT_TRANSITION',
        'USE_RETURNED_BOOTSTRAP',
        'REPEAT_UNTIL_UNIT_TERMINAL_OR_YIELD'
      ),
      'success_guard','WORK_ITEM_DONE_AND_REQUIRED_CHECKPOINTS_TERMINAL',
      'legacy_scheduler_storage',true
    );
end;
$function$;


-- Reconcile merge authorization with the canonical PASE repair-window policy.
-- REPAIR_OBSERVE_ONLY controls remain applicable/diagnostic but cannot block an
-- ordinary merge. ACTIVE_BLOCKING controls, if any, still require exact terminal
-- PASS evidence. F09/F10 are pre-activation qualification of the control system,
-- not a prerequisite for every ordinary engineering merge during quarantine.
create or replace function programacion.fn_engineering_merge_authorization_contract_v1()
returns jsonb
language sql
immutable
set search_path to 'pg_catalog'
as $function$
select jsonb_build_object(
  'schema_version','ENGINEERING_PROCESS_MERGE_AUTHORIZATION_V1_1',
  'authorization_owner','PROCESS',
  'human_approval_required',false,
  'auto_merge_when_authorized',true,
  'authorization_capability','SAFE_CHANGE_ADMISSION',
  'required_execution_permission','DOWNSTREAM_EXECUTION_ELIGIBLE',
  'required_preconditions',jsonb_build_array(
    'EKB_PREFLIGHT_CLEAR',
    'PASE_MERGE_POLICY_EFFECTIVE_ALLOW',
    'EXACT_HEAD_MATCH',
    'PR_MERGEABLE_TRUE'
  ),
  'pase_policy',jsonb_build_object(
    'repair_policy_id','PASE_CONTROL_REPAIR_QUARANTINE_V1',
    'repair_window_state','SUPPORTED',
    'observe_only_results_cannot_block_merge',true,
    'active_blocking_controls_require_exact_terminal_pass',true,
    'structural_governance_remains_fail_closed',true,
    'global_f09_f10_completion_required_for_ordinary_merge',false,
    'control_system_activation_requires_separate_terminal_qualification',true
  ),
  'forbidden',jsonb_build_array(
    'MERGE_WITHOUT_PROCESS_AUTHORIZATION',
    'TREAT_RECOMMENDATION_AS_PERMISSION',
    'SKIP_EKB_PREFLIGHT',
    'SKIP_ACTIVE_BLOCKING_CONTROL_WHEN_APPLICABLE',
    'TREAT_REPAIR_OBSERVE_ONLY_AS_MERGE_BLOCKER',
    'REQUIRE_GLOBAL_PASE_F09_F10_FOR_ORDINARY_MERGE',
    'MERGE_DIFFERENT_HEAD'
  ),
  'on_authorized','MERGE_AND_CONTINUE_CURRENT_UNIT',
  'on_not_authorized','YIELD_CURRENT_UNIT_CONTINUE_SCHEDULER',
  'global_scheduler_stop',false,
  'fail_closed',true
);
$function$;

comment on function programacion.fn_engineering_merge_authorization_contract_v1()
is 'Governed merge authorization aligned with PASE_CONTROL_REPAIR_QUARANTINE_V1: observe-only results cannot block ordinary merge; active blocking controls and structural governance remain fail-closed.';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-MERGE-AUTH-PASE-REPAIR-WINDOW-001',
  'ENGINEERING_ORCHESTRATION',
  'Merge authorization must honor PASE repair-window enforcement semantics',
  'ENGINEERING_PROCESS_MERGE_AUTHORIZATION_V1 required a synthetic PASE_ROUTER_TERMINAL_ALLOW even while the canonical PASE repair policy declares all REPAIR_OBSERVE_ONLY controls non-blocking for ordinary merges.',
  'The executor merge contract projected PASE as a single terminal prerequisite instead of consuming the effective merge policy produced by Changeset Governance plus PASE_CONTROL_REPAIR_QUARANTINE_V1.',
  'OBSERVE_ONLY_CONTROL_INCORRECTLY_PROMOTED_TO_GLOBAL_MERGE_BLOCKER',
  'Require PASE_MERGE_POLICY_EFFECTIVE_ALLOW. During the repair window, preserve applicability and diagnostics, require PASS only from ACTIVE_BLOCKING controls, and keep structural governance fail-closed. Do not require F09/F10 global pre-activation closure for each ordinary merge.',
  'Source authority: README_PASE_CONTROL_REPAIR_QUARANTINE_V1 states REPAIR_OBSERVE_ONLY results cannot block merge; PASE_MERGE_GATE_V1 requires PASS only from ACTIVE_BLOCKING controls. ENGINEERING_PROCESS_MERGE_AUTHORIZATION_V1_1 now projects that rule.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/s28_ci_lane_router/README_PASE_CONTROL_REPAIR_QUARANTINE_V1.md; github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/pase_merge_gate/README.md',
  'EXECUTION',
  array['ENGINEERING_SCHEDULER','PROGRAMMING_AGENT']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'Parallel executor governed merge during PASE repair window',
  'supabase://programacion.fn_engineering_merge_authorization_contract_v1'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  ultima_vez=now(),
  updated_at=now();

update public.lf_error_knowledge
set prevencion='WRITE_GIT packets must carry ENGINEERING_PROCESS_MERGE_AUTHORIZATION_V1_1. Merge automatically only when SAFE_CHANGE_ADMISSION returns DOWNSTREAM_EXECUTION_ELIGIBLE, EKB is clear, effective PASE merge policy allows the exact change, exact-head matches and PR is mergeable. During PASE repair quarantine, REPAIR_OBSERVE_ONLY results cannot block merge; ACTIVE_BLOCKING controls remain fail-closed.',
    validacion='Reconciled 2026-10-06 with canonical PASE_CONTROL_REPAIR_QUARANTINE_V1 and PASE_MERGE_GATE_V1. The executor no longer requires global PASE F09/F10 closure for ordinary merges while controls are REPAIR_OBSERVE_ONLY.',
    ultima_vez=now(),
    updated_at=now()
where codigo='ENGINEERING-PROCESS-AUTO-MERGE-AUTHORITY-001';
