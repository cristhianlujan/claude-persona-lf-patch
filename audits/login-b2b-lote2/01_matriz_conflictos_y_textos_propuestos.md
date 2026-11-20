# LF L40 — Corrección aprobada documentalmente por el dueño: opción C (21:30 Lima)
Estado `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`; `identity_verified=false`. Esta corrección **sustituye** la eliminación del token de AUTH-040; el token se CONSERVA.
**Criterio único:** por dispositivo, una actividad autenticada completa y verificada por servidor reinicia **30 días renovables** en `lf_ops.dispositivos_confiables.last_used_at`. Cookie sola, intento fallido o desafío incompleto NO. Dispositivo nuevo/caducado/revocado => OTP Brevo; contraseña 3 meses => OTP incluso reconocido. Cambios correo, teléfono y recuperación => OTP SIEMPRE; Intico exclusivamente soporte manual autorizado sin fallback automático. Token aleatorio con hash, cookie __Host-, revocación manual, por cambio de contraseña o por recuperación APROBADA.
## Matriz de conciliación
| Fuente | Cambio | Texto nuevo / criterio |
|---|---|---|
| AUTH-033 | Reformula | Dispositivo nuevo/revocado/sin uso autenticado 30d o clave 3 meses => OTP; dispositivo usa last_used_at solo tras acceso válido |
| AUTH-040 | Reformula | Mantener token opaco/hash y cookie __Host-, confianza renovable 30d, sin autenticación propia |
| AUTH-039 (VIGENTE) | Propuesta separada | Revocación manual + cambio de clave + recuperación APROBADA; 30d renovables |
| AUTH-034 | Reformula | OTP Brevo por disparadores; cambios de correo/teléfono/recuperación siempre OTP; Intico solo soporte |
| AUTH-035 | Conservar | TOTP sigue retirado, sin habilitación de método adicional |
| AUTH-038 | Conservar | Expiración/reenvío OTP de recuperación no depende de token |
| AUTH-041 | Reformula | OTP de uso único también en operaciones sensibles, sin inventar IDs B2B de correo/teléfono |
| AUTH-042 | Conservar | Rate limit de recuperación aislado; sin bypass por token |
| Política 25 (CANDIDATO) | Reformula | 30 días fijos, no configurable por empresa, renovación solo acceso autenticado, revocaciones |
| AUTH-013/030/043 | Alineadas | Auth primaria, recuperación/revocación y rate-limit MFA compatibles con opción C |
**Origen:** 33 snapshots `lf_ops.reglas` (incluye AUTH039 VIGENTE y STATE001 VIGENTE), política25 CANDIDATO con SHA fuente `b3eb2d4f3ab1a67bd99c58f243f55c7092dd8040e2710c3ce1d28a82d36bbc4c`. Los 8 textos íntegros y JSONB config se encuentran en `sandbox/lf_contract_gate_test/edge_function_operation/fixtures/login_b2b_lote2_conflict_only_patch_20261113.json`; política25 y guard real de procedencia en `login_b2b_lote2_option_c_policy25_20261113.json`.
**Alcance de laboratorio:** 8 UPDATE a reglas (013/030/033/034/039/040/041/043) y 1 UPDATE a política25, `BEGIN → SHA durante → ROLLBACK → SHA después`, PG17.6 y PG18.7. **25 filas regla sin cambios**, incluyendo 035,038,042 y STATE001. Nunca actualizar 018,019,020,021,026,047.
**Guard real:** `programacion.fn_guard_input_parameter_provenance_v1` requiere procedencia distinta por cada clave de config cambiada. El fixture usa `LF_PROVISIONAL_DEFAULT/LF_PROVISIONAL`, reflejando identidad no verificada y necesidad de firma antes de producción; no se afirma acto canónico firmado.
**Riesgos NO-GO:** AUTH039 VIGENTE no admite writer V2 CANDIDATO; política25 requiere migración/escritor gobernado y firma. Contrato de `fecha de último cambio de contraseña` y OTP para cambio email/teléfono requieren QA/registro de operación B2B (IDs existentes 4/5; no inventar otros). Política19 y 20 siguen sujetas al PR #3844 y deben leerse conjuntamente. 0 escrituras Supabase vivo, 0 promociones, 0 escritores V2.