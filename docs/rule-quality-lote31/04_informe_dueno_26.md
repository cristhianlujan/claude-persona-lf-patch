# LF L31 — Login B2B | Dictamen por 26 reglas escaladas, Q01/Q11/Q12

**Dictamen:** 3 propuestas corregidas documentalmente, 23 continúan bloqueadas; **0 reglas aprobadas, promovidas o modificadas en Supabase**. No implica READY funcional.

## Fuente y cadena de autoridad
- Fuente actual: `mhwmirqcgxxukpctffuv.lf_ops.reglas`; 49 reglas reales de L29 (9 VIGENTE, 40 CANDIDATO), 2 códigos AUTH-009/010 ausentes y fuera de este lote. Exactamente 26 con dictamen L29 `ESCALAR_A_HUMANO`.
- SHA-256 de universo 49 del SELECT vivo: `4959cfd6d9319ea26b60f9a21a1751c674e06c4417fb4d589f3665424d539bd3`, idéntico a origen L29.
- Preimagen íntegra 26/26 en `00_preimagen_viva_26.json`, calculada ANTES de propuestas. SHA individual de fila de Postgres y readback comprobado.
- Fuente decisiones: L30 Q01/Q11/Q12, `DECIDIDA_EN_CONVERSACION_PENDIENTE_FIRMA`. **0 firmas acreditadas**; no equiparar conversación con cambio canónico o permiso de publicar.
- EKB Input Governance V1.4 consultado; esta revisión no suplanta Router→Perfil→RUN→IG→Juez→Registro. **Ningún RUN nuevo ni anterior se tocó en L31**.

## Q01 — MFA por correo/Brevo, SMS contingente
- Correo OTP por Brevo como factor principal cuando aplique MFA. Admin Empresa **perfil 2 = OTP correo Brevo**; perfiles 3–6 continúan con ese mecanismo. Admin LF **perfil 1 = método pendiente**; no afirmar SAML aprobado para perfil 1 ni 2.
- MFA condicional después de **30 días sin uso** o **tres meses calendario sin cambio de clave**, almacenados SOLO en propuesta de política central **3**; los demás disparadores siguen pendientes. La cobertura de seis perfiles no equivale a MFA en todo intento.
- SMS solo contingencia con proveedor **NO CONFIRMADO**, sin fallback automático. El OTP correo no se declara AAL2 nativo de Supabase.
- **Bloqueo crítico:** política **19** sigue exigiendo `PHISHING_RESISTANT` a administradores. OTP correo del perfil 2 no demuestra ese control. La regla AUTH-019 tiene diff propuesto, pero queda **BLOQUEADA** hasta dictamen de Seguridad, reconciliación contractual, firma y QA; no se suprime ningún guardarraíl.

## Q11 — Recuperación de identidad
- Soporte, documento de identidad, dos personas autorizadas, **48 horas en política 20** y aviso al contacto anterior; procedimiento separado, auditable, sin acceso operativo/contraseña sola/bypass.
- La propuesta AUTH-020 incluye decisión funcional, pero faltan proveedor IDV, doble control acreditado, permisos y elegibilidad del Admin Empresa. **El método Admin LF sigue pendiente**. No se ejecutó recuperación ni se atribuyó evidencia externa.

## Q12 — Umbrales de riesgo
- Decidido conceptualmente: parámetros **configurables en BD**, valor inicial **5**, pantalla de mantenimiento.
- **BLOQUEADO para implementación**: no están identificados el parámetro canónico, control/evento ni unidad del 5, telemetría, pantalla/permiso. No escribir `5` en ninguna regla ni convertir `RATE-B2B-LOGIN = 5 solicitudes / 900 s` en contador de fallos. Se documentó propuesta no ejecutable en `02_politicas_centrales_q01_q11_y_q12.json`.

## Dictamen individual de las 26
**CORREGIDA significa solo propuesta con diff completo y SHA, no autorización de adopción ni paso a producción.** Todos los bloqueos materiales se conservan en el JSON detallado.

| Código | Estado de este lote | Motivo específico / condición aún pendiente |
|---|---|---|
| `B2B-RULE-AUTH-002` | BLOQUEADA | Modelo físico multiempresa `PENDING_FUNCTIONAL_DEFINITION`; no se acredita binding. |
| `B2B-RULE-AUTH-003` | BLOQUEADA | Política MFA 3 está VIGENTE con cobertura exigible; sucesora condicional y firma aún inexistentes. |
| `B2B-RULE-AUTH-013` | BLOQUEADA | IdP/adapter OIDC y webhook Brevo sin binding; falta prueba de canal servidor. |
| `B2B-RULE-AUTH-015` | BLOQUEADA | ADR-003 M1 sin grant, contrato de intercambio de identidad ni proveedor seleccionado. |
| `B2B-RULE-AUTH-016` | BLOQUEADA | Proveedor e identidad local pendientes; prueba de timeout/QA no acredita integración. |
| `B2B-RULE-AUTH-017` | BLOQUEADA | Respuesta segura de autenticación depende de identidad local no seleccionada. |
| `B2B-RULE-AUTH-018` | **CORREGIDA (propuesta)** | Diff MFA condicional corregido; política 3 VIGENTE, otros disparadores e IdP pendientes. |
| `B2B-RULE-AUTH-019` | BLOQUEADA | Conflicto: Admin Empresa perfil 2 OTP/Brevo frente a requisito `PHISHING_RESISTANT`; perfil 1 y proveedor SMS pendientes. |
| `B2B-RULE-AUTH-020` | **CORREGIDA (propuesta)** | Recuperación soporte+documento+doble persona corregida; permisos/IDV/alcance Admin Empresa y política 20 pendientes. |
| `B2B-RULE-AUTH-021` | BLOQUEADA | Identidad/abuso sin binding; Q12 valor 5 sin parámetro, control ni unidad identificados. |
| `B2B-RULE-AUTH-022` | BLOQUEADA | Sesión depende de OIDC/local identity no seleccionado y validación completa MFA. |
| `B2B-RULE-AUTH-026` | BLOQUEADA | Spike ADR-003 M1, proveedor OIDC y adapter físico siguen sin evidencia. |
| `B2B-RULE-AUTH-028` | BLOQUEADA | Dependencia provider_binding/local_identity_decision sin acreditación. |
| `B2B-RULE-AUTH-030` | BLOQUEADA | Dependencia provider_binding/local_identity_decision sin acreditación. |
| `B2B-RULE-AUTH-033` | **CORREGIDA (propuesta)** | Recheck MFA y revocación corregidos; política 25 `DEVICE_ONLY` y otros disparadores sin reconciliar. |
| `B2B-RULE-AUTH-034` | BLOQUEADA | Ruta OTP condicionada por AUTH-033/política 3; entrega real Brevo y QA pendientes. |
| `B2B-RULE-AUTH-035` | BLOQUEADA | Dependencia provider_binding/local_identity_decision; no reactivar TOTP legado. |
| `B2B-RULE-AUTH-036` | BLOQUEADA | Binding de identidad local y contrato backend no resueltos. |
| `B2B-RULE-AUTH-037` | BLOQUEADA | Proveedor de entrega OTP sin implementación/QA. |
| `B2B-RULE-AUTH-039` | BLOQUEADA | Regla VIGENTE de OTP tras revocación se conserva; falta coherencia con política 25 y prueba de dispositivos. |
| `B2B-RULE-AUTH-040` | BLOQUEADA | Política de confianza 25 candidata y QA de revocación pendientes. |
| `B2B-RULE-AUTH-043` | BLOQUEADA | Contador específico OTP dispositivo nuevo; Q12 5 sin unidad/control, no confundir con RATE 5/900 s; QA pendiente. |
| `B2B-RULE-AUTH-044` | BLOQUEADA | Brevo transactional email: credenciales no acreditadas, integración/webhook sin prueba. |
| `B2B-RULE-AUTH-045` | BLOQUEADA | Webhook Brevo: destino firmado, secret y rotación sin evidencia; NO crear secretos ficticios. |
| `B2B-RULE-AUTH-047` | BLOQUEADA | `pendiente_decision=true`; Caps Lock y política de intentos fallidos no resueltos; no homologar a rate limit. |
| `B2B-RULE-AUTH-048` | BLOQUEADA | Submit endpoint de Login e identidad local sin binding ejecutable. |

## Cuatro diffs de reglas con SHA-256
SHA de `jsonb::text` PostgreSQL para objeto exacto `{codigo,descripcion,valor_config}`, no hash de fila/origen ni constancia de firma.

| Regla | SHA-256 del candidato | Dictamen |
|---|---|---|
| `B2B-RULE-AUTH-018` | `46e118ed2febbb49eea4ba95c040f4e3837dd7eff417dea2f945014eb8330914` | CORREGIDA_PROPUESTA_NO_APROBADA |
| `B2B-RULE-AUTH-019` | `e5e0451dff2ce569307bccc931e9a22903eddd0851ec3b4a9e81083479a59e01` | BLOQUEADA |
| `B2B-RULE-AUTH-020` | `c0a4238b25cae6f92402a22a9dba3c08a40a05822be6083f2ff966734aae37ef` | CORREGIDA_PROPUESTA_NO_APROBADA |
| `B2B-RULE-AUTH-033` | `b06846214880f86c470a1d004d80cd9409211cd1470591dfca98eff74079ecee` | CORREGIDA_PROPUESTA_NO_APROBADA |

## Cuatro propuestas de políticas centrales
Ninguna editó la política VIGENTE 3 ni las CANDIDATO 19/20/25.

| Política | SHA-256 del candidato |
|---|---|
| `SEC-B2B-MFA` (ID 3, VIGENTE) | `b126d6332a1cc95576165b23bf15f4587fd937d0f28117857dd3fef7f04c3e78` |
| `SEC-B2B-MFA-FACTOR-ELIGIBILITY` (ID 19, CANDIDATO) | `8106aae1530296855cffdbb51eac5ca7f115a8bf183de945190d35875be4ff06` |
| `SEC-B2B-MFA-RECOVERY` (ID 20, CANDIDATO) | `3a157e2ba33676d1b4c965b54a2e60ee320b506caf19d2102c9a17020ffbb82b` |
| `SEC-B2B-TRUSTED-DEVICE` (ID 25, CANDIDATO) | `0fa5e4560f259b4e307995efaf20a51755df1718273ea723df673d44d73ef3f1` |

## Pruebas reales y límites
- **Post-escritura de documentos (no de BD):** SELECT vivo, 26/26 huellas fuente y 26/26 candidatas coincidentes; 4/4 políticas originales y 4/4 candidatas coincidentes.
- **16/16 controles deterministas ejecutados**: 30d/3m solo central, perfil 2 y 1 separados, SMS no confirmado, resistencia a phishing preservada, sin reclamar AAL2 email, Q11 48h/two-person/IDV no bypass, Q12 5 sin binding, AUTH039 revocación preservada, AUTH047 aún pendiente y ninguna firma/promoción.
- **49/49 fuente sin deriva SHA**, 9 VIGENTE y 40 CANDIDATO conservados. 23 preliminares fuera de alcance. No hubo INSERT/UPDATE/DELETE/DDL en Supabase.
- **NO EJECUTADO:** Curator independiente real, juez V3/Step70, IG recuración nueva, pruebas de comportamiento IAM/OTP/IDV/Brevo, RUN de perfil, QA E2E y promoción. No atribuirlos a los SELECT ni a la CI PG18 del lote anterior.

## Próxima decisión necesaria para desbloquear
1. Seguridad/owner: reconciliar OTP correo del perfil 2 con `PHISHING_RESISTANT`, resolver perfil 1 y demás disparadores MFA, sin relajar controles en silencio.
2. IAM/Soporte/owner: definir permisos/alcance recuperación del perfil 2, IDV y doble firma, validar 48h y aviso anterior.
3. Riesgos/Producto: asignar valor 5 a un **parámetro y unidad exactos**, actor que puede cambiarlo y pantalla autorizada.
4. Registrador/IG: solo tras esas evidencias y firma formal, ejecutar operación gobernada separada, readback, juez/QA y decisión de promoción. **Este lote termina NO-GO**.

**Evidencia primaria:** `00_preimagen_viva_26.json`, `01_matriz_26_estado_diffs_sha256.json`, `02_politicas_centrales_q01_q11_y_q12.json`, `03_pruebas_live_readback_16.json`. No se alteró L29, L30, main, ninguna regla ni un RUN.
