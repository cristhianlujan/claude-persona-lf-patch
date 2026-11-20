-- LF L37: CANDIDATE ONLY. NOT A SUPABASE MIGRATION. No run in live DB.
-- Exact owner-scope: description ONLY, no config/status/promotion.
-- Must enter supabase/migrations/<TRAIN_ASSIGNED_VERSION>_lf_b2b_policy19_admin_otp_description_v1.sql
-- only after PG17.6/18.7 rollback PASS, Router attestation, owner explicit fire approval.
DO $lf_policy19_candidate$
DECLARE
  v_before lf_ops.politicas_seguridad%ROWTYPE;
  v_after lf_ops.politicas_seguridad%ROWTYPE;
  v_expected_source_sha constant text := 'f82cf4ed0887d8240e1a20d193a7a3a82f92271334de6eb543e4489ecac21b07';
  v_source_sha text;
  v_expected_description constant text := $lf_policy19_description$La política central 19 determina el segundo factor por perfil cuando la política de aplicabilidad MFA lo exige; no altera los disparadores ni umbrales de MFA de la política central 3. Para Admin LF (profile_id 1) y Admin Empresa (profile_id 2), el inicio de sesión comienza con usuario y contraseña validados por el servidor. Si MFA corresponde a ese acceso, LF_AUTH_BOUNDARY genera un código de un solo uso (OTP), lo entrega al correo registrado mediante Brevo y verifica el código del lado servidor antes de completar AUTHENTICATED, crear una sesión operativa o conceder permisos. Para ambos administradores el segundo factor es OTP por correo/Brevo, sin exigir FIDO2/WebAuthn, passkeys o llaves de seguridad. Los perfiles 3, 4, 5 y 6 mantienen el segundo factor OTP por correo gestionado por LF y entregado mediante Brevo, verificado por el servidor cuando MFA aplique. Se prohíben el acceso mediante contraseña sola si MFA es requerido, el bypass por dispositivo reconocido, la aceptación de OTP inválido, vencido o no verificado y la elección de factor o estado AUTHENTICATED desde el cliente. SMS continúa como contingencia sin proveedor confirmado y sin fallback automático. El OTP por correo no es resistente a phishing y no se declara Supabase native AAL2 sin evidencia. La integración de Brevo, el binding del proveedor de identidad conforme ADR-003 M1, la recuperación de cuenta y las pruebas reales siguen pendientes. Riesgo residual aceptado por el dueño en conversación, pendiente de firma: el OTP por correo puede ser retransmitido mediante phishing.$lf_policy19_description$;
BEGIN
  SELECT * INTO v_before FROM lf_ops.politicas_seguridad
   WHERE security_policy_id=19 AND policy_code='SEC-B2B-MFA-FACTOR-ELIGIBILITY'
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'LF_POLICY19_SOURCE_MISSING';
  END IF;
  IF v_before.status <> 'CANDIDATO' THEN
    RAISE EXCEPTION 'LF_POLICY19_NOT_CANDIDATE';
  END IF;
  v_source_sha := encode(pg_catalog.sha256(convert_to(to_jsonb(v_before)::text,'UTF8')),'hex');
  IF v_source_sha IS DISTINCT FROM v_expected_source_sha THEN
    RAISE EXCEPTION 'LF_POLICY19_SOURCE_PREIMAGE_DRIFT:%',v_source_sha;
  END IF;
  UPDATE lf_ops.politicas_seguridad
     SET description=v_expected_description
   WHERE security_policy_id=19 AND policy_code='SEC-B2B-MFA-FACTOR-ELIGIBILITY'
   RETURNING * INTO v_after;
  IF v_after.description IS DISTINCT FROM v_expected_description
     OR v_after.status <> 'CANDIDATO'
     OR (to_jsonb(v_after)-'description'-'updated_at') IS DISTINCT FROM
        (to_jsonb(v_before)-'description'-'updated_at') THEN
    RAISE EXCEPTION 'LF_POLICY19_READBACK_OR_SCOPE_DRIFT';
  END IF;
  -- deliberately no promotion and no status/config write
END;
$lf_policy19_candidate$;
