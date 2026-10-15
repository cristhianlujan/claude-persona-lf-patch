-- LF Backoffice Empresa: recovery risk and removal of one demonstrably duplicated storage TTL.
-- Data-only governed candidate. The LF Migration Merge Train remints the version.
-- No new tables, fields, states, permissions, runtime activation, or numeric threshold changes.
-- Canonical: lf_ops.politicas_seguridad ID 20 and ID 6.
-- EKB: PRV-ARC-013, PRV-SEC-013, PRV-DB-GIT-FIRST-PERSISTENT-OBJECT-001.
BEGIN;

DO $preflight$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM lf_ops.politicas_seguridad p
    WHERE p.security_policy_id=20 AND p.policy_code='SEC-B2B-MFA-RECOVERY'
      AND p.status='CANDIDATO'
      AND p.policy_config->>'email_access_recovery_status'='PENDING_FUNCTIONAL_DEFINITION'
      AND p.policy_config->>'password_only_bypass'='DENY'
  ) THEN RAISE EXCEPTION 'B2B_RECOVERY_POLICY_GUARD_FAILED'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM lf_ops.reglas r
    WHERE r.id=439 AND r.codigo='B2B-RULE-AUTH-020' AND r.estado='CANDIDATO'
      AND r.valor_config->>'mfa_recovery_security_policy_id'='20'
      AND r.valor_config->>'email_access_recovery_status'='PENDING_FUNCTIONAL_DEFINITION'
  ) THEN RAISE EXCEPTION 'B2B_RECOVERY_RULE_GUARD_FAILED'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM lf_ops.politicas_seguridad p
    WHERE p.security_policy_id=6 AND p.policy_code='SEC-B2B-STORAGE-PRIVATE'
      AND p.status='CANDIDATO'
      AND p.policy_config->>'signed_url_ttl_seconds'='300'
  ) THEN RAISE EXCEPTION 'B2B_STORAGE_POLICY_GUARD_FAILED'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM lf_ops.reglas r
    WHERE r.codigo='B2B-RULE-STORAGE-001' AND r.estado='CANDIDATO'
      AND (
        (r.valor_config->>'signed_url_ttl_seconds'='300'
         AND NOT (r.valor_config ? 'security_policy_id'))
        OR
        (r.valor_config->>'security_policy_id'='6'
         AND NOT (r.valor_config ? 'signed_url_ttl_seconds'))
      )
  ) THEN RAISE EXCEPTION 'B2B_STORAGE_RULE_GUARD_FAILED'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM lf_ops.otp_operaciones o
    JOIN lf_ops.otp_politicas p ON p.id=o.politica_id
    WHERE o.id=5 AND p.id=2 AND o.estado='CANDIDATO' AND p.estado='CANDIDATO'
  ) OR NOT EXISTS (
    SELECT 1 FROM lf_ops.politicas_rate_limit
    WHERE rate_limit_policy_id=7 AND policy_code='RATE-B2B-PASSWORD-RECOVERY-OTP'
  ) THEN RAISE EXCEPTION 'B2B_RECOVERY_REFERENCES_MISSING'; END IF;
END
$preflight$;

UPDATE lf_ops.politicas_seguridad
SET description = description ||
    ' Cuando el mismo buzon recibe codigos para recuperar la contrasena y para el segundo control, controlar ese buzon no demuestra una segunda verificacion independiente de identidad. Ante sospecha o reporte de compromiso del correo, ningun codigo enviado a ese mismo canal puede justificar por si solo la recuperacion del factor o una sesion operativa. El procedimiento independiente y auditable para los perfiles no administradores permanece PENDING_FUNCTIONAL_DEFINITION. No se permite bypass ni degradacion a contrasena sola.',
    updated_at = CURRENT_TIMESTAMP
WHERE security_policy_id=20 AND policy_code='SEC-B2B-MFA-RECOVERY' AND status='CANDIDATO'
  AND description NOT LIKE '%controlar ese buzon no demuestra una segunda verificacion independiente%';

UPDATE lf_ops.reglas
SET descripcion = descripcion ||
    ' Si se perdio el control del correo o existe sospecha de compromiso, reenviar un OTP al mismo buzon no aporta verificacion independiente. Para los perfiles no administradores debe aplicarse un procedimiento de identidad separado, auditable y aun PENDING_FUNCTIONAL_DEFINITION, bajo la politica central de recuperacion ID 20, sin autorizar acceso operativo ni bypass.',
    updated_at = CURRENT_TIMESTAMP
WHERE id=439 AND codigo='B2B-RULE-AUTH-020' AND estado='CANDIDATO'
  AND descripcion NOT LIKE '%reenviar un OTP al mismo buzon no aporta verificacion independiente%';

-- The canonical 300-second TTL ALREADY exists in security policy ID 6.
-- Remove its duplicate from the screen-facing rule; retain the numeric policy reference.
UPDATE lf_ops.reglas
SET valor_config = (valor_config - 'signed_url_ttl_seconds')
                  || jsonb_build_object('security_policy_id',6),
    updated_at = CURRENT_TIMESTAMP
WHERE codigo='B2B-RULE-STORAGE-001' AND estado='CANDIDATO'
  AND valor_config->>'signed_url_ttl_seconds'='300'
  AND NOT (valor_config ? 'security_policy_id');

DO $readback$
BEGIN
  IF (SELECT count(*) FROM lf_ops.politicas_seguridad
      WHERE security_policy_id=20 AND status='CANDIDATO'
        AND policy_config->>'email_access_recovery_status'='PENDING_FUNCTIONAL_DEFINITION'
        AND policy_config->>'password_only_bypass'='DENY'
        AND description LIKE '%controlar ese buzon no demuestra una segunda verificacion independiente%')<>1
   OR (SELECT count(*) FROM lf_ops.reglas
       WHERE id=439 AND estado='CANDIDATO'
         AND descripcion LIKE '%reenviar un OTP al mismo buzon no aporta verificacion independiente%')<>1
   OR (SELECT count(*) FROM lf_ops.reglas
       WHERE codigo='B2B-RULE-STORAGE-001' AND estado='CANDIDATO'
         AND valor_config->>'security_policy_id'='6'
         AND NOT (valor_config ? 'signed_url_ttl_seconds'))<>1
   OR (SELECT count(*) FROM lf_ops.politicas_seguridad
       WHERE security_policy_id=6 AND policy_config->>'signed_url_ttl_seconds'='300')<>1
   OR (SELECT count(*) FROM lf_ops.politicas_rate_limit
       WHERE rate_limit_policy_id=7 AND max_requests=6 AND window_seconds=900)<>1
   OR (SELECT count(*) FROM lf_ops.otp_politicas
       WHERE id=2 AND max_intentos=5 AND max_reenvios=3 AND expiracion_minutos=5)<>1
  THEN RAISE EXCEPTION 'B2B_RECOVERY_STORAGE_PARAM_READBACK_FAILED'; END IF;
END
$readback$;

COMMIT;
