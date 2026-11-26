-- SALY onboarding: catálogo funcional de 66 códigos homologados, NO vigente.
-- Fuente: Drive doc 11, conformidad expresa del dueño y doc 12 para OTP.
-- Sin DDL, grants, mapeo de proveedores, cambios LF/Overall ni activación.
-- Categoria, titulo, severidad y log son propuestas de clasificación para revisión.
BEGIN;
DO $seed$
DECLARE p record; n integer:=0;
BEGIN
 FOR p IN SELECT * FROM (VALUES
    ('SALY-SEC-GENERIC', 'SYSTEM', 'Revisa tu solicitud', 'No pudimos procesar tu solicitud. Intenta nuevamente o contáctanos.', 'Mostrar salida segura según el estado; no revelar elegibilidad ni causa interna.', 'T', 'LF AUTH/GENERIC_SECURITY_MESSAGE; O:generic_registration_error; L:ONB-001-PHONE-BLOCKED; L:ONB-003-REQUEST-BLOCKED', 'DOC_11_H'),
    ('SALY-NET-LOST', 'SYSTEM', 'Revisa tu solicitud', 'Se perdió la conexión. Verifica tu conexión e inténtalo nuevamente.', 'Consultar resultado antes de repetir una operación con efecto.', 'T', 'LF-B2B-NET-001', 'DOC_11_H'),
    ('SALY-SYS-TEMP', 'SYSTEM', 'Revisa tu solicitud', 'Tuvimos un inconveniente temporal. Inténtalo nuevamente.', 'Reintentar solo si el backend confirma que es seguro.', 'T', 'O:runtime_failure (9 filas); L:ONB-003-PROCESS-FAILED; L:ONB-004-PROCESS-FAILED; L:ONB-001-SUBMIT-FAILED; LF-B2B-SYS-001', 'DOC_11_H'),
    ('SALY-SYS-UNCONFIRMED', 'SYSTEM', 'Revisa tu solicitud', 'Estamos verificando el resultado de tu solicitud.', 'Consultar estado; no repetir una operación no reconciliada.', 'T', 'Nueva propuesta; principio LF S3-C19, sin trasladar política de pagos', 'DOC_11_H'),
    ('SALY-DOC-OPEN', 'SYSTEM', 'Revisa tu solicitud', 'No pudimos abrir el documento. Inténtalo nuevamente.', 'Reintentar apertura; si obligatorio no aceptar sin acceso al texto.', 'T', 'O:document_link_open_failure; O:document_unavailable', 'DOC_11_H'),
    ('SALY-DOC-REQUIRED', 'VALIDATION', 'Revisa tu solicitud', 'Ingresa tu número de documento.', 'Enfocar documento.', '2', 'L:ONB-003-DOC-REQUIRED; O:dni_required', 'DOC_11_H'),
    ('SALY-DOC-TYPE', 'VALIDATION', 'Revisa tu solicitud', 'Selecciona tu tipo de documento.', 'Enfocar selector.', '2', 'Nueva: paso 2 aprobado', 'DOC_11_H'),
    ('SALY-DNI-LENGTH', 'VALIDATION', 'Revisa tu solicitud', 'Revisa la longitud de tu DNI.', 'Validar formato oficial vigente; longitud definida en catálogo.', '2', 'L:DNI-LENGTH; O:dni_invalid_format', 'DOC_11_H'),
    ('SALY-DNI-NUMERIC', 'VALIDATION', 'Revisa tu solicitud', 'El DNI solo puede contener números.', 'Corregir campo.', '2', 'L:DNI-NUMERIC; O:dni_invalid_format', 'DOC_11_H'),
    ('SALY-CE-FORMAT', 'VALIDATION', 'Revisa tu solicitud', 'Ingresa un Carné de Extranjería válido (letras o números).', 'Validar límites desde VALIDACION.CE_MIN_LENGTH y VALIDACION.CE_MAX_LENGTH.', '2', 'L:CE-ALPHANUMERIC; L:CE-LENGTH (9–12 es referencia LF, no activar sin homologación); conformidad dueño 26/11/2026', 'DOC_11_H'),
    ('SALY-PASSPORT-FORMAT', 'VALIDATION', 'Revisa tu solicitud', 'Ingresa un pasaporte válido (letras o números).', 'Validar límites desde VALIDACION.PASSPORT_MIN_LENGTH y VALIDACION.PASSPORT_MAX_LENGTH.', '2', 'L:PASSPORT-ALPHANUMERIC; L:PASSPORT-LENGTH (5–20 es referencia LF, no activar sin homologación); conformidad dueño 26/11/2026', 'DOC_11_H'),
    ('SALY-PHONE-REQUIRED', 'VALIDATION', 'Revisa tu solicitud', 'Ingresa tu celular para continuar.', 'Enfocar celular.', '2', 'O:phone_required', 'DOC_11_H'),
    ('SALY-PHONE-PE-LENGTH', 'VALIDATION', 'Revisa tu solicitud', 'Revisa la longitud de tu número de celular.', 'Validar longitud desde catálogo propio del país.', '2', 'L:ONB-001-PHONE-LENGTH; L:ONB-002-PHONE-NEW-LENGTH; S22AJ-483-1', 'DOC_11_H'),
    ('SALY-PHONE-NUMERIC', 'VALIDATION', 'Revisa tu solicitud', 'El celular solo puede contener números.', 'Corregir campo.', '2', 'L:ONB-001-PHONE-NUMERIC; L:ONB-002-PHONE-NEW-NUMERIC', 'DOC_11_H'),
    ('SALY-PHONE-PE-PREFIX', 'VALIDATION', 'Revisa tu solicitud', 'Revisa que tu celular tenga el prefijo requerido en Perú.', 'Validar prefijo y longitud desde catálogo propio del país, sin prefijo internacional.', '2', 'L:ONB-001-PHONE-PREFIX; L:ONB-002-PHONE-NEW-PREFIX; O:phone_invalid_format; S22AJ-483-1; conformidad dueño 26/11/2026', 'DOC_11_H'),
    ('SALY-EMAIL-REQUIRED', 'VALIDATION', 'Revisa tu solicitud', 'Ingresa tu correo electrónico.', 'Enfocar correo.', '2', 'L:ONB-004-EMAIL-REQUIRED; O:email_required', 'DOC_11_H'),
    ('SALY-EMAIL-INVALID', 'VALIDATION', 'Revisa tu solicitud', 'Ingresa un correo válido, por ejemplo: nombre@correo.com.', 'Corregir correo.', '2', 'L:ONB-004-EMAIL-INVALID; O:email_invalid_format', 'DOC_11_H'),
    ('SALY-EMAIL-LENGTH', 'VALIDATION', 'Revisa tu solicitud', 'El correo ingresado es demasiado largo.', 'Validar máximo desde VALIDACION.EMAIL_MAX_LENGTH.', '2', 'L:ONB-004-EMAIL-TOO-LONG; conformidad dueño 26/11/2026', 'DOC_11_H'),
    ('SALY-TERMS-REQUIRED', 'VALIDATION', 'Revisa tu solicitud', 'Debes aceptar los Términos y Condiciones para continuar.', 'Mostrar aceptación y documento.', '2', 'L:ONB-004-TERMS-REQUIRED; O:terms_required', 'DOC_11_H'),
    ('SALY-PRIVACY-REQUIRED', 'VALIDATION', 'Revisa tu solicitud', 'Autoriza el tratamiento de tus datos personales y biométricos para continuar.', 'Regresar a aceptación válida del paso 2; no capturar sin consentimiento.', '2/6', 'L:ONB-003-CONSENT-REQUIRED; O:data_protection_required; decisión paso 6', 'DOC_11_H'),
    ('SALY-OTP-REQUIRED', 'AUTHENTICATION', 'Revisa tu solicitud', 'Ingresa el código de verificación recibido.', 'Enfocar canal pendiente.', '3', 'O:email_otp_required; O:phone_otp_required', 'DOC_11_H'),
    ('SALY-OTP-LENGTH', 'AUTHENTICATION', 'Revisa tu solicitud', 'El código debe tener {longitud} dígitos.', 'Completar según política central.', '3', 'L:ONB-002-OTP-LENGTH', 'DOC_11_H'),
    ('SALY-OTP-NUMERIC', 'AUTHENTICATION', 'Revisa tu solicitud', 'El código solo puede contener números.', 'Corregir código.', '3', 'L:ONB-002-OTP-NUMERIC', 'DOC_11_H'),
    ('SALY-OTP-INVALID', 'AUTHENTICATION', 'Revisa tu solicitud', 'Código incorrecto. Revisa e intenta de nuevo.', 'Corregir; mostrar intentos restantes después del fallo si aplica.', '3', 'L:ONB-002-OTP-INVALID; O:email_otp_invalid; O:phone_otp_invalid; S9-C02', 'DOC_11_H'),
    ('SALY-OTP-EXPIRED', 'AUTHENTICATION', 'Revisa tu solicitud', 'Tu código ha vencido. Solicita uno nuevo.', 'Reenviar si servidor autoriza.', '3', 'L:ONB-002-OTP-EXPIRED; O:email_otp_expired; O:phone_otp_expired', 'DOC_11_H'),
    ('SALY-OTP-SEND-FAILED', 'AUTHENTICATION', 'Revisa tu solicitud', 'No pudimos enviar el código. Intenta nuevamente o verifica tus datos.', 'Reintentar o editar canal; alternativo solo si habilitado.', '3', 'L:ONB-001-OTP-SEND-FAILED; L:ONB-002-OTP-SEND-FAILED; O:channel_delivery_failure; O:sms_delivery_failure; O:whatsapp_fallback_failure', 'DOC_11_H'),
    ('SALY-OTP-RESEND-WAIT', 'AUTHENTICATION', 'Revisa tu solicitud', 'Espera {tiempo_restante} antes de solicitar otro código.', 'Mostrar espera calculada por servidor.', '3', 'O:email_resend_blocked; O:phone_resend_blocked', 'DOC_11_H'),
    ('SALY-OTP-CYCLE-EXHAUSTED', 'AUTHENTICATION', 'Revisa tu solicitud', 'Este código ya no puede usarse. Espera {tiempo_restante} para solicitar uno nuevo.', 'Esperar hasta autorización del servidor.', '3', 'L:ONB-002-OTP-CYCLE-EXHAUSTED; O:otp_block_level_1; O:otp_block_level_2; O:otp_block_level_3 (no se trasladan sus duraciones)', 'LOTE_3_Y_OTP'),
    ('SALY-CHANNELS-INCOMPLETE', 'VALIDATION', 'Revisa tu solicitud', 'Valida tu celular y tu correo para continuar.', 'Enfocar primer canal pendiente.', '3', 'O:channels_incomplete', 'DOC_11_H'),
    ('SALY-PHONE-UNCHANGED', 'VALIDATION', 'Revisa tu solicitud', 'El nuevo número debe ser distinto al anterior.', 'Validar solo al cambiar celular; no impedir reenvío legítimo.', '3', 'L:ONB-002-PHONE-NEW-SAME; conformidad dueño 26/11/2026', 'DOC_11_H'),
    ('SALY-PEP-ANSWER', 'VALIDATION', 'Revisa tu solicitud', 'Responde esta pregunta para continuar.', 'Enfocar declaración titular/familiar pendiente; no inducir respuesta.', '4', 'O:pep_self_required; O:pep_related_required', 'DOC_11_H'),
    ('SALY-PEP-DETAIL', 'VALIDATION', 'Revisa tu solicitud', 'Completa los datos solicitados para continuar.', 'Enfocar campo; mantener detalle condicional.', '4', 'O:pep_detail_required (estado normal, no error); adaptación nueva para dato faltante', 'DOC_11_H'),
    ('SALY-BANK-REQUIRED', 'VALIDATION', 'Revisa tu solicitud', 'Selecciona tu banco para continuar.', 'Enfocar selector.', '5', 'O:bank_required', 'DOC_11_H'),
    ('SALY-ACCOUNT-REQUIRED', 'VALIDATION', 'Revisa tu solicitud', 'Ingresa tu número de cuenta para continuar.', 'Enfocar campo.', '5', 'O:account_required', 'DOC_11_H'),
    ('SALY-ACCOUNT-FORMAT', 'VALIDATION', 'Revisa tu solicitud', 'Revisa el número de cuenta según el banco seleccionado.', 'Aplicar únicamente formatos validados y vigentes.', '5', 'O:BR_ONB_PE_005_ACCOUNT_REQUIRED; documento 09', 'DOC_11_H'),
    ('SALY-CCI-REQUIRED', 'VALIDATION', 'Revisa tu solicitud', 'Ingresa tu CCI para continuar.', 'Enfocar campo.', '5', 'O:cci_required', 'DOC_11_H'),
    ('SALY-CCI-NUMERIC', 'VALIDATION', 'Revisa tu solicitud', 'Ingresa solo números en el CCI.', 'Corregir campo.', '5', 'O:cci_invalid_format', 'DOC_11_H'),
    ('SALY-CCI-LENGTH', 'VALIDATION', 'Revisa tu solicitud', 'Revisa la longitud de tu CCI.', 'Aplicar formato oficial vigente del catálogo propio.', '5', 'O:cci_invalid_length', 'DOC_11_H'),
    ('SALY-CCI-BANK', 'VALIDATION', 'Revisa tu solicitud', 'El CCI no corresponde al banco seleccionado. Revisa tus datos.', 'Corregir banco/CCI.', '5', 'O:BR_ONB_PE_BANK_CCI_PREFIX_VALIDATION; documento 09', 'DOC_11_H'),
    ('SALY-ACCOUNT-MISMATCH', 'VALIDATION', 'Revisa tu solicitud', 'No pudimos verificar esta cuenta. Revisa el número e intenta de nuevo.', 'Corregir datos o soporte.', '5', 'O:BR_BANK_PE_001_HOST_TO_HOST_VALIDATION; BR_BANK_PE_002_CCI_SSI_VALIDATION', 'DOC_11_H'),
    ('SALY-CARD-INVALID', 'TOKENIZATION', 'Revisa tu solicitud', 'No pudimos registrar tu tarjeta. Revisa los datos e inténtalo nuevamente.', 'Reabrir componente seguro del proveedor si autorizado.', '5.2', 'O:CARD_DATA_INVALID; O:card_tokenization_failed; O:UNKNOWN_TOKENIZATION_ERROR', 'DOC_11_H'),
    ('SALY-CARD-EXPIRED', 'TOKENIZATION', 'Revisa tu solicitud', 'Utiliza una tarjeta vigente.', 'Reabrir componente seguro solo ante rechazo confirmado.', '5.2', 'O:CARD_EXPIRED', 'LOTE_3_Y_OTP'),
    ('SALY-CARD-CVV', 'TOKENIZATION', 'Revisa tu solicitud', 'Revisa los datos de tu tarjeta.', 'Reabrir componente seguro; no capturar CVV en SALY.', '5.2', 'O:DYNAMIC_CVV_REQUIRED_OR_INVALID', 'LOTE_3_Y_OTP'),
    ('SALY-CARD-ONLINE', 'TOKENIZATION', 'Revisa tu solicitud', 'Revisa la configuración de tu tarjeta en tu banco.', 'Mostrar ayuda validada solo si causa confirmada.', '5.2', 'O:CARD_INTERNET_PURCHASES_DISABLED', 'LOTE_3_Y_OTP'),
    ('SALY-CARD-DECLINED', 'TOKENIZATION', 'Revisa tu solicitud', 'Tu banco no autorizó el registro de la tarjeta.', 'Contactar banco; reintento seguro.', '5.2', 'O:ISSUER_DECLINED_OR_BLOCKED', 'LOTE_3_Y_OTP'),
    ('SALY-CARD-TIMEOUT', 'TOKENIZATION', 'Revisa tu solicitud', 'La validación demoró más de lo esperado. Estamos verificando el resultado.', 'Reconciliar antes de volver a tokenizar.', '5.2', 'O:TOKENIZATION_TIMEOUT', 'DOC_11_H'),
    ('SALY-CARD-REQUIRED', 'TOKENIZATION', 'Revisa tu solicitud', 'Necesitamos validar tu tarjeta para continuar.', 'Abrir componente seguro solo si configuración exige tarjeta.', '5.2', 'O:card_exception_required', 'LOTE_3_Y_OTP'),
    ('SALY-CAMERA-PERMISSION', 'IDENTITY', 'Revisa tu solicitud', 'Activa el permiso de cámara para verificar tu identidad.', 'Abrir ajustes del dispositivo.', '6', 'O:camera_permission_denied', 'DOC_11_H'),
    ('SALY-ID-MISMATCH', 'IDENTITY', 'Revisa tu solicitud', 'No pudimos confirmar tu identidad. Intenta nuevamente.', 'Contar solo comparación fallida confirmada; permitir si hay intentos.', '6', 'O:identity_mismatch', 'DOC_11_H'),
    ('SALY-ID-DATA-MISSING', 'IDENTITY', 'Revisa tu solicitud', 'No recibimos todos los datos necesarios. Inténtalo nuevamente.', 'Reintentar servicio sin penalizar si falla técnica.', '6', 'O:identity_required_data_missing', 'DOC_11_H'),
    ('SALY-BIO-QUALITY', 'IDENTITY', 'Revisa tu solicitud', 'No pudimos validar la captura. Intenta con buena luz y mirando al frente.', 'Nueva captura según proveedor; no contar como comparación fallida.', '6', 'O:selfie_quality_error', 'DOC_11_H'),
    ('SALY-BIO-TECH', 'IDENTITY', 'Revisa tu solicitud', 'No pudimos completar la validación. Inténtalo nuevamente.', 'Reintentar seguro; no penalizar.', '6', 'Decisión paso 6.2; O:runtime_failure', 'DOC_11_H'),
    ('SALY-BIO-LIMIT', 'IDENTITY', 'Revisa tu solicitud', 'Llegaste al máximo de intentos. Te ayudaremos a continuar.', 'Derivar a Soporte SALY autorizado.', '6', 'O:selfie_max_retry_reached; decisión paso 6.2', 'DOC_11_H'),
    ('SALY-ID-DOC-QUALITY', 'IDENTITY', 'Revisa tu solicitud', 'No pudimos leer tu documento.', 'Capturar nuevamente; no contar fallo de calidad como comparación fallida.', '6.3', 'Nueva propuesta paso 6.3; contrato proveedor pendiente', 'LOTE_3_Y_OTP'),
    ('SALY-ID-VIDEO-QUALITY', 'IDENTITY', 'Revisa tu solicitud', 'No pudimos validar el video.', 'Grabar nuevamente; no contar fallo de calidad como comparación fallida.', '6.3', 'Nueva propuesta paso 6.3; contrato proveedor pendiente', 'LOTE_3_Y_OTP'),
    ('SALY-PWD-REQUIRED', 'AUTHENTICATION', 'Revisa tu solicitud', 'Crea tu contraseña para continuar.', 'Enfocar contraseña.', '7', 'O:password_required', 'DOC_11_H'),
    ('SALY-PWD-MISMATCH', 'AUTHENTICATION', 'Revisa tu solicitud', 'Las contraseñas no coinciden.', 'Corregir confirmación.', '7', 'O:password_mismatch; decisión paso 7', 'DOC_11_H'),
    ('SALY-PWD-RESTRICTED', 'AUTHENTICATION', 'Revisa tu solicitud', 'No se permiten comillas simples ni tildes.', 'Mostrar error en tiempo real sin eliminar caracteres.', '7', 'Decisión paso 7', 'DOC_11_H'),
    ('SALY-PWD-NUMBER', 'AUTHENTICATION', 'Revisa tu solicitud', 'Incluye la cantidad requerida de números.', 'Actualizar guía según AUTH.PASSWORD_MIN_NUMBERS.', '7', 'Decisión paso 7', 'DOC_11_H'),
    ('SALY-PWD-SPECIAL', 'AUTHENTICATION', 'Revisa tu solicitud', 'Incluye los caracteres especiales permitidos que se requieren.', 'Actualizar guía según AUTH.PASSWORD_MIN_SPECIAL; lista exacta pendiente.', '7', 'Decisión paso 7', 'DOC_11_H'),
    ('SALY-PWD-LENGTH', 'AUTHENTICATION', 'Revisa tu solicitud', 'Utiliza al menos {longitud_minima} caracteres.', 'Resolver AUTH.PASSWORD_MIN_LENGTH desde política SALY; proveedor pendiente.', '7', 'S22C-C03; paso 7; conformidad dueño 26/11/2026', 'DOC_11_H'),
    ('SALY-PWD-CASE', 'AUTHENTICATION', 'Revisa tu solicitud', 'Incluye las mayúsculas y minúsculas requeridas.', 'Resolver AUTH.PASSWORD_MIN_UPPERCASE y AUTH.PASSWORD_MIN_LOWERCASE.', '7', 'S22C-C03; paso 7; conformidad dueño 26/11/2026', 'DOC_11_H'),
    ('SALY-CONTRACT-REQUIRED', 'VALIDATION', 'Revisa tu solicitud', 'Acepta y firma el contrato de servicio para continuar.', 'Enfocar aceptación independiente.', '7', 'O:final_consent_required; decisión paso 7', 'DOC_11_H'),
    ('SALY-DISCOUNT-REQUIRED', 'VALIDATION', 'Revisa tu solicitud', 'Acepta y firma la autorización de descuento para continuar.', 'Enfocar aceptación independiente.', '7', 'O:final_consent_required; decisión paso 7', 'DOC_11_H'),
    ('SALY-SIGN-FAILED', 'VALIDATION', 'Revisa tu solicitud', 'No pudimos confirmar la firma de tus documentos.', 'Consultar estado antes de repetir; no duplicar firma.', '7', 'Nueva propuesta; contrato firma pendiente', 'LOTE_3_Y_OTP'),
    ('SALY-RRHH-MAIL-FAILED', 'DELIVERY', 'Notificación pendiente', 'Notificación de RRHH pendiente de reenvío.', 'Mensaje interno a operador; solicitud permanece en bandeja; no bloquear cliente.', '8', 'Decisión RRHH; nueva propuesta literal', 'DOC_11_H')
 ) AS v(codigo,categoria,titulo,mensaje,accion,paso,fuente,origen)
 LOOP
  IF EXISTS(SELECT 1 FROM saly.errores_catalogo e WHERE e.codigo=p.codigo) THEN
   RAISE EXCEPTION 'SALY_ONB_ERROR_ALREADY_EXISTS %',p.codigo;
  END IF;
  INSERT INTO saly.errores_catalogo(codigo,categoria,severidad,titulo_usuario,mensaje_usuario,accion_sugerida,reintentable,nivel_log,mapeo_proveedor,estado,vigente,metadata)
  VALUES(p.codigo,p.categoria,'MEDIUM',p.titulo,p.mensaje,p.accion,false,'WARN','{}'::jsonb,'BORRADOR',false,
   jsonb_build_object('paso',p.paso,'fuente_documental',p.fuente,'origen',p.origen,'homologacion_funcional',true,'mapeo_tecnico_verificado',false,'activacion_autorizada',false,'clasificacion_tecnica_pendiente',true,'audiencia',CASE WHEN p.codigo='SALY-RRHH-MAIL-FAILED' THEN 'OPERADOR' ELSE 'CLIENTE' END));
  IF NOT EXISTS(SELECT 1 FROM saly.errores_catalogo e WHERE e.codigo=p.codigo AND e.mensaje_usuario=p.mensaje AND e.estado='BORRADOR' AND NOT e.vigente AND e.mapeo_proveedor='{}'::jsonb) THEN
   RAISE EXCEPTION 'SALY_ONB_ERROR_READBACK %',p.codigo;
  END IF;
  n:=n+1;
 END LOOP;
 IF n<>66 THEN RAISE EXCEPTION 'SALY_ONB_ERROR_COUNT %',n; END IF;
 RAISE NOTICE 'SALY_ONB_ERRORS_DRAFT %',n;
END $seed$;
COMMIT;
