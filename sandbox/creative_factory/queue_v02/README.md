# SALY · Cola global serial v0.2 / vínculo RUN–claim–entrega (candidato)

**NO DESPLEGADO · PR DRAFT #4616 · NO RENDER**. El esquema SQL todavía está en `sandbox/creative_factory/queue_v02`, no en `supabase/migrations`.

## Evidencia verificada

- **39/39 PASS**, PostgreSQL **17.12**, dos conexiones simultáneas, CI `45051926045`, job `137298706916`, SHA probado `6f7933ca4c90ef0a0413e5453a16f4b3d7c2f88d`. El código SQL y los tests se conservaron desde ese SHA; el workflow temporal se retiró después de la prueba.
- Se utilizaron **transcripciones** de `creative_run_guard_l1`, `creative_item_guard_l1`, `creative_order_close_guard_l1` y `creative_execution_policy_v1` extraídas de lectura de Supabase el 22/11/2026. **No es una restauración íntegra ni una copia byte a byte del esquema**.
- Los 39 PASS incluyen rechazo de RUN directo sin token, asociación inmutable `queue_claim_id`, estado `EJECUTANDO`/EXITOSO` por RPC controlada, QA independiente, comprobación de recibo, rollback, leases, dependencia, PENDIENTE excluido, cierre automático y concurrencia real entre procesos.
- El workflow temporal que ejecutó PG17 se retira del PR para respetar la gobernanza PASE. El registro de CI persiste en GitHub.

## Fuentes efectivamente leídas antes del lote

- `LF_resguardos_construccion.md` (adjunto en el proyecto): B1 esquema real primero, B6 procedencia no es calidad, B11 pruebas negativas por control, B13 límites en configuración, B25 error específico, B27 relojes y B30 registrar no es publicar.
- `AGENTS.md` main blob `18b0eee33f60021c54bf2d5cf7435cd45a2c0551` y `CLAUDE.md` main blob `df6c199c6d108b2e0a711f8b53a5aac23b1cdedb`: toda escritura vía PR, PASE y Merge Train; sin DDL directo.
- `skills/creative_factory/SKILL.md` main blob `be48e6d29decd0b4dc4ca55ef33d94de6a7682d0`: todavía `PLAN_ONLY/REVIEW_ONLY`.
- `sandbox/creative_factory/native_transport_capture_v1.py` main blob `b953181428661fb262869e8ee5d5e6c54841ab2a`: `validate_provider_ack` rechaza con `NATIVE_PROVIDER_ATTESTATION_UNAVAILABLE`. Una captura local NO acredita entrega de imagen.
- `saly.config_global` live (readback 22/11/2026): 25 filas, **0** con `scope='CREATIVE_FACTORY'`. El valor de prueba `LEASE_SECONDS=600` de la fixture es sintético y NO es una decisión operativa.

## Control de configuración agregado

- `creative_queue_claim_next_v1` verifica la política existente con `creative_execution_policy_v1` antes de reservar un ítem. Si falta un valor, devuelve el error específico `CREATIVE_CONFIG_MISSING:<KEY>`.
- `claim_next` y `heartbeat` obtienen `LEASE_SECONDS` desde la misma fuente versionada. Rechazan `CREATIVE_QUEUE_LEASE_POLICY_MISMATCH` ante duraciones distintas pedidas por el trabajador.
- La prueba real PG17 comprueba la ausencia de configuración, override rechazado, lease de fixture aplicado y renovación sin override. **La política CREATIVE_FACTORY debe definirse por ruta gobernada antes de cualquier activación**, sin trasladar valores de las pruebas.

## Esquema propuesto

- `saly.creative_queue_claims_v1`: una reserva global activa, dueño `worker_ref`, token único, vencimiento y estado.
- `saly.creative_runs.queue_claim_id`: FK única al claim. No modifica `input_snapshot`, que el contrato L2C exige inmutable.
- `saly.creative_queue_delivery_receipts_v1`: vínculo `claim_id + run_id`, referencia, hash y recibo de entrega.
- `saly.creative_queue_claim_next_v1`: admite solo ítems `LISTO` de pedidos autorizados con `queue_mode='SERIAL_V1'`.
- `saly.creative_queue_admit_run_v1`: requiere token activo y crea el RUN vinculado, sujeto a los triggers de Supabase.
- `saly.creative_queue_advance_run_v1`: transiciones de RUN verificando token y trabajador.
- `saly.creative_queue_record_delivery_v1`: registra un recibo vinculado exactamente al RUN EXITOSO.
- `saly.creative_queue_release_v1(DONE)`: requiere RUN EXITOSO asociado, ítem APROBADO por QA interno y recibo de entrega con referencia/hash coincidentes. Si todos los ítems obligatorios están listos, marca pedido `COMPLETADO` sin aprobación creativa humana.

## Comando aislado

```bash
export PGHOST=localhost PGPORT=5432 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=saly_queue_test
bash sandbox/creative_factory/queue_v02/test_pg17.sh
```

`test_pg17.sh` impide ejecutarse con otro nombre de BD, y la fixture ejecuta DDL destructivo **solo sobre la BD desechable**.

## Límites y condiciones antes de migración productiva

1. La skill oficial continúa `PLAN_ONLY/REVIEW_ONLY`: ninguna llamada real a proveedor de generación fue probada.
2. El **recibo de entrega es sintético en los tests**. Supabase solo valida referencia y hash; la verificación real de entrega debe venir de un adaptador confiable externo, que **aún no está conectado**. No declarar delivery real.
3. No conceder `GRANT EXECUTE` a runtime/app hasta revisar la identidad de los operadores y el código del transportador. Las RPC están revocadas a `PUBLIC`.
4. El productor debe comprobar token de fencing antes y después de hablar con proveedores externos; leases vencidos requieren reconciliación idempotente y bloqueo de entregas duplicadas.
5. Probar el **esquema completo** real PG17/ROLLBACK antes de convertir la candidata en migración `supabase/migrations`.
6. Sin aprobación del usuario posterior a la generación. `APROBADO` de ítem es **QA técnico interno**, no visto bueno del dueño.
7. No tocar ni cerrar pedidos previos en este lote. Refinamiento = nuevo pedido enlazado en un lote distinto.
8. La base actual no tiene la configuración operativa `CREATIVE_FACTORY`; el contrato falla cerrado. Los números de los tests no se trasladan a producción. La versión candidata no debe ir al Merge Train antes de resolver estas brechas. **PASE PASS no equivale a autorización de producción**.

## Estado

Código SQL+tests preparado y probado con fixtures. Falta integración del runtime/entrega real y ruta gobernada de migración, merge y readback.