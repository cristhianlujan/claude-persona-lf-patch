# PG-11_C1 — Higiene de diff final y alcance (04/11/2026)

## Fuente contractual oficial (solo lectura)
**PG-11_C1:** «0 archivos fuera de scope; 0 residuos (debug, código muerto, TODO sin ticket); dependencias y compatibilidad preservadas».

**Criterio de salida PG-11:** «Diff final no contiene cambios huérfanos, deuda inventada ni scope creep».

La consulta de checkpoints mostró PG-11_C1 a C5 en `PENDING`.

## Preparación fuente
`tools/pg11_c1_diff_hygiene_candidate_v1.py` exporta `prepare_pg11_c1`, que recibe un par de SHA base/HEAD, un manifiesto de diff declarado, un manifiesto de alcance autorizado, observaciones de residuos, dependencias y compatibilidad.

Compara rutas y tipos de operación sobre listas declaradas; prepara hallazgos tipados sobre:
1. Archivos fuera de alcance, archivos autorizados ausentes del diff y tipos de cambio discordantes.
2. Residuos reportados (`DEBUG`, `DEAD_CODE`, `TODO_WITHOUT_TICKET`) y referencia a ticket cuando existe.
3. Cambios de dependencias referenciados con baseline y evidencia reportada.
4. Superficies de compatibilidad reportadas (`API`, `SCHEMA`, `DEPENDENCY`, `RUNTIME`, `MODULE_CONTRACT`).

Rechaza duplicados, rutas no canónicas, referencias vacías, operaciones de rename mal formadas, ausencia de evidencias de compatibilidad y pares de SHA mal formados. Incluye digests de las observaciones, pero **esos digests no autentican el diff real**.

## Límite de autoridad (obligatorio)
- Este módulo es un **inventario de revisión**, no un escáner de Git ni de código.
- Con una lista declarada sin hallazgos **no** se puede concluir que haya cero archivos fuera de scope o cero residuos reales.
- No se leyó ni escaneó un diff final auténtico en esta implementación; tampoco se ejecutaron tests de compatibilidad ni verificación de lockfile.
- Incluso si no hay `blocker_hints` reportados, `clean_diff_verified=false`, `pg11_c1_pass=false`, `pg11_c1_admitted=false`, `handoff_allowed=false`, `production_authority=false`.

**Estado:** `PG11_C1_SOURCE_PREPARED / REAL_DIFF_NOT_SCANNED / NOT_TESTED / OFFICIAL_PENDING`.

## Deuda técnica diferida
- Conectar lectura de base/HEAD reales y todos los archivos modificados, incluyendo renames, y contrastar contra el scope auténtico versionado.
- Implementar scans de debug/código muerto/TODO sin ticket, criterios para falsos positivos, y evidencias reproducibles.
- Verificar compatibilidad con módulos vecinos, dependencias y lockfiles. Ejecutar pruebas adversariales exact-HEAD y revisión independiente.
- Asegurar que la calificación abarque el diff final del cambio (no una selección parcial presentada por el agente).

**Siguiente componente candidato:** PG-11_C2 — lenguaje y glosario, códigos de catálogo literales y textos no inventados.

PR #3528 continúa draft. Sin escrituras en Análisis, Supabase, main ni producto.
