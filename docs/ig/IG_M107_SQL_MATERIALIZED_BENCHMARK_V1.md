# M10.7 — prueba controlada de eficiencia SQL y `MATERIALIZED` (V1)

## Alcance y fuente

- Pantalla 43, run histórico 933, versión 19, cinco familias (`ACTIONS`, `ANALYTICS`, `API_DATA_CONTRACT`, `APPLICABILITY_READINESS`, `ASSETS_ICONS`).
- 246 reglas efectivas, dos contratos (`INPUT_READINESS_CONTRACT` y `INPUT_GOVERNANCE_EXECUTION_CONTRACT`).
- Sólo lecturas SQL con `supabase_read_only_user`; `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`, varias observaciones por variante y comprobación de igualdad `jsonb = jsonb` dentro de una sentencia.
- EKB previo: `IG-M107-ALL-STAGES-QUERY-INVENTORY-007`, `IG-M107-ATOMIC-MANIFEST-REPEAT-005`, `IG-M107-A3-EFFECTIVE-LINKS-MATERIALIZED-CANDIDATE-015`, `IG-M107-INMEM-SNAPSHOT-PILOT-022`.
- **No** cambia funciones, tablas, triggers, contratos de producto, runtime, Curator, Validator, CP3 ni G3.

## Diseño de las cinco consultas comparadas

El subquery caro de reglas conserva exactamente la autoridad existente:

```sql
SELECT regla_id, binding_source
FROM programacion.fn_input_effective_rule_links_v1(
  43, 'INPUT_GOVERNANCE'
);
```

Se añaden los dos contratos y las cinco familias del mismo caso, devolviendo siempre el mismo `jsonb_build_object` con siete campos: `rules`, `rule_count`, `contracts`, `contract_count`, `families`, `family_count`. La consulta no altera ninguna función canónica.

- **MULTI_MATERIALIZED:** `WITH r AS MATERIALIZED (...), c AS MATERIALIZED (...), f AS MATERIALIZED (...)`; cada CTE es consumida una vez para su JSON y otra para su conteo.
- **MULTI_DEFAULT:** misma consulta que MULTI, sin palabra `MATERIALIZED` explícita; PostgreSQL materializa automáticamente las CTE multirrefernciadas.
- **MULTI_NOT_MATERIALIZED:** misma consulta que MULTI, con `AS NOT MATERIALIZED`; el optimizador repite los cómputos.
- **ONCE_DEFAULT:** cada CTE es leída nominalmente una sola vez para armar un `jsonb_agg`; luego se forma un JSON con ese agregado y un `jsonb_array_length`. El plan observado volvió a evaluar el agregado/función.
- **ONCE_MATERIALIZED:** ONCE con `AS MATERIALIZED` explícito en las tres CTE.

Los filtros en contratos y familias se aplican antes de agregar. En producción, pantalla/run/versión/familias son **parámetros**, jamás constantes codificadas; el ejemplo 43/933 sirve únicamente como fixture de comparación.

## Resultados de ejecución SQL, no transporte externo

Tres observaciones calientes con orden alternado; tiempos `Execution Time` del propio PostgreSQL:

| Variante | Medición 1, ms | Medición 2, ms | Medición 3, ms | Mediana, ms | Nodos Function Scan en plan | Shared Hit Blocks |
|---|---:|---:|---:|---:|---:|---:|
| MULTI_MATERIALIZED | 40.661 | 38.714 | 38.856 | **38.856** | 1 | 3,458 |
| MULTI_DEFAULT | 40.936 | 39.475 | 41.362 | **40.936** | 1 | 3,458 |
| ONCE_MATERIALIZED | 48.207 | 44.922 | 44.001 | **44.922** | 1 | 3,481 |
| MULTI_NOT_MATERIALIZED | 154.985 | 156.285 | 150.886 | **154.985** | 6 | 12,713 |
| ONCE_DEFAULT | 159.576 | 152.833 | 161.187 | **159.576** | 6 | 12,712 |

En la primera pasada fría `MULTI_MATERIALIZED` registró 370.482 ms; NO utilizar sólo el mejor valor ni prometer una mejora de este tamaño siempre. La mediana caliente `MULTI_MATERIALIZED` frente a `MULTI_NOT_MATERIALIZED` reduce el tiempo SQL alrededor de 74.9% **en este caso específico**. CTE automática `MULTI_DEFAULT` ya tiene un plan eficiente; agregar la palabra `MATERIALIZED` **no** es necesario cuando PostgreSQL ya elige el mismo plan.

## Equivalencia verificable

En las cinco variantes:
- `md5(payload::text)` = `172b9f7661c8554757def6c2a0351e96`.
- `rule_count=246` y `family_count=5`.
- Comparación directa en la **misma sentencia** `(payload_materialized = payload_not_materialized) = true` y `(payload_materialized = payload_default) = true`, por igualdad JSONB (no sólo hash).
- No se omitieron reglas, contratos ni referencias de familias; son exactamente las mismas entradas.
- No se ejecutaron fases funcionales Curator/Validator, ni se probaron los negativos de identidad de runtime o la mejora en escritura/validaciones reales.

## Regla de selección y siguiente prueba

1. Repetir el plan en la consulta objetivo real; comparar buffers, número de evaluaciones, latencias frías/calientes y el costo de materializar.
2. Materializar **solamente** subconsultas costosas con reutilización efectiva cuando se demuestre ahorro. No añadir `MATERIALIZED` a todos los CTE porque puede impedir pushdown e incrementar trabajo o memoria.
3. Reducir N+1, usar índices existentes, seleccionar columnas/filas necesarias y conservar todos los controles semánticos.
4. Combinar la SQL ganadora con **una sola extracción por run** y el snapshot en memoria del contrato vigente.
5. Antes de G3: prueba integrada baseline/propuesta de Curator+Validator con mismo alcance, semántica igual, 0 falsos PASS, tiempos desglosados y sin ampliar presupuesto.

**Estado:** `PASS_SQL_EQUIVALENCE_AND_PLAN_MICROBENCHMARK_ONLY`. No significa mejora comprobada del runtime completo.
