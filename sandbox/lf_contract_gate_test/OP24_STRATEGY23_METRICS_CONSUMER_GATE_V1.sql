-- OP24 Strategy23 Metrics Consumer Gate V1 — sandbox candidate only.
-- Calls the V2 verifier directly; never trusts a self-declared verifier PASS.
-- No Strategy23 execution, runtime activation or production authorization.

create or replace function private.sbx_fn_lf_strategy23_metrics_consumer_gate_v1(
  p_metrics jsonb,
  p_observations jsonb,
  p_parent_version text,
  p_expected_parent_version text,
  p_strategy26_family_e2e_fingerprint text,
  p_fixture_fingerprint text
)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog', 'private'
as $function$
declare
  v_errors jsonb := '[]'::jsonb;
  v_verify jsonb;
begin
  if coalesce(p_parent_version,'') <> coalesce(p_expected_parent_version,'')
     or coalesce(p_expected_parent_version,'') <> 'v0.3' then
    v_errors := v_errors || jsonb_build_array('PARENT_STRATEGY_VERSION_NOT_V03');
  end if;

  if length(btrim(coalesce(p_strategy26_family_e2e_fingerprint,''))) = 0 then
    v_errors := v_errors || jsonb_build_array('STRATEGY26_FAMILY_E2E_FINGERPRINT_REQUIRED');
  end if;

  if length(btrim(coalesce(p_fixture_fingerprint,''))) = 0 then
    v_errors := v_errors || jsonb_build_array('FROZEN_FIXTURE_FINGERPRINT_REQUIRED');
  end if;

  if to_regprocedure('private.sbx_fn_lf_learning_efficiency_metrics_v2(jsonb,jsonb)') is null then
    v_errors := v_errors || jsonb_build_array('LEARNING_EFFICIENCY_VERIFIER_V2_REQUIRED');
    v_verify := jsonb_build_object('valid',false,'errors',jsonb_build_array('VERIFIER_NOT_MATERIALIZED'));
  else
    v_verify := private.sbx_fn_lf_learning_efficiency_metrics_v2(p_metrics,p_observations);
    if coalesce((v_verify->>'valid')::boolean,false) is not true then
      v_errors := v_errors || jsonb_build_array('LEARNING_EFFICIENCY_METRICS_INVALID');
    end if;
  end if;

  return jsonb_build_object(
    'consumer_gate_pass', jsonb_array_length(v_errors)=0,
    'errors', v_errors,
    'verifier_result', v_verify,
    'parent_version', p_parent_version,
    'strategy26_family_e2e_fingerprint', nullif(p_strategy26_family_e2e_fingerprint,''),
    'fixture_fingerprint', nullif(p_fixture_fingerprint,''),
    'experiment_result_persistence_authorized', false,
    'strategy23_execution_authorized', false,
    'production_authorized', false
  );
end
$function$;

revoke all on function private.sbx_fn_lf_strategy23_metrics_consumer_gate_v1(jsonb,jsonb,text,text,text,text)
  from public, anon, authenticated, service_role;
