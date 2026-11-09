# PG-10_C4 — Paquete de decisión humana (04/11/2026)

## Contrato canónico consultado
`PG-10_C4`: «Paquete de decisión (PROGRAMMING_HUMAN_DECISION_PACKET_V1): pregunta, opciones, recomendación, riesgo de no decidir, referencias y condición de reanudación; al resolverse se reanuda solo el scope afectado y lo demás READY sigue».

Criterio de salida de PG-10: Programación nunca redefine unilateralmente el objetivo para poder terminar.

## Implementación fuente
`tools/pg10_c4_human_decision_packet_candidate_v1.py` exporta `prepare_pg10_c4(pg10_c3, decision_observations)`. Produce una propuesta `PROGRAMMING_HUMAN_DECISION_PACKET_V1` por conflicto cuya ruta C3 sea explícitamente `HUMAN_DECISION_PACKET_CANDIDATE`.

Cada paquete exige una pregunta no vacía, por lo menos dos opciones únicas con consecuencias, recomendación vinculada a una de esas opciones, fundamento, riesgo de no decidir, referencias, alcance afectado y condición de reanudación. Registra por separado el scope READY no afectado. Rechaza superposición de ambas listas y paquetes para conflictos técnicos o huecos de evidencia/requisito.

C4 comprueba el digest de C3, exactitud del conjunto de soluciones y cobertura de conflictos humanos, duplicados y banderas de no autoridad. No admite que una recomendación se confunda con una decisión efectiva.

## Límites explícitos
- Ni la vigencia de una decisión previa ni la elegibilidad READY del scope se verifican en esta fuente. Deben verificarse mediante ledger y contexto reales antes de emitir una pregunta.
- `question_sent=false`, `decision_recorded=false`, `affected_scope_resumed=false`, `unaffected_ready_scope_executed=false`.
- Proponer una condición de reanudación no autoriza a reanudar ningún proceso. No se ejecuta el Worker, PG-03 ni el retorno a Fase 1.
- Los materiales son declaraciones del invocador; su digest garantiza consistencia interna, **no autenticidad de hechos externos**.
- `pg10_c4_pass=false`, `pg10_c4_admitted=false`, `handoff_allowed=false`, `production_authority=false`.

## Pendientes de calificación (deuda técnica diferida)
Pruebas unitarias y adversariales C1→C4 en HEAD exacto; validación de decisiones anteriores con fingerprint/scope/vigencia; verificación real de alcance afectado vs READY; control de repetición de preguntas y reanudación aislada; calificador independiente y evidencia de ejecución.

**Estado:** `PG10_C4_SOURCE_PREPARED / NOT_TESTED / NOT_QUALIFIED / OFFICIAL_PENDING`.

**Siguiente:** PG-10_C5 — aseguramiento con negativos. Mantener el PR #3528 en draft; sin modificar Análisis, Supabase, main o producto.
