-- Governed LF DB migration proposal, owner decision 2026-11-14 04:52 America/Lima.
-- Scope: ten already registered candidate B2B spacing names are PRESERVED (no rename);
-- FACEPHI is only an optional IDV provider, CONFIGURED_OFF, no SDK/network/API.
-- ACT-0001 -> ACTUALIZACION_DB_LF -> reviewed PR -> ready-to-merge -> Migration Merge Train.
-- Documentary decision is not identity verified. Never claim production readiness.
BEGIN;
DO $pre$
DECLARE v_actual text; v_n integer;
BEGIN
SELECT encode(extensions.digest(convert_to(to_jsonb(x)::text,'UTF8'),'sha256'),'hex') INTO v_actual FROM lf_ops.reglas x WHERE codigo='B2B-RULE-AUTH-020' AND estado='CANDIDATO';
IF v_actual IS DISTINCT FROM 'f17060b3b5c28a4c6b1736a5b78673c3951aebac6623b3dd1b7f16245f6cc18c' THEN RAISE EXCEPTION 'LF_Q11_RULE_PREIMAGE_DRIFT:B2B-RULE-AUTH-020:%',v_actual; END IF;
SELECT encode(extensions.digest(convert_to(to_jsonb(x)::text,'UTF8'),'sha256'),'hex') INTO v_actual FROM lf_ops.reglas x WHERE codigo='REG_IDV_PROGRESSIVE_001' AND estado='CANDIDATO';
IF v_actual IS DISTINCT FROM '0846aef2b1637185b5b324be17265c66dc3ea7184221b5da2bfad92ba22570b3' THEN RAISE EXCEPTION 'LF_Q11_RULE_PREIMAGE_DRIFT:REG_IDV_PROGRESSIVE_001:%',v_actual; END IF;
SELECT encode(extensions.digest(convert_to(to_jsonb(x)::text,'UTF8'),'sha256'),'hex') INTO v_actual FROM lf_ops.reglas x WHERE codigo='REG_CLIENT_RECOVERY_IDV_STEPUP_001' AND estado='VIGENTE';
IF v_actual IS DISTINCT FROM '95185d992bf1c7e03773796030024b3642f26757fcea899f1ed02fda681d42b4' THEN RAISE EXCEPTION 'LF_Q11_RULE_PREIMAGE_DRIFT:REG_CLIENT_RECOVERY_IDV_STEPUP_001:%',v_actual; END IF;
SELECT encode(extensions.digest(convert_to(to_jsonb(x)::text,'UTF8'),'sha256'),'hex') INTO v_actual FROM lf_ops.reglas x WHERE codigo='REG_CLIENT_RECOVERY_IDV_OUTCOME_001' AND estado='VIGENTE';
IF v_actual IS DISTINCT FROM '772b74d119e1b471e997432273585bc410f081567bd87c26c58dcfacfb4eb30d' THEN RAISE EXCEPTION 'LF_Q11_RULE_PREIMAGE_DRIFT:REG_CLIENT_RECOVERY_IDV_OUTCOME_001:%',v_actual; END IF;
SELECT encode(extensions.digest(convert_to(to_jsonb(x)::text,'UTF8'),'sha256'),'hex') INTO v_actual FROM lf_ops.reglas x WHERE codigo='REG_CLIENT_RECOVERY_REBIND_ATOMIC_001' AND estado='VIGENTE';
IF v_actual IS DISTINCT FROM '88b650cd7f9c964281f40b23823c3000b0da9bf91d3b5ef423d453f2129f5557' THEN RAISE EXCEPTION 'LF_Q11_RULE_PREIMAGE_DRIFT:REG_CLIENT_RECOVERY_REBIND_ATOMIC_001:%',v_actual; END IF;
SELECT encode(extensions.digest(convert_to(to_jsonb(x)::text,'UTF8'),'sha256'),'hex') INTO v_actual FROM lf_ops.politicas_seguridad x WHERE policy_code='SEC-B2B-MFA-RECOVERY' AND status='CANDIDATO';
IF v_actual IS DISTINCT FROM '700c785c955107725c262681fd05031f6c69693989813dae861f88f421135f16' THEN RAISE EXCEPTION 'LF_Q11_POLICY_PREIMAGE_DRIFT:SEC-B2B-MFA-RECOVERY:%',v_actual; END IF;
SELECT encode(extensions.digest(convert_to(to_jsonb(x)::text,'UTF8'),'sha256'),'hex') INTO v_actual FROM lf_ops.politicas_seguridad x WHERE policy_code='SEC-B2B-AUTH-PROVIDER-ARCHITECTURE' AND status='CANDIDATO';
IF v_actual IS DISTINCT FROM '9fa60095558a8e36c1d1979c9fe8684c528356c4da8d450b445b4730861241c4' THEN RAISE EXCEPTION 'LF_Q11_POLICY_PREIMAGE_DRIFT:SEC-B2B-AUTH-PROVIDER-ARCHITECTURE:%',v_actual; END IF;
IF EXISTS(SELECT 1 FROM lf_ops.politicas_seguridad WHERE policy_code='SEC-LF-IDV-FACEPHI-OPTIONAL') THEN RAISE EXCEPTION 'LF_Q11_FACEPHI_POLICY_ALREADY_EXISTS'; END IF;
IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo IN ('LF-IDV-FACEPHI-DISABLED-GUARD-001','LF-B2B-TOKEN-NAME-DRIFT-001')) THEN RAISE EXCEPTION 'LF_Q11_EKB_ALREADY_EXISTS'; END IF;
SELECT count(*) INTO v_n FROM lf_design.spacing_tokens WHERE design_system_code='LF_DS_V1' AND status='CANDIDATO' AND (spacing_token_id,token_name,value_px) IN (VALUES
(38,'b2b_filter_drawer_width',360),
(37,'b2b_modal_max_width',640),
(32,'b2b_page_padding_desktop',24),
(34,'b2b_page_padding_mobile',16),
(33,'b2b_page_padding_tablet',20),
(30,'b2b_sidebar_width_collapsed',80),
(29,'b2b_sidebar_width_expanded',280),
(36,'b2b_table_row_height',48),
(31,'b2b_topbar_height',72),
(35,'b2b_touch_target_min',44)
);
IF v_n<>10 THEN RAISE EXCEPTION 'LF_Q11_TEN_TOKEN_IDENTITY_DRIFT:%',v_n; END IF;
END $pre$;
-- The catalog has no sequence/default for security_policy_id: allocate under table lock.
LOCK TABLE lf_ops.politicas_seguridad IN SHARE ROW EXCLUSIVE MODE;
INSERT INTO lf_ops.politicas_seguridad
(security_policy_id,policy_code,category,description,enforcement_level,policy_config,status,source_decision_id,parameter_provenance)
VALUES ((SELECT coalesce(max(security_policy_id),0)+1 FROM lf_ops.politicas_seguridad),'SEC-LF-IDV-FACEPHI-OPTIONAL','AUTHENTICATION','FACEPHI queda identificado como proveedor de verificación de identidad (IDV), NO como OIDC/IdP. Configurado pero apagado. Solo una exigencia explícita de empresa B2B para su salida a producción permite iniciar una activación gobernada posterior; nunca se autohabilita ni bloquea Login B2B estándar.','CONDITIONAL','{"provider_code":"FACEPHI","provider_kind":"IDENTITY_VERIFICATION_IDV_NOT_LOGIN_IDP","enabled":false,"default_enabled":false,"integration_status":"NOT_IMPLEMENTED_NO_EXTERNAL_CALLS","external_invocation_when_disabled":"DENY","automatic_activation":"DENY","activation_trigger":"B2B_ENTERPRISE_EXPLICITLY_REQUIRES_IDV_FOR_GO_LIVE","activation_authority":"SEPARATE_GOVERNED_OWNER_APPROVAL_AND_QA_REQUIRED","b2b_regular_login_dependency":false,"client_recovery_provider_state":"DISABLED_NO_BYPASS"}'::jsonb,'CANDIDATO','DOC-OWNER-20261114-0452-IDV-FACEPHI','{"provider_code":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","origin_version":"2026-11-14","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"provider_kind":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","origin_version":"2026-11-14","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"enabled":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","origin_version":"2026-11-14","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"default_enabled":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","origin_version":"2026-11-14","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"integration_status":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","origin_version":"2026-11-14","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"external_invocation_when_disabled":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","origin_version":"2026-11-14","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"automatic_activation":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","origin_version":"2026-11-14","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"activation_trigger":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","origin_version":"2026-11-14","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"activation_authority":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","origin_version":"2026-11-14","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"b2b_regular_login_dependency":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","origin_version":"2026-11-14","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"client_recovery_provider_state":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","origin_version":"2026-11-14","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"}}'::jsonb);

-- RULE: B2B-RULE-AUTH-020. Exact source-state hash and status guarded in preflight.
UPDATE lf_ops.reglas x
SET valor_config=coalesce(x.valor_config,'{}'::jsonb)||'{"idv_provider_policy_code":"SEC-LF-IDV-FACEPHI-OPTIONAL","idv_branch_requires_provider_enabled":true,"idv_fallback_when_disabled":"ASSISTED_SUPPORT_DNI_GOVERNED_ONLY","idv_auto_fallback":"DENY","idv_not_required_for_regular_login":true}'::jsonb,

descripcion=x.descripcion||' La verificación automatizada IDV es opcional y queda deshabilitada por la política central SEC-LF-IDV-FACEPHI-OPTIONAL; no participa en el Login regular. La recuperación asistida por soporte/DNI, cuando corresponda, conserva permisos, aprobaciones y auditoría; la rama IDV no se ejecuta mientras permanezca apagada.',
updated_at=now()
WHERE codigo='B2B-RULE-AUTH-020' AND estado='CANDIDATO';

-- RULE: REG_IDV_PROGRESSIVE_001. Exact source-state hash and status guarded in preflight.
UPDATE lf_ops.reglas x
SET valor_config=coalesce(x.valor_config,'{}'::jsonb)||'{"idv_provider_policy_code":"SEC-LF-IDV-FACEPHI-OPTIONAL","idv_provider_default_state":"DISABLED","idv_invoke_while_disabled":"DENY","idv_activation_requires_governed_scope":"B2B_ENTERPRISE_PRODUCTION_DEPENDENCY","idv_disabled_recovery_outcome":"BLOCK_IDV_ONLY_PRESERVE_OTHER_APPROVED_PROOFS"}'::jsonb,

descripcion=x.descripcion||' Mientras FACEPHI esté configurado pero apagado, ni el flujo normal ni el step-up de recuperación lo invocan; la rama que lo exige queda no disponible y no produce verificación ficticia.',
updated_at=now()
WHERE codigo='REG_IDV_PROGRESSIVE_001' AND estado='CANDIDATO';

-- RULE: REG_CLIENT_RECOVERY_IDV_STEPUP_001. Exact source-state hash and status guarded in preflight.
UPDATE lf_ops.reglas x
SET valor_config=coalesce(x.valor_config,'{}'::jsonb)||'{"idv_provider_policy_code":"SEC-LF-IDV-FACEPHI-OPTIONAL","idv_provider_state_gate":"ENABLED_REQUIRED_BEFORE_EXTERNAL_CALL","idv_when_disabled":"BLOCK_ONLY_REQUIRING_IDV_STEPUP_NO_BYPASS","idv_absence_does_not_block_normal_login":true}'::jsonb,

descripcion=x.descripcion||' La obligación de step-up no autoriza llamar al proveedor deshabilitado ni conceder identidad verificada sin prueba; bloquear únicamente la recuperación que necesite esa prueba y no tenga otra prueba aprobada.',
updated_at=now()
WHERE codigo='REG_CLIENT_RECOVERY_IDV_STEPUP_001' AND estado='VIGENTE';

-- RULE: REG_CLIENT_RECOVERY_IDV_OUTCOME_001. Exact source-state hash and status guarded in preflight.
UPDATE lf_ops.reglas x
SET valor_config=coalesce(x.valor_config,'{}'::jsonb)||'{"idv_provider_policy_code":"SEC-LF-IDV-FACEPHI-OPTIONAL","idv_disabled_outcome":"IDENTITY_VALIDATION_SERVICE_UNAVAILABLE","idv_disabled_cannot_emit_verified":true,"idv_provider_raw_payload_when_disabled":"DENY"}'::jsonb,

descripcion=x.descripcion||' La normalización nunca emite VERIFIED si el proveedor está deshabilitado; la respuesta de rama no disponible no reasigna cuentas ni autoriza acceso.',
updated_at=now()
WHERE codigo='REG_CLIENT_RECOVERY_IDV_OUTCOME_001' AND estado='VIGENTE';

-- RULE: REG_CLIENT_RECOVERY_REBIND_ATOMIC_001. Exact source-state hash and status guarded in preflight.
UPDATE lf_ops.reglas x
SET valor_config=coalesce(x.valor_config,'{}'::jsonb)||'{"idv_provider_policy_code":"SEC-LF-IDV-FACEPHI-OPTIONAL","idv_verified_proof_requires_enabled_provider":true,"idv_disabled_rebind":"DENY_WITHOUT_OTHER_APPROVED_RECOVERY_PROOF","old_phone_otp_path_unchanged":true}'::jsonb,

descripcion=x.descripcion||' La prueba IDV_VALIDATED no es válida con proveedor apagado; se mantiene independiente el OTP del teléfono anterior cuando sea prueba autorizada.',
updated_at=now()
WHERE codigo='REG_CLIENT_RECOVERY_REBIND_ATOMIC_001' AND estado='VIGENTE';

-- POLICY: SEC-B2B-MFA-RECOVERY. Exact source-state hash and status guarded in preflight.
UPDATE lf_ops.politicas_seguridad x
SET policy_config=coalesce(x.policy_config,'{}'::jsonb)||'{"idv_provider_policy_code":"SEC-LF-IDV-FACEPHI-OPTIONAL","idv_optional_branch_enabled":false,"idv_disabled_resolution":"ASSISTED_SUPPORT_DNI_GOVERNED_NO_EXTERNAL_IDV","idv_gate_applies_only_to_idv_branch":true,"regular_login_mfa_unchanged":true}'::jsonb,
parameter_provenance=coalesce(x.parameter_provenance,'{}'::jsonb)||'{"idv_provider_policy_code":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","origin_version":"2026-11-14","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"idv_optional_branch_enabled":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","origin_version":"2026-11-14","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"idv_disabled_resolution":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","origin_version":"2026-11-14","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"idv_gate_applies_only_to_idv_branch":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","origin_version":"2026-11-14","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"regular_login_mfa_unchanged":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","origin_version":"2026-11-14","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"}}'::jsonb,

description=x.description||' FACEPHI se configura apagado como vía IDV opcional; su indisponibilidad bloquea solo esa vía. La recuperación asistida vigente por soporte/DNI y los controles de aviso, aprobación y auditoría no se degradan ni dependen del proveedor IDV opcional.',
updated_at=now()
WHERE policy_code='SEC-B2B-MFA-RECOVERY' AND status='CANDIDATO';

-- POLICY: SEC-B2B-AUTH-PROVIDER-ARCHITECTURE. Exact source-state hash and status guarded in preflight.
UPDATE lf_ops.politicas_seguridad x
SET policy_config=coalesce(x.policy_config,'{}'::jsonb)||'{"idv_provider_policy_code":"SEC-LF-IDV-FACEPHI-OPTIONAL","idv_is_authentication_idp":false,"idv_provider_activation_scope":"B2B_ENTERPRISE_REQUIRES_IDV_FOR_PRODUCTION","idv_never_called_by_login":true}'::jsonb,
parameter_provenance=coalesce(x.parameter_provenance,'{}'::jsonb)||'{"idv_provider_policy_code":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","origin_version":"2026-11-14","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"idv_is_authentication_idp":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","origin_version":"2026-11-14","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"idv_provider_activation_scope":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","origin_version":"2026-11-14","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"},"idv_never_called_by_login":{"origin_type":"LF_PROVISIONAL_DEFAULT","value_status":"LF_PROVISIONAL","decision_ref":"DOC-OWNER-20261114-0452-IDV-FACEPHI","origin_reference":"OWNER_CHAT_DOCUMENTARY_NOT_IDENTITY_VERIFIED","origin_version":"2026-11-14","replacement_policy":"MUST_BE_RATIFIED_OR_OVERRIDDEN"}}'::jsonb,

description=x.description||' FACEPHI es un servicio IDV opcional separado del proveedor de autenticación OIDC/IdP; no se habilita por defecto ni condiciona el Login B2B ordinario. Una empresa B2B debe declarar su necesidad de IDV para producción y tramitar activación gobernada antes de integrarlo.',
updated_at=now()
WHERE policy_code='SEC-B2B-AUTH-PROVIDER-ARCHITECTURE' AND status='CANDIDATO';

INSERT INTO public.lf_error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,lote_origen,estado,evidencia,source_context,source_ref)
VALUES
('LF-IDV-FACEPHI-DISABLED-GUARD-001','AUTHENTICATION','Proveedor IDV seleccionado no equivale a activado','Una configuración documental FACEPHI no autoriza SDK, red, verificación ni bypass; los flujos IDV se bloquean por defecto y Login B2B sigue su propio contrato.','Confundir proveedor configurado con integración habilitada','Provider declared while enabled=false','Verificar bandera central, falta de integración y requerimiento B2B explícito antes de una activación futura por ruta oficial','Estado apagado debe negar invocación, negar VERIFIED sin prueba, preservar flujos no IDV y ausencia de API externa','High',1,'Q11-20261114','ACTIVO','DOC-OWNER-20261114-0452-IDV-FACEPHI;identity_verified=false','LF B2B/Cliente, proveedor IDV opcional','supabase://lf_ops.politicas_seguridad/SEC-LF-IDV-FACEPHI-OPTIONAL'),
('LF-B2B-TOKEN-NAME-DRIFT-001','DESIGN_TOKENS','No duplicar diez nombres de tokens B2B ya registrados','Los diez spacing_tokens B2B CANDIDATO de LF_DS_V1 ya tienen nombre snake_case; la decisión ratifica su nomenclatura sin cambiar identidad, estado ni valor.','Proponer nombres nuevos sin consultar catálogo','Duplicate/rename canonical token identities','Reutilizar token_name existente y enlazar componente a token; no valores literales ni renombres silenciosos','Exactamente 10 IDs y nombres de candidato, sin inserciones/renombres ni cambios de valor','Medium',1,'Q11-20261114','ACTIVO','DOC-OWNER-20261114-0452-TOKEN-NAMES;identity_verified=false','LF_DS_V1.spacing_tokens','supabase://lf_design.spacing_tokens/LF_DS_V1');
DO $post$
DECLARE v_n integer;
BEGIN
 SELECT COUNT(*) INTO v_n FROM lf_ops.politicas_seguridad WHERE policy_code='SEC-LF-IDV-FACEPHI-OPTIONAL'
 AND status='CANDIDATO' AND policy_config->>'provider_code'='FACEPHI'
 AND policy_config->>'enabled'='false'
 AND policy_config->>'integration_status'='NOT_IMPLEMENTED_NO_EXTERNAL_CALLS';
 IF v_n<>1 THEN RAISE EXCEPTION 'LF_Q11_FACEPHI_POSTSTATE_INVALID'; END IF;
 SELECT COUNT(*) INTO v_n FROM lf_design.spacing_tokens WHERE design_system_code='LF_DS_V1' AND status='CANDIDATO' AND (spacing_token_id,token_name,value_px) IN (VALUES
(38,'b2b_filter_drawer_width',360),
(37,'b2b_modal_max_width',640),
(32,'b2b_page_padding_desktop',24),
(34,'b2b_page_padding_mobile',16),
(33,'b2b_page_padding_tablet',20),
(30,'b2b_sidebar_width_collapsed',80),
(29,'b2b_sidebar_width_expanded',280),
(36,'b2b_table_row_height',48),
(31,'b2b_topbar_height',72),
(35,'b2b_touch_target_min',44)
 );
 IF v_n<>10 THEN RAISE EXCEPTION 'LF_Q11_TEN_TOKEN_POSTSTATE_DRIFT'; END IF;
 IF (SELECT COUNT(*) FROM public.lf_error_knowledge WHERE codigo IN ('LF-IDV-FACEPHI-DISABLED-GUARD-001','LF-B2B-TOKEN-NAME-DRIFT-001'))<>2
 THEN RAISE EXCEPTION 'LF_Q11_EKB_NOT_REGISTERED'; END IF;
END $post$;
COMMIT;
