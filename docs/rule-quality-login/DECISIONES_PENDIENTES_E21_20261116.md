# DECISIONES_PENDIENTES — Login B2B, E21 (2026-11-16)

Estado: **CANDIDATO / SIN DECISIÓN NUEVA DEL OWNER**. La prueba contractual del candidato no equivale a prueba del runtime de autenticación.

| Referencia | Regla / dependencia | Pregunta exacta para el owner | Estado / efecto |
|---|---|---|---|
| L16-Q12 + L16-Q06 | B2B-RULE-AUTH-049 → B2B-RULE-AUTH-047 | **¿El valor inicial 5 de Q12 corresponde a intentos fallidos de contraseña por cuenta, IP, dispositivo o combinación? ¿Cuál es la ventana de medición, qué evento reinicia el contador, cuál es la consecuencia (desafío o bloqueo) y por cuánto tiempo?** Aclarar que no es la política `RATE-B2B-LOGIN` (5 solicitudes/900 segundos por IP_USER). | **PENDIENTE**. No fijar umbrales ni activar bloqueo. `AUTH-049` queda `CANDIDATO`, `pendiente_decision=true`. |
| L16-Q01 (ya existente) | B2B-RULE-AUTH-019, MFA | **No abrir una decisión nueva.** Las condiciones de método OTP correo/Brevo están referenciadas en la regla. | Implementación/QA e identidad del owner por acreditar; no declarar promoción. |
| L16-Q11 (ya existente) | B2B-RULE-AUTH-020, recuperación de segundo control | **No abrir una decisión nueva.** La recuperación asistida y doble control ya tienen referencia a Q11. | Implementación/QA y autorización humana real aún por comprobar. |

## Evidencia y límites

- Fuente: `lf_ops.reglas` y `lf_ops.reglas_pantallas`, pantalla 51 `B2B-AUTH-001`, observadas por SELECT.
- No existe una política canónica de **intentos fallidos de contraseña** independiente de rate limiting; `B2B-RULE-AUTH-047` declara esa dependencia como `MISSING` y exige una decisión.
- El nuevo candidato añade un contrato estructural y su enlace a pantalla; **no** crea un contador de runtime, no realiza QA de autenticación, no acredita puntos A del scoring ni emite recibos de Paso50.
- Las promociones requieren pruebas reales PG17/PG18 con `ci_run`, RAW vinculada a cada regla, evidencia vigente y autoridad `PROMOCION_REGLA_LF`. No registrar `PASS` ni `VIGENTE` por simple creación de candidato.
