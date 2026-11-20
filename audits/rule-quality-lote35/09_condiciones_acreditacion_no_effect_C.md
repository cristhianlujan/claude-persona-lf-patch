# L35 — Condiciones para demostrar «NO_EFFECT» automáticamente (43 RUN C)

**SELECT ejecutado:** 2026-11-13 14:52:51.310277 UTC, 43 IDs exactos. Consulta `05_class_C_extra_readonly_43.sql`, resultado RAW `06_class_C_extra_readback_43.json`.

| Resultado de 12 rutas locales | RUN | Veredicto |
|---|---:|---|
| Sin vínculo observado | 37 | NO_LINK_IN_CHECKED_PATHS, NO ES NO_EFFECT |
| Con vínculo local adicional | 6 | Reclasificación propuesta C→B |
| Efecto ausente acreditado exhaustivamente | 0 | PENDIENTE |

## Condiciones técnicas deterministas necesarias

1. `SINK_REGISTRY_COMPLETE`: registro oficial y firmado de **todas** las tablas, writers, destinos GitHub, storage, workers, Edge, n8n, colas, terceros, y rutas directas posibles por operación. Sin ello, no certificar NO_EFFECT.
2. `CONSISTENT_WATERMARK`: ventana de observación de todas las colas/ACK y sistemas con corte común, sin eventos en tránsito ni workers activos/fencing no reconciliado.
3. `DB_NEGATIVE`: cero commit/change-audit/WAL/PK con `execution_id`, parent, request/idempotency/dispatch key en todos los sinks DB declarados, no sólo cero registros de guard.
4. `EXTERNAL_NEGATIVE`: GitHub PR/commit/Actions/merge, servicios externos, workers y proveedores deben aportar readback negativo automatizado del mismo RUN y su alcance; que no exista log no basta.
5. `GUARDS_IDEMPOTENCY`: todas las reservas y guard SUCCEEDED/RESERVED/ABANDONED conciliadas; sin duplicados, ejecuciones hijas sin revisar ni ack pendiente.
6. `SIGNED_EVIDENCE`: recibo criptográfico verificable, hash de respuesta, identidad del servicio/custodio, autenticación del emisor y prueba independiente de integridad.
7. `INDEPENDENT_VERDICT`: sólo si 1–6 son completos y sin excepciones, emitir `NO_EFFECT_PROPOSED_BY_MACHINE`; nunca `SAFE_TO_RETRY` implícito. L28 G02 sigue requiriendo firma Ops/DBA y auditor para cierre oficial.

## Seis RUN con nueva evidencia (clase C del L34 no se altera retroactivamente)

- `EXEC-ASSURANCE-REDESIGN-EKB-CI-20260926-001` — 2 vínculo(s) local(es), revisar pasos/hijos antes de inferir ausencia de efectos.
- `EXEC-PACK-VALIDATION-REBIND-PR1128-20260927-001` — 9 vínculo(s) local(es), revisar pasos/hijos antes de inferir ausencia de efectos.
- `EXEC-RUNTIME-UPDATE-REENABLE-20260919-001` — 1 vínculo(s) local(es), revisar pasos/hijos antes de inferir ausencia de efectos.
- `EXEC-S30-LF-ASSURANCE-METHOD-V1-GATED-20260916-001` — 7 vínculo(s) local(es), revisar pasos/hijos antes de inferir ausencia de efectos.
- `EXEC-S30-LF-ASSURANCE-METHOD-V1-GATED-20260916-002` — 6 vínculo(s) local(es), revisar pasos/hijos antes de inferir ausencia de efectos.
- `LF-AUTOLEARN-RUN-20260901-037` — 8 vínculo(s) local(es), revisar pasos/hijos antes de inferir ausencia de efectos.

**Corte histórico L33 intacto.** 37 sin vínculo no equivalen a 37 sin efectos. Certificados automáticos emitidos: **0/43**. RUN reintentados/cerrados: **0**.
