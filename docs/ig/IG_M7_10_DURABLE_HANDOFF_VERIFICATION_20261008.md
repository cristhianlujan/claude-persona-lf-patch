# M7.10 — handoff persistente Curator → Validator

La comprobación de GitHub no modifica runtime ni migraciones. Se reutiliza `programacion.provenance_receipts` y el `run_id` para transferir de forma duradera la evidencia entre invocaciones.

La reparación requiere asociar el SHA canónico del grafo con la entrega verificada y comprobar la misma evidencia desde Validator. No declarar DONE sin prueba E2E y rollback.
