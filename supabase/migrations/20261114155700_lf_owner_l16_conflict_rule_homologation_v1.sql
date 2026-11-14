-- LF L16 owner decision conflicts, source-first, 2026-11-14; no rule insertion/promotion.
-- Decision evidence: L27 Q04/Q05; L30 Q01/Q10/Q11/Q12; L35/L36 factor 1-2.
-- identity_verified=false, no signature/production authority. Only six existing lf_ops.reglas.
-- Relevant neighboring central security policies 19/20/22 remain CANDIDATO; not changed here.
BEGIN;
DO $preimage$
DECLARE v_match integer;
BEGIN
 SELECT count(*) INTO v_match FROM lf_ops.reglas r JOIN (VALUES
(235,'REG_B2B_005','VIGENTE','167490cb4c2c4d82be6558ef1c49b043'),
(438,'B2B-RULE-AUTH-019','CANDIDATO','de2520de2abd34df0abffb05a07601bc'),
(439,'B2B-RULE-AUTH-020','CANDIDATO','d14a231e2ee319d951ff3be0eaf8debb'),
(440,'B2B-RULE-AUTH-021','CANDIDATO','583350c424781044cbc82f2d0d9b58f7'),
(532,'REG_CLIENT_INSTALLMENT_COLLECTION_FAILURE_001','VIGENTE','1d9cb2d306f98308973f5eeb3b7812fd'),
(577,'B2B-RULE-AUTH-047','CANDIDATO','66a832d20d1aa0c6258a2da1d78f5020')
 ) e(id,code,estado,hash) ON e.id=r.id AND e.code=r.codigo AND e.estado=r.estado
 WHERE md5(coalesce(r.descripcion,'')||'|'||coalesce(r.valor_config::text,'')||'|'||coalesce(r.pendiente_detalle,'')||'|'||coalesce(r.estado,'')||'|'||coalesce(r.pendiente_decision::text,''))=e.hash;
 IF v_match<>6 THEN RAISE EXCEPTION 'LF_L16_HOMOLOGATION_PREIMAGE_DRIFT:matched=%',v_match; END IF;
END $preimage$;

-- 235 REG_B2B_005 | L16-Q10 | state preserved VIGENTE
UPDATE lf_ops.reglas SET
 descripcion='La Carta de No Adeudo es emitida y firmada por el aliado acreedor (o representante autorizado), no por LF. LF aloja, entrega y habilita reenvío solamente con permisos del perfil y evidencia de emisión. Se contemplan dos formatos de carta del aliado; su recepción, firma, entrega y reenvío requieren integración y pruebas. El SLA para generarla y la escalación al aliado provienen exclusivamente del convenio/contrato confirmado: NO existe un SLA de 48 horas aprobado para esta carta. Hasta acreditar convenio, modelos y permisos, no publicar promesa de plazo fijo.',
 razon='L16-Q10: dos modelos, reenvío y pantalla gobernada por permisos; SLA contractual externo aún no firmado. No confundir con espera de 48 horas de recuperación Q11.',
 valor_config=(coalesce(valor_config,'{}'::jsonb) - 'sla_generacion_h') || '{"owner_decision_ref":"L16-Q10","owner_decision_source":"docs/rule-quality-lote30/01_registro_decisiones_dueno_l30.json","owner_decision_identity_verified":false,"letter_models":"TWO_ALLY_MODELS_PENDING_SOURCE","resend_permission":"PENDING_PROFILE_PERMISSION_EVIDENCE","sla_source":"PENDING_SIGNED_ALLY_AGREEMENT","sla_generation_h_status":"NOT_DEFINED_NO_48H_CLAIM","implementation_status":"PENDING_ALLY_INTEGRATION_QA","owner_evidence_mode":"DECISION_DUENO_EN_CONVERSACION_SIN_FIRMA; identity_verified=false; implementation/QA NO-GO"}'::jsonb,
 pendiente_decision=false,
 pendiente_detalle='L16-Q10 aplicada documentalmente; pendientes los dos modelos y firma del aliado, permiso de reenvío, integración/SLA contractual y QA. La espera de 48 horas de Q11 pertenece a recuperación de cuenta, NO a la Carta de No Adeudo.',
 updated_at=clock_timestamp()
 WHERE id=235 AND codigo='REG_B2B_005' AND estado='VIGENTE';
DO $row_235$ BEGIN IF (SELECT count(*) FROM lf_ops.reglas WHERE id=235 AND valor_config->>'owner_decision_ref'='L16-Q10' AND estado='VIGENTE')<>1 THEN RAISE EXCEPTION 'LF_L16_HOMOLOGATION_ROW_235_NOT_APPLIED'; END IF; END $row_235$;

-- 438 B2B-RULE-AUTH-019 | L16-Q01|L35-OWNER-AUTH019-OPTION-A-001|L36-OWNER-ADMIN-LF-PROFILE1-OTP-BREVO-001 | state preserved CANDIDATO
UPDATE lf_ops.reglas SET
 descripcion='El factor MFA se resuelve exclusivamente mediante las políticas centrales SEC-B2B-MFA (3) y SEC-B2B-MFA-FACTOR-ELIGIBILITY (19). Para los perfiles humanos 1 y 2 (Admin LF y Admin Empresa), el primer factor es usuario/contraseña validado por servidor; cuando MFA aplica, LF genera y valida OTP de un solo uso entregado al correo registrado mediante Brevo. Perfiles 3, 4, 5 y 6 siguen el mismo segundo factor OTP correo/Brevo cuando corresponde. El SSO administrativo legado no es el método aprobado de MFA y el binding IdP permanece PENDING_ADR_003_M1_SPIKE. Se prohíbe el bypass por contraseña sola, factor elegido por cliente y sesiones antes de verificación MFA. No atribuir a OTP correo resistencia a phishing, FIDO2 requerido ni Supabase native AAL2 sin evidencia. Implementación Brevo/IdP, recuperación, QA y firma del owner pendientes.',
 razon='Decisiones L16-Q01, L35 y L36 sustituyen Google Workspace/SAML por OTP por correo/Brevo en perfiles 1–6; preservar seguridad fail-closed y política central 19 CANDIDATO.',
 valor_config=(coalesce(valor_config,'{}'::jsonb) - 'admin_method' - 'admin_provider_status' - 'admin_phishing_resistant_requirement') || '{"owner_decision_ref":"L16-Q01|L35-OWNER-AUTH019-OPTION-A-001|L36-OWNER-ADMIN-LF-PROFILE1-OTP-BREVO-001","owner_decision_source":"docs/rule-quality-lote37/01_manifiesto_firma_en_bloque_v1.json","owner_decision_identity_verified":false,"admin_primary_method":"USERNAME_PASSWORD_SERVER_VALIDATED","admin_identity_provider":"PENDING_ADR_003_M1_SPIKE","admin_sso_protocol":"PENDING_ADR_003_M1_SPIKE","admin_factor_method":"LF_EMAIL_OTP","admin_factor_delivery_provider":"BREVO","admin_factor_delivery_channel":"EMAIL","admin_phishing_resistant_requirement":"NOT_REQUIRED_FOR_PROFILES_1_2_OWNER_RISK_ACCEPTED_PENDING_SIGNATURE","admin_provider_status":"PENDING_REAL_IDP_AND_BREVO_INTEGRATION_QA","implementation_status":"PENDING_IMPLEMENTATION_QA_AND_OWNER_SIGNATURE","owner_evidence_mode":"DECISION_DUENO_EN_CONVERSACION_SIN_FIRMA; identity_verified=false; implementation/QA NO-GO"}'::jsonb,
 pendiente_decision=false,
 pendiente_detalle='L16-Q01/L35/L36 documentadas: OTP correo/Brevo para perfiles 1–6. Quedan integración real, proveedor identidad ADR-003 M1, seguridad/QA y firma del owner; política central 19 continúa CANDIDATO, sin declarar AAL2 o resistencia phishing.',
 updated_at=clock_timestamp()
 WHERE id=438 AND codigo='B2B-RULE-AUTH-019' AND estado='CANDIDATO';
DO $row_438$ BEGIN IF (SELECT count(*) FROM lf_ops.reglas WHERE id=438 AND valor_config->>'owner_decision_ref'='L16-Q01|L35-OWNER-AUTH019-OPTION-A-001|L36-OWNER-ADMIN-LF-PROFILE1-OTP-BREVO-001' AND estado='CANDIDATO')<>1 THEN RAISE EXCEPTION 'LF_L16_HOMOLOGATION_ROW_438_NOT_APPLIED'; END IF; END $row_438$;

-- 439 B2B-RULE-AUTH-020 | L16-Q11 | state preserved CANDIDATO
UPDATE lf_ops.reglas SET
 descripcion='Recuperación asistida de cuenta o segundo factor sin bypass: ante pérdida del correo/factor el usuario solicita soporte; verificar identidad con documento de identidad, requerir dos personas distintas en el control/aprobación, esperar 48 horas y notificar al contacto anterior. Separar solicitud, verificación, autorización privilegiada, re-enrolamiento y auditoría. Prohibido conceder sesión operativa, solo contraseña, OTP al mismo correo comprometido como evidencia suficiente o reutilizar TOTP legado. Se aplica a perfiles 1–6 conforme permisos; no se delega por defecto a Google Workspace. La opción IDV automatizada permanece apagada y no es requisito del login normal; para producción faltan operador/segundo aprobador, proveedor/medio de comprobación documental, aviso, permiso y QA. La política central 20 está CANDIDATO y requiere homologación documental separada.',
 razon='L16-Q11: soporte + DNI + doble persona + espera 48h + notificación al contacto anterior; no bypass; IDV externo opcional inactivo.',
 valor_config=(coalesce(valor_config,'{}'::jsonb) - 'admin_recovery_mode' - 'non_admin_recovery_mode' - 'email_access_recovery_status' - 'required_assurance_after_reenrollment') || '{"owner_decision_ref":"L16-Q11","owner_decision_source":"docs/rule-quality-lote30/01_registro_decisiones_dueno_l30.json","owner_decision_identity_verified":false,"admin_recovery_mode":"ASSISTED_SUPPORT_DNI_TWO_PERSONS_48H_NOTIFY_PREVIOUS","non_admin_recovery_mode":"ASSISTED_SUPPORT_DNI_TWO_PERSONS_48H_NOTIFY_PREVIOUS","identity_verification":"DNI_AND_INDEPENDENT_SUPPORT_CHECK","human_approval_count_required":2,"hold_hours":48,"notify_previous_contact":true,"email_access_recovery_status":"OWNER_DECIDED_IMPLEMENTATION_QA_PENDING","required_assurance_after_reenrollment":"GOVERNED_POLICY_PENDING_AUTHENTICATION_PROOF","idv_optional_branch_enabled":false,"implementation_status":"PENDING_IDV_PROVIDER_OR_ASSISTED_CHECK_QA","owner_evidence_mode":"DECISION_DUENO_EN_CONVERSACION_SIN_FIRMA; identity_verified=false; implementation/QA NO-GO"}'::jsonb,
 pendiente_decision=false,
 pendiente_detalle='Decisión Q11 aplicada a regla candidata, no a política central 20 (todavía cita Google Workspace). Faltan verificación/QA de DNI, roles de doble control, permiso, aviso y soporte; no producción ni bypass.',
 updated_at=clock_timestamp()
 WHERE id=439 AND codigo='B2B-RULE-AUTH-020' AND estado='CANDIDATO';
DO $row_439$ BEGIN IF (SELECT count(*) FROM lf_ops.reglas WHERE id=439 AND valor_config->>'owner_decision_ref'='L16-Q11' AND estado='CANDIDATO')<>1 THEN RAISE EXCEPTION 'LF_L16_HOMOLOGATION_ROW_439_NOT_APPLIED'; END IF; END $row_439$;

-- 440 B2B-RULE-AUTH-021 | L16-Q12|L16-Q06 | state preserved CANDIDATO
UPDATE lf_ops.reglas SET
 descripcion='Login evalúa anti-bot, rate limit por operación y señales de abuso con sujeto y red/IP sin bloqueo definitivo por una sola señal. Umbrales numéricos son parámetros centrales calibrables en base de datos, nunca constantes embebidas en regla o frontend. L16-Q12 aporta un valor inicial propuesto de 5, pero NO identifica control, unidad ni evento: NO se aplica como 5 intentos de contraseña, 5 IP requests ni cuota de otro contador. Se requiere vinculación explícita a política, control y unidad, pruebas sobre NAT/CGNAT y panel gobernado de mantenimiento. Conserva la política central 22 CANDIDATO y el rate-limit funcional existente sin equiparar contadores.',
 razon='L16-Q12 no habilita asignar 5 a un control desconocido; Q06 exige comparar parámetros por sujeto, evento y alcance.',
 valor_config=(coalesce(valor_config,'{}'::jsonb)) || '{"owner_decision_ref":"L16-Q12|L16-Q06","owner_decision_source":"docs/rule-quality-lote30/01_registro_decisiones_dueno_l30.json","owner_decision_identity_verified":false,"threshold_initial_owner_note":"5_UNBOUND_NOT_RUNTIME","threshold_policy_binding":"PENDING_SPECIFIC_CONTROL_UNIT_EVENT","threshold_storage":"CENTRAL_DB_POLICY_ONLY","threshold_implementation_authorized":false,"owner_evidence_mode":"DECISION_DUENO_EN_CONVERSACION_SIN_FIRMA; identity_verified=false; implementation/QA NO-GO"}'::jsonb,
 pendiente_decision=false,
 pendiente_detalle='Q12 decidió parametrización y valor inicial 5 sin indicar control/unidad. Bloquea binding y QA; no usar valor como password attempts, IP requests ni lockout. Política central 22 CANDIDATO; calibración proveedor pendiente.',
 updated_at=clock_timestamp()
 WHERE id=440 AND codigo='B2B-RULE-AUTH-021' AND estado='CANDIDATO';
DO $row_440$ BEGIN IF (SELECT count(*) FROM lf_ops.reglas WHERE id=440 AND valor_config->>'owner_decision_ref'='L16-Q12|L16-Q06' AND estado='CANDIDATO')<>1 THEN RAISE EXCEPTION 'LF_L16_HOMOLOGATION_ROW_440_NOT_APPLIED'; END IF; END $row_440$;

-- 532 REG_CLIENT_INSTALLMENT_COLLECTION_FAILURE_001 | L16-Q04 | state preserved VIGENTE
UPDATE lf_ops.reglas SET
 descripcion='Cada cobro de cuota utiliza outcomes normalizados: PAYMENT_CONFIRMED marca PAGADA; PAYMENT_PENDING_CONFIRMATION mantiene EN_PROCESO y bloquea segundo intento hasta conciliar; PAYMENT_DECLINED_CONFIRMED mantiene impaga y por sí solo NO la vuelve VENCIDA; caída antes de envío no equivale a rechazo. Decisión Q04: NO hay periodo de gracia. A medianoche de America/Lima se concilian cobros EN_PROCESO con Niubiz; resultado no determinado conserva EN_PROCESO, registra excepción, escala a humano y notifica al correo configurado sin datos sensibles. Si la fecha contractual termina y, al día siguiente, no hay pago confirmado ni estado EN_PROCESO pendiente de conciliación, la cuota pasa a VENCIDA. Son estados PENDIENTE, EN_PROCESO, PAGADA, VENCIDA y CANCELADA; mora/cargos adicionales NO están definidos por esta regla. La cancelación por antigüedad usa parámetro central ANTIGUEDAD_CANCELACION_AUTOMATICA_MESES (valor inicial decidido 12 meses), sin recálculo desde cliente; el tratamiento contable INCOBRABLE y reintentos/recordatorios/mora continúan pendientes de Negocio/Legal/Finanzas.',
 razon='L16-Q04: no gracia, corte Lima, conciliación segura Niubiz, cancelación controlada; preserva cinco estados y cuatro subtemas pendientes.',
 valor_config=(coalesce(valor_config,'{}'::jsonb) - 'overdue_authority' - 'grace_or_delinquency_policy') || '{"owner_decision_ref":"L16-Q04","owner_decision_source":"audits/rule-quality-lote21/01_registro_unico_decisiones.md#L16-Q04","owner_decision_identity_verified":false,"overdue_authority":"CONTRACTUAL_DUE_DATE_NEXT_DAY_LIMA_NO_GRACE","grace_policy":"NO_GRACE_OWNER_DECIDED","timezone":"America/Lima","in_process_reconciliation":"NIUBIZ_MIDNIGHT_UNDETERMINED_KEEP_IN_PROCESS_ESCALATE","decline_marks_overdue":"DENY_REQUIRES_DUE_DATE_AND_RECONCILIATION","grace_or_delinquency_policy":"NO_GRACE_MORA_SUBTOPIC_PENDING","automatic_cancel_parameter":"ANTIGUEDAD_CANCELACION_AUTOMATICA_MESES","automatic_cancel_parameter_default_owner_decision":"12_CALENDAR_MONTHS_PENDING_CANONICAL_PARAMETER","accounting_write_authorized":false,"owner_evidence_mode":"DECISION_DUENO_EN_CONVERSACION_SIN_FIRMA; identity_verified=false; implementation/QA NO-GO"}'::jsonb,
 pendiente_decision=true,
 pendiente_detalle='L16-Q04 aplicado: vencimiento sin gracia, medianoche Lima y conciliación EN_PROCESO. Pendientes reintentos automáticos, recordatorios, mora y destino contable de INCOBRABLE; falta parámetro central 12 meses implementado/QA y ledger.',
 updated_at=clock_timestamp()
 WHERE id=532 AND codigo='REG_CLIENT_INSTALLMENT_COLLECTION_FAILURE_001' AND estado='VIGENTE';
DO $row_532$ BEGIN IF (SELECT count(*) FROM lf_ops.reglas WHERE id=532 AND valor_config->>'owner_decision_ref'='L16-Q04' AND estado='VIGENTE')<>1 THEN RAISE EXCEPTION 'LF_L16_HOMOLOGATION_ROW_532_NOT_APPLIED'; END IF; END $row_532$;

-- 577 B2B-RULE-AUTH-047 | L16-Q12|L16-Q06 | state preserved CANDIDATO
UPDATE lf_ops.reglas SET
 descripcion='El aviso Bloq Mayús del Login B2B es local, visible solo con foco y detección del estado Caps Lock, sin enviar contraseña ni contar intentos. Se condiciona a una política canónica diferenciada de intentos fallidos de contraseña, actualmente AUSENTE. L16-Q12 propone valor inicial 5 para un control de riesgo aún no identificado: está prohibido inferir 5 intentos de contraseña o reutilizar los 5 requests/900s por IP_USER de la política RATE-B2B-LOGIN. Hasta confirmar control, sujeto, evento y unidad, AUTH-047 permanece CANDIDATO sin promoción funcional.',
 razon='Evitar que un aviso UX consuma o atribuya cuotas incorrectas; decisiones L16-Q12/Q06 y política de contraseñas aún faltante.',
 valor_config=(coalesce(valor_config,'{}'::jsonb)) || '{"owner_decision_ref":"L16-Q12|L16-Q06","owner_decision_source":"docs/rule-quality-lote30/01_registro_decisiones_dueno_l30.json","owner_decision_identity_verified":false,"owner_threshold_note":"5_UNBOUND_DO_NOT_ENFORCE","threshold_policy_binding":"PENDING_CONTROL_UNIT","dependency_status":"MISSING","promotion_authorized":false,"owner_evidence_mode":"DECISION_DUENO_EN_CONVERSACION_SIN_FIRMA; identity_verified=false; implementation/QA NO-GO"}'::jsonb,
 pendiente_decision=true,
 pendiente_detalle='PENDING_DEPENDENCY_PASSWORD_ATTEMPT_POLICY: no existe contador canónico de fallos password; el 5 de Q12 está sin control/unidad. No confundir con RATE-B2B-LOGIN (5 solicitudes/900s IP_USER) ni promover por esta decisión.',
 updated_at=clock_timestamp()
 WHERE id=577 AND codigo='B2B-RULE-AUTH-047' AND estado='CANDIDATO';
DO $row_577$ BEGIN IF (SELECT count(*) FROM lf_ops.reglas WHERE id=577 AND valor_config->>'owner_decision_ref'='L16-Q12|L16-Q06' AND estado='CANDIDATO')<>1 THEN RAISE EXCEPTION 'LF_L16_HOMOLOGATION_ROW_577_NOT_APPLIED'; END IF; END $row_577$;

DO $assert$
BEGIN
 IF (SELECT count(*) FROM lf_ops.reglas WHERE id IN (235,438,439,440,532,577) AND valor_config->>'owner_decision_identity_verified'='false')<>6 THEN RAISE EXCEPTION 'LF_L16_OWNER_EVIDENCE_NOT_EXACT_6'; END IF;
 IF EXISTS (SELECT 1 FROM lf_ops.reglas WHERE id=438 AND (descripcion ILIKE '%Google Workspace%' OR valor_config->>'admin_identity_provider'='GOOGLE_WORKSPACE')) THEN RAISE EXCEPTION 'LF_L16_AUTH019_GOOGLE_DRIFT'; END IF;
 IF (SELECT valor_config->>'admin_factor_method' FROM lf_ops.reglas WHERE id=438)<>'LF_EMAIL_OTP' THEN RAISE EXCEPTION 'LF_L16_AUTH019_FACTOR_DRIFT'; END IF;
 IF (SELECT valor_config->>'human_approval_count_required' FROM lf_ops.reglas WHERE id=439)<>'2' OR (SELECT valor_config->>'hold_hours' FROM lf_ops.reglas WHERE id=439)<>'48' THEN RAISE EXCEPTION 'LF_L16_AUTH020_RECOVERY_DRIFT'; END IF;
 IF EXISTS (SELECT 1 FROM lf_ops.reglas WHERE id=235 AND (valor_config?'sla_generacion_h' OR descripcion LIKE '%48h%')) THEN RAISE EXCEPTION 'LF_L16_LETTER_SLA_UNAUTHORIZED'; END IF;
 IF (SELECT valor_config->>'grace_policy' FROM lf_ops.reglas WHERE id=532)<>'NO_GRACE_OWNER_DECIDED' THEN RAISE EXCEPTION 'LF_L16_NO_GRACE_LOST'; END IF;
 IF EXISTS (SELECT 1 FROM lf_ops.reglas WHERE id IN (440,577) AND (valor_config?'password_attempt_limit' OR valor_config?'risk_threshold_count')) THEN RAISE EXCEPTION 'LF_L16_UNBOUND_5_WRONG_CONTROL'; END IF;
 IF (SELECT count(*) FROM lf_ops.reglas WHERE id IN (235,438,439,440,532,577) AND estado='CANDIDATO')<>4 THEN RAISE EXCEPTION 'LF_L16_CANDIDATE_STATUS_DRIFT'; END IF;
END $assert$;
COMMIT;
