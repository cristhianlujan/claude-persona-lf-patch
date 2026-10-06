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

