# PG-06_C5 — Preparación de revisión independiente

El código `tools/pg06_c5_independent_assurance_request_v1.py` construye un paquete candidato con los hashes de PG05→PG06 y PG06_C1–C4. Conserva los hallazgos de toolchains, reversibilidad y build/lint por solución. Exige un manifiesto con referencia y digest de las fuentes.

El paquete **no** invoca `INDEPENDENT_ASSURANCE`, no certifica recibos del ledger, no crea ramas, no ejecuta Worker ni habilita escritura.

Para la revisión real se requiere verificar: PG05 admitido; decisión PG01 CURRENT; catálogo y herramientas reales; cobertura A7 y rollback; build/lint sobre un target sin cambios; independencia del revisor y recibo exacto VERIFIED.

**Estado:** `SOURCE_REVIEW_REQUEST_READY`, `OFFICIAL_PENDING`, `PG07_WORKER_DISPATCH_BLOCKED`.

Pruebas Python aplazadas por indicación del Owner. No se modifica Análisis, Supabase ni main.
