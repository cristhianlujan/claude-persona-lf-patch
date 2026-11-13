-- LF policy19 factor-selection compatibility — governed, source-pinned, one migration.
-- This is NOT a security waiver: only policy 19 + exact eight L36 values + [1,2].
-- Provider pending state keeps implementation/QA/production BLOCKED in existing semantic path.
BEGIN;
DO $lf_policy19_semantic$
DECLARE
  v_sig text;
  v_md5 text;
  v_before text;
  v_after text;
  v_readback text;
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
  IF (SELECT count(*) FROM public.lf_operation_execution e
      WHERE e.operation_code='ACTUALIZACION_DB_LF'
        AND e.target_type='MIGRATION'
        AND e.status='IN_PROGRESS'
        AND e.target_code~'^[0-9]{14}_lf_policy19_semantic_factor_selection_compat_v1$'
        AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
        AND e.target_path='supabase/migrations/'||e.target_code||'.sql'
        AND e.manifest->>'producer'='lf-migration-merge-train'
        AND e.manifest->>'router_authority_receipt' IS NOT NULL)<>1
  THEN RAISE EXCEPTION 'LF_POLICY19_SEMANTIC_TRAIN_CONTEXT_REQUIRED'; END IF;
  IF to_regprocedure('programacion.fn_input_governance_semantic_probe_v3_ctx(integer,text,bigint,jsonb)') IS NULL
  OR to_regprocedure('programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)') IS NULL
  OR to_regprocedure('programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)') IS NULL
  THEN RAISE EXCEPTION 'LF_POLICY19_SEMANTIC_FUNCTIONS_MISSING'; END IF;
  FOR v_sig,v_md5 IN
    SELECT src.sig,src.expected_md5
    FROM (VALUES ('programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)','8e2fd437a0ab693ce02fb3d6afe95406'),
  ('programacion.fn_input_governance_semantic_probe_v3_cached_v1(integer,text,bigint,jsonb)','f057bbe4e4fdf0c35d2bd73c1ccc5ac5'),
  ('programacion.fn_input_governance_semantic_probe_v3_ctx(integer,text,bigint,jsonb)','58d3ae035dba9c380cbf14fc65edc710')) AS src(sig,expected_md5)
  LOOP
    v_before:=pg_get_functiondef(v_sig::regprocedure);
    IF md5(v_before) IS DISTINCT FROM v_md5
       OR (length(v_before)-length(replace(v_before,v_old,'')))<>length(v_old)
       OR position('v_implementation_pending' in v_before)=0
       OR position('MFA_PROVIDER_IMPLEMENTATION_PENDING' in v_before)=0
    THEN RAISE EXCEPTION 'LF_POLICY19_SEMANTIC_SOURCE_PREIMAGE_DRIFT:%',v_sig; END IF;
    v_after:=replace(v_before,v_old,v_new);
    EXECUTE v_after;
    v_readback:=pg_get_functiondef(v_sig::regprocedure);
    IF position(v_new in v_readback)=0
       OR (length(v_readback)-length(replace(v_readback,v_new,'')))<>length(v_new)
       OR position('MFA_PROVIDER_IMPLEMENTATION_PENDING' in v_readback)=0
       OR position('v_implementation_pending' in v_readback)=0
       OR replace(v_readback,v_new,v_old) IS DISTINCT FROM v_before
    THEN RAISE EXCEPTION 'LF_POLICY19_SEMANTIC_READBACK_DRIFT:%:new=%:old=%:pending=%:reversed=%:len_before=%:len_after=%',
      v_sig,(position(v_new in v_readback)>0),(position(v_old in v_readback)>0),
      (position('v_implementation_pending' in v_readback)>0),
      (replace(v_readback,v_new,v_old)=v_before),length(v_before),length(v_readback); END IF;
  END LOOP;
END $lf_policy19_semantic$;
COMMIT;
