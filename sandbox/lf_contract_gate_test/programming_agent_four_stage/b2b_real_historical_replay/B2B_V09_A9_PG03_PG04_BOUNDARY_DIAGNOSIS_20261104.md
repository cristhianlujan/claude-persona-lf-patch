# LF — Auditoría real de frontera A9 → PG-01 → PG-03_C8 → PG-04
Fecha: 2026-11-04. Repositorios: `cristhianlujan/claude-persona-lf-patch` (contratos/candidatos) y `cristhianlujan/libertad-financiera` (target histórico).

## 1. Entrada histórica auténtica

Supabase `private.lf_decision_context_asof_v1.context_id` = `38a8f5c8-a6f3-45d6-b1ee-823af130e647`.
- `subject_ref=B2B_APP_SHELL`, `subject_version=v0.9`.
- `context_sha256=5ed3ffd513e4caadc65a9cbfb5991b6f8caeac8f714bec2c95fab23849a16e10`, **idéntico** a `encode(sha256(convert_to(context_payload::text,'UTF8')),'hex')` comprobado en PostgreSQL vivo por SELECT.
- `snapshot.schema_version=PROGRAMMING_CONTEXT_SNAPSHOT_V1`, `package_readiness=PARTIAL_READY`, 9 scopes: READY S01/S02/S03/S04/S09; BLOCKED S05/S06/S07/S08.
- Sin dependencias bloqueadas entre los cinco READY históricos. `analysis_stop_rule.decision=STOP` con `decision_stable=true`.
- Snapshot conserva 6 requisitos y 10 frentes materiales. `scope_front_matrix=[]`, 0 filas y cinco scopes READY sin relación explícita en la matriz.
- `private.lf_programming_context_handoff_receipts_v1` contiene **0 recibos para el contexto**; total tabla también 0 en consulta contemporánea.
- Snapshot no posee `obligations`, `outcome_registry` ni `acceptances` aptos para el particionador PG04.

La versión v1.0 posterior del mismo sujeto tiene `NEED_MORE_EVIDENCE` y **0/9 READY**: v0.9 es un material **histórico de ensayo**, no autorización CURRENT.

## 2. Git objetivo / evidencia de ausencia de componentes

Target `cristhianlujan/libertad-financiera` commit base histórico `e3a116db67ff4637fdd6dee4fee150b96a4d959d`. Consultas GitHub de lectura comprobaron `package.json` (Next 16.2.10, TypeScript) y ausencia entonces de:
- `src/app/b2b/(portal)/layout.tsx`
- `src/components/b2b-shell/b2b-shell.tsx`
- `src/lib/b2b/session-context.ts`

La implementación posterior aparece en el PR histórico **#9**, merge commit `994bda4aac4f92ea40531a2e84fdad6765397e84`. El compare base→merge está a 14 commits delante, 0 detrás; hay 25 archivos afectados, incluidos B2B shell, estilos, rutas, tests y contextos. **No usar el diff posterior como entrada para fabricar estrategia.** Utilizarlo solo para una evaluación *a posteriori* del agente.

## 3. Contratos y productores realmente existentes

**No escribir otro adaptador PG03→PG04.** Ya existe:
- `pg03_strategy_candidate/pg03_handoff_boundary_v1.py` → `prepare_pg04_handoff`, productor del sobre `PG03_C8_PG04_HANDOFF_CANDIDATE_V1`.
- `pg04_semantic_partition_candidate/tools/pg03_pg04_exact_handoff_bridge_v1.py` → `partition_from_pg03_c8`, bridge del PR **#3534**.
- `pg04_semantic_partition_candidate/tools/pg04_semantic_partition_candidate_v1.py` → `partition_by_semantic_outcome`, particionador real candidato.

El bridge exige exact SHA de handoff/estrategia, `requirement_owners`, `acceptance_owners`, `solution_dependencies`, identidad de contrato y que los grupos de PG03 coincidan con los generados por PG04. Mantiene `pg03_source_authenticated=false`, `semantic_judge_executed=false`, `production_authority=false`, `dispatch_allowed=false`, `handoff_allowed=false`.

**Límite real del bridge:** `partition_from_pg03_c8` todavía requiere que el invocador suministre `obligations` y `outcome_registry` *tipados*. Ni el sobre C8 ni el snapshot B2B v0.9 contienen estos insumos en la forma de PG04. No inyectar outcome labels, `source_ref`, `risk_level`, `implementation_state`, `write_scope`, `acceptance_ids` o `bounded_reuse_assessment_ref` por inferencia. El particionador verifica estos campos y falla si faltan.

PG01 moderno necesita además `scope_front_matrix` coherente, recibo exacto de contexto, evidencia de currentness, `IMPLEMENTABILITY_SCHEMA_V1` completo y paridad A9→PG01. El documento existente `PG04_REAL_A9_PACKAGE_DISCOVERY_20261103.md` ya detectó que el implementability_schema histórico es incompleto y que no hay fuente A9 moderna admisible para los tres snapshots en Supabase. Este diagnóstico **confirma** el hallazgo, no crea otro criterio.

## 4. Evidencia SQL read-only reproducible

```sql
WITH c AS (
  SELECT context_payload AS p, context_sha256 AS stored_sha,
    context_payload #> '{extensions,programming_context_snapshot}' AS s
  FROM private.lf_decision_context_asof_v1
  WHERE context_id='38a8f5c8-a6f3-45d6-b1ee-823af130e647'::uuid
)
SELECT
  encode(sha256(convert_to(p::text,'UTF8')),'hex')=stored_sha AS sha_matches,
  s->>'schema_version' AS schema,
  s->>'package_readiness' AS readiness,
  jsonb_array_length(s->'scope_readiness') AS scope_count,
  (SELECT count(*) FROM jsonb_array_elements(s->'scope_readiness') v
   WHERE v->>'status'='READY') AS ready_count,
  jsonb_array_length(s->'scope_front_matrix') AS matrix_rows,
  s ? 'obligations' AS contains_pg04_obligations,
  s ? 'outcome_registry' AS contains_pg04_outcomes,
  (SELECT count(*) FROM private.lf_programming_context_handoff_receipts_v1 r
   WHERE r.context_id='38a8f5c8-a6f3-45d6-b1ee-823af130e647'::uuid) AS handoff_receipts
FROM c;
```

Resultado de lectura observado: `sha_matches=true`, `schema=PROGRAMMING_CONTEXT_SNAPSHOT_V1`, `readiness=PARTIAL_READY`, `scope_count=9`, `ready_count=5`, `matrix_rows=0`, `contains_pg04_obligations=false`, `contains_pg04_outcomes=false`, `handoff_receipts=0`.

## 5. Fallos / interruptores y siguiente tramo legítimo

| Frontera | Entrada | Resultado observado | ¿Admisión? |
|---|---|---|---|
| A9 histórico: lectura/hashes | payload real Supabase | `HISTORICAL_INPUT_INTEGRITY_PASS` | NO |
| PG-01 moderno: matriz | `scope_front_matrix=[]` | `BLOCK_SCOPE_FRONT_MATRIX_MISSING` (diagnóstico SQL) | NO |
| PG-01 moderno: autoridad/recibos | 0 handoffs y currentness histórico | `BLOCK_HANDOFF_RECEIPT_MISSING` (diagnóstico SQL) | NO |
| PG-03_C8 | candidato de estrategia con owners/coverage | **NOT_EXECUTED** sobre este paquete: falta entrada admitida | NO |
| PG-04 | obligations + outcome_registry | **NOT_EXECUTED** sobre este paquete: no existen entradas tipadas verificadas | NO |

`OFF` solo para **gates de autoridad del laboratorio**: se permite continuar inspección estructural con `SKIPPED_FOR_DIAGNOSTICS`, sin otorgar PASS. No desactivar paridad material ni forjar obligations. Si se pretende llegar a PG04, el productor de PG03 debe obtener del **Análisis moderno con fuentes acreditadas** los átomos/soluciones y outcome_registry con provenance real, o debe comprobarse que otro módulo upstream existente los produce. Un adaptador solo transporta y verifica, **no inventa datos**.

**Prueba siguiente de mayor valor**: solicitar un pequeño paquete A9 CURRENT completo a su productor, para el target exacto y scopes independientes; probar PG01 en entorno aislado y luego ejecutar los productores PG03_C8/PG04 con sus inputs tipados, registrando rechazo/éxito exactos. No habilitar Worker ni Testing si PG04 no produce una partición basada en fuentes verificadas.

## 6. Declaración de ejecución

Se ejecutaron **consultas SELECT reales en Supabase** y consultas GitHub de archivos/commits. No se invocó `partition_from_pg03_c8` con el paquete antiguo porque carece de entradas tipadas exigidas; no se atribuye PASS a productores PG03 o PG04. No hubo modificaciones en Análisis, Supabase, `main`, Worker, Testing, código PG existente o PRs previamente calificados.
