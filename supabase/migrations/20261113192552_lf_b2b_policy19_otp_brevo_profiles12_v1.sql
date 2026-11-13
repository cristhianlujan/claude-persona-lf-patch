-- L36 owner-documentary decision; single atomic candidate UPDATE for LF policy 19.
-- Apply only by official LF Merge Train with ACT-0001 receipt and guarded writer.
-- Exactly 8 existing keys; 5 NEW optional fields from L36 are deliberately OUT OF SCOPE.
-- The official policy19 owner declaration is a DOCUMENTARY decision, not an authenticated signature.
DO $lf_policy19$
DECLARE
  v_before lf_ops.politicas_seguridad%ROWTYPE;
  v_after lf_ops.politicas_seguridad%ROWTYPE;
  v_source_sha constant text := 'f82cf4ed0887d8240e1a20d193a7a3a82f92271334de6eb543e4489ecac21b07';
  v_expected_description_sha constant text := '0beb7404a61197b3d2528de19a210350a02ae83a5d7fbc58d57726645173975b';
  v_description constant text := $policy19_text$La política central 19 determina el segundo factor por perfil cuando la política de aplicabilidad MFA lo exige; no altera los disparadores ni umbrales de MFA de la política central 3. Para Admin LF (profile_id 1) y Admin Empresa (profile_id 2), el inicio de sesión comienza con usuario y contraseña validados por el servidor. Si MFA corresponde a ese acceso, LF_AUTH_BOUNDARY genera un código de un solo uso (OTP), lo entrega al correo registrado mediante Brevo y verifica el código del lado servidor antes de completar AUTHENTICATED, crear una sesión operativa o conceder permisos. Para ambos administradores el segundo factor es OTP por correo/Brevo, sin exigir FIDO2/WebAuthn, passkeys o llaves de seguridad. Los perfiles 3, 4, 5 y 6 mantienen el segundo factor OTP por correo gestionado por LF y entregado mediante Brevo, verificado por el servidor cuando MFA aplique. Se prohíben el acceso mediante contraseña sola si MFA es requerido, el bypass por dispositivo reconocido, la aceptación de OTP inválido, vencido o no verificado y la elección de factor o estado AUTHENTICATED desde el cliente. SMS continúa como contingencia sin proveedor confirmado y sin fallback automático. El OTP por correo no es resistente a phishing y no se declara Supabase native AAL2 sin evidencia. La integración de Brevo, el binding del proveedor de identidad conforme ADR-003 M1, la recuperación de cuenta y las pruebas reales siguen pendientes. Riesgo residual aceptado por el dueño en conversación, pendiente de firma: el OTP por correo puede ser retransmitido mediante phishing.$policy19_text$;
  v_old_eight constant jsonb := '{"admin_minimum_strength":"PHISHING_RESISTANT","admin_phishing_resistant_requirement":"GOOGLE_WORKSPACE_PASSKEY_OR_SECURITY_KEY_POLICY","phishing_resistant_option_required":true,"admin_primary_method":"GOOGLE_WORKSPACE_SAML_SSO","admin_identity_provider":"GOOGLE_WORKSPACE","admin_sso_protocol":"SAML_2_0","admin_provider_configuration_status":"PENDING_GOOGLE_WORKSPACE_TENANT_AND_SAML_METADATA","factor_selection_status":"CLOSED_POLICY_DEFINED"}'::jsonb;
  v_new_eight constant jsonb := '{"admin_minimum_strength":"APPROVED_MFA","admin_phishing_resistant_requirement":"NOT_REQUIRED_FOR_PROFILES_1_2_OWNER_RISK_ACCEPTED_PENDING_SIGNATURE","phishing_resistant_option_required":false,"admin_primary_method":"USERNAME_PASSWORD_SERVER_VALIDATED","admin_identity_provider":"PENDING_ADR_003_M1_SPIKE","admin_sso_protocol":"PENDING_ADR_003_M1_SPIKE","admin_provider_configuration_status":"PENDING_REAL_IDP_AND_BREVO_INTEGRATION_QA","factor_selection_status":"OWNER_DECIDED_IN_CONVERSATION_PENDING_SIGNATURE_IMPLEMENTATION"}'::jsonb;
  v_next_config jsonb;
  v_next_provenance jsonb;
  v_k text;
  v_actual_sha text;
  v_execution_id text;
  v_execution_count bigint;
  v_receipt jsonb;
  v_effect jsonb;
BEGIN
  -- Only one genuine current migration Train RUN can authorize the scope receipt.
  SELECT count(*),max(e.execution_id) INTO v_execution_count,v_execution_id
  FROM public.lf_operation_execution e
  WHERE e.operation_code='ACTUALIZACION_DB_LF' AND e.target_type='MIGRATION'
    AND e.status='IN_PROGRESS'
    AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
    AND e.target_code ~ '^[0-9]{14}_lf_b2b_policy19_otp_brevo_profiles12_v1$'
    AND e.target_path='supabase/migrations/'||e.target_code||'.sql'
    AND e.manifest->>'producer'='lf-migration-merge-train'
    AND e.manifest->>'pr'='3819'
    AND e.manifest->>'train_run_id' ~ '^[0-9]{8,20}$'
    AND coalesce(e.request_sha256,'') ~ '^[0-9a-f]{64}$';
  IF v_execution_count IS DISTINCT FROM 1 OR v_execution_id IS NULL
  THEN RAISE EXCEPTION 'LF_POLICY19_TRAIN_RUN_NOT_UNIQUE'; END IF;
  SELECT * INTO v_before FROM lf_ops.politicas_seguridad
   WHERE security_policy_id=19 AND policy_code='SEC-B2B-MFA-FACTOR-ELIGIBILITY'
   FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'LF_POLICY19_SOURCE_MISSING'; END IF;
  IF v_before.status IS DISTINCT FROM 'CANDIDATO' THEN
    RAISE EXCEPTION 'LF_POLICY19_NOT_CANDIDATE';
  END IF;
  v_actual_sha := encode(pg_catalog.sha256(convert_to(to_jsonb(v_before)::text,'UTF8')),'hex');
  IF v_actual_sha IS DISTINCT FROM v_source_sha THEN
    RAISE EXCEPTION 'LF_POLICY19_SOURCE_PREIMAGE_DRIFT:%',v_actual_sha;
  END IF;
  IF encode(pg_catalog.sha256(convert_to(v_description,'UTF8')),'hex')
       IS DISTINCT FROM v_expected_description_sha THEN
    RAISE EXCEPTION 'LF_POLICY19_DESCRIPTION_SHA_DRIFT';
  END IF;
  IF (SELECT jsonb_object_agg(k, v_before.policy_config->k) FROM jsonb_object_keys(v_old_eight) k)
     IS DISTINCT FROM v_old_eight THEN
    RAISE EXCEPTION 'LF_POLICY19_EIGHT_KEYS_PREIMAGE_DRIFT';
  END IF;
  IF (SELECT count(*) FROM jsonb_object_keys(v_new_eight))<>8 THEN
    RAISE EXCEPTION 'LF_POLICY19_EIGHT_KEYS_REQUIRED';
  END IF;
  v_next_config := v_before.policy_config || v_new_eight;
  v_next_provenance := v_before.parameter_provenance;
  FOR v_k IN SELECT jsonb_object_keys(v_new_eight) LOOP
    v_next_provenance := jsonb_set(v_next_provenance,ARRAY[v_k],
      jsonb_build_object(
        'origin_type','LF_CANONICAL',
        'value_status','LF_CANONICAL',
        'decision_ref','L36-OWNER-ADMIN-LF-PROFILE1-OTP-BREVO-001',
        'origin_reference','docs/rule-quality-lote36/00_decision_dueno_admin_lf_perfil1_otp_brevo.json',
        'origin_version','2026-11-13',
        'change_purpose','OWNER_DOCUMENTARY_DECISION_PROFILES_1_2_OTP_BREVO',
        'identity_verified',false,
        'source_document_git_blob_sha1','0b41825b9221c5d7a01a80190e2e2924e6fdc203',
        'source_fullrow_sha256',v_source_sha,
        'field',v_k
      ),true);
  END LOOP;
  IF NOT programacion.fn_input_parameter_provenance_valid_v1(v_next_provenance) THEN
    RAISE EXCEPTION 'LF_POLICY19_PARAMETER_PROVENANCE_INVALID';
  END IF;
  -- ACT-0001 receipt certifies route scope, not permission for the DB effect.
  v_receipt:=public.lf_router_scope_bind_v1(v_execution_id);
  IF v_receipt->>'status' IS DISTINCT FROM 'SCOPE_ATTESTED_ROUTE_ONLY'
    OR v_receipt->>'router' IS DISTINCT FROM 'ACT-0001'
    OR v_receipt->>'scope_code' IS DISTINCT FROM 'LF_POLICY19_ADMIN12_OTP_BREVO_CHANGE_V1'
    OR v_receipt->>'execution_id' IS DISTINCT FROM v_execution_id
    OR v_receipt->>'effect_authority' IS DISTINCT FROM 'false'
    OR v_receipt->>'downstream_execution_allowed' IS DISTINCT FROM 'false'
    OR v_receipt->>'identity_verified' IS DISTINCT FROM 'false'
    OR coalesce(v_receipt->>'receipt_sha256','') !~ '^[0-9a-f]{64}$'
  THEN RAISE EXCEPTION 'LF_POLICY19_ACT0001_RECEIPT_INVALID'; END IF;

  -- Only the installed official writer consumes the same receipt and applies the update.
  v_effect:=public.lf_ig_policy19_apply_v1(v_execution_id,v_description,v_new_eight);
  IF v_effect->>'status' IS DISTINCT FROM 'CANDIDATO_GOVERNED_READBACK'
    OR v_effect->>'execution_id' IS DISTINCT FROM v_execution_id
    OR v_effect->>'scope_receipt_sha256' IS DISTINCT FROM v_receipt->>'receipt_sha256'
    OR v_effect->>'description_sha256' IS DISTINCT FROM v_expected_description_sha
    OR v_effect->>'config_keys_changed' IS DISTINCT FROM '8'
    OR v_effect->>'provenance_keys_refreshed' IS DISTINCT FROM '8'
    OR v_effect->>'identity_verified' IS DISTINCT FROM 'false'
  THEN RAISE EXCEPTION 'LF_POLICY19_WRITER_RECEIPT_OR_READBACK_INVALID'; END IF;
  SELECT * INTO v_after FROM lf_ops.politicas_seguridad
  WHERE security_policy_id=19 AND policy_code='SEC-B2B-MFA-FACTOR-ELIGIBILITY';
  IF v_effect->>'after_sha256' IS DISTINCT FROM
     encode(pg_catalog.sha256(convert_to(to_jsonb(v_after)::text,'UTF8')),'hex')
  THEN RAISE EXCEPTION 'LF_POLICY19_WRITER_POSTIMAGE_DRIFT'; END IF;
  IF NOT FOUND OR v_after.status IS DISTINCT FROM 'CANDIDATO'
     OR v_after.description IS DISTINCT FROM v_description
     OR v_after.policy_config IS DISTINCT FROM v_next_config
     OR v_after.parameter_provenance IS DISTINCT FROM v_next_provenance
     OR (to_jsonb(v_after)-'description'-'policy_config'-'parameter_provenance'-'updated_at')
           IS DISTINCT FROM
        (to_jsonb(v_before)-'description'-'policy_config'-'parameter_provenance'-'updated_at')
     OR encode(pg_catalog.sha256(convert_to(v_after.description,'UTF8')),'hex')
           IS DISTINCT FROM v_expected_description_sha
  THEN RAISE EXCEPTION 'LF_POLICY19_READBACK_OR_SCOPE_DRIFT'; END IF;
END;
$lf_policy19$;
