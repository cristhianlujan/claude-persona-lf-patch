-- LF E21: missing canonical B2B password-failure attempt policy, candidate only.
-- No invented threshold, no lockout runtime, no production/promotion effect.
-- Existing Q01 (MFA) and Q11 (recovery) remain bound to AUTH-019/020.
BEGIN;
DO $e21$
DECLARE v_screen_id integer; v_rule_id integer;
BEGIN
 SELECT p.id INTO v_screen_id
 FROM lf_ops.pantallas p
 WHERE p.id=51 AND p.codigo='B2B-AUTH-001' AND p.activa IS TRUE;
 IF v_screen_id IS NULL THEN
   RAISE EXCEPTION 'E21_SCREEN51_LOGIN_SOURCE_DRIFT';
 END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas
           WHERE codigo='B2B-RULE-AUTH-049') THEN
   RAISE EXCEPTION 'E21_PASSWORD_ATTEMPTS_CANDIDATE_ALREADY_EXISTS';
 END IF;
 IF NOT EXISTS(
  SELECT 1 FROM lf_ops.reglas r
  JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
  WHERE r.codigo='B2B-RULE-AUTH-047' AND rp.pantalla_id=v_screen_id
    AND r.pendiente_decision IS TRUE
    AND r.valor_config->>'dependency'='PASSWORD_ATTEMPT_POLICY'
 ) THEN
   RAISE EXCEPTION 'E21_ORIGIN_PASSWORD_ATTEMPT_GAP_NOT_PROVEN';
 END IF;

 INSERT INTO lf_ops.reglas(
    codigo,categoria,titulo,descripcion,razon,valor_config,
    es_transversal,estado,origen,pendiente_decision,pendiente_detalle,created_by)
 VALUES (
   'B2B-RULE-AUTH-049',
   'SECURITY',
   'Contabilización de fallos de contraseña sin umbral asumido',
   'La frontera de autenticación del servidor identifica fallos de credencial de contraseña como eventos específicos, nunca confunde solicitudes por IP o MFA con intentos de contraseña, no revela existencia de cuentas, no almacena contraseña y no permite bloqueo automático sin política canónica aprobada y pruebas de comportamiento.',
   'Cierre estructural de dependencia PASSWORD_ATTEMPT_POLICY reportada en B2B-RULE-AUTH-047; política candidata no ejecutable hasta decisión de alcance, control, ventana y conducta.',
   jsonb_build_object(
     'screen_id',51,
     'source_rule_code','B2B-RULE-AUTH-047',
     'policy_family','PASSWORD_CREDENTIAL_FAILURE_ATTEMPTS',
     'owner_decision_ref','L16-Q12|L16-Q06',
     'owner_decision_status','CONTROL_UNIT_WINDOW_NOT_DEFINED',
     'countable_outcome','INVALID_CREDENTIALS',
     'excluded_outcomes',jsonb_build_array('MFA_REQUIRED','RATE_LIMITED','SERVICE_UNAVAILABLE','BOT_CHALLENGE'),
     'server_side_authority','REQUIRED',
     'client_counter_authority','DENY',
     'credential_value_storage','DENY',
     'username_enumeration','DENY',
     'privacy_safe_counter_key','OWNER_POLICY_DEFINITION_REQUIRED',
     'threshold_source','GOVERNED_SECURITY_POLICY_ONLY',
     'threshold_binding','UNDEFINED_DO_NOT_ENFORCE',
     'window_duration','UNDEFINED_DO_NOT_ENFORCE',
     'reset_and_lockout_behavior','UNDEFINED_DO_NOT_ENFORCE',
     'rate_limit_policy_reuse_as_password_failure','DENY',
     'numeric_thresholds_in_rule','DENY',
     'implementation_status','PENDING_OWNER_DEFINITION_AND_RUNTIME_QA',
     'production_authorized',false,
     'promotion_authorized',false
   ),
   false,'CANDIDATO','LF_E21_GOVERNED_MISSING_RULE_20261116',true,
   '¿El valor inicial 5 de L16-Q12 corresponde a intentos fallidos de contraseña por cuenta, IP, dispositivo o combinación? ¿Cuál es la ventana, el evento de reinicio, la consecuencia (desafío o bloqueo) y su duración? Distinguir expresamente esta política del rate-limit RATE-B2B-LOGIN.',
   'LF_GOVERNED_MIGRATION_E21'
 )
 RETURNING id INTO v_rule_id;

 INSERT INTO lf_ops.reglas_pantallas(regla_id,pantalla_id,nota)
 VALUES (v_rule_id,v_screen_id,
  'CANDIDATO: dependencia de AUTH-047 y Q12/Q06; no autoriza bloqueo ni promoción');

 IF NOT EXISTS(
    SELECT 1 FROM lf_ops.reglas r
    JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
    WHERE r.id=v_rule_id AND rp.pantalla_id=51
      AND r.estado='CANDIDATO' AND r.pendiente_decision IS TRUE
      AND r.valor_config->>'implementation_status'='PENDING_OWNER_DEFINITION_AND_RUNTIME_QA'
      AND r.valor_config->>'owner_decision_ref'='L16-Q12|L16-Q06'
      AND r.valor_config->>'production_authorized'='false'
 ) THEN RAISE EXCEPTION 'E21_CANDIDATE_POST_WRITE_READBACK_FAILED'; END IF;
END $e21$;
COMMIT;
