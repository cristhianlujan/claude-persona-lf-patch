# SALY · Cola global serial v0.2 — candidato

Estado: **NO DESPLEGADO / NO MERGEADO / NO AUTORIZADO PARA RENDER**.

Objetivo: implementar exclusión de un solo worker creativo de SALY a la vez, cubrir toda la vida de procesamiento (claim → brief → diseño → producción → QA interno → release) y cierre automático `COMPLETADO` sin esperar aprobación creativa del dueño.

## Archivos

- `001_saly_queue_serial_candidate.sql`: DDL de registro global de claims, índice de máximo un RUN activo, funciones de claim/heartbeat/release. Solo candidata, NO ejecutar en producción.
- `fixture_pg17.sql`: esquema sintético PG17 desechable y fixtures que simulan campos relevantes. **No es una copia íntegra de Supabase**.
- `test_pg17.sh`: pruebas SQL y 2 conexiones simultáneas de `psql`, incluidas prueba de rollback, reclamación de lease, token viejo, dependencias, RUN único, QA interno y cierre sin aprobación de usuario.
- `saly-creative-queue-pg17.yml`: job CI aislado PG17 sobre PR. No enlaza a Supabase.

## Comando de prueba real PG17 (solo BD desechable)

```bash
export PGHOST=localhost PGPORT=5432 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=saly_queue_test
bash test_pg17.sh
```

El script bloquea ejecución si PGDATABASE no es exactamente `saly_queue_test`. No usar contra producción.

## Puertas pendientes antes de merge o despliegue

1. PASS de PostgreSQL 17 real, con dos sesiones simultáneas. Los PASS de Python v0.1 no sustituyen la prueba.
2. Verificar compatibilidad con los triggers reales `creative_run_guard_l1`, `creative_item_guard_l1`, `creative_order_close_guard_l1` sobre una copia aislada de esquema (positivos + negativos + ROLLBACK).
3. Integrar **token de claim/fencing en el ejecutor y en la admisión de RUN**. El índice global bloquea dos RUN activos pero no evita por sí solo una llamada externa no autorizada fuera de la cola.
4. Definir renovación/caducidad de lease y despacho idempotente al proveedor; nunca liberar y volver a enviar si no se conoce el resultado de un proveedor anterior.
5. Integrar el proceso P01 de generación autónoma de brief, aún candidato; el SKILL oficial v0.12 sigue `PLAN_ONLY/REVIEW_ONLY`.
6. Aprobar migración y PR mediante PASE + Merge Train (un PR a la vez), readback de tablas/RPC al terminar.
7. No alterar pedidos reales `SALY_HOME_BATCH_001` o `SALY_HOME_TEMPLATE_AB_001` en este lote.

## Semántica

- `saly.creative_orders.COMPLETADO`: salida entregada y evidenciada para todos los ítems obligatorios; NO aprobación creativa del usuario.
- `saly.creative_order_items.APROBADO`: QA independiente interno; mantiene trigger real de QA.
- Falla de diseño/producción sin artefacto: `BLOQUEADO`, no `COMPLETADO`.
- Refinamiento: otro pedido ligado al original, fuera de la ejecución de esta migración.
- Máximo un claim `ACTIVE`, índice único global de RUN `EN_COLA/EJECUTANDO`.

## Riesgos conocidos

- Los leases son renovables y un worker aislado puede seguir ejecutando una solicitud externa aunque pierda el lease: integración del token de fencing antes de llamar/procesar proveedor es obligatoria.
- Las pruebas de fixture no demuestran por sí mismas la compatibilidad de todos los triggers y tablas de Supabase.
- Se requieren observabilidad, manejo de stale provider receipt e idempotencia antes del despliegue.