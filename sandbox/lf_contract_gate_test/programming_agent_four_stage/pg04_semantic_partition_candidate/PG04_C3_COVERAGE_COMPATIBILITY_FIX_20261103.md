# PG-04_C3 — corrección de cobertura por solución (2026-11-03)

## Hallazgo y corrección específica de Programación

En el PR #3528 se detectó una incompatibilidad entre dos componentes ya construidos:
- El productor `pg04_semantic_partition_candidate_v1.py` permite que un átomo tenga **solo** `requirement_ids` o **solo** `acceptance_ids` siempre que tenga al menos una obligación y que **el conjunto final cubra el 100 %** de ambas familias.
- El inspector `pg04_partition_admission_probe_v1.py` rechazaba cualquier `SOLUTION` cuyo array de requisitos o aceptaciones estuviera vacío, confundiendo **cobertura global** con **correspondencia local uno-a-uno**.

Se corrigió **el inspector existente** (sin duplicar motor ni alterar A1–A9):
- Dentro de una solución, `requirement_ids=[]` o `acceptance_ids=[]` pueden ser válidos **por separado**.
- Se prohíbe que **ambos** estén vacíos para una misma solución mediante `SOLUTION_WITHOUT_MATERIAL_OBLIGATION`.
- Las dos listas de la estrategia fuente siguen siendo **no vacías**; se exige cobertura exacta `set(req_owners)==set(strategy.requirement_ids)` y `set(acc_owners)==set(strategy.acceptance_ids)`.
- Se mantiene la propiedad fail-closed: sin dueños duplicados, sin orfandad global, sin autoridades concedidas.

## Pruebas añadidas

En `tests/test_pg04_partition_admission_probe_v1.py`:
1. Cuatro soluciones distribuyen las dos familias (requisitos solos/aceptaciones solas) y cubren 2/2 globalmente.
2. Solución con ambas listas vacías → `SOLUTION_WITHOUT_MATERIAL_OBLIGATION`.
3. Familia completa de requisitos ausente en estrategia → `STRATEGY_REQUIREMENTS_INVALID`.

En `tests/test_pg04_semantic_partition_candidate_v1.py`:
4. Pipeline productor→inspector donde algunos átomos tienen solo requisitos o aceptaciones, mientras la solución agregada y el plan completo conservan 100 % de cobertura, devuelve `CANDIDATE_NOT_ADMITTED`.

Los casos están presentes en GitHub; **no se atribuye PASS exact-HEAD a estas nuevas regresiones sin ejecución verificable**. El PASE anterior del PR (run #41713595075) fue SUCCESS, pero no prueba por sí solo que estas nuevas pruebas Python se ejecutaran. Verificar ejecución de `python3 -m unittest discover -s tests -p 'test_pg04_*.py' -v` en checkout exacto.

## Límite de este cambio

Esta corrección es para **PG-04_C3**. No autentica A9, no ejecuta jueces semánticos, no reemplaza el verificador independiente de C7, no altera `ANALYSIS_IMPLEMENTATION_PACKAGE_V1` ni perfiles de Análisis. No marca checkpoint como DONE, no genera ledger y no habilita runtime.

**Resultado:** `PG04_C3_LOCAL_INSPECTION_LOGIC_FIXED / NEW_REGRESSIONS_ADDED / EXACT_HEAD_QUALIFICATION_PENDING / NO_RUNTIME_AUTHORITY`.
