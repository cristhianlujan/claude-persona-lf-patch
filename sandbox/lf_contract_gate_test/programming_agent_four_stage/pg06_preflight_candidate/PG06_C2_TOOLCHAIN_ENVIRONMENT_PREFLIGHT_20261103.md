# PG-06_C2 — Validación candidata de toolchain y entorno (2026-11-03)

## Contrato y alcance

PG-06_C2 exige herramientas y entorno disponibles en las versiones del catálogo; en su descripción V1 enumera Maven/JDK, pnpm/Node y Docker Compose con PostgreSQL 17 + Floci. Si falta un requisito, debe devolver **BLOCKED_TOOL_UNAVAILABLE** (PRV-TOOL-004).

La definición está en `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`. En esta revisión no se identificó un catálogo versionado independiente que justifique asumir valores fijos para cada versión: **el componente no define versiones por su cuenta**, ni interpreta la mención ilustrativa del contrato como una autorización para inventar versiones.

## Implementación

`tools/pg06_c2_toolchain_environment_candidate_v1.py` expone:

`prepare_pg06_c2(pg05_exit, pg06_c1, toolchain_catalog, environment_observations)`

Exige:
- sobre PG05 → PG06 y resultado PG06_C1 candidatos, con SHA256 íntegros y vinculación cruzada;
- `target_binding` explícito de repositorio y SHA base, sin aceptar destino nulo;
- selección del catálogo con `catalog_ref`, `catalog_sha256`, `profile_ref`, y una fila por herramienta (identificador, componente, versión exacta, fuente y soluciones aplicables);
- observación del entorno del mismo repositorio y SHA, con disponibilidad `AVAILABLE`, `UNAVAILABLE` o `UNKNOWN`, versión reportada y referencia de evidencia;
- cobertura de todas las soluciones de PG-05 por al menos un requisito de herramienta.

No se infiere qué toolchain aplica a una solución: esa decisión debe venir del catálogo real y una selección explícita del perfil correspondiente. No se invoca Maven, JDK, pnpm, Node, Docker Compose, PostgreSQL o Floci, ni se modifica el entorno.

## Diagnósticos

- Si falta la observación, herramienta ausente, disponibilidad desconocida o versión diferente de la versión exacta seleccionada → `BLOCKED_TOOL_UNAVAILABLE`.
- Si el reporte declara `AVAILABLE` y la versión es exactamente igual a la del catálogo → `MATCH_REPORTED_UNVERIFIED`; esto solo refleja igualdad entre declaraciones no autenticadas.
- Los hallazgos se registran **por herramienta y por solución**; la ausencia de una herramienta para un lote no promueve otro lote a ejecución.
- Un destino sin `repo_full_name` y `base_head_sha` válidos provoca fallo estructural `PG06_C2_TARGET_BINDING_MISSING`, incluso si catálogo y observación contienen valores nulos.

El resultado `PG06_C2_TOOLCHAIN_PREFLIGHT_CANDIDATE_V1` mantiene:
`catalog_currentness_verified=false`,
`environment_currentness_verified=false`,
`toolchain_execution_verified=false`,
`toolchain_available_attested=false`,
`requirements_auto_inferred=false`,
`pg06_ready=false`,
`write_allowed=false`,
`production_authority=false`,
`handoff_allowed=false`.

## Desbloqueo real

1. Obtener el `target_binding` auténtico admitido para PG05/PG06.
2. Consultar el catálogo vigente autorizado y determinar los requisitos exactos por perfil y solución, sin asumir umbrales ni versiones.
3. Ejecutar sondas reales sobre el entorno de destino, registrar versiones observadas con origen, digest y recibos.
4. Verificar que las decisiones de PG-06_C1 y las observaciones del entorno sean CURRENT; no re-vincular a mitad de ejecución.
5. Ejecutar los controles de gobernanza y calificación de PG-06 antes de permitir trabajo en el target.

**Estado:** `PG06_C2_SOURCE_COMPARISON_READY / CATALOG_AND_ENVIRONMENT_UNVERIFIED / TOOLCHAIN_NOT_EXECUTED / OFFICIAL_PENDING`.

Las pruebas Python permanecen aplazadas por decisión del Owner. No se afirma PASS exact-HEAD ni instalación de herramientas. No se escribieron datos en Supabase, ni se tocó Análisis, `main` o un repositorio de destino.
