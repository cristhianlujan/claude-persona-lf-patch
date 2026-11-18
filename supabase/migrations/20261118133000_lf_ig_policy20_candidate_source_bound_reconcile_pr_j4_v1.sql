-- Owner-approved PR-I candidate policy20 reconciliation, after AUTH020 579 verified.
-- Source: docs/input-governance/PR_I_AUTH020_SOURCE_BOUND_PATCH_20261118.json
-- Source Git blob SHA-1: 14e40d0107a0735330d4f82b534aac754c4d2b42; source policy md5 excluding updated_at: 97dbf5ff2e9da91da0ab33d6a837d4c2.
-- No new owner signature needed per PR-I gate matrix; remains CANDIDATO.
-- Canonical parameter provenance trigger UNCHANGED; 20 exact impacted keys refreshed.
BEGIN;
DO $p20$
DECLARE v_before lf_ops.politicas_seguridad%ROWTYPE;
        v_after lf_ops.politicas_seguridad%ROWTYPE;
        v_target jsonb:=$target_p20${"profile_ids":[1,2,3,4,5,6],"audit_actions":["MFA_RECOVERY_REQUESTED","MFA_RECOVERY_IDENTITY_VERIFIED","MFA_FACTOR_RESET","MFA_REENROLLED"],"recovery_flow":"SEPARATE_GOVERNED_FLOW","admin_recovery_mode":"ASSISTED_SUPPORT_DNI_SINGLE_PERMISSION38_OPERATOR_TEMP_KEY","password_only_bypass":"DENY","authorization_registry":"lf_ops.perfiles_permisos","factor_reset_authority":"SERVER_SIDE_PRIVILEGED_OPERATION_ONLY","idv_disabled_resolution":"ASSISTED_SUPPORT_DNI_GOVERNED_NO_EXTERNAL_IDV","lost_totp_recovery_mode":"SUPERSEDED_FOR_NON_ADMIN_CANDIDATE","new_factor_reenrollment":"REQUIRED","non_admin_recovery_mode":"ASSISTED_SUPPORT_DNI_SINGLE_PERMISSION38_OPERATOR_TEMP_KEY","weaker_factor_downgrade":"DENY","idv_provider_policy_code":"SEC-LF-IDV-FACEPHI-OPTIONAL","future_profile_assignment":"EFFECTIVE_VIGENTE_PERMISSION_ID_38_ONLY","admin_recovery_profile_ids":[1,2],"authorization_relation_key":"permission_id","numeric_thresholds_in_rule":"DENY","idv_optional_branch_enabled":false,"regular_login_mfa_unchanged":true,"email_access_recovery_status":"FUNCTIONAL_SCOPE_DEFINED_NOT_PRODUCTION_READY","assisted_recovery_profile_ids":[3,4,5,6],"authorization_relation_key_type":"NUMERIC_ID","authorized_recovery_actor_binding":"PERMISSION_BASED_DEFINED","authorized_recovery_permission_id":38,"emergency_access_is_user_recovery":"DENY","session_before_recovery_completion":"DENY","idv_gate_applies_only_to_idv_branch":true,"subscriber_notification_on_recovery":"REQUIRED","password_only_access_during_recovery":"DENY","lost_factor_revocation_or_replacement":"REQUIRED","required_assurance_after_reenrollment":"AAL2","authenticator_rebinding_after_recovery":"REQUIRED_WHEN_FACTOR_LOST","provider_architecture_security_policy_id":23,"identity_verification_before_factor_reset":"REQUIRED","authenticated_operational_session_before_completion":"DENY","single_authorized_support_operator":true,"recovery_operator_permission_id":38,"dni_evidence_type":"PHOTO_OR_SCAN_SECURE_REFERENCE","temporary_key_ttl_config_ref":"AUTH/TEMP_KEY_TTL_HOURS","temporary_key_one_time_use":true,"temporary_key_reissue_invalidates_prior":true,"temporary_key_expiry_requires_new_identity_check":true,"temporary_key_login_scope":"PASSWORD_CHANGE_ONLY_NO_OPERATIONAL_SESSION","new_password_required_before_operational_session":true,"change_email_after_new_password":true,"recovery_completion_atomic":true,"recovery_hold_after_completion":"NONE","previous_contact_notice_effect":"INFORMATIONAL_ONLY_NONBLOCKING","post_recovery_access":"FULL_UNDER_NORMAL_AUTH_AND_APPLICABLE_MFA","recovery_audit_no_raw_secrets_or_dni_image":true}$target_p20$::jsonb;
        v_source_provenance jsonb:=$source_prov_p20${"provider_binding":{"origin_type":"LF_PROVISIONAL_DEFAULT","decision_ref":"DEC-B2B-AUTH-PLATFORM-ALIGNMENT-001","value_status":"LF_PROVISIONAL","change_purpose":"SUPERSEDED_PROVIDER_BINDING","origin_version":"2026-09-28","origin_reference":"public.lf_decisiones_gov:136","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"idv_disabled_resolution":{"origin_type":"LF_PROVISIONAL_DEFAULT","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","value_status":"LF_PROVISIONAL","origin_version":"2026-11-14","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"idv_provider_policy_code":{"origin_type":"LF_PROVISIONAL_DEFAULT","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","value_status":"LF_PROVISIONAL","origin_version":"2026-11-14","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"idv_optional_branch_enabled":{"origin_type":"LF_PROVISIONAL_DEFAULT","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","value_status":"LF_PROVISIONAL","origin_version":"2026-11-14","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"regular_login_mfa_unchanged":{"origin_type":"LF_PROVISIONAL_DEFAULT","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","value_status":"LF_PROVISIONAL","origin_version":"2026-11-14","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"idv_gate_applies_only_to_idv_branch":{"origin_type":"LF_PROVISIONAL_DEFAULT","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","value_status":"LF_PROVISIONAL","origin_version":"2026-11-14","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"provider_architecture_security_policy_id":{"origin_type":"LF_PROVISIONAL_DEFAULT","decision_ref":"DEC-B2B-AUTH-PLATFORM-ALIGNMENT-001","value_status":"LF_PROVISIONAL","change_purpose":"SUPERSEDED_PROVIDER_BINDING","origin_version":"2026-09-28","origin_reference":"public.lf_decisiones_gov:136","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"}}$source_prov_p20$::jsonb;
        v_expected_keys text[]:=ARRAY['admin_recovery_mode','change_email_after_new_password','current_authorized_recovery_profile_ids','dni_evidence_type','email_access_recovery_status','future_profile_assignment','new_password_required_before_operational_session','non_admin_recovery_mode','post_recovery_access','previous_contact_notice_effect','recovery_audit_no_raw_secrets_or_dni_image','recovery_completion_atomic','recovery_hold_after_completion','recovery_operator_permission_id','single_authorized_support_operator','temporary_key_expiry_requires_new_identity_check','temporary_key_login_scope','temporary_key_one_time_use','temporary_key_reissue_invalidates_prior','temporary_key_ttl_config_ref'];
        v_actual_keys text[];
        v_provenance jsonb;
        v_key text;
        v_permission_before text; v_permission_after text;
        v_auth18 text; v_auth19 text;
        v_auth20 text;
        v_before_md5 text;
        v_after_md5 text;
BEGIN
 SELECT * INTO v_before FROM lf_ops.politicas_seguridad
 WHERE security_policy_id=20 AND policy_code='SEC-B2B-MFA-RECOVERY'
   AND status='CANDIDATO' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PR_J4_POLICY20_TARGET_NOT_CANDIDATE'; END IF;
 v_before_md5:=md5((to_jsonb(v_before)-'updated_at')::text);
 IF v_before_md5 IS DISTINCT FROM '97dbf5ff2e9da91da0ab33d6a837d4c2'
    OR v_before.parameter_provenance IS DISTINCT FROM v_source_provenance
 THEN RAISE EXCEPTION 'PR_J4_POLICY20_SOURCE_PREIMAGE_DRIFT:%',v_before_md5; END IF;
 IF (SELECT count(*) FROM lf_ops.reglas)<>579
 THEN RAISE EXCEPTION 'PR_J4_RULE_INVENTORY_DRIFT'; END IF;
 SELECT md5((to_jsonb(r)-'updated_at')::text) INTO v_auth20
 FROM lf_ops.reglas r WHERE codigo='B2B-RULE-AUTH-020' AND estado='VIGENTE';
 IF v_auth20 IS DISTINCT FROM '9d558e62bd85cefe6dbe0f4147e59056'
    OR NOT EXISTS (
       SELECT 1 FROM public.lf_ig_rule_change_v2 c
       WHERE c.rule_code='B2B-RULE-AUTH-020'
         AND c.state='VIGENTE_VERIFIED'
         AND c.finalized_snapshot_sha256='16729473fcfc98cb04a04d2489cfa6338cb59f1c1cace12ce9443a4c24bee061'
    )
 THEN RAISE EXCEPTION 'PR_J4_AUTH020_V2_FINALIZED_PREREQUISITE_MISSING'; END IF;
 IF NOT EXISTS (
      SELECT 1 FROM public.lf_global_config
      WHERE scope='AUTH' AND config_key='TEMP_KEY_TTL_HOURS'
        AND value_type='INTEGER' AND value_status='REAL'
    )
 THEN RAISE EXCEPTION 'PR_J4_TEMP_KEY_GLOBAL_AUTHORITY_MISSING'; END IF;
 SELECT md5((to_jsonb(r)-'updated_at')::text) INTO v_auth18
 FROM lf_ops.reglas r WHERE codigo='B2B-RULE-AUTH-018';
 SELECT md5((to_jsonb(r)-'updated_at')::text) INTO v_auth19
 FROM lf_ops.reglas r WHERE codigo='B2B-RULE-AUTH-019';
 IF v_auth18 IS DISTINCT FROM '89982bb3090cf3d7d52727caf2967cbe'
    OR v_auth19 IS DISTINCT FROM '48f15fb6e5242ab02d1453c3012a58e8'
 THEN RAISE EXCEPTION 'PR_J4_ADJACENT_RULE_PREIMAGE_DRIFT'; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(pp) ORDER BY pp.profile_code,pp.permission_code)::text,'[]'))
 INTO v_permission_before FROM lf_ops.perfiles_permisos pp WHERE permission_id=38;
 IF v_permission_before IS DISTINCT FROM 'b71336fb01ca83aa531ecc6f1f7b4ad4'
    OR (SELECT count(*) FROM lf_ops.perfiles_permisos
        WHERE permission_id=38 AND status='VIGENTE' AND access_effect='ALLOW')<>0
 THEN RAISE EXCEPTION 'PR_J4_PERMISSION38_PREIMAGE_DRIFT'; END IF;

 SELECT coalesce(array_agg(key ORDER BY key),ARRAY[]::text[]) INTO v_actual_keys
 FROM (
   SELECT k.key FROM (
      SELECT jsonb_object_keys(v_before.policy_config) AS key
      UNION SELECT jsonb_object_keys(v_target) AS key
   ) k
   WHERE v_before.policy_config->k.key IS DISTINCT FROM v_target->k.key
 ) delta;
 IF v_actual_keys IS DISTINCT FROM v_expected_keys
    OR cardinality(v_expected_keys)<>20
    OR (SELECT count(*) FROM jsonb_object_keys(v_target))<>50
    OR v_target ? 'current_authorized_recovery_profile_ids'
 THEN RAISE EXCEPTION 'PR_J4_POLICY20_20_KEY_DELTA_NOT_EXACT'; END IF;

 v_provenance:=v_before.parameter_provenance;
 FOREACH v_key IN ARRAY v_actual_keys LOOP
    v_provenance:=jsonb_set(v_provenance,ARRAY[v_key],jsonb_build_object(
       'origin_type','LF_PROVISIONAL_DEFAULT',
       'value_status','LF_PROVISIONAL',
       'replacement_policy','MUST_BE_RATIFIED_OR_OVERRIDDEN',
       'origin_reference','github://cristhianlujan/claude-persona-lf-patch@060801ba71ba8c06aa1369c8eae3838133d533c3/docs/input-governance/PR_I_AUTH020_SOURCE_BOUND_PATCH_20261118.json',
       'origin_version','2026-11-18',
       'change_purpose','AUTH020_OWNER_DELEGATED_POLICY20_CANDIDATE_RECONCILIATION',
       'source_rule_code','B2B-RULE-AUTH-020',
       'source_rule_md5','9d558e62bd85cefe6dbe0f4147e59056',
       'source_policy_md5',v_before_md5,
       'source_patch_sha256','adaffe6a15e705fc4ec48fa809135088736915cd0d4446691ede078899704a02',
       'identity_verified',false,
       'signed_owner_decision',false,
       'field',v_key
    ),true);
 END LOOP;
 IF NOT programacion.fn_input_parameter_provenance_valid_v1(v_provenance)
 THEN RAISE EXCEPTION 'PR_J4_POLICY20_PROVENANCE_SCHEMA_INVALID'; END IF;
 UPDATE lf_ops.politicas_seguridad
    SET description=$desc_p20$Recuperación asistida de cuenta y segundo factor B2B para perfiles humanos 1–6, incluyendo administradores, mediante un único operador de soporte con permiso de recuperación 38 efectivamente VIGENTE. Verificar DNI en foto o escaneo antes de emitir al correo indicado una clave temporal de un solo uso con vigencia determinada por AUTH/TEMP_KEY_TTL_HOURS en lf_global_config; emitir nueva clave revoca anteriores y vencimiento exige nueva validación. La clave temporal solo autoriza la definición inmediata de contraseña nueva, sin sesión ni acceso operativo hasta completar. La nueva contraseña y actualización del correo se ejecutan atómicamente; después se aplica MFA normal, sin espera ni bloqueo de acciones. Aviso al contacto anterior informativo y no bloqueante. Auditoría sin exponer DNI ni secretos. Política permanece CANDIDATO, pues permiso 38 no está VIGENTE y no se ha probado backend real de recuperación.$desc_p20$,
        policy_config=v_target,parameter_provenance=v_provenance
 WHERE security_policy_id=20 AND policy_code='SEC-B2B-MFA-RECOVERY' AND status='CANDIDATO'
 RETURNING * INTO v_after;
 IF NOT FOUND THEN RAISE EXCEPTION 'PR_J4_POLICY20_CANONICAL_UPDATE_REJECTED'; END IF;
 v_after_md5:=md5((to_jsonb(v_after)-'updated_at')::text);
 IF v_after.policy_config IS DISTINCT FROM v_target
    OR v_after.parameter_provenance IS DISTINCT FROM v_provenance
    OR v_after.description IS DISTINCT FROM $desc_p20$Recuperación asistida de cuenta y segundo factor B2B para perfiles humanos 1–6, incluyendo administradores, mediante un único operador de soporte con permiso de recuperación 38 efectivamente VIGENTE. Verificar DNI en foto o escaneo antes de emitir al correo indicado una clave temporal de un solo uso con vigencia determinada por AUTH/TEMP_KEY_TTL_HOURS en lf_global_config; emitir nueva clave revoca anteriores y vencimiento exige nueva validación. La clave temporal solo autoriza la definición inmediata de contraseña nueva, sin sesión ni acceso operativo hasta completar. La nueva contraseña y actualización del correo se ejecutan atómicamente; después se aplica MFA normal, sin espera ni bloqueo de acciones. Aviso al contacto anterior informativo y no bloqueante. Auditoría sin exponer DNI ni secretos. Política permanece CANDIDATO, pues permiso 38 no está VIGENTE y no se ha probado backend real de recuperación.$desc_p20$
    OR v_after.status IS DISTINCT FROM 'CANDIDATO'
    OR (to_jsonb(v_after)-'description'-'policy_config'-'parameter_provenance'-'updated_at')
       IS DISTINCT FROM (to_jsonb(v_before)-'description'-'policy_config'-'parameter_provenance'-'updated_at')
    OR v_after_md5 IS NOT DISTINCT FROM v_before_md5
 THEN RAISE EXCEPTION 'PR_J4_POLICY20_POSTIMAGE_DRIFT'; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(pp) ORDER BY pp.profile_code,pp.permission_code)::text,'[]'))
 INTO v_permission_after FROM lf_ops.perfiles_permisos pp WHERE permission_id=38;
 IF v_permission_after IS DISTINCT FROM v_permission_before
    OR (SELECT count(*) FROM lf_ops.reglas)<>579
    OR (SELECT md5((to_jsonb(r)-'updated_at')::text) FROM lf_ops.reglas r
        WHERE codigo='B2B-RULE-AUTH-020') IS DISTINCT FROM v_auth20
    OR (SELECT md5((to_jsonb(r)-'updated_at')::text) FROM lf_ops.reglas r
        WHERE codigo='B2B-RULE-AUTH-018') IS DISTINCT FROM v_auth18
    OR (SELECT md5((to_jsonb(r)-'updated_at')::text) FROM lf_ops.reglas r
        WHERE codigo='B2B-RULE-AUTH-019') IS DISTINCT FROM v_auth19
 THEN RAISE EXCEPTION 'PR_J4_UNAUTHORIZED_ASSET_DELTA'; END IF;
 RAISE NOTICE 'PR_J4_POLICY20_CANDIDATE_RECONCILED before=% after=% changed_config_keys=20 refreshed_provenance_keys=20 identity_verified=false production_authorized=false',
      v_before_md5,v_after_md5;
END $p20$;
COMMIT;
