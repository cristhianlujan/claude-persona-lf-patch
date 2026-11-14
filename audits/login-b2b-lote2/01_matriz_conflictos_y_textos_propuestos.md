# LF · Lote 2 · Reconciliación de otras reglas Login B2B (solo propuesta)
**Fuente real:** SELECT Supabase vivo, 13-nov-2026. **PR base de decisiones:** [#3844](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3844), HEAD `980c203d67df6469161cf44bbb457861cc32c065`. Prueba aislada replica el método `jsonb_populate_record + full-row SHA-256 + BEGIN/UPDATE/ROLLBACK` de #3844; no toca ese PR ni sus reglas.
**Alcance:** 32 revisadas (31 CANDIDATO y STATE-001 VIGENTE). **5 choques reales**, 27 sin contradicción directa. Reglas `018,019,020,021,026,047` reservadas al chat Login: **excluidas**.
## Tabla de decisión: regla | ¿choca? | texto nuevo propuesto (resumen)
| Regla | ¿Choca? | Texto nuevo propuesto |
|---|---|---|
| `AUTH-004` | No | — sin cambios |
| `AUTH-005` | No | — sin cambios |
| `AUTH-006` | No | — sin cambios |
| `AUTH-007` | No | — sin cambios |
| `AUTH-011` | No | — sin cambios |
| `AUTH-012` | No | — sin cambios |
| `AUTH-013` | **SÍ** | LF_AUTH_BOUNDARY: usuario/clave server-side; OTP Brevo por política 3; quitar GOOGLE_WORKSPACE/SAML/passkeys de config; IdP real pendiente. |
| `AUTH-014` | No | — sin cambios |
| `AUTH-017` | No | — sin cambios |
| `AUTH-023` | No | — sin cambios |
| `AUTH-024` | No | — sin cambios |
| `AUTH-025` | No | — sin cambios |
| `AUTH-027` | No | — sin cambios |
| `AUTH-028` | No | — sin cambios |
| `AUTH-029` | No | — sin cambios |
| `AUTH-030` | **SÍ** | Permitir actualización tras AUTH-029 **o** recuperación asistida AUTH-020/política 20: DNI, permisos, 1–2 aprobadores, 48h y clave temporal única. |
| `AUTH-031` | No | — sin cambios |
| `AUTH-032` | No | — sin cambios |
| `AUTH-033` | **SÍ** | MFA por 30 días sin uso **o** 3 meses sin cambio de clave para perfiles 1–6; no disparar ni omitir por dispositivo; Brevo primero, Intico solo soporte. |
| `AUTH-034` | **SÍ** | OTP de MFA solo al aplicar política 3; Brevo primero, Intico manual auditado; retirar dependencia del rate limit exclusivo de NEW_DEVICE. |
| `AUTH-035` | No | — sin cambios |
| `AUTH-036` | No | — sin cambios |
| `AUTH-037` | No | — sin cambios |
| `AUTH-038` | No | — sin cambios |
| `AUTH-040` | No | — sin cambios |
| `AUTH-041` | No | — sin cambios |
| `AUTH-042` | No | — sin cambios |
| `AUTH-043` | **SÍ** | Contador de OTP de MFA condicional, separado de recuperación/contraseña/RATE-B2B-LOGIN; recurso canónico general pendiente de homologar. |
| `AUTH-044` | No | — sin cambios |
| `AUTH-045` | No | — sin cambios |
| `AUTH-048` | No | — sin cambios |
| `STATE-001` | No (VIGENTE) | — sin cambios |
## Reemplazo exacto, sin modificaciones de Supabase
El archivo `sandbox/lf_contract_gate_test/edge_function_operation/fixtures/login_b2b_lote2_conflict_only_patch_20261113.json` preserva los **cinco textos íntegros** (campo `proposed_description`), `config_patch`, `original_description`, justificación, códigos y SHA de origen (fila completa). `source_snapshot_20261113.json` conserva la preimagen completa de 32 filas con SHA calculado por PostgreSQL. Solo UPDATE de `descripcion` y merge JSONB `valor_config` para códigos 013,030,033,034,043 en Docker, dentro de transacción abortada con ROLLBACK.
## Riesgos y límites
- **AUTH-043:** el recurso `AUTH_NEW_DEVICE_OTP_SEND` y política 8 no son autoridad de MFA condicional general; la homologación del recurso y rate limit general debe resolverla Arquitectura/DBA antes de cualquier promoción. El nuevo marcador `PENDING_CANONICAL_MFA_EMAIL_OTP_RESOURCE` es **placeholder de bloqueo documental**, NO un código oficial activo.
- **AUTH-034:** las referencias antiguas a rate limit por nuevo dispositivo quedan deshabilitadas en propuesta, no suplidas sin fuente; requiere configuración de un contador MFA general homologado.
- **AUTH-013:** no se presupone IdP primario nuevo; pendiente ADR-003 M1.
- **AUTH-030:** la tabla `lf_ops.b2b_recovery_profile_permissions` es diseño del #3844, no se afirma desplegada; política20 approvers_required=1 inicial, permitido 1/2; sin selfie ni IDV inventado.
- **Otros:** ausencia de detalle no es contradicción; no ampliar alcance. `STATE-001` está **VIGENTE**, no es candidata editable.
- Solo la prueba CI Docker con hashes reales puede etiquetarse PASS. No hay QA E2E, no hay juez independiente, no hay escritura viva, no hay promoción.
