# Análisis A1–A15 — comprobación independiente de la evidencia disponible

**Estado:** `NOT_OPERATIONALLY_QUALIFIED`. **Modalidad:** pruebas controladas offline en `scalora-vps`, directorios temporales aislados, sin despliegue de modelos, sin base mutada, sin ejecución de B2B, sin PG-01 real ni producción. **Alcance:** examen del método y de sus afirmaciones de evidencia; no una prueba de funcionamiento del agente desplegado.

## Fuentes exactas

- Plan ledger: `PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1` muestra **15/15 DONE**; indicador administrativo, no aprobación operacional.
- Source canónico en `main` de GitHub `cristhianlujan/claude-persona-lf-patch`, directorio `sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/`.
- Evaluador anterior `run_analysis_a14_candidate_v1.py`, Git blob `175f74dfb39952b730919d1bba230c05775075df`; scorer blob `39f4fd41fe68fcc1ded8cb1936b91e6cddb123ef`; validator `9d4432b79c6cddecea8aac077aa1fa4dd019e6f1`. Set `analysis_a14_fresh_cases_v1.json`, blob `463b22186f243496deb5c651cb246193a4d721a9`, 12 fixtures; oracle blob `b8b7ddc220b5530f9c847f3364c36b4f0ee71f26`.
- Reparación existente (NO DUPLICAR): Draft PR [#2071](https://github.com/cristhianlujan/claude-persona-lf-patch/pull/2071), rama `agent/programming-analysis-evidence-boundary-20261009`. Blobs del parche probados: runner `e48ed7f9e1216861fc0374b2b43681fab9026a58`; scorer `b6c361fb41526b52ea5169615a0a51f3548d5ca1`; validator `0167d817e21ffff74a50c92bc907cd0d94001e9d`; tests `857230e47aa13500306b646895cc04e522c45a6a` y `95af205885daf034c23bfc8832fba61d654a025a`.
- EKB aplicable: `PROGRAMMING-ANALYSIS-A14-EVIDENCE-TIER-FALSE-READY-001`, `PROGRAMMING-ANALYSIS-CONTEXT-SNAPSHOT-HANDOFF-001`, `PROGRAMMING-ANALYSIS-DEPTH-POLICY-UNDEFINED-001`, `PROGRAMMING-ANALYSIS-SPECIALIST-LATE-BINDING-001`. No cambiar el estado EKB desde una prueba de source.

## Ejecución real de esta revisión

| Ejecución | Resultado observado | Alcance |
|---|---|---|
| Runner A14 anterior + scorer anterior, corpus histórico | `PASS`, 12/12, clasificación 100%, usable 100% | Reproducción de contrato |
| Inspección de salida A14 anterior | `provider_response_id` 0/12, `exact_model_or_profile` 0/12; campos `requirements` y recibos persistidos 0/12; `source_read_count` declarado 68, lecturas externas observables no instrumentadas | NO inferencia real |
| Falsificación: conservar etiquetas oracle-friendly, quitar telemetría de lecturas/modelo y sin especificación/recibos | `PASS`, usable 100%, handoff parity 100% | **Demuestra un falso soporte operativo del PASS anterior** |
| Control negativo del scorer antiguo: quitar impacto crítico de resultado | `FAIL`, 1 omisión crítica | Sí detecta un tipo de error concreto |
| PR #2071 `test_analysis_evidence_boundary_v1.py` | `PASS_ANALYSIS_EVIDENCE_BOUNDARY`; 10 categorías reportadas, incluidos adulteraciones de digest, front contradictions, invalid provider claim y false ready | Validación del límite de evidencia |
| PR #2071 `test_analysis_pg01_snapshot_payload_v1.py` | `PASS_ANALYSIS_PG01_SNAPSHOT_PAYLOAD`; 1 positivo, 1 matrix assembler positivo, 2 negatives assembler, 14 negatives payload | Validación de estructura, NO PG-01 runtime |
| PR #2071 `validate_wave1_boundary_contracts_v1.py --self-test` | `PASS_WAVE1_BOUNDARY_CONTRACTS`, negativos=99 | Contratos A1–A9 |
| PR #2071 patched A14 runner+scorer, mismo corpus | `PASS`, pero `evidence_tier=DETERMINISTIC_CONTRACT_REPLAY` y `operational_integration_admissible=false` | Correcta delimitación de confianza |
| Inspección PR #2145 | `Draft`, no merge | Procedimientos definidos, no integrados |

**Técnica de aislamiento:** scripts Python existentes copiados a directorios temporales, modificación de objetos de resultado solo en memoria y re-ejecución de comandos, sin cambiar originales. Sin llaves/modelos externos invocados. El scorer `PASS` del parche no implica que el modelo haya analizado una solicitud.

## Decisión gobernada

**No autorizar `ANALYSIS_V1_OPERATIONAL_FROZEN`, READY operativo, ni PG-01/admisión de Programación**, exclusivamente por 15/15 DONE, por `A14 PASS`, por tests estructurales o por snapshot de ejemplo. Tampoco negar que los contratos estén completos como *fuente*.

### Tres evidencias pendientes (ninguna certificada por esta revisión)

1. **Ejecutor real**: identificar y enlazar exactamente el modelo/perfil de Análisis y ejecutar entradas frescas independientes vía la ruta gobernada, capturando respuesta efectiva, fuente consultada, versión exacta, identidad verificable del proveedor, tiempo/tokens y paquete tipado A1–A9. Sin autorizar runtime productivo; usar camino de evaluación controlado.
2. **Juicio independiente**: oráculo preparado aparte, muestras ocultas al candidato, contra-ejemplos positivos y negativos, cobertura de requisitos/impactos/frentes, dependencia, decisiones, falso READY, coste/latencia y over-search. Gates canónicos: 0 omisiones críticas, 0 false READY críticos, >=95% profundidad/clasificación, >=95% paquetes utilizables sin reinterpretación material. El juez no es el creador del paquete ni el replay.
3. **Consumo real por PG-01 en entorno controlado**: producir snapshot *real* inmutable de `DECISION_CONTEXT_ASOF@CURRENT`, lectura exacta por consumidor, parity `context_sha256`/schema/currentness, matriz front↔scope, zero rediscovery vigente y negatives de recepción. No usar fixture o `PG01` simulado como prueba de consumo.

**Estado medible:** definición A1–A9 9/9; ledger Análisis 15/15 DONE; verificaciones estructurales reproducidas PASS; **evidencias operativas 0/3 verificadas en esta ejecución**. El porcentaje de calidad operacional no puede calcularse con rigor hasta obtener respuesta y juicio reales. No inventar un 100%.

## Invariantes de siguiente paso

- Mantener PR #2071 como reparación exacta del evaluador, evitar un segundo scorer.
- Mantener PR #2145 fuente/procedimiento separada de implementación de producto.
- No construir soluciones ni tocar B2B por usarlo como ejemplo previo; seleccionar evaluación independiente del producto.
- No merge, migración, runtime productivo ni cambios de estados persistidos sin la gobernanza correspondiente.


## Macrolote de diagnóstico operacional — 2026-10-10

**EKB preflight:** se releyeron cuatro entradas activas de Análisis antes de las comprobaciones. `A14-EVIDENCE-TIER-FALSE-READY` sigue `ACTIVO`; ningún control estructural permite declararlo resuelto.

### 1. Servidor LLM y gobernanza

- Host conectado: `scalora-vps` vía SentinelX; **sin cambio de servicios**.
- API LF Profile Runtime local `http://127.0.0.1:8090/health` (consulta GET): `classification=INSTALLED_NOT_INTEGRATED_PENDING_LIVE_REVERIFY`, `operational_ready=false`, `downstream_authorized=false`; fuente `af6540c5757b39130c92a8ffd7a61d3cd7b8cb58`.
- El catálogo de perfiles actualmente visible en código tiene `product_director_lf`, `ui_architect`, `quality_pack` como bindings predefinidos; **no se identificó un binding de Agente de Análisis A1–A9**. No es lícito reclamar que `/v1/profile/execute` ejecuta el método A1–A9.
- Servidor LLM local ya cargado `127.0.0.1:8080`, modelo `/opt/profile-runtime-benchmark/model/model.gguf`, aproximadamente 3.09B parámetros, Q4_K. No se inició modelo nuevo.

### 2. Inferencia real aislada, NO ejecución admitida del Agente de Análisis

Primero una consulta de viabilidad local `/v1/chat/completions` devolvió HTTP 200, respuesta id `chatcmpl-mtRNjBI8KhAZyOYARhmZ4JAAD6N8Fe0L`, 126 tokens, 8.92s. Esto sólo demuestra el transporte de inferencia.

Segundo, se presentó una solicitud **sintética no B2B**: añadir exportación de actividad a un portal sin autoridad de permisos, retención ni formato. El system prompt incluyó resumen A1–A9 y la prohibición explícita de inventar decisiones. El servidor respondió HTTP 200 con `chatcmpl-OuR7cOuX0buEx2MYlZOrqLnS41KJLsLU`, `prompt_tokens=195`, `completion_tokens=96`, `total_tokens=291`, 11.0s. Respuesta:

```json
{
  "intent": "Add an option to users to export their activity in the account portal.",
  "depth": 1,
  "material_unknowns": [],
  "material_impacts": [],
  "required_decisions": [],
  "scope_readiness": "READY",
  "reason": "The request is clear and specific, requiring only the addition of an export option for user activity in the account portal. No additional decisions or external sources are needed."
}
```

**Finding: exploración modelo = FAIL_SEMANTIC_FALSE_READY.** Los vacíos materiales estaban expresamente señalados en el input; el modelo los omitió y proclamó READY. No es una inferencia del runtime gobernado, no se tomó ninguna decisión de producto ni se escribió en DB.

### 3. Reutilización del validador en PR #2071 (sin engine paralelo)

Se tomó la salida del modelo como candidato de ingreso:
- Payload bruto → `REJECTED_AS_REQUIRED: SNAPSHOT_PAYLOAD_SCHEMA` por `validate_programming_snapshot_payload_v1` exacto PR #2071, Git blob `0167d817e21ffff74a50c92bc907cd0d94001e9d`.
- Intento de envolver `READY` con schema `PROGRAMMING_CONTEXT_SNAPSHOT_V1`, sin `material_fronts`, `currentness_refs`, `source_refs` ni matriz → `REJECTED_AS_REQUIRED: SNAPSHOT_PAYLOAD_MATRIX_REQUIRED`.

**Alcance de resultado:** el validador existente bloquea la salida insegura. No prueba que el agente pueda descubrir los impactos sin un oráculo ni sustituye A1–A9.

### 4. Macrolotes y evidencia faltante

| Macrolote | Hallazgo verificable | Estado |
|---|---|---|
| M-A: preflight fuente/EKB y replay estructural | 15/15 ledger DONE; PR #2071 passes 99 negativos, A14 replay delimitado | `STRUCTURAL_CHECKS_PASS` |
| M-B: ejecutor real A1–A9 | LLM local responde, pero la API LF no está integrada y la respuesta sintética fue false READY | `BLOCKED_EXECUTOR_BINDING_AND_SEMANTIC_FAILURE` |
| M-C: juez independiente y holdout | El A14 histórico usó contract replay; no hay evaluación semántica admitida de outputs reales A1–A9 | `NOT_PROVEN` |
| M-D: handoff PG-01 | Validador source rechaza negativos; ningún consumo real de snapshot fue ejecutado | `NOT_PROVEN` |

**Admisión operativa:** `NOT_OPERATIONALLY_QUALIFIED`. La corrección PR #2071 y el procedimiento PR #2145 siguen Draft / sin merge. Cualquier porcentaje global de calidad operativa sería inventado. No realizar implementación B2B, no llamar PG-01 productivo ni aplicar SQL.

**Siguiente orden:** (1) enlazar el productor gobernado real de A1–A9 con fuente exacta y control de identidad, (2) preparar evaluación independiente a partir de familias/frentes derivados, no hardcoded de B2B, (3) generar y consumir receipt real de A9→PG-01 en sandbox, con controles de aceptación y rechazo. Si falla el modelo, remediar el método/evidencia general y revaluar, sin promover un PASS falso.
