# PG-07_C6 — Evidencia candidata por lote del Worker

## Contrato oficial

PG-07_C6 exige evidencia por lote: **recibo sellado del Worker**, diff, inputs y STD aplicados. Su salida prepara el paquete de PG-12; no equivale a la admisión de PG-12 ni a un PASS de ejecución.

El contrato PG-12 pide además base SHA, árbol y SHA del candidato, digest del diff, paths/objetos afectados, identidad del builder, contexto y versiones, datos de consumo/costo, checks de PG-08 y PG-11, persistencia y readback exacto. **Esas responsabilidades siguen en PG-12.**

## Superficie de recibos preexistente

La migración `20260818205254_programacion_agent_task_pass_requires_context_bound_worker_receipt.sql` define `programacion.fn_guard_evidence()` para `VERIFIED_WORKER_RECEIPT` de `PROGRAMMING_AGENT_WORKER`, con enlaces al Context Pack v2, ejecución RUNNING, HEAD, snapshot, identidad de tarea, digest del recibo, manifiesto del oráculo y flags que prohíben commit/push/merge/producción por el Worker.

Esta implementación NO sustituye esos guardias ni registra directamente un `VERIFIED_WORKER_RECEIPT`. Las migraciones antiguas describen además Worker v10 especializado; no se asume que su runtime corresponda al Worker v0.8 de PG-07.

## Código añadido

`tools/pg07_c6_worker_batch_evidence_candidate_v1.py` expone:

`prepare_pg07_c6(pg07_c1, pg07_c2, pg07_c3, pg07_c4, pg07_c5, worker_batch_evidence)`

- Revisa hashes íntegros de C1–C5 y sus cadenas de procedencia.
- Exige cobertura una-a-una de las soluciones en C2–C5 y en el manifiesto de lotes.
- Congela referencias declaradas a ejecución, Context Pack, HEAD candidato, diff, paths modificados, entradas, reglas aplicadas, recibos de formateo, recibo del Worker y uso de tokens.
- Rechaza la declaración de reglas aplicadas que no pertenezcan al conjunto declarado en C4.
- Conserva bloqueos de presupuesto de C3, derivaciones pendientes a PG-10 de C5 y ausencia de recibos de formateo o consumo; no promociona otras soluciones a READY.
- Forma `PG07_C6_BATCH_EVIDENCE_MANIFEST_CANDIDATE_V1` con `candidate_sha256`, utilizable como **insumo no autenticado** para la preparación de PG-12.

## Diferencia entre propuesta y evidencia real

Todos los datos de `worker_batch_evidence` provienen del invocador. Esta función no puede asegurar que el Worker haya ejecutado una llamada, que el diff pertenezca al HEAD indicado, que las rutas permanezcan en write-scope, que las STD se hayan aplicado, que el coste sea auténtico ni que el recibo exista en el ledger.

Por eso devuelve siempre:
`receipt_guard_authority_executed=false`, `receipt_sealed=false`, `receipt_digest_authenticated=false`, `worker_invoked=false`, `pg12_admitted=false`, `dispatch_allowed=false`, `write_allowed=false`, `production_authority=false`, `handoff_allowed=false`.

No se remiten al Worker las referencias al oráculo oculto: C2 conserva el sobre del verificador por separado y C6 solo transporta referencias de trabajo permitidas. El runtime deberá comprobar efectivamente esa separación.

## Bloqueos reales

1. PG-04/05/06 y C1–C5 admitidos por sus mecanismos gobernados.
2. Worker v0.8 conectado al despachador real, con ejecución/recibos auténticos.
3. Guardias actuales de evidencias y recibo sellado, con readback.
4. Diff real, formateo, scope, STD y consumo comprobados contra el target exacto.
5. PG-12 construye/persiste el manifiesto final con checks PG-08/PG-11.

**Estado:** `PG07_C6_SOURCE_EVIDENCE_MANIFEST_PREPARED / RECEIPT_UNVERIFIED / WORKER_NOT_INVOKED / OFFICIAL_PENDING`.

No se ejecutaron pruebas por instrucción del Owner; no se modificó Análisis, Supabase o main.
