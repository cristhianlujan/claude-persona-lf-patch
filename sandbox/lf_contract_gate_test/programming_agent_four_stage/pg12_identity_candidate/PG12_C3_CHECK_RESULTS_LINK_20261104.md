# PG-12_C3 — Enlace de resultados de PG-08 y PG-11 (2026-11-04)

## Criterio oficial consultado
**PG-12_C3:** «Resultados de checks de PG-08 y PG-11 enlazados».
Criterio de salida PG-12: «La identidad del candidato puede reconstruirse sin inferencias posteriores». Estado oficial `PENDING`.

## Fuente candidata
`tools/pg12_c3_check_results_link_candidate_v1.py`, función `prepare_pg12_c3(pg12_c2, candidate_identity_sha256, check_observations)`.

La función reutiliza el sobre C2 y exige digest canónico, ausencia de autoridad y coincidencia exacta con el digest de identidad C1 registrado en C2. Cubre de forma explícita los **8 checkpoints PG-08_C1–C8 y los 5 PG-11_C1–C5**.

Cada fila reporta el identificador de checkpoint, la identidad del candidato, contrato aplicado, referencia al resultado, digest SHA-256 del resultado, ejecutor, estado observado declarado y referencia a recibo. Impide registros repetidos, checkpoints fuera del conjunto, vinculación con otra identidad candidata y falsos recibos para estados `NOT_RUN`. Para estados distintos de `NOT_RUN`, obliga a declarar un recibo y un digest, pero **no los autentica**.

## No-go técnico y deuda diferida
Los resultados `PASS`, `FAIL`, `BLOCKED` o `INCONCLUSIVE` son declaraciones del invocador; nunca equivalen a un dictamen independiente ni a evidencia del Worker. Este módulo **no ejecuta pruebas**, no verifica que los checks hayan corrido sobre el mismo Git HEAD ni consulta recibos, CI o almacenamiento.

La salida fija `real_checks_executed_by_this_component=0`, `verified_check_pass_count=0`, `all_check_results_verified=false`, `pg12_c3_pass=false`, `handoff_allowed=false` y `production_authority=false`.

Validaciones pendientes:
1. Contrastar el inventario de checks con el contrato real de PG-08/PG-11 y sus respectivos sujetos/verificadores.
2. Releer resultados, SHA, ejecutor, firma, snapshot de código y recibos desde fuentes autorizadas; calificar identidad exact-HEAD y frescura.
3. Probar negativos: resultado ajeno a candidato, check faltante, PASS inventado, recibo duplicado y resultado fuera de vigencia.
4. Obtener revisión técnica independiente y su dictamen sin promover estados por inferencia.

**Estado:** `PG12_C3_SOURCE_PREPARED / NO_CHECKS_EXECUTED / OFFICIAL_PENDING`.

**Siguiente:** PG-12_C4, persistencia y relectura real; puede prepararse un contrato de persistencia aislado sin efectuar escritura en Supabase ni sustituir al escritor gobernado.

PR #3528 continúa draft; no se modifican Análisis, Supabase, main ni código del producto.
