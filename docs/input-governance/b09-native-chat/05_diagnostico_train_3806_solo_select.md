# Train #3806 — discrepancia histórica de manifest/recibo (solo SELECT)
NO CORREGIR, REESCRIBIR, REINTENTAR NI CERRAR RUN.

Fuente: Supabase temporal `mhwmirqcgxxukpctffuv`, consulta SELECT de 2026-11-13, y GitHub Actions [Train run 43384804628](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43384804628).
RUN histórico `EXEC-DB-TRAIN-PR3806-20261113071927-R43384804628`, operación `ACTUALIZACION_DB_LF`, estado final `COMPLETED`. Proponente `LF_GOVERNANCE` (no decisor autenticado).

## READBACK comprobado
- `lf_router_scope_receipt_v1.issued_at` = `2026-11-13 07:20:21.409447+00`.
- `lf_operation_execution.updated_at` = `2026-11-13 07:20:49.285697+00`; `completed_at` = `2026-11-13 07:20:49.28751+00`.
- SHA del manifiesto actual: `dbd025406eebfff530c03b0e081c85d53b1c7d11b5a4a3af174f2e6ffd9417a0`.
- SHA del manifiesto capturado en recibo: `3e8f53e52372ec2f1e0ef7d9248c6dabaf055ad28698a5f76ab86e21c083c9b6`. Hashes distintos.
- **Verificación causal positiva SELECT:** `SHA256((manifest - 'closed_by' - 'closure_evidence' - 'operation_closed')::text)` = `3e8f53e52372ec2f1e0ef7d9248c6dabaf055ad28698a5f76ab86e21c083c9b6`, coincide 100% con valor capturado.
- El Train devolvió `TRAIN_EXECUTION_PATCH_RECORDED` y posteriormente `TRAIN_EXECUTION_COMPLETED`, además `PASS_EXECUTION_BOOKKEEPING` en run 43384804628.

## Causa y limitación
La huella se capturó cuando el manifiesto todavía no tenía `closed_by`, `closure_evidence`, `operation_closed`. El cierre posterior añadió estas tres claves, desplazando su SHA. El consumidor de recibos reconstruye la huella desde el manifiesto **actual**, y exige `status='IN_PROGRESS'`. Un RUN histórico `COMPLETED` y con fields de cierre nuevos no puede reutilizar sin violar estas condiciones.
La equivalencia SHA tras quitar exactamente esas 3 claves acredita el delta causal de bytes; no constituye autorización para editar, migrar o reinterpretar el recibo. Mantener incidente externo a B09 y a la rama de implementación del receptor.

## Decisión
NO_FIX_HISTORICAL. Registro documental; sin UPDATE, sin backfill, sin alteración de lease o estado de ejecución. Cualquier eventual contrato de historial de receipt requiere PR independiente, preimagen, autorización y readback propio.
