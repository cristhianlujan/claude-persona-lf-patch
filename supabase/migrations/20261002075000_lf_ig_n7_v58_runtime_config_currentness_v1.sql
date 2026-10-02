-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · N-7 / PAULO-172
-- Repair one stale V5.8 assertion expectation for screen 53 RUNTIME_CONFIG.
-- The current canonical AUTH-030 rule declares provider_binding=OIDC_PROVIDER_PENDING_M1_SPIKE;
-- the historical assertion template still expected SUPABASE_AUTH and therefore failed rebind.
-- This changes only that exact expected value. Relevance, source authority and fail-closed behavior remain unchanged.

do $n7_v58_runtime_config$
declare
  v_reg regprocedure := 'programacion.fn_input_v58_assertion_template(integer,text,jsonb)'::regprocedure;
  v_def text;
  v_new text;
  v_old text := '"provider_binding":"SUPABASE_AUTH","password_security_policy_id":24,"provider_architecture_security_policy_id":23';
  v_replacement text := '"provider_binding":"OIDC_PROVIDER_PENDING_M1_SPIKE","password_security_policy_id":24,"provider_architecture_security_policy_id":23';
  v_expected_pre_md5 constant text := 'e6cc2838fb077a2c4e479819f42ad532';
  v_expected_post_md5 constant text := 'fe756e847398595c0c94eede625b2ec4';
  v_occurrences integer;
begin
  v_def := pg_get_functiondef(v_reg);

  if md5(v_def) <> v_expected_pre_md5 then
    raise exception 'IG_N7_V58_RUNTIME_CONFIG_BASELINE_DRIFT:%', md5(v_def);
  end if;

  v_occurrences := (length(v_def) - length(replace(v_def,v_old,''))) / length(v_old);
  if v_occurrences <> 1 then
    raise exception 'IG_N7_V58_RUNTIME_CONFIG_ANCHOR_COUNT:%', v_occurrences;
  end if;

  v_new := replace(v_def,v_old,v_replacement);
  execute v_new;

  if md5(pg_get_functiondef(v_reg)) <> v_expected_post_md5 then
    raise exception 'IG_N7_V58_RUNTIME_CONFIG_POST_MD5_MISMATCH:%', md5(pg_get_functiondef(v_reg));
  end if;
end;
$n7_v58_runtime_config$;

comment on function programacion.fn_input_v58_assertion_template(integer,text,jsonb) is
  'N-7 currentness repair: screen 53 RUNTIME_CONFIG V5.8 expectation follows current canonical AUTH-030 provider_binding while preserving exact-source relevance and fail-closed evaluation.';
