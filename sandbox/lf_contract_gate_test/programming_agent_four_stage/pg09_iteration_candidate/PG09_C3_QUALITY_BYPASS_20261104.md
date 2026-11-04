# PG-09_C3 — Protección contra atajos de calidad (candidato fuente, 2026-11-04)

## Contrato
La ruta crítica define **PG-09_C3** como: “Prohibido desactivar reglas, agregar supresiones sin waiver o borrar tests para pasar”. Su criterio de salida es **“Negativo → BLOCK”**. Fuente: `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`.

Este componente no escanea realmente los archivos ni ejecuta un Worker. Recibe declaraciones de cambios propuestas por el invocador, cuya identidad y autenticidad permanecen sin verificar.

## Implementación

Archivo: `tools/pg09_c3_quality_bypass_guard_candidate_v1.py`.

Función: `prepare_pg09_c3(pg07_c5, pg09_c2, quality_change_observations)`.

Reutiliza `PG07_C5_ITERATION_GUARD_CANDIDATE_V1` para las referencias exactas de cada propuesta y su diff; reutiliza `PG09_C2_CONVERGENCE_GUARD_CANDIDATE_V1` para conservar la misma secuencia de intentos. Los enlaces son SHA-256 de los sobres serializados y no equivalen a recibos de ejecución autenticados.

Cada observación debe asociar una solución e iteración existentes, mismo `diff_ref` y `diff_sha256` de PG-07_C5, y una lista de cambios declarados con tipo, ruta, referencia de evidencia, hashes anterior/posterior y referencias opcionales de waiver.

### Clasificación

- `RULE_DISABLE`: **BLOCK**. No se admite desactivar reglas para hacer pasar verificaciones.
- `QUALITY_GATE_BYPASS`: **BLOCK**. No se admite saltarse verificadores.
- `TEST_DELETE`: **BLOCK**. No se admite borrar pruebas para superar un gate.
- `SUPPRESSION_ADD`: `REQUIRES_WAIVER_VERIFICATION`. La presencia de un número o referencia de waiver **no** es suficiente para permitir la supresión: se requiere autoridad, alcance y vigencia comprobados.
- `NORMAL_CHANGE`: `NO_DECLARED_BYPASS_UNVERIFIED`, nunca permiso de escritura ni veredicto de que todo el diff sea seguro.

Los reportes rechazan registros duplicados, cambios sin relación con la iteración, referencias de diff incongruentes, rutas con traversal, hashes de formato incorrecto y una eliminación de test declarada que simultáneamente presenta un hash posterior.

## Riesgos deliberadamente no resueltos

1. **Clasificación declarada, no detección real**: un invocador malicioso podría llamar `NORMAL_CHANGE` a una supresión o a una eliminación de pruebas. Se necesita un juez determinista sobre el patch exacto y una revisión de los patrones de calidad aplicables.
2. **Reglas y waivers**: no se inspeccionan los contenidos ni vigencia de las reglas o de los permisos de excepción. Se requiere validación independiente.
3. **No bypass por refactor**: no se prueba si la eliminación aparente de una regla se escondió tras un renombre o cambio de archivo.
4. **Sin ejecución real**: ni los hashes reportados ni la estructura del sobre acreditan que ocurrió una edición del repo.
5. **Compatibilidad con C1 y C2**: esta proyección no autoriza reintentos ni reemplaza los límites de presupuesto o convergencia anteriores. Solo prepara una señal para el orquestador futuro.

La salida conserva `real_diff_scanned=false`, `ruleset_currentness_verified=false`, `waivers_authenticated=false`, `worker_execution_observed=false`, `quality_gate_bypass_allowed=false`, `retry_authorized=false`, `pg09_c3_pass=false`, `pg09_c3_admitted=false`, `handoff_allowed=false` y `production_authority=false`.

## Estado y continuación

**`PG09_C3_SOURCE_PREPARED / DIFF_NOT_SCANNED / NEGATIVE_TEST_NOT_EXECUTED / OFFICIAL_PENDING`**.

Pendiente para calificar: leer diff real exact-HEAD; identificar cambios en reglas, supresiones, tests y workflow de CI; ejecutar pruebas negativas que demuestren `BLOCK`; autenticar waivers; revisión independiente.

**Siguiente checkpoint: PG-09_C4 — Escalamiento tipado RETURN o BLOCKED con diagnóstico.**

Sin cambios a Análisis, Supabase, main ni el producto. El PR #3528 permanece en draft y las pruebas oficiales siguen pausadas.
