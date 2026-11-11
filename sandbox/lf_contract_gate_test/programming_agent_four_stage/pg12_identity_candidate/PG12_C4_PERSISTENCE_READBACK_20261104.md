# PG-12_C4 — Persistido y releído (04/11/2026)

## Contrato oficial (consulta en solo lectura)
**PG-12_C4:** «Persistido y releído». Criterio de salida PG-12: «La identidad del candidato puede reconstruirse sin inferencias posteriores». Estado oficial: `PENDING`.

## Preparación fuente
`tools/pg12_c4_persistence_readback_request_candidate_v1.py`: `prepare_pg12_c4(pg12_c3, storage_contract_ref, authorized_writer_ref, readback_contract_ref, record_key_ref, expected_store_namespace)`.

La función recibe el sobre candidato PG-12_C3 y comprueba su esquema, digest, ausencia de autoridad y cobertura declarada completa de PG-08_C1–C8 y PG-11_C1–C5. Congela un **payload candidato** con su digest SHA-256 y genera un **plan de comparación de relectura** que exige:
- Coincidencia de llave y digest del payload persistido.
- Misma identidad de candidato y cobertura de checks.
- Recibo de escritor auténtico y relectura independiente del almacenamiento.

## No-Go real
**No existe operación de escritura ni lectura de Supabase en esta implementación.** La referencia al escritor es una declaración no autenticada, no permiso para escribir. El esquema del payload es candidato, no una afirmación de compatibilidad con una tabla productiva.

Los campos de ejecución son incondicionalmente `write_attempted=false`, `persisted=false`, `storage_readback_attempted=false`, `readback_matched=false`, `readback_authenticated=false`; tampoco puede emitir un recibo sintético. `pg12_c4_pass=false`, `pg12_c4_admitted=false`, `handoff_allowed=false`, `production_authority=false`.

## Deuda técnica diferida
1. Localizar y validar contrato del escritor gobernado existente, sin crear segundo escritor ni sustituirlo.
2. Calificar identidad real Git, insumos y checks PG-08/PG-11 sobre SHA exacto.
3. Persistir mediante autoridad autorizada, capturar recibo confiable y releer por camino independiente.
4. Comparar contenido/candidate SHA/digest/llave, comprobar permisos, pruebas adversariales y calificación técnica independiente.

**Estado:** `PG12_C4_SOURCE_PREPARED / NO_WRITE / NO_READBACK / OFFICIAL_PENDING`.

**PG-12:** 4/4 componentes fuente preparados, 0/4 checkpoints oficialmente calificados.

**Siguiente etapa canónica:** PG-13_C1 — «Congelar el SHA exacto». El freeze es solo exactitud para Pruebas, no despliegue, runtime readiness, merge o activación.

PR #3528 permanece draft, sin cambios en Análisis, Supabase, `main` ni producto.
