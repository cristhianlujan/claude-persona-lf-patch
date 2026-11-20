-- LF L43. Policy19+22 CANDIDATO -> VIGENTE by EXISTING governed migration train.
-- DRAFT only. Owner approval/independent judge required BEFORE ready-to-merge; not a signed receipt.
-- No new writer or router; no changes to RUN 952, rate1, policy3/17 or PRs 3844/46/47/48.
-- Source preimages from SELECT 2026-11-14, HEAD of PR #3848 pinned in fixture.
DO $lf_l43$
DECLARE
  v19_old lf_ops.politicas_seguridad%ROWTYPE;
  v22_old lf_ops.politicas_seguridad%ROWTYPE;
  v19_new lf_ops.politicas_seguridad%ROWTYPE;
  v22_new lf_ops.politicas_seguridad%ROWTYPE;
  v_before jsonb;
  v_after jsonb;
  v_cfg22 CONSTANT jsonb := '{"recovery_functional_operation":"SUPPORT_ASSISTED_RECOVERY_PENDING_CANONICAL_RESOURCE","recovery_rate_limit_policy_id":null,"legacy_recovery_otp_rate_limit_policy_id":7,"new_device_otp_rate_limit_scope":"LEGACY_NEW_DEVICE_ONLY_NOT_GENERAL_MFA","general_mfa_otp_resource":"PENDING_CANONICAL_MFA_EMAIL_OTP_RESOURCE","password_failure_policy_code":"AUTH_LOGIN_FAILED_PASSWORD","password_failure_counter_interference":"DENY","login_ip_request_limit_policy_id":1,"login_ip_request_counter_independent":"REQUIRED","assisted_recovery_support_ticket_rate_limit":"PENDING_CANONICAL_RATE_MAPPING_NO_NEW_ID","assisted_recovery_policy_id":20,"support_recovery_wait_hours":48,"support_recovery_approvers_allowed":[1,2],"sms_support_only_manual":true,"sms_automatic_fallback":"DENY"}'::jsonb;
  v_prov22 CONSTANT jsonb := '{"recovery_functional_operation":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN","origin_reference":"OWNER_LOGIN_B2B_NEW_DECISIONS_20261113_PENDING_SIGNATURE","identity_verified":false},"recovery_rate_limit_policy_id":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN","origin_reference":"OWNER_LOGIN_B2B_NEW_DECISIONS_20261113_PENDING_SIGNATURE","identity_verified":false},"legacy_recovery_otp_rate_limit_policy_id":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN","origin_reference":"OWNER_LOGIN_B2B_NEW_DECISIONS_20261113_PENDING_SIGNATURE","identity_verified":false},"new_device_otp_rate_limit_scope":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN","origin_reference":"OWNER_LOGIN_B2B_NEW_DECISIONS_20261113_PENDING_SIGNATURE","identity_verified":false},"general_mfa_otp_resource":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN","origin_reference":"OWNER_LOGIN_B2B_NEW_DECISIONS_20261113_PENDING_SIGNATURE","identity_verified":false},"password_failure_policy_code":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN","origin_reference":"OWNER_LOGIN_B2B_NEW_DECISIONS_20261113_PENDING_SIGNATURE","identity_verified":false},"password_failure_counter_interference":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN","origin_reference":"OWNER_LOGIN_B2B_NEW_DECISIONS_20261113_PENDING_SIGNATURE","identity_verified":false},"login_ip_request_limit_policy_id":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN","origin_reference":"OWNER_LOGIN_B2B_NEW_DECISIONS_20261113_PENDING_SIGNATURE","identity_verified":false},"login_ip_request_counter_independent":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN","origin_reference":"OWNER_LOGIN_B2B_NEW_DECISIONS_20261113_PENDING_SIGNATURE","identity_verified":false},"assisted_recovery_support_ticket_rate_limit":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN","origin_reference":"OWNER_LOGIN_B2B_NEW_DECISIONS_20261113_PENDING_SIGNATURE","identity_verified":false},"assisted_recovery_policy_id":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN","origin_reference":"OWNER_LOGIN_B2B_NEW_DECISIONS_20261113_PENDING_SIGNATURE","identity_verified":false},"support_recovery_wait_hours":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN","origin_reference":"OWNER_LOGIN_B2B_NEW_DECISIONS_20261113_PENDING_SIGNATURE","identity_verified":false},"support_recovery_approvers_allowed":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN","origin_reference":"OWNER_LOGIN_B2B_NEW_DECISIONS_20261113_PENDING_SIGNATURE","identity_verified":false},"sms_support_only_manual":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN","origin_reference":"OWNER_LOGIN_B2B_NEW_DECISIONS_20261113_PENDING_SIGNATURE","identity_verified":false},"sms_automatic_fallback":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN","origin_reference":"OWNER_LOGIN_B2B_NEW_DECISIONS_20261113_PENDING_SIGNATURE","identity_verified":false}}'::jsonb;
  v_desc19 CONSTANT text := 'La política central 19 determina el segundo factor por perfil cuando la política de aplicabilidad MFA lo exige; no altera los disparadores ni umbrales de MFA de la política central 3. Para Admin LF (profile_id 1) y Admin Empresa (profile_id 2), el inicio de sesión comienza con usuario y contraseña validados por el servidor. Si MFA corresponde a ese acceso, LF_AUTH_BOUNDARY genera un código de un solo uso (OTP), lo entrega al correo registrado mediante Brevo y verifica el código del lado servidor antes de completar AUTHENTICATED, crear una sesión operativa o conceder permisos. Para ambos administradores el segundo factor es OTP por correo/Brevo, sin exigir FIDO2/WebAuthn, passkeys o llaves de seguridad. Los perfiles 3, 4, 5 y 6 mantienen el segundo factor OTP por correo gestionado por LF y entregado mediante Brevo, verificado por el servidor cuando MFA aplique. Se prohíben el acceso mediante contraseña sola si MFA es requerido, la omisión de MFA por reconocimiento de dispositivo cuando cualquiera de sus disparadores aplica, la aceptación de OTP inválido, vencido o no verificado y la elección de factor o estado AUTHENTICATED desde el cliente. SMS Intico es exclusivamente contingencia manual habilitada y auditada por soporte cuando el correo actualizado no recibe el OTP; sin fallback automático. El OTP por correo no es resistente a phishing y no se declara Supabase native AAL2 sin evidencia. La integración de Brevo, el binding del proveedor de identidad conforme ADR-003 M1, la recuperación de cuenta y las pruebas reales siguen pendientes. Riesgo residual aceptado por el dueño en conversación, pendiente de firma: el OTP por correo puede ser retransmitido mediante phishing.';
  v_desc22 CONSTANT text := 'La defensa contra abuso del Login B2B separa tres controles: (1) RATE-B2B-LOGIN, limitación de solicitudes a la frontera de Login según su política de red, independiente del contador de contraseña; (2) AUTH_LOGIN_FAILED_PASSWORD, escalones por fallos de credencial 5→15 minutos, 3 adicionales→1 hora y 3 adicionales→24 horas, con reinicio por Login válido o 24 horas sin intentos, aviso por correo en 1h y 24h, y liberación del bloqueo 24h por soporte, sin diferencia observable para usuario existente o inexistente; (3) operación OTP por MFA condicional (dispositivo nuevo/revocado o sin uso autenticado 30 días, o contraseña sin cambiar 3 meses) y solicitudes de recuperación asistida por soporte con DNI, 48h y approvers_required 1 o 2. Los límites de operación no comparten contadores ni invalidan seguridad anti-enumeración. La IP se usa como señal anti-abuso, sin bloqueo permanente por un único indicio; los eventos de soporte requieren recurso/rate limit canónico por homologar. La política previa RATE-B2B-PASSWORD-RECOVERY-OTP y RATE-B2B-NEW-DEVICE-OTP no se declaran automáticamente suficientes para todo el flujo nuevo. SMS Intico es solo contingencia manual y auditada, nunca fallback automático. La protección anti-bot sigue separada.';
  v_count int;
  v_train_count int;
BEGIN
  -- Transport: EXISTING ACTUALIZACION_DB_LF / Merge Train, one current target execution.
  SELECT count(*) INTO v_train_count FROM public.lf_operation_execution e
   WHERE e.operation_code='ACTUALIZACION_DB_LF'
     AND e.target_type='MIGRATION' AND e.status='IN_PROGRESS'
     AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
     AND e.target_code ~ '^[0-9]{14}_lf_b2b_policy19_22_predecision_promotion_v1$'
     AND e.target_path='supabase/migrations/'||e.target_code||'.sql'
     AND e.manifest->>'producer'='lf-migration-merge-train'
     AND e.manifest->>'pr'='3854'
     AND e.manifest->>'train_run_id' ~ '^[0-9]{8,20}$'
     AND coalesce(e.request_sha256,'') ~ '^[0-9a-f]{64}$';
  IF v_train_count<>1 THEN RAISE EXCEPTION 'LF_L43_TRAIN_EXECUTION_NOT_UNIQUE'; END IF;
  -- Verify full-row sources and both stable VIGENTE parent references; no updates to parents.
  IF (SELECT encode(pg_catalog.sha256(convert_to(to_jsonb(p)::text,'UTF8')),'hex')
      FROM lf_ops.politicas_seguridad p WHERE security_policy_id=3) IS DISTINCT FROM 'f3e8366724d29a4d7a51e12f5ec3a863a9de39ae92485e7b41aaa328826fa243'
    OR (SELECT encode(pg_catalog.sha256(convert_to(to_jsonb(p)::text,'UTF8')),'hex')
      FROM lf_ops.politicas_seguridad p WHERE security_policy_id=17) IS DISTINCT FROM '176c31df86c6d73550f161f27ec612930292ec94f2338ec6a368fbbfd1c64191'
    OR (SELECT encode(pg_catalog.sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex')
      FROM lf_ops.politicas_rate_limit r WHERE rate_limit_policy_id=1) IS DISTINCT FROM '10eb22138ce577d6e4b41bee4f695e2da4f8da2b65cf534fbfd115c5dfa7cfd7'
  THEN RAISE EXCEPTION 'LF_L43_PARENT_OR_RATE_SOURCE_DRIFT'; END IF;
  SELECT * INTO v19_old FROM lf_ops.politicas_seguridad
   WHERE security_policy_id=19 AND policy_code='SEC-B2B-MFA-FACTOR-ELIGIBILITY' FOR UPDATE;
  SELECT * INTO v22_old FROM lf_ops.politicas_seguridad
   WHERE security_policy_id=22 AND policy_code='SEC-B2B-AUTH-ABUSE-PROTECTION' FOR UPDATE;
  IF NOT FOUND OR v19_old.status IS DISTINCT FROM 'CANDIDATO' OR v22_old.status IS DISTINCT FROM 'CANDIDATO'
  THEN RAISE EXCEPTION 'LF_L43_TARGET_NOT_CANDIDATE'; END IF;
  IF encode(pg_catalog.sha256(convert_to(to_jsonb(v19_old)::text,'UTF8')),'hex') IS DISTINCT FROM 'b4845fbce7c28690a50908d77ad8194e65a708b5a4d23d909f938a2298e1d891'
    OR encode(pg_catalog.sha256(convert_to(to_jsonb(v22_old)::text,'UTF8')),'hex') IS DISTINCT FROM '016da7ef14978fff31f57c9243a4ae9487c9eda5ebf9a5488f8a4f20c25a7d95'
  THEN RAISE EXCEPTION 'LF_L43_SOURCE_SHA_DRIFT'; END IF;
  IF v19_old.policy_config->'profile_ids' IS DISTINCT FROM '[1,2,3,4,5,6]'::jsonb
     OR v22_old.policy_config->>'ip_hard_limit' IS DISTINCT FROM 'DENY'
  THEN RAISE EXCEPTION 'LF_L43_MFA_ABUSE_CONTRACT_DRIFT'; END IF;
  IF (SELECT count(*) FROM jsonb_object_keys(v_cfg22))<>15
    OR (SELECT count(*) FROM jsonb_object_keys(v_prov22))<>15
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(v_cfg22) k WHERE NOT (v_prov22 ? k))
    OR NOT programacion.fn_input_parameter_provenance_valid_v1(v22_old.parameter_provenance||v_prov22)
  THEN RAISE EXCEPTION 'LF_L43_SEC22_PROVENANCE_INVALID'; END IF;
  v_before := programacion.fn_input_governance_predecision_crosscheck_v1(952);
  IF v_before->>'schema_version' IS DISTINCT FROM 'LF_IG_PREDECISION_CROSSCHECK_V1'
    OR (v_before->>'deterministic_finding_count')::int<>3
    OR (SELECT count(*) FROM jsonb_array_elements(v_before->'deterministic_findings') f
        WHERE f->>'type'='VIGENTE_REFERENCES_CANDIDATO'
          AND (f->>'target_id')::int IN (19,22))<>2
    OR (SELECT count(*) FROM jsonb_array_elements(v_before->'deterministic_findings') f
        WHERE f->>'type'='IP_COMPOSITE_SCOPE_REQUIRES_RUNTIME_PROOF')<>1
  THEN RAISE EXCEPTION 'LF_L43_PREDECISION_SOURCE_DRIFT'; END IF;
  UPDATE lf_ops.politicas_seguridad SET description=v_desc19,status='VIGENTE'
   WHERE security_policy_id=19 AND status='CANDIDATO' RETURNING * INTO v19_new;
  IF NOT FOUND THEN RAISE EXCEPTION 'LF_L43_POLICY19_UPDATE_MISSING'; END IF;
  UPDATE lf_ops.politicas_seguridad SET description=v_desc22,
     policy_config=policy_config||v_cfg22,
     parameter_provenance=parameter_provenance||v_prov22,
     status='VIGENTE'
   WHERE security_policy_id=22 AND status='CANDIDATO' RETURNING * INTO v22_new;
  IF NOT FOUND THEN RAISE EXCEPTION 'LF_L43_POLICY22_UPDATE_MISSING'; END IF;
  IF v19_new.policy_config IS DISTINCT FROM v19_old.policy_config
    OR v19_new.parameter_provenance IS DISTINCT FROM v19_old.parameter_provenance
    OR v19_new.status<>'VIGENTE' OR v22_new.status<>'VIGENTE'
    OR v22_new.policy_config IS DISTINCT FROM (v22_old.policy_config||v_cfg22)
    OR v22_new.parameter_provenance IS DISTINCT FROM (v22_old.parameter_provenance||v_prov22)
    OR (to_jsonb(v19_new)-'description'-'status'-'updated_at') IS DISTINCT FROM (to_jsonb(v19_old)-'description'-'status'-'updated_at')
    OR (to_jsonb(v22_new)-'description'-'policy_config'-'parameter_provenance'-'status'-'updated_at') IS DISTINCT FROM (to_jsonb(v22_old)-'description'-'policy_config'-'parameter_provenance'-'status'-'updated_at')
  THEN RAISE EXCEPTION 'LF_L43_POSTIMAGE_SCOPE_DRIFT'; END IF;
  v_after := programacion.fn_input_governance_predecision_crosscheck_v1(952);
  IF v_after->>'schema_version' IS DISTINCT FROM 'LF_IG_PREDECISION_CROSSCHECK_V1'
    OR (v_after->>'deterministic_finding_count')::int<>1
    OR (SELECT count(*) FROM jsonb_array_elements(v_after->'deterministic_findings') f
        WHERE f->>'type'='IP_COMPOSITE_SCOPE_REQUIRES_RUNTIME_PROOF'
          AND f->>'scope_key'='IP_USER')<>1
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_after->'deterministic_findings') f WHERE f->>'type'='VIGENTE_REFERENCES_CANDIDATO')
  THEN RAISE EXCEPTION 'LF_L43_PREDECISION_AFTER_NOT_1_IP_RUNTIME'; END IF;
  RAISE NOTICE 'LF_L43_PREDECISION_3_TO_1; IP_COMPOSITE_SCOPE still requires runtime proof; signer and production QA external';
END;
$lf_l43$;
