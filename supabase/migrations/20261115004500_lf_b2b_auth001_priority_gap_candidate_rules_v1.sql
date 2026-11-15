-- LF B2B-AUTH-001: five Product Director priority gaps; proposal only, NEVER production.
-- Pattern copied from 20260929151800_lf_b2b_auth_security_timeout_readiness_v1.sql:
-- INSERT lf_ops.reglas(CANDIDATO) -> INSERT lf_ops.reglas_pantallas -> SELECT readback.
-- No UPDATE existing rules/policies, no promotion, no execution RUN modification.
BEGIN;

DO $preflight$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM lf_ops.pantallas WHERE id=51 AND codigo='B2B-AUTH-001')
  THEN RAISE EXCEPTION 'LF_AUTH001_SCREEN_SOURCE_DRIFT'; END IF;
  IF NOT EXISTS (SELECT 1 FROM lf_ops.politicas_rate_limit
                 WHERE rate_limit_policy_id=1 AND policy_code='RATE-B2B-LOGIN'
                   AND status='VIGENTE' AND window_seconds=900 AND max_requests=5
                   AND scope_key='IP_USER')
  THEN RAISE EXCEPTION 'LF_AUTH001_REQUEST_RATE_POLICY_SOURCE_DRIFT'; END IF;
  IF NOT EXISTS (SELECT 1 FROM lf_ops.politicas_seguridad
                 WHERE security_policy_id=3 AND policy_code='SEC-B2B-MFA'
                   AND status='VIGENTE'
                   AND policy_config->'profile_ids'='[1,2,3,4,5,6]'::jsonb)
     OR NOT EXISTS (SELECT 1 FROM lf_ops.politicas_seguridad
                 WHERE security_policy_id=19 AND policy_code='SEC-B2B-MFA-FACTOR-ELIGIBILITY'
                   AND status='CANDIDATO'
                   AND policy_config->'profile_ids'='[1,2,3,4,5,6]'::jsonb)
     OR NOT EXISTS (SELECT 1 FROM lf_ops.politicas_seguridad
                 WHERE security_policy_id=20 AND policy_code='SEC-B2B-MFA-RECOVERY'
                   AND status='CANDIDATO')
  THEN RAISE EXCEPTION 'LF_AUTH001_SECURITY_POLICY_SOURCE_DRIFT'; END IF;
  IF (SELECT count(*) FROM lf_ops.reglas
      WHERE (codigo='B2B-RULE-AUDIT-001' AND estado='VIGENTE')
         OR (codigo IN ('B2B-RULE-AUTH-020','B2B-RULE-AUTH-024',
                       'B2B-RULE-AUTH-018','B2B-RULE-AUTH-019',
                       'B2B-RULE-AUTH-021','B2B-RULE-AUTH-047')
             AND estado='CANDIDATO'))<>7
  THEN RAISE EXCEPTION 'LF_AUTH001_EXISTING_RULE_SOURCE_DRIFT'; END IF;
  IF EXISTS (SELECT 1 FROM lf_ops.reglas WHERE codigo IN ('B2B-RULE-AUTH-GAP-PASSWORD-ATTEMPTS-001',
    'B2B-RULE-AUTH-GAP-AUDIT-001',
    'B2B-RULE-AUTH-GAP-MFA-RECOVERY-001',
    'B2B-RULE-AUTH-GAP-TENANT-ISOLATION-001',
    'B2B-RULE-AUTH-GAP-MFA-COVERAGE-001')
             AND (estado<>'CANDIDATO'
                  OR origen<>'LF_PRODUCT_DIRECTOR_AUTH001_GAPS_CANDIDATE_20261115'
                  OR valor_config->>'schema_version'<>'LF_B2B_AUTH001_GAP_CANDIDATE_V1'))
  THEN RAISE EXCEPTION 'LF_AUTH001_CANDIDATE_COLLISION_DRIFT'; END IF;
END;
$preflight$;

WITH candidate AS (
  SELECT * FROM jsonb_to_recordset($candidates$
[{"codigo":"B2B-RULE-AUTH-GAP-PASSWORD-ATTEMPTS-001","categoria":"SECURITY","titulo":"Contador de intentos fallidos de contraseña separado del rate limit de requests","descripcion":"Contabilizar exclusivamente resultados INVALID_CREDENTIALS de contraseña en la frontera LF del servidor por sujeto de cuenta y empresa, con ventana móvil y política configurable. No equiparar RATE-B2B-LOGIN (5 solicitudes/900s IP_USER) a 5 contraseñas erróneas. La respuesta pública no enumera cuentas; IP solo señal de riesgo, nunca sujeto único de bloqueo; sin bloqueo permanente por un solo indicio.","razon":"AUTH-021 y AUTH-047 no definen unidad, sujeto ni ventana; nota de dueño Q12=5 no vinculada a control.","valor_config":{"schema_version":"LF_B2B_AUTH001_GAP_CANDIDATE_V1","screen_id":51,"screen_code":"B2B-AUTH-001","production_authorized":false,"promotion_authorized":false,"implementation_status":"PENDING_IMPLEMENTATION_QA","source_authority":"PRODUCT_DIRECTOR_PROFILE_OUTPUT_STEP50_60_20261114","evidence_mode":"CANDIDATE_DOCUMENTARY_ONLY","control":"PASSWORD_FAILED_CREDENTIAL_ATTEMPTS","source_rule_codes":["B2B-RULE-AUTH-021","B2B-RULE-AUTH-047"],"distinct_request_rate_limit_policy_id":1,"distinct_request_rate_limit_policy_code":"RATE-B2B-LOGIN","counter_event":"INVALID_CREDENTIALS_PASSWORD_ONLY","counter_owner":"SERVER_AUTH_BOUNDARY","counter_subject":"TENANT_ID_AND_RESOLVED_ACCOUNT_ID_OR_OPAQUE_NORMALIZED_SUBJECT_DIGEST","tenant_id_source":"SERVER_VERIFIED_AUTH_CONTEXT","counter_window_mode":"SLIDING","max_failed_password_attempts":null,"failed_password_window_seconds":null,"parameters_status":"PENDING_OWNER_DECISION","proposal_not_enforcement":{"max_failed_password_attempts":5,"failed_password_window_seconds":900},"account_enumeration":"DENY","ip_hard_limit":"DENY","reset_policy":"SERVER_CONFIG_PENDING","permanent_lockout_from_single_signal":"DENY","credentials_in_telemetry":"DENY","negative_tests":["PASSWORD_FAILURE_COUNTED","VALIDATION_ERROR_NOT_COUNTED","REQUEST_RATE_COUNTER_NOT_REUSED","OTHER_TENANT_COUNTER_ISOLATED","WINDOW_EXPIRES","UNKNOWN_ACCOUNT_NO_ENUMERATION"]},"pendiente_decision":true,"pendiente_detalle":"DECISION_CERRADA: ¿Apruebas 5 fallos de contraseña por cuenta y empresa en ventana móvil de 15 minutos (RECOMENDADO), Sí/No? Hasta responder mantener max_failed_password_attempts y failed_password_window_seconds NULL sin enforcement."},{"codigo":"B2B-RULE-AUTH-GAP-AUDIT-001","categoria":"AUDIT","titulo":"Contrato verificable de eventos de auditoría de autenticación B2B","descripcion":"Vincular los eventos de login, rechazo, MFA, recuperación y sesión a la fuente canónica de auditoría append-only con correlación, empresa y actor cuando se conocen. No persistir contraseñas, OTP, tokens, correo íntegro ni payload crudo del proveedor. Auditar el resultado autorizado por el servidor, incluidas negativas, sin confundir logs analíticos con evidencia de seguridad.","razon":"Completar verificabilidad de AUTH-024 usando B2B-RULE-AUDIT-001 sin duplicar su implementación transversal.","valor_config":{"schema_version":"LF_B2B_AUTH001_GAP_CANDIDATE_V1","screen_id":51,"screen_code":"B2B-AUTH-001","production_authorized":false,"promotion_authorized":false,"implementation_status":"PENDING_IMPLEMENTATION_QA","source_authority":"PRODUCT_DIRECTOR_PROFILE_OUTPUT_STEP50_60_20261114","evidence_mode":"CANDIDATE_DOCUMENTARY_ONLY","source_rule_codes":["B2B-RULE-AUTH-024","B2B-RULE-AUDIT-001"],"audit_sink_ref":"lf_ops.auditoria_eventos","append_only_rule_id":416,"login_audit_rule_id":443,"required_audit_actions":["LOGIN_SUCCESS","LOGIN_FAILURE","MFA_REQUIRED","MFA_SUCCESS","MFA_FAILURE","RATE_LIMIT_TRIGGERED","SESSION_CREATED","RECOVERY_INITIATED","MFA_RECOVERY_REQUESTED","MFA_RECOVERY_IDENTITY_VERIFIED","MFA_FACTOR_RESET","MFA_REENROLLED"],"required_fields":["event_code","occurred_at","correlation_id","result","actor_id_when_authenticated","company_id_when_resolved","source_policy_ref"],"forbidden_fields":["PASSWORD","OTP_VALUE","ACCESS_TOKEN","REFRESH_TOKEN","FULL_EMAIL","PROVIDER_RAW_PAYLOAD"],"write_boundary":"SERVER_ONLY","audit_update_delete":"DENY","unknown_actor_handling":"NULL_NON_IDENTIFYING","negative_tests":["NO_CREDENTIALS_IN_AUDIT","FAILURE_EVENT_RECORDED","EVENT_APPEND_ONLY","CORRELATION_PRESENT","TENANT_CONTEXT_NOT_CLIENT_FORGED"]},"pendiente_decision":false,"pendiente_detalle":null},{"codigo":"B2B-RULE-AUTH-GAP-MFA-RECOVERY-001","categoria":"SECURITY","titulo":"Recuperación MFA sin bypass y conciliación pendiente AUTH-020 con política central 20","descripcion":"Recuperación por canal separado con verificación de identidad independiente, dos revisores y espera documentada de 48h según AUTH-020, aviso al contacto previo, revocación del factor y re-enrolamiento, sin sesión previa ni contraseña sola. La política central 20 aún describe Google Workspace para administradores, incompatible con la política factor 19 OTP Brevo 1-6; bloquear solo la rama conflictiva de recuperación hasta conciliación autorizada. No cambiar ni promocionar política central 20 en este lote.","razon":"AUTH-020 y SEC-B2B-MFA-RECOVERY tienen conflicto de proveedor y un procedimiento no-admin aún PENDING_FUNCTIONAL_DEFINITION; mantener hallazgo explícito.","valor_config":{"schema_version":"LF_B2B_AUTH001_GAP_CANDIDATE_V1","screen_id":51,"screen_code":"B2B-AUTH-001","production_authorized":false,"promotion_authorized":false,"implementation_status":"PENDING_IMPLEMENTATION_QA","source_authority":"PRODUCT_DIRECTOR_PROFILE_OUTPUT_STEP50_60_20261114","evidence_mode":"CANDIDATE_DOCUMENTARY_ONLY","source_rule_codes":["B2B-RULE-AUTH-020"],"source_rule_id":439,"mfa_recovery_security_policy_id":20,"factor_security_policy_id":19,"applicability_security_policy_id":3,"policy20_current_status":"CANDIDATO","policy20_admin_recovery_mode_observed":"GOOGLE_WORKSPACE_IDP_MANAGED","policy19_factor_profile_coverage":[1,2,3,4,5,6],"policy19_factor_observed":"LF_EMAIL_OTP","provider_conflict_status":"PENDING_GOVERNED_RECONCILIATION","recovery_flow":"SEPARATE","assisted_identity_check":"DNI_AND_INDEPENDENT_SUPPORT_CHECK","human_approvals_required":2,"hold_hours_from_auth020":48,"previous_contact_notification":"REQUIRED","server_only_factor_reset":true,"reenrollment":"REQUIRED","password_only_bypass":"DENY","session_during_recovery":"DENY","same_email_as_second_factor_alone_is_identity_proof":"DENY","facephi_optional_branch":"DISABLED_NO_AUTOMATIC_FALLBACK","conflicting_recovery_branch":"HOLD_UNTIL_POLICY20_AUTHORITY","normal_login_continuation":"NOT_BLOCKED_BY_RECOVERY_POLICY_CONFLICT","negative_tests":["TWO_APPROVALS_REQUIRED","HOLD_WINDOW_OBSERVED","OLD_FACTOR_REVOKED","RECOVERY_EMAIL_ALONE_REJECTED","NO_EARLY_OPERATIONAL_SESSION","POLICY20_PROVIDER_DRIFT_DETECTED"]},"pendiente_decision":false,"pendiente_detalle":"Requiere conciliación futura de la política central 20 por su dueño; no hay aprobación de mutación en este lote."},{"codigo":"B2B-RULE-AUTH-GAP-TENANT-ISOLATION-001","categoria":"AUTHORIZATION","titulo":"Aislamiento de empresa obligatorio en autenticación y sesión B2B","descripcion":"Resolver company_id y permisos exclusivamente del contexto firmado por servidor; todo acceso a recursos B2B y contexto post-login se comprueba contra empresa autorizada. No confiar en tenant_id o company_id enviados por cliente, ni permitir correlación o cache compartidos entre empresas. Acceso cruzado se deniega antes de consultar datos y no filtra existencia de recursos.","razon":"Falta regla específica verificable de aislamiento B2B por empresa en Login y límites de sesión.","valor_config":{"schema_version":"LF_B2B_AUTH001_GAP_CANDIDATE_V1","screen_id":51,"screen_code":"B2B-AUTH-001","production_authorized":false,"promotion_authorized":false,"implementation_status":"PENDING_IMPLEMENTATION_QA","source_authority":"PRODUCT_DIRECTOR_PROFILE_OUTPUT_STEP50_60_20261114","evidence_mode":"CANDIDATE_DOCUMENTARY_ONLY","source_rule_codes":["B2B-RULE-AUTH-023","B2B-RULE-AUTH-STATE-001"],"tenant_boundary":"SERVER_AUTHORIZED_COMPANY_CONTEXT","company_id_source":"SIGNED_SERVER_SESSION_OR_CANONICAL_AUTH_CONTEXT","client_company_id_authority":"DENY","server_side_resource_authorization":"REQUIRED_EACH_REQUEST","cross_tenant_access":"DENY","cross_tenant_error":"GENERIC_ACCESS_DENIED","cross_tenant_existence_disclosure":"DENY","cross_company_session_reuse":"DENY","authorization_source_refs":["lf_ops.perfiles_permisos","lf_ops.pantallas_perfiles"],"tenant_scoped_cache":"REQUIRED","session_company_binding":"IMMUTABLE_WITHOUT_REAUTHORIZATION","negative_tests":["COMPANY_A_CANNOT_ACCESS_COMPANY_B","CLIENT_COMPANY_ID_OVERRIDDEN","CROSS_TENANT_CACHE_MISS","NO_RESOURCE_ENUMERATION","SESSION_REBIND_REQUIRES_REAUTH"]},"pendiente_decision":false,"pendiente_detalle":null},{"codigo":"B2B-RULE-AUTH-GAP-MFA-COVERAGE-001","categoria":"SECURITY","titulo":"Aplicabilidad MFA a los seis perfiles humanos B2B por referencia central","descripcion":"La política de aplicabilidad SEC-B2B-MFA id 3 exige MFA para profile_id 1..6 y debe evaluarse servidor-side antes de crear sesión. El factor concreto se resuelve exclusivamente desde la política central 19 (actual CANDIDATO); no se duplica tabla de factores ni se concede sesión con contraseña sola. La falta de integración Brevo/IdP es hallazgo de implementación, no aprobación de bypass.","razon":"Acreditar referencia efectiva a política central 3 para seis perfiles y diferenciarla de factor policy19 y recuperación policy20.","valor_config":{"schema_version":"LF_B2B_AUTH001_GAP_CANDIDATE_V1","screen_id":51,"screen_code":"B2B-AUTH-001","production_authorized":false,"promotion_authorized":false,"implementation_status":"PENDING_IMPLEMENTATION_QA","source_authority":"PRODUCT_DIRECTOR_PROFILE_OUTPUT_STEP50_60_20261114","evidence_mode":"CANDIDATE_DOCUMENTARY_ONLY","source_rule_codes":["B2B-RULE-AUTH-018","B2B-RULE-AUTH-019"],"applicability_security_policy_id":3,"applicability_policy_code":"SEC-B2B-MFA","applicability_policy_status_observed":"VIGENTE","factor_security_policy_id":19,"factor_policy_status_observed":"CANDIDATO","coverage_verification":"READ_CENTRAL_POLICY_AT_RUNTIME","profile_ids_observed":[1,2,3,4,5,6],"profile_coverage_source":"lf_ops.politicas_seguridad.policy_config.profile_ids","server_side_verification":"REQUIRED","factor_selection_source":"SECURITY_POLICY_19_ONLY","password_only_session":"DENY","operational_session_before_mfa":"DENY","otp_security_claim":"NO_NATIVE_AAL2_CLAIM","negative_tests":["EACH_PROFILE_1_TO_6_MFA_REQUIRED","NO_PROFILE_EXEMPTION","CLIENT_CANNOT_SELECT_FACTOR","NO_PASSWORD_ONLY_SESSION","FACTOR_POLICY_PENDING_DOES_NOT_AUTO_AUTHORIZE_BYPASS"]},"pendiente_decision":false,"pendiente_detalle":null}]
$candidates$::jsonb)
  AS spec(codigo text, categoria text, titulo text, descripcion text,
          razon text, valor_config jsonb, pendiente_decision boolean,
          pendiente_detalle text)
)
INSERT INTO lf_ops.reglas
  (codigo,categoria,titulo,descripcion,razon,valor_config,es_transversal,
   estado,origen,pendiente_decision,pendiente_detalle,created_by)
SELECT codigo,categoria,titulo,descripcion,razon,valor_config,false,
       'CANDIDATO','LF_PRODUCT_DIRECTOR_AUTH001_GAPS_CANDIDATE_20261115',
       pendiente_decision,pendiente_detalle,
       'PR_GOVERNED_PRODUCT_DIRECTOR_AUTH001_20261115'
FROM candidate
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO lf_ops.reglas_pantallas (regla_id,pantalla_id,nota)
SELECT r.id,51,'CANDIDATO: Product Director auth gap; no production/promotion.'
FROM lf_ops.reglas r
WHERE r.codigo IN ('B2B-RULE-AUTH-GAP-PASSWORD-ATTEMPTS-001',
    'B2B-RULE-AUTH-GAP-AUDIT-001',
    'B2B-RULE-AUTH-GAP-MFA-RECOVERY-001',
    'B2B-RULE-AUTH-GAP-TENANT-ISOLATION-001',
    'B2B-RULE-AUTH-GAP-MFA-COVERAGE-001')
ON CONFLICT (regla_id,pantalla_id) DO NOTHING;

-- SELECT evidence inside the same transaction, not a guessed insertion receipt.
DO $readback$
DECLARE v_links integer; v_rules integer; v_pending integer;
BEGIN
  SELECT count(*) INTO v_rules
  FROM lf_ops.reglas r
  WHERE r.codigo IN ('B2B-RULE-AUTH-GAP-PASSWORD-ATTEMPTS-001',
    'B2B-RULE-AUTH-GAP-AUDIT-001',
    'B2B-RULE-AUTH-GAP-MFA-RECOVERY-001',
    'B2B-RULE-AUTH-GAP-TENANT-ISOLATION-001',
    'B2B-RULE-AUTH-GAP-MFA-COVERAGE-001')
    AND r.estado='CANDIDATO'
    AND r.es_transversal=false
    AND r.origen='LF_PRODUCT_DIRECTOR_AUTH001_GAPS_CANDIDATE_20261115'
    AND r.valor_config->>'schema_version'='LF_B2B_AUTH001_GAP_CANDIDATE_V1'
    AND r.valor_config->>'production_authorized'='false';
  IF v_rules<>5 THEN RAISE EXCEPTION 'LF_AUTH001_CANDIDATE_COUNT_READBACK:%',v_rules; END IF;

  SELECT count(*) INTO v_links
  FROM lf_ops.reglas r
  JOIN lf_ops.reglas_pantallas rp ON rp.regla_id=r.id
  WHERE r.codigo IN ('B2B-RULE-AUTH-GAP-PASSWORD-ATTEMPTS-001',
    'B2B-RULE-AUTH-GAP-AUDIT-001',
    'B2B-RULE-AUTH-GAP-MFA-RECOVERY-001',
    'B2B-RULE-AUTH-GAP-TENANT-ISOLATION-001',
    'B2B-RULE-AUTH-GAP-MFA-COVERAGE-001') AND rp.pantalla_id=51
    AND r.estado='CANDIDATO';
  IF v_links<>5 THEN RAISE EXCEPTION 'LF_AUTH001_SCREEN51_LINK_READBACK:%',v_links; END IF;
  SELECT count(*) INTO v_pending FROM lf_ops.reglas
  WHERE codigo='B2B-RULE-AUTH-GAP-PASSWORD-ATTEMPTS-001' AND pendiente_decision IS TRUE
    AND valor_config->>'parameters_status'='PENDING_OWNER_DECISION'
    AND valor_config->>'max_failed_password_attempts' IS NULL
    AND valor_config->>'failed_password_window_seconds' IS NULL;
  IF v_pending<>1 THEN RAISE EXCEPTION 'LF_AUTH001_PASSWORD_PARAMETERS_NOT_GOVERNED'; END IF;
  IF EXISTS (SELECT 1 FROM lf_ops.reglas r
             WHERE r.codigo IN ('B2B-RULE-AUTH-GAP-PASSWORD-ATTEMPTS-001',
    'B2B-RULE-AUTH-GAP-AUDIT-001',
    'B2B-RULE-AUTH-GAP-MFA-RECOVERY-001',
    'B2B-RULE-AUTH-GAP-TENANT-ISOLATION-001',
    'B2B-RULE-AUTH-GAP-MFA-COVERAGE-001') AND r.estado='VIGENTE')
  THEN RAISE EXCEPTION 'LF_AUTH001_PROMOTION_FORBIDDEN'; END IF;
  RAISE NOTICE 'LF_AUTH001_CANDIDATE_READBACK rules=% screen51_links=% pending_business_decision=%',v_rules,v_links,v_pending;
END;
$readback$;
COMMIT;
