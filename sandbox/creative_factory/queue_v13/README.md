# SALY · cola creativa serial — configuración inicial v13 (PR #4616)
Estado: **FUENTE CANDIDATA / SIN MIGRACIÓN APLICADA / SIN RENDER**.

## Parámetros seleccionados (solicitud del dueño, 22/11/2026)
No existen mediciones reales de latencia de generación Native/entrega para dimensionarlos. Los valores son una **selección técnica inicial conservadora**, no parámetros históricos ni tomados de fixture. Su implantación no acredita por sí sola integraciones Native.

| scope | config_key | valor | unidad | criterio |
|---|---|---:|---|---|
| CREATIVE_FACTORY | QUEUE_MAX | 1 | RUN en cola | Serialización; backpressure sobre recursos compartidos |
| CREATIVE_FACTORY | MAX_ATTEMPTS | 2 | intentos | Original + un reintento; reintentos visibles/no ilimitados |
| CREATIVE_FACTORY | QUEUE_TIMEOUT_SECONDS | 900 | segundos | 15 min máximo en cola; medir y calibrar |
| CREATIVE_FACTORY | LEASE_SECONDS | 600 | segundos | 10 min por worker; vencimiento recuperable, calibración requerida |

Autoridad para la **selección técnica**: pedido explícito del usuario de completar los cuatro parámetros del PR #4616. No atribuirle al usuario la elección individual de cifras ni indicar que están medidas.

## Contrato y seguridad
1. La fuente de verdad es `saly.config_global` con `scope='CREATIVE_FACTORY'`, `value_type=INTEGER`, `value_status=REAL`, versión `valid_from`; la función existente `saly.creative_execution_policy_v1(timestamptz)` es su lector.
2. Migración propuesta: `supabase/migrations/20261123020000_lf_saly_creative_factory_policy_seed_v1.sql`. Una sola transacción; no sobrescribe versiones, bloquea si hay políticas preexistentes o RUN activos, revalida las 4 claves e incorpora bloqueo de concurrencia. No contiene GRANT ni modifica pedidos/ítems/RUN.
3. `QUEUE_MAX=1` no asegura por sí mismo atestación, ni sustituye el lock global/fencing del candidato V02-V12; no es autorización para render, QA o cierre.
4. `LEASE_SECONDS=600` y `QUEUE_TIMEOUT_SECONDS=900` no son promesas de servicio. El runtime debe manejar vencimiento, retry y resultado ya entregado idempotentemente. No ampliar tiempos para ocultar errores sin métricas.
5. El PR #4629 ya implantó `TERMINADO` para cinco imágenes históricas; V12 en este PR sigue usando la semántica anterior `APROBADO` / alias `TERMINADO`. **No fusionar #4616** hasta reconciliar explícitamente ambas puertas y validar entorno real sin regenerar los cinco PNG.
6. Persisten las brechas de autoridad Native real, readback host/bytes y escritor confiable de atestación VERIFIED. Una migración de valores no resuelve estas brechas.

## Pruebas
`PGHOST=127.0.0.1 PGDATABASE=saly_policy_test bash sandbox/creative_factory/queue_v13/test_policy_pg17.sh`

La prueba usa PostgreSQL 17 desechable; incluye aplicación positiva 4/4, replay exacto, alteración de valor con rollback, RUN activo, función ausente, y dos clientes concurrentes con un único ganador. **No afirmar PASS hasta ejecutar CI real y conservar el run/SHA.**

## Pendientes de activación
- Router ACT-0001 para la operación concreta, PASE y Merge Train; la lectura actual del Router devolvió un bloqueo semántico de objeto, por lo que **sin etiqueta de merge**.
- PG17 con esquema real fiel + prueba de compatibilidad con guard L1 y estado `TERMINADO`.
- Integración confiable del modelo y mensaje de entrega al usuario, junto con evidencia de bytes e identidad.
- Sin pruebas end-to-end reales y reconciliación de TERMINADO, mantener DRAFT.
