-- LF B2B - one authority for trusted-device duration; data only, no screen/runtime activation.
-- Policy ID 25 is canonical; company-scoped applied duration remains in lf_ops.empresas.
-- Existing B2B validation 103 becomes a consumer; no hardcoded list/default there.
BEGIN;
DO $preflight$
BEGIN
 IF (SELECT count(*) FROM lf_ops.politicas_seguridad
   WHERE security_policy_id=25 AND policy_code='SEC-B2B-TRUSTED-DEVICE'
   AND status='CANDIDATO'
   AND policy_config->'trusted_device_duration_allowed_days'='[7,15,30,60,90]'::jsonb
   AND policy_config->>'trusted_device_duration_default_days'='30'
   AND policy_config->>'trusted_device_duration_source'='lf_ops.empresas.trusted_device_duration_days')<>1
 THEN RAISE EXCEPTION 'B2B_TRUSTED_DEVICE_POLICY_GUARD_FAILED'; END IF;
 IF (SELECT count(*) FROM lf_ops.campos_validaciones
   WHERE id=103 AND codigo='B2B_VAL_TRUSTED_DEVICE_DURATION_ALLOWED'
   AND estado='ACTIVO'
   AND valor_config->>'policy_code'='SEC-B2B-TRUSTED-DEVICE'
   AND valor_config->>'default_value'='30'
   AND valor_config->'allowed_values'='[7,15,30,60,90]'::jsonb)<>1
 THEN RAISE EXCEPTION 'B2B_TRUSTED_DEVICE_VALIDATION_GUARD_FAILED'; END IF;
 IF (SELECT count(*) FROM information_schema.columns
     WHERE table_schema='lf_ops' AND table_name='empresas'
     AND column_name='trusted_device_duration_days')<>1
 THEN RAISE EXCEPTION 'B2B_TRUSTED_DEVICE_COMPANY_CONFIG_MISSING'; END IF;
END $preflight$;

UPDATE lf_ops.campos_validaciones
 SET valor_config = (valor_config-'default_value'-'allowed_values')
                   || jsonb_build_object(
                     'security_policy_id',25,
                     'relation_key','security_policy_id',
                     'relation_key_type','NUMERIC_ID',
                     'policy_source','lf_ops.politicas_seguridad',
                     'server_side_validation','REQUIRED')
 WHERE id=103 AND codigo='B2B_VAL_TRUSTED_DEVICE_DURATION_ALLOWED'
 AND estado='ACTIVO';

DO $readback$
BEGIN
 IF (SELECT count(*) FROM lf_ops.campos_validaciones
   WHERE id=103 AND estado='ACTIVO'
   AND valor_config->>'security_policy_id'='25'
   AND valor_config->>'policy_code'='SEC-B2B-TRUSTED-DEVICE'
   AND valor_config->>'server_side_validation'='REQUIRED'
   AND NOT (valor_config ? 'default_value')
   AND NOT (valor_config ? 'allowed_values'))<>1
 OR (SELECT count(*) FROM lf_ops.politicas_seguridad
   WHERE security_policy_id=25 AND status='CANDIDATO'
   AND policy_config->>'trusted_device_duration_default_days'='30'
   AND policy_config->'trusted_device_duration_allowed_days'='[7,15,30,60,90]'::jsonb)<>1
 THEN RAISE EXCEPTION 'B2B_TRUSTED_DEVICE_DEDUP_READBACK_FAILED'; END IF;
END $readback$;
COMMIT;
