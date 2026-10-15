# LF Backoffice Empresa — Auditoría de parámetros y fuentes canónicas (2026-10-15)

**Ámbito:** `B2B_APP_SHELL`, `lf_ops.*`. Inventario fuente de Supabase, no certificación de runtime ni aprobación de políticas `CANDIDATO`.

## Autoridad y método

- Router `ACT-0001` resolvió `MIGRATION / UPDATE → ACTUALIZACION_DB_LF`, `READY_TO_EXECUTE`; política y contrato `CONTRACT-ACTUALIZACION-DB-LF-v0.1`.
- Secuencia obligatoria: Git migration → Train → merge exact-head → apply/ledger → readback Git=ledger=DB. No DDL ni actualización directa de BD.
- Prevenciones: `PRV-ARC-013` (no nueva fuente), `PRV-DB-GIT-FIRST-PERSISTENT-OBJECT-001`, `PRV-SEC-013` (anti-enumeración), `PRV-INPUT-GOV-DECISION-RULE-PROVENANCE-PARITY-001`.
- Inspección ejecutada: **153 reglas con código B2B-**, **79 validaciones vinculadas a campos B2B** (29 con `min/max/allowed`), **25 políticas de seguridad**, **2 políticas OTP**, **5 operaciones OTP**, **9 rate limits**, **10 políticas timeout**; total general de `lf_ops.reglas`: **578**. No se presume equivalencia B2B para registros REG_* de CLIENT_APP_SHELL.

## Distribución canónica existente — conservar

| Parámetro / capacidad | Autoridad `lf_ops` | Patrón de consumo |
|---|---|---|
| Caducidad, intentos y reenvíos OTP | `otp_politicas` | `otp_operaciones.politica_id`, lector `v_otp_config` |
| Variaciones OTP por operación | `otp_operaciones` | COALESCE(override, política base): sin duplicar cuando no existe override |
| Límites de solicitudes | `politicas_rate_limit` | IDs en reglas y `pantallas_politicas` |
| Timeouts y retries técnicos | `politicas_timeout` | referencia de política / operación; distinto del reintento funcional |
| Sesiones | `politicas_sesion` | referencia de política; no literales de frontend |
| Seguridad/almacenamiento | `politicas_seguridad` | referencia de ID numérico |
| Restricciones de formato/campo | `campos_validaciones` | validación específica; no tabla global nueva |
| Condiciones de aprobación por empresa | `politicas_aprobacion` | `company_id`, no valor global |
| Duración de dispositivo confiable por empresa | `empresas.trusted_device_duration_days` | tenant-scoped, no valor fijo |
| Monitoreo | `observabilidad_alertas.threshold_config` | separado de reglas de auth |
| Tokens de UI | `lf_design.*` | no trasladar a parámetros funcionales |

## Comprobaciones reales de recuperación

- `OTP_OP_B2B_AUTH_PASSWORD_RECOVERY_EMAIL` ID 5 y `OTP_OP_B2B_AUTH_SECOND_FACTOR_EMAIL` ID 4 enlazan a `otp_politicas.id=2`.
- Los overrides `expiracion_minutos/max_intentos/max_reenvios` de ambas operaciones están NULL; la vista `lf_ops.v_otp_config` resuelve los parámetros base: **5 min / 5 intentos / 3 reenvíos**.
- `RATE-B2B-PASSWORD-RECOVERY-OTP` ID 7: 6 solicitudes / 900 s, estado `CANDIDATO`; la regla `B2B-RULE-AUTH-042` lo referencia.
- `SEC-B2B-MFA-RECOVERY` ID 20 y `B2B-RULE-AUTH-020` ID 439 conservan `PENDING_FUNCTIONAL_DEFINITION_EMAIL_ACCESS_RECOVERY` y prohibición de bypass.
- Correo comprometido: el OTP enviado a ese mismo correo no constituye un segundo canal independiente. Debe requerirse procedimiento separado y auditable, cuyo método concreto sigue **PENDING_FUNCTIONAL_DEFINITION**. No se activan producción ni acceso.
- El registro semántico se incluye en la migración de esta rama; no modifica los límites actuales.

## Matriz de hallazgos configurables

| ID | Hallazgo | Fuente correcta / destino | Estado/acción |
|---|---|---|---|
| P-01 | `B2B-RULE-STORAGE-001` tiene `signed_url_ttl_seconds=300` duplicado | Ya existe `SEC-B2B-STORAGE-PRIVATE` ID **6** con TTL **300** | Migración propuesta: eliminar solo copia en regla y enlazar `security_policy_id=6`. Requiere Train/readback |
| P-02 | `currency_precision_decimals=2` repetido en `B2B-RULE-INSTALLMENT-001` y `B2B-RULE-INSTALLMENT-PLAN-001` | Validación monetaria empresarial / fuente de precisión aún por reconciliar | **PENDING_FUNCTIONAL_DEFINITION** de contrato consumidor. No crear tabla ni mover sin equivalencia |
| P-03 | `contextual_export_max_days=30` en `B2B-RULE-REPORTS-EXTRACTION-001` | Regla de exportación contextual B2B y módulo de extracción; autoridad parametrizada no identificada | Mantener candidata, resolver fuente/configuración y alcance real de Reportes antes de mover |
| P-04 | `installment_term_policy.default_max_installments=12` y conjuntos de ejemplo en `B2B-RULE-INSTALLMENT-PLAN-001` | Configuración por **empresa**, explícitamente pendiente de mapeo físico en la regla | No transportar ejemplos `[1,3,6,12]` como defaults de runtime; pendiente modelo autorizado |
| P-05 | `B2B_VAL_PAGE_SIZE_ENUM.allowed=[10,25,50,100]` | `campos_validaciones`, actualmente única validación enumerada | Si reusable en otras pantallas, verificar consumidor común; no hardcodear React |
| P-06 | Validaciones B2B de correo `max_length=254` en distintos campos | `campos_validaciones`: Login, Recovery, Usuario, Contacto | Son restricciones de campo; reutilizar lógica/validator, no crear fuente duplicada |
| P-07 | `B2B_VAL_MFA_ENROLL_CODE_REQUIRED` sigue mencionando `SUPABASE_TOTP` | Validación de enrolamiento heredado, flujo normal reemplazado por OTP correo | Auditar alcance/estado legacy antes de cambiar su semántica |
| P-08 | `REG_RATE_*` y `REG_SES_*` contienen números en otras reglas LF | Fuera del alcance B2B; son otro consumidor/dominio | No convertir en variables globales B2B por similitud |
| P-09 | `SEC-B2B-UPLOAD-HARDENING.max_size_mb_candidate=25` | Ya parametrizado en política seguridad ID de esa política | Consumir desde política en validación `B2B_VAL_FILE_SIZE`, ya usa `policy_code` |
| P-10 | `B2B_VAL_LOGIN_PASSWORD_REQUIRED.min_length=1` | Valida no-vacío; distinta de complejidad central `SEC-B2B-PASSWORD-CREDENTIAL.minimum_length=8` | No confundir ni igualar mecánicamente; implementar ambos de manera correcta |

## Regla transversal de programación (aplicable dentro de LF)

`pantalla → regla/validación → policy_id/operation_id → fuente canónica`. El frontend utiliza valores autorizados de lectura o proyección, nunca un constante local como fuente de verdad. Las reglas del producto LF permanecen en `lf_ops`; lecciones interproyecto en `transversal`; componentes y tokens en `lf_design`; gobernanza de ejecución en `programacion`.

**Invariante:** no duplicar parámetros si ya existe la política, no migrar una constante demostrativa o clave relacional como si fuese un umbral configurable. Los valores por empresa deben conservar alcance `company_id`, no convertirse en globales.

## Cierre exigido

1. Train clasifica y versiona la migración, comprueba permisos, CI exact-head y ejecución `ACTUALIZACION_DB_LF`.
2. Aplicación vía Train y ledger exact-version; comparar Git=ledger=DB; dos casos negativos: política no coincidente bloquea, y ruta de correo comprometido no autoriza bypass.
3. Resolver los pendientes P-02/03/04/05/07 por lote especializado y validación de consumidores. No afirmar cobertura completa del código hasta hacer auditoría de código y E2E.

**Límite de esta auditoría:** inventario de definiciones y patrones de configuración en BD; no certifica ausencia de literales en frontend/backend ni modifica las políticas todavía candidatas.
