# PG-11_C3 — Supresiones y waivers STD-GEN-05 (04/11/2026)

## Criterio oficial
**PG-11_C3:** «Toda supresión tiene waiver válido (STD-GEN-05)».
**Criterio de salida PG-11:** «Diff final no contiene cambios huérfanos, deuda inventada ni scope creep».
Consultado por lectura únicamente; estado oficial `PENDING`.

## Fuente candidata preparada
`tools/pg11_c3_suppression_waiver_candidate_v1.py` exporta `prepare_pg11_c3(pg11_c2, suppression_observations, waiver_observations, std_gen_05_source_ref)`.

Verifica el esquema, SHA-256 y estado no admitido de PG-11_C2. Recibe declaraciones tipadas de supresiones (archivos, renombres con retirada, código, pruebas, verificaciones o contratos) y de waivers asociados a STD-GEN-05. Detecta:
- Supresión declarada sin waiver.
- Waiver inexistente en el conjunto reportado.
- Waiver de otra ruta o de otra supresión.
- Estado declarado no aprobado, como PENDING/REJECTED/EXPIRED.
- Declaración APPROVED sin comprobación auténtica, que **no** autoriza supresión.
- Waivers declarados que no corresponden a ninguna supresión.

La existencia de un `waiver_ref` o un `approval_record_ref` **no** autentica que el waiver sea válido. El productor siempre emite `suppression_allowed=false` y `all_suppressions_authorized=false`.

## Límites y deuda técnica diferida
1. Leer el diff real e identificar exhaustivamente todas las supresiones, incluyendo eliminaciones parciales, cambios de renombre y borrado de tests, no depender de la lista del invocador.
2. Consultar la fuente canónica de STD-GEN-05 y comprobar waiver, alcance, firmante/autoridad, estado, vigencia, versión y efectos colaterales.
3. Probar negativos de waiver ausente, inventado, vencido, fuera de scope y con firma inválida, con ejecución reproducible y calificación independiente.
4. Integrar guardia con el mecanismo real de admisión antes de permitir supresiones.

Este código no modifica ni elimina archivos del producto, no ejecuta el Worker ni toca Análisis, Supabase o `main`.

**Estado:** `PG11_C3_SOURCE_PREPARED / WAIVERS_NOT_AUTHENTICATED / NOT_TESTED / OFFICIAL_PENDING`.

**Siguiente desarrollo:** PG-11_C4 — trazabilidad diff ↔ requisito ↔ lote. PR #3528 permanece draft.
