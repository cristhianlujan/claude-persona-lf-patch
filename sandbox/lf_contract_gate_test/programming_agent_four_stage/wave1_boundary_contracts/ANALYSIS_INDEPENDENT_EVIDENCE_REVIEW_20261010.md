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
