-- OP24 Strategy23 Metrics Consumer Gate V1 — sandbox candidate only.
-- Calls the V2 verifier directly and resolves current S24/S26 authority from Supabase.
-- Caller-provided parent/fingerprint values are claims to verify, never authority.
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
  v_parent_id bigint;
  v_parent_version text;
  v_parent_status text;
  v_parent_updated_at timestamptz;
  v_s26_id bigint;
  v_s26_version text;
  v_s26_status text;
  v_s26_runtime_state text;
  v_s26_updated_at timestamptz;
  v_s26_family_e2e_status text;
  v_s26_source_sha text;
  v_s26_fingerprint text;
begin
  select s.id,s.version,s.status,s.updated_at
    into v_parent_id,v_parent_version,v_parent_status,v_parent_updated_at
  from public.lf_strategy_snapshots s
  where s.snapshot_code='LF_LEARNED_CONTEXT_MEMORY_MODEL_20260904'
  order by s.id desc
  limit 1;

  if not found then
    v_errors := v_errors || jsonb_build_array('PARENT_STRATEGY_LIVE_SNAPSHOT_REQUIRED');
  elsif coalesce(v_parent_version,'') <> 'v0.3' then
    v_errors := v_errors || jsonb_build_array('PARENT_STRATEGY_LIVE_VERSION_NOT_V03');
  end if;

  if coalesce(p_expected_parent_version,'') <> 'v0.3'
     or coalesce(p_parent_version,'') <> coalesce(v_parent_version,'') then
    v_errors := v_errors || jsonb_build_array('PARENT_STRATEGY_CALLER_VERSION_MISMATCH');
  end if;

  select s.id,s.version,s.status,s.runtime_state,s.updated_at,
         s.metadata->>'family_e2e_status',
         s.metadata->'runtime_reconciliation'->>'source_sha'
    into v_s26_id,v_s26_version,v_s26_status,v_s26_runtime_state,v_s26_updated_at,
         v_s26_family_e2e_status,v_s26_source_sha
  from public.lf_strategy_snapshots s
  where s.snapshot_code='LF_PROFILE_GOVERNANCE_GOLDEN_FAMILY_20260904'
  order by s.id desc
  limit 1;

  if not found then
    v_errors := v_errors || jsonb_build_array('STRATEGY26_LIVE_SNAPSHOT_REQUIRED');
  else
    v_s26_fingerprint := encode(
      extensions.digest(
        convert_to(
          jsonb_build_object(
            'snapshot_id',v_s26_id,
            'version',v_s26_version,
            'status',v_s26_status,
            'runtime_state',v_s26_runtime_state,
            'updated_at',v_s26_updated_at,
            'family_e2e_status',v_s26_family_e2e_status,
            'source_sha',v_s26_source_sha
          )::text,
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    );

    if coalesce(v_s26_family_e2e_status,'') <> 'FAMILY_E2E_PASS' then
      v_errors := v_errors || jsonb_build_array('STRATEGY26_FAMILY_E2E_NOT_PASS');
    end if;

    if length(btrim(coalesce(p_strategy26_family_e2e_fingerprint,''))) = 0
       or p_strategy26_family_e2e_fingerprint is distinct from v_s26_fingerprint then
      v_errors := v_errors || jsonb_build_array('STRATEGY26_FAMILY_E2E_FINGERPRINT_MISMATCH');
    end if;
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
    'parent_snapshot_id', v_parent_id,
    'parent_live_version', v_parent_version,
    'parent_live_status', v_parent_status,
    'parent_live_updated_at', v_parent_updated_at,
    'caller_parent_version', p_parent_version,
    'strategy26_snapshot_id', v_s26_id,
    'strategy26_live_version', v_s26_version,
    'strategy26_live_status', v_s26_status,
    'strategy26_live_runtime_state', v_s26_runtime_state,
    'strategy26_family_e2e_status', v_s26_family_e2e_status,
    'strategy26_observed_fingerprint', v_s26_fingerprint,
    'strategy26_claimed_fingerprint', nullif(p_strategy26_family_e2e_fingerprint,''),
    'fixture_fingerprint', nullif(p_fixture_fingerprint,''),
    'experiment_result_persistence_authorized', false,
    'strategy23_execution_authorized', false,
    'production_authorized', false
  );
end
$function$;

revoke all on function private.sbx_fn_lf_strategy23_metrics_consumer_gate_v1(jsonb,jsonb,text,text,text,text)
  from public, anon, authenticated, service_role;
