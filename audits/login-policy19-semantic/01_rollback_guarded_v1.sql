-- Inverse is governed and requires fresh authorization in Train.
-- FAIL CLOSED once policy 19 uses the decided new value; do not revert consumer alone.
BEGIN;
DO $lf_policy19_semantic_rollback$
DECLARE
  v_sig text; v_md5 text; v_def text; v_restored text;
  v_old constant text := $factor_old$factor.policy_config->>'factor_selection_status'='CLOSED_POLICY_DEFINED'$factor_old$;
  v_new constant text := $factor_new$(
 factor.policy_config->>'factor_selection_status'='CLOSED_POLICY_DEFINED'
 OR (
   factor.security_policy_id=19
   AND factor.policy_config->>'factor_selection_status'='OWNER_DECIDED_IN_CONVERSATION_PENDING_SIGNATURE_IMPLEMENTATION'
   AND factor.policy_config->>'admin_minimum_strength'='APPROVED_MFA'
   AND factor.policy_config->>'admin_phishing_resistant_requirement'='NOT_REQUIRED_FOR_PROFILES_1_2_OWNER_RISK_ACCEPTED_PENDING_SIGNATURE'
   AND factor.policy_config->'phishing_resistant_option_required'='false'::jsonb
   AND factor.policy_config->>'admin_primary_method'='USERNAME_PASSWORD_SERVER_VALIDATED'
   AND factor.policy_config->>'admin_identity_provider'='PENDING_ADR_003_M1_SPIKE'
   AND factor.policy_config->>'admin_sso_protocol'='PENDING_ADR_003_M1_SPIKE'
   AND factor.policy_config->>'admin_provider_configuration_status'='PENDING_REAL_IDP_AND_BREVO_INTEGRATION_QA'
   AND factor.policy_config->'admin_profile_ids'='[1,2]'::jsonb
 )
)$factor_new$;
BEGIN
  IF EXISTS (SELECT 1 FROM lf_ops.politicas_seguridad p
    WHERE p.security_policy_id=19 AND
      p.policy_config->>'factor_selection_status'='OWNER_DECIDED_IN_CONVERSATION_PENDING_SIGNATURE_IMPLEMENTATION')
  THEN RAISE EXCEPTION 'LF_POLICY19_SEMANTIC_ROLLBACK_POLICY19_ACTIVE'; END IF;
  FOR v_sig,v_md5 IN
    SELECT src.sig,src.expected_md5 FROM (VALUES ('programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)','8e2fd437a0ab693ce02fb3d6afe95406'),
  ('programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)','f057bbe4e4fdf0c35d2bd73c1ccc5ac5'),
  ('programacion.fn_input_governance_semantic_probe_v3_ctx(integer,text,bigint,jsonb)','58d3ae035dba9c380cbf14fc65edc710')) AS src(sig,expected_md5)
  LOOP
    v_def:=pg_get_functiondef(v_sig::regprocedure);
    IF (length(v_def)-length(replace(v_def,v_new,'')))<>length(v_new)
    THEN RAISE EXCEPTION 'LF_POLICY19_SEMANTIC_ROLLBACK_SOURCE_DRIFT:%',v_sig; END IF;
    EXECUTE replace(v_def,v_new,v_old);
    v_restored:=pg_get_functiondef(v_sig::regprocedure);
    IF md5(v_restored) IS DISTINCT FROM v_md5
    THEN RAISE EXCEPTION 'LF_POLICY19_SEMANTIC_ROLLBACK_READBACK_DRIFT:%',v_sig; END IF;
  END LOOP;
END $lf_policy19_semantic_rollback$;
COMMIT;
