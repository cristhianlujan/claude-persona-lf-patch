-- M9.3 opt-in governed T-EQUIV corpus without changing other transversal consumers.
-- No production activation. Replaces the exact existing normalizer with one
-- conditional path only for declared governed-dynamic capability executions.
DO $guard$ BEGIN
 IF NOT EXISTS (
  SELECT 1 FROM programacion.engineering_plan_units
   WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.3'
    AND unit_metadata#>>'{transversal_execution_v1,TEQUIV_CONSUMPTION,capabilities,0,handler}'='T_EQUIV_SHADOW'
    AND unit_metadata#>>'{transversal_execution_v1,TEQUIV_CONSUMPTION,capabilities,0,capability_code}'='CONTROL_EQUIVALENCE_JUDGE'
 ) THEN RAISE EXCEPTION 'M93_TEQUIV_CONSUMER_SOURCE_DRIFT'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION programacion.fn_engineering_action_spec_sanitize_v1(p_plan_code text, p_unit_code text, p_checkpoint_code text, p_spec jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
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
      if v_meta#>>array['transversal_execution_v1',p_checkpoint_code,'capabilities','0','selection_mode']='GOVERNED_DYNAMIC' then
        v_query := $m93dynamic$with version_auth as (select public.fn_lf_version_compatibility_current_version_id_v1('PROGRAMACION_CONTRACT','INPUT_READINESS_CONTRACT','INPUT_GOVERNANCE_AGENT') version_id),
selected as (select pantalla_id from programacion.v_input_governance_representative_cohort_v1 order by display_order,representative_rank,pantalla_id limit 1),
observed as materialized (select s.pantalla_id,v.version_id,programacion.fn_input_governance_shadow_evaluate_v2(s.pantalla_id,v.version_id) shadow from selected s cross join version_auth v)
select jsonb_build_object('shadow_contract','ENGINEERING_T_EQUIV_DYNAMIC_CORPUS_V2','governed_selection',true,'selection_source','programacion.v_input_governance_representative_cohort_v1','version_id',max(version_id),'screen_count',count(*),'screens',jsonb_agg(jsonb_build_object('pantalla_id',pantalla_id,'summary',shadow->'summary','shadow_sha256',shadow->>'shadow_sha256') order by pantalla_id)) from observed$m93dynamic$;
        v_out := jsonb_set(v_out,'{capability_execution}',
          (coalesce(v_out->'capability_execution','{}'::jsonb)-'corpus_screen_ids')
          ||jsonb_build_object('corpus_selection_source',
              'programacion.v_input_governance_representative_cohort_v1',
              'case_selection_policy','FIRST_ACTIVE_AT_EXECUTION'),true);
        v_out := jsonb_set(v_out,'{capability_execution,result_contract,pass_when}',
          (coalesce(v_out#>'{capability_execution,result_contract,pass_when}','{}'::jsonb)-'screen_count')
          ||jsonb_build_object('shadow_contract','ENGINEERING_T_EQUIV_DYNAMIC_CORPUS_V2',
                               'governed_selection',true),true);
        v_out := jsonb_set(v_out,'{verification_queries}',jsonb_build_array(v_query),true);
      end if;
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
$function$
;
UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,
   '{transversal_execution_v1,TEQUIV_CONSUMPTION,capabilities,0,selection_mode}',
   '"GOVERNED_DYNAMIC"'::jsonb,true)
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.3';
