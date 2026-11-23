# SECURITY: cinco candidatas para juicio Claude, S1-C02..S1-C06

Las fuentes legadas 25, 124, 125, 126 y 130 están intactas. Solo nuevas candidatas sin juicio ni promoción; alcance BACKEND/HEREDA debe revisarse contra convivencia IG antes de futuras publicaciones.

## S1-C02: Bloquear consulta sin formato validado

Fuente: lf_ops.reglas/25 (REG_SEG_007). Legadas del alcance propuesto: 1; **certificadas: 0**.

BLOQUEAR solo el intento de consulta de datos del backend en contexto de validación cuando el formato del dato no fue validado. La condición exige los tres hechos lógicos agregados y no certifica protección contra inyección ni binding.

Condición: s1c02_intento_consulta AND s1c02_validacion_servidor AND s1c02_formato_no_validado.

| Intento | Contexto | Violación | BLOQUEAR |
|---|---|---|---|
| false | false | false | false |
| false | false | true | false |
| false | true | false | false |
| false | true | true | false |
| true | false | false | false |
| true | false | true | false |
| true | true | false | false |
| true | true | true | true |

## S1-C03: Bloquear despacho OTP por webhook no autenticado

Fuente: lf_ops.reglas/124 (REG_ATQ_004). Legadas del alcance propuesto: 1; **certificadas: 0**.

BLOQUEAR solo el intento de despachar OTP mediante el webhook n8n si la autenticación interna no es válida. Los tres hechos de la condición se verifican antes del despacho; no se acredita código HTTP ni binding.

Condición: s1c03_intento_despachar_otp AND s1c03_webhook_n8n_otp AND s1c03_autenticacion_interna_invalida.

| Intento | Contexto | Violación | BLOQUEAR |
|---|---|---|---|
| false | false | false | false |
| false | false | true | false |
| false | true | false | false |
| false | true | true | false |
| true | false | false | false |
| true | false | true | false |
| true | true | false | false |
| true | true | true | true |

## S1-C04: Bloquear aceptación de OTP por firma HMAC inválida

Fuente: lf_ops.reglas/125 (REG_ATQ_005). Legadas del alcance propuesto: 1; **certificadas: 0**.

BLOQUEAR solo el intento de aceptar petición del webhook OTP cuando el resultado agregado de verificación de firma HMAC-SHA256 o su tiempo es inválido. El límite temporal se obtiene desde public.lf_global_config, AUTH/OTP_HMAC_TIMESTAMP_WINDOW_SECONDS. La condición requiere intento, contexto y violación; sin binding físico acreditado.

Condición: s1c04_intento_aceptar_solicitud AND s1c04_webhook_otp_firmado AND s1c04_verificacion_firma_o_tiempo_invalida.

| Intento | Contexto | Violación | BLOQUEAR |
|---|---|---|---|
| false | false | false | false |
| false | false | true | false |
| false | true | false | false |
| false | true | true | false |
| true | false | false | false |
| true | false | true | false |
| true | true | false | false |
| true | true | true | true |

## S1-C05: Bloquear despacho OTP con sesión inelegible

Fuente: lf_ops.reglas/126 (REG_ATQ_006). Legadas del alcance propuesto: 1; **certificadas: 0**.

BLOQUEAR solo el intento de despachar OTP en contexto de sesión OTP cuando el backend comunica que la sesión no es elegible. La inelegibilidad agrupa sesión inexistente, OTP verificado, reenvíos agotados o cooldown activo; condición usa hecho agregado, no verifica esos campos individualmente ni acredita binding.

Condición: s1c05_intento_despachar_otp AND s1c05_contexto_sesion_otp AND s1c05_sesion_inelegible.

| Intento | Contexto | Violación | BLOQUEAR |
|---|---|---|---|
| false | false | false | false |
| false | false | true | false |
| false | true | false | false |
| false | true | true | false |
| true | false | false | false |
| true | false | true | false |
| true | true | false | false |
| true | true | true | true |

## S1-C06: Bloquear respuesta de error demasiado temprana

Fuente: lf_ops.reglas/130 (REG_ATQ_010). Legadas del alcance propuesto: 1; **certificadas: 0**.

BLOQUEAR solo el intento de emitir una respuesta de error de validación de DNI, celular u OTP cuando su duración sea inferior al mínimo de public.lf_global_config, AUTH/ERROR_RESPONSE_MINIMUM_MS. La condición usa tres hechos lógicos sin umbral fijo ni binding del reloj acreditado.

Condición: s1c06_intento_responder_error AND s1c06_validacion_dni_celular_otp AND s1c06_duracion_inferior_minimo.

| Intento | Contexto | Violación | BLOQUEAR |
|---|---|---|---|
| false | false | false | false |
| false | false | true | false |
| false | true | false | false |
| false | true | true | false |
| true | false | false | false |
| true | false | true | false |
| true | true | false | false |
| true | true | true | true |

## Cuadro de migración de las 586 legadas

| Métrica | Real / alcance |
|---|---:|
| Legadas aún conservadas | 586 |
| CUBIERTA funcional acreditada mediante relación versionada | 0 |
| Fuentes legadas distintas del lote | 5 |
| Candidatas creadas | 5 |
| Legadas retiradas o deprecadas | 0 |
| Publicaciones nuevas de esta tanda | 0 |

Ninguna referencia `origen.ref` prueba por sí sola cobertura funcional. Requiere juicio independiente de las cinco reglas y verificación de convivencia, sin tocar IG.
