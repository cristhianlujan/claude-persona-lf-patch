# M10.7 — Pilot de snapshot en memoria, datos reales, lectura solamente

## Alcance y autoridad

- Contrato vigente: `docs/ig/IG_EXECUTION_SOURCE_CONTEXT_V1_G0.md` (blob `4e23b692f605f54766608c4f8f9eb35021ebf560`).
- Run histórico fuente `programacion.input_readiness_runs/933`: pantalla 43, version 19, contrato 5.13.1; `source_snapshot_sha256=0e542fbc90da9092ea20989bab49b746822286666b6c985d016ae4d04b1e3cce`.
- Cinco familias: ACTIONS, ANALYTICS, API_DATA_CONTRACT, APPLICABILITY_READINESS, ASSETS_ICONS.
- Reglas efectivas: 246; contratos fuente consultados: `INPUT_READINESS_CONTRACT` e `INPUT_GOVERNANCE_EXECUTION_CONTRACT`.
- No se ejecuta Curator ni Validator, no se crean runs ni se escriben datos de negocio, no se activan G3/CP3.
- EKB consultado antes: `IG-M107-ALL-STAGES-QUERY-INVENTORY-007`, `IG-M107-ATOMIC-MANIFEST-REPEAT-005`, `IG-M107-RUN-CONTEXT-CANDIDATE-G1-010`, `IG-M107-A3-EFFECTIVE-LINKS-MATERIALIZED-CANDIDATE-015`.

## Metodología y reproducción

Todas las lecturas se efectuaron con `supabase_read_only_user`, desde el mismo cliente de herramientas y dentro de cada pareja de mediciones.

**Baseline:** cinco solicitudes SQL secuenciales, una por familia. Cada solicitud resuelve todas las reglas mediante `programacion.fn_input_effective_rule_links_v1(43,'INPUT_GOVERNANCE')`, relee ambos `programacion.contratos` en `version_id=19`, consulta esa familia y la identidad fija del run 933; devuelve JSONB ordenado.

**Optimizado:** una sola solicitud SQL que devuelve el mismo conjunto de 246 reglas, ambos contratos, las cinco familias y la identidad del run. El cliente guarda una instantánea **inmutable en memoria JavaScript**, y todos los accesos de las cinco familias leen ese objeto sin volver a consultar Supabase.

Por cada corrida se compara exactamente la serialización JSON del objeto de identidad, reglas, contratos y familia entre los métodos. El segundo y tercer pares alternaron el orden de ejecución (snapshot primero, baseline primero), a fin de evitar depender de un orden fijo. No se comparten resultados de Validator.

| Pareja | Baseline: cinco consultas ms | Snapshot: una consulta ms | Comprobaciones de equivalencia |
|---|---:|---:|---:|
| 1 | 3032 | 627 | 20/20 |
| 2 | 3638 | 452 | 20/20 |
| 3 | 2832 | 536 | 20/20 |

- Medianas observadas: baseline 3032 ms, snapshot 536 ms. Ganancia relativa de medianas ~82.3%; **solo extracción/transporte de esta muestra**.
- La primera prueba comprobó `deepFreeze` del objeto y rechazo local de identidad `run_id=934` frente al `run_id=933` del snapshot.
- Los tiempos provienen de reloj cliente por ronda (incluyen herramienta/red/SQL/serialización), NO de un profiler interno de Curator/Validator.
- Cantidad de consultas por pareja: 5 → 1. **60/60** igualdades de identidad, reglas, contratos y familias en las tres parejas.
- El ensayo no aísla efectos de calentamiento/carga, no acredita distribución p90 del proceso completo ni reduce el SLO de 150 s.
- Este piloto **no implementa el mecanismo transversal en consumidores**, ni demuestra ahorro en los 122115 ms del DB_WRITE de Validator del run 933.

## Criterio de paso y continuación

**PASS solo del experimento de extracción y reutilización de entradas en memoria.** El siguiente checkpoint debe implementar el snapshot real en la ruta de consumidores (mantener decisiones Validator independientes y currentness necesario), instrumentar trabajo repetido y comparar el mismo caso baseline/optimizado con evidencia del runtime. No se autoriza un cierre CP3, un cambio de triggers ni habilitar G3 a partir de este microbenchmark.
