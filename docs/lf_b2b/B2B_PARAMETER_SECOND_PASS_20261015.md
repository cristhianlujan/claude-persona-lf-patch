# LF Backoffice Empresa — Segunda pasada de configuración (2026-10-15)

## Estado y alcance
Auditoría read-only de `lf_ops`, con EKB consultada antes de proponer cambios.
Ruta canónica: `ACT-0001 / MIGRATION UPDATE / ACTUALIZACION_DB_LF`, `READY_TO_EXECUTE`.
No se ha aplicado la migración de esta rama: PR bloqueado en la conexión GitHub y falta Train, ledger y readback. No declarar PASS runtime.

## Verificación EKB
- `PRV-ARC-013`: buscar estructuras existentes antes de diseñar tabla.
- `PRV-DB-GIT-FIRST-PERSISTENT-OBJECT-001`: ningún DML persistente fuera de Train.
- `PRV-GOVERNED-PATH-WRITE-AUTHORITY-001`: no declarar operación sin recibo.
- `PRV-INPUT-GOV-DECISION-RULE-PROVENANCE-PARITY-001`: coherencia con decisión fuente.
- `PROGRAMMING-TARGET-AUTHORITY-IMPLEMENTATION-STATE-SPLIT-001`: autoridad en DB ≠ código runtime implementado.

## Verificaciones y resolución por hallazgo

| Hallazgo | Evidencia actual Supabase | Disposición |
|---|---|---|
| TOTP legado | `B2B-AUTH-005` ID55 `VIGENTE,activa=true`; ruta 14 `CANDIDATO`; `B2B_VAL_MFA_ENROLL_CODE_REQUIRED` `CANDIDATO` `provider_validation=SUPABASE_TOTP`; regla `B2B-RULE-AUTH-035` ID454 `RETIRED_LEGACY_TRACE_ONLY`, `activation_authority=DENY`; `SEC-B2B-MFA-FACTOR-ELIGIBILITY` ID19 `LF_EMAIL_OTP`. | Migración candidata en esta rama: pantalla `REEMPLAZADO/activa=false`, ruta `INACTIVO`, validación `DEPRECATED` sin binding proveedor obsoleto. Sin borrar historial ni modificar MFA |
| Precisión monetaria | `B2B-RULE-INSTALLMENT-001` y `B2B-RULE-INSTALLMENT-PLAN-001` tienen `currency_precision_decimals=2`, ambas `CANDIDATO`. `B2B_IMP_VAL_INSTALLMENT_SUM` ID88 sigue `tolerance_policy=PENDING_DECISION`, aunque la regla candidata describe exactitud después de normalizar a dos decimales. | Pendiente establecer proyección única de la regla a la validación con contrato de consumidor existente; no inventar nueva tolerancia ni tratar regla candidata como VIGENTE |
| Extracción 30 días | `B2B-RULE-REPORTS-EXTRACTION-001` tiene `contextual_export_max_days=30`, `CANDIDATO`. `B2B_REPORTES` es módulo `CANDIDATO, is_active=true`, sin pantalla B2B_REPORTES en `lf_ops.pantallas`. | No hardcodear 30 en UI; definir autoridad configurable del horizonte y contrato de descarga por módulo antes de materializar reportes |
| Máximo de cuotas | `B2B-RULE-INSTALLMENT-PLAN-001` establece `default_max_installments=12` y ejemplos, pero `company_plan_config_physical_status=PENDING_NO_CANONICAL_COMPANY_PLAN_CONFIGURATION_STRUCTURE_FOUND`. | Mantener pendiente de modelo físico empresarial autorizado; no activar arrays de demostración como defaults; ningún límite global reemplaza configuración por empresa |
| Duración dispositivo confiable | `SEC-B2B-TRUSTED-DEVICE` ID25 `CANDIDATO` contiene `trusted_device_duration_default_days=30`, `trusted_device_duration_allowed_days=[7,15,30,60,90]` y `trusted_device_duration_source=lf_ops.empresas.trusted_device_duration_days`. `B2B_VAL_TRUSTED_DEVICE_DURATION_ALLOWED` `ACTIVO` repite `default_value=30`, `allowed_values=[7,15,30,60,90]` y además `policy_code=SEC-B2B-TRUSTED-DEVICE`. | Candidato a reducir validación a referencia `policy_code` si contrato consumidor realmente resuelve la política; comprobar primero que no se rompen formularios activos |

## Preflight de migración TOTP (consulta read-only)
- Identidad pantalla/estado/descr. candidata: 1/1.
- Ruta 14: 1/1.
- Validación con proveedor obsoleto: 1/1.
- Regla legado `activation_authority=DENY`: 1/1.
- Factor alternativo LF_EMAIL_OTP en política 19: 1/1.
- Negativos simulados: si falta pantalla o autoridad, el preflight lógico devuelve false.
- La pantalla actual ID54 de verificación por correo continúa activa; no existe ruta TOTP VIGENTE.
- No equivale a una prueba real `BEGIN/ROLLBACK` ni al readback de Train.

## Regla de arquitectura para programación
Se consume `Backoffice → módulo → pantalla → regla/validación → policy_id`, no se copian valores de seguridad a componentes frontend; las capacidades server-side hacen enforcement. Parámetros empresariales conservan `company_id`. Los estados `CANDIDATO` no se promocionan por existir.

## Pendientes
1. Recuperar PR para la migración de retiro de TOTP **por una ruta admitida**, sin repetir ni eludir un bloqueo de seguridad de herramienta.
2. Probar transaccionalmente con rollback autorizado y postcondiciones; Train exact-version; readback Git=ledger=BD.
3. Verificar implementación de consumidor de duración de dispositivo confiable antes de deduplicar.
4. Reconciliar reglas monetarias con validador, configuración por empresa y extracción histórica; nuevos changesets por alcance, no mezclar dominios.
