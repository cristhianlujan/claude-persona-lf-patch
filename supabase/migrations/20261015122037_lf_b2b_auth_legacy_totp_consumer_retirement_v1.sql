-- LF B2B auth: resolve drift between RETIRED_LEGACY_TRACE_ONLY and live screen.
-- Data-only, scoped to screen 55, route 14 and validation B2B_VAL_MFA_ENROLL_CODE_REQUIRED.
-- Existing enums only: REEMPLAZADO, INACTIVO, DEPRECATED.
-- No removal of history, credentials, OTP policy, or live authentication flow.
-- EKB: PRV-ARC-013, PRV-DB-GIT-FIRST-PERSISTENT-OBJECT-001,
--      PRV-INPUT-GOV-DECISION-RULE-PROVENANCE-PARITY-001.
BEGIN;

DO $preflight$
BEGIN
  IF (SELECT count(*) FROM lf_ops.pantallas
      WHERE id=55 AND codigo='B2B-AUTH-005'
        AND estado='VIGENTE' AND activa=true
        AND descripcion ILIKE '%retirada del flujo operativo%') <> 1 THEN
    RAISE EXCEPTION 'B2B_TOTP_SCREEN_PRECONDITION_FAILED';
  END IF;
  IF (SELECT count(*) FROM lf_ops.rutas
      WHERE route_id=14 AND pantalla_id=55
        AND route_code='B2B_ROUTE_AUTH_MFA_ENROLL' AND status='CANDIDATO') <> 1 THEN
    RAISE EXCEPTION 'B2B_TOTP_ROUTE_PRECONDITION_FAILED';
  END IF;
  IF (SELECT count(*) FROM lf_ops.campos_validaciones
      WHERE codigo='B2B_VAL_MFA_ENROLL_CODE_REQUIRED'
        AND estado='CANDIDATO'
        AND valor_config->>'provider_validation'='SUPABASE_TOTP') <> 1 THEN
    RAISE EXCEPTION 'B2B_TOTP_VALIDATION_PRECONDITION_FAILED';
  END IF;
  IF (SELECT count(*) FROM lf_ops.reglas
      WHERE id=454 AND codigo='B2B-RULE-AUTH-035'
        AND valor_config->>'lifecycle_status'='RETIRED_LEGACY_TRACE_ONLY'
        AND valor_config->>'activation_authority'='DENY'
        AND valor_config->>'implementation_as_active_path'='DENY'
        AND valor_config->>'production_authorized'='false') <> 1 THEN
    RAISE EXCEPTION 'B2B_TOTP_LEGACY_RULE_AUTHORITY_MISSING';
  END IF;
  IF (SELECT count(*) FROM lf_ops.politicas_seguridad
      WHERE security_policy_id=19 AND policy_code='SEC-B2B-MFA-FACTOR-ELIGIBILITY'
        AND policy_config->>'non_admin_method'='LF_EMAIL_OTP'
        AND status='CANDIDATO') <> 1 THEN
    RAISE EXCEPTION 'B2B_TOTP_REPLACEMENT_FACTOR_NOT_DEFINED';
  END IF;
END $preflight$;

UPDATE lf_ops.pantallas
SET estado='REEMPLAZADO', activa=false
WHERE id=55 AND codigo='B2B-AUTH-005' AND estado='VIGENTE' AND activa=true;

UPDATE lf_ops.rutas
SET status='INACTIVO'
WHERE route_id=14 AND pantalla_id=55
  AND route_code='B2B_ROUTE_AUTH_MFA_ENROLL' AND status='CANDIDATO';

-- Preserve historical field/validation identity; remove obsolete runtime vendor binding.
UPDATE lf_ops.campos_validaciones
SET estado='DEPRECATED', valor_config=valor_config-'provider_validation'
WHERE codigo='B2B_VAL_MFA_ENROLL_CODE_REQUIRED'
  AND estado='CANDIDATO'
  AND valor_config->>'provider_validation'='SUPABASE_TOTP';

DO $postflight$
BEGIN
  IF (SELECT count(*) FROM lf_ops.pantallas
      WHERE id=55 AND codigo='B2B-AUTH-005'
        AND estado='REEMPLAZADO' AND activa=false) <> 1
  OR (SELECT count(*) FROM lf_ops.rutas
      WHERE route_id=14 AND pantalla_id=55
        AND route_code='B2B_ROUTE_AUTH_MFA_ENROLL' AND status='INACTIVO') <> 1
  OR (SELECT count(*) FROM lf_ops.campos_validaciones
      WHERE codigo='B2B_VAL_MFA_ENROLL_CODE_REQUIRED'
        AND estado='DEPRECATED'
        AND NOT (valor_config ? 'provider_validation')
        AND valor_config->>'numeric_thresholds_in_validation'='DENY') <> 1
  OR (SELECT count(*) FROM lf_ops.pantallas
      WHERE id=54 AND codigo='B2B-AUTH-004' AND activa=true) <> 1
  OR (SELECT count(*) FROM lf_ops.politicas_seguridad
      WHERE security_policy_id=19 AND policy_config->>'non_admin_method'='LF_EMAIL_OTP') <> 1
  OR (SELECT count(*) FROM lf_ops.reglas
      WHERE id=454 AND valor_config->>'activation_authority'='DENY') <> 1
  THEN RAISE EXCEPTION 'B2B_TOTP_RETIREMENT_READBACK_FAILED';
  END IF;
END $postflight$;

COMMIT;
