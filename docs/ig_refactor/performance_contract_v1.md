# INPUT_GOVERNANCE_PERFORMANCE_ASSURANCE_V1

Plan: `IG_CURATOR_VALIDATOR_REFACTOR_V2`  
Unidad: `M8.0 / PAULO-110`  
Owner: `SUPER_ADMIN`  
Estado del artefacto: contrato de gobernanza; **no cambia runtime, timeouts ni tuning**.

## Principio rector

Una optimización de Input Governance solo puede aceptarse cuando **performance mejora** y la evidencia de **correctness/readiness permanece equivalente o superior**. Performance nunca puede compensar un FAIL, una pérdida de oracle/evidence ni la omisión de Validator.

## Autoridades reutilizadas

- `TIMEOUT_PHASE_BUDGET_POLICY@1.0.0` — única política de presupuesto/timeout.
- `PERFORMANCE_EXACT_SOURCE_BENCHMARK@1.0.0` — único productor de receipts exact-source de performance.
- `M7.0 / Q_TAXONOMY_V1` — Q0–Q8 y modelo `dimension + property + oracle + expected + evidence`.
- `M7.3 / INPUT_GOVERNANCE_REGRESSION` — negativos gobernados; un `BLOCKED/UNPROVEN` legítimo no se convierte en PASS para acelerar.

No se crea evaluator, benchmark engine, cache engine ni política de timeout paralelos.

## Presupuesto obligatorio por pantalla

| Fase | Budget máximo |
|---|---:|
| CONNECT | 10 s |
| READ / preflight-currentness-source | 20 s |
| CURATOR | 30 s |
| VALIDATOR | 45 s |
| ORCHESTRATION / final readback | 15 s |
| **TOTAL** | **120 s** |

Límite Edge: **150 s**. Margen contractual: **30 s = 20%**.  
Objetivo de promoción: **p90 ≤ 100 s** en cada cohorte de pantalla afectada y en el agregado afectado.

`INFERENCE` no está presupuestado en M8.0. Si una optimización futura introduce esa fase, requiere revisión gobernada del contrato; no puede apropiarse silenciosamente del margen.

El estado AS-IS no cumple todavía el objetivo: T-PERF registró p90 global `184.5244698 s`, 8 pantallas con p90 por encima de 150 s y máximo `2163.317522 s`. Estos timings históricos son contexto factual, no benchmark exact-code retroactivo.

## Gates M7 no salteables

Toda optimización debe conservar todas las clases **aplicables** Q0–Q8:

- Q0 binding/provenance exactos.
- Q1 estructura/cardinalidad/source identity.
- Q2 parity/compatibility, sin confundir parity con correctness.
- Q3 semantic correctness mediante oracle independiente.
- Q4 coherencia cross-family.
- Q5 readiness/stage/blockers/N/A.
- Q6 resistencia a false PASS/bypass/missing evidence.
- Q7 currentness/lineage/replay/cache freshness.
- Q8 composición E2E/release assurance cuando el alcance llegue a promoción/release.

Baseline vivo al definir este contrato: **168/168** casos de `INPUT_GOVERNANCE_REGRESSION` con `q_class, dimension, property, oracle, expected, evidence`; distribución Q0=10, Q1=70, Q2=3, Q3=15, Q4=12, Q5=30, Q6=15, Q7=11, Q8=2. M7.3 aporta **91/91** negativos reconciliados.

### Validator es obligatorio

El Validator no puede omitirse, cortocircuitarse ni sustituirse por una conclusión del Curator. Un resultado rápido sin evidencia de ejecución del Validator es `FAIL`.

## Timeout y fail-closed

1. Cada fase usa `TIMEOUT_PHASE_BUDGET_POLICY` con el budget de este contrato.
2. Exceder budget produce `FAIL_CLOSED_WITH_FIRST_BAD_HOP_EVIDENCE`; no produce PASS parcial.
3. `NO_BLIND_TIMEOUT_EXTENSION`: subir timeout sin diagnóstico + receipt exact-source del mismo phase/source es `FAIL`.
4. Incluso con receipt válido, T-PERF solo puede producir `EVIDENCE_BOUND_EXTENSION_CANDIDATE`; requiere autoridad superior y **no muta** el timeout automáticamente.
5. UNKNOWN phase/currentness/freshness falla cerrado.

## Cache

Reuso permitido solo con identidad exacta de source y contrato, freshness/currentness válida, scope de cache gobernado y fingerprints/evidence preservados. Cache stale o currentness UNKNOWN => `FAIL`. La mejora no puede provenir de reutilizar evidencia vencida.

## Evidencia mínima de mejora válida

Una mejora candidata debe aportar simultáneamente:

- receipt `PERFORMANCE_EXACT_SOURCE_BENCHMARK` ligado al source exacto;
- cohort/workload igual o equivalencia gobernada explícita;
- call-count efectivo y prueba de que el harness no reevalúa trabajo oculto;
- timings por fase + total por pantalla;
- p90 por cada pantalla afectada + agregado afectado;
- resultados M7 Q0–Q8 aplicables con oracle/expected/evidence;
- evidencia de ejecución del Validator;
- currentness/cache-freshness;
- identidades exactas de source y contrato.

La optimización solo puede declarar PASS si: `performance mejora` **y** `p90 ≤ 100 s` **y** `total ≤ 120 s` **y** `assurance equivalente o superior`.

## Regresiones que invalidan

Cualquiera de estas condiciones invalida la optimización:

- Validator omitido/cortocircuitado.
- Cualquier Q aplicable omitida.
- performance PASS con assurance FAIL.
- `BLOCKED/UNPROVEN` convertido a PASS sin oracle autorizado.
- timeout aumentado sin evidencia/diagnóstico gobernado.
- cache stale/UNKNOWN reutilizado.
- promedio/p50 mejora pero p90 crítico empeora o supera 100 s.
- total >120 s o fase por encima de budget sin excepción gobernada.
- source/contract identity mismatch.
- harness con call-count o reevaluación no equivalentes.
- reducción del cohort de tests sin equivalencia gobernada.
- pérdida de metadata/oracle/evidence M7.
- debilitamiento de currentness/fail-closed.

## Pruebas negativas obligatorias

| Caso | Resultado |
|---|---|
| Reducir tiempo omitiendo Validator | FAIL |
| Subir timeout sin diagnóstico | FAIL |
| Reutilizar cache stale | FAIL |
| Mejorar promedio empeorando p90 crítico | FAIL |
| Performance PASS con assurance FAIL | FAIL |

## Alcance M8.0

Este contrato **no** autoriza ni ejecuta optimizaciones M8.x, no cambia funciones, Edge, roles, session/statement timeouts, cache runtime, deploy ni producción. Las unidades posteriores solo podrán optimizar bajo este contrato.
