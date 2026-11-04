# PG-10_C3 — Ruteo tipado de decisiones (2026-11-04)

## Contrato oficial consultado (solo lectura)
**PG-10_C3:** «Ruteo: solo va a una persona la decisión verdaderamente humana; una decisión técnica → PG-03; falta de implementación → no es pregunta. Un hueco de evidencia o de requisito no se investiga aquí: con motivo tipado y resolver tipado se consulta lo exacto; si es investigación de requisito → vuelve a la Fase 1 (A3). Antes de preguntar se reutiliza una decisión vigente; prohibido preguntar dos veces».

Criterio de salida compartido PG-10: «Programación nunca redefine unilateralmente el objetivo para poder terminar».

## Fuente preparada
`tools/pg10_c3_typed_decision_routing_candidate_v1.py` expone `prepare_pg10_c3(pg10_c2, routing_observations)`.

- Verifica esquema, SHA-256 y falta de autoridad de C2; exige la misma cobertura de soluciones y de conflictos, sin faltantes ni duplicados.
- Distingue `HUMAN_DECISION` (preparar packet C4), `TECHNICAL_DECISION` (devolución candidata PG-03), `IMPLEMENTATION_MISSING` (trabajo de implementación, nunca pregunta), `EVIDENCE_GAP` (consulta exacta tipada) y `REQUIREMENT_GAP` (retorno candidato a Fase 1 A3).
- Para gaps exige `exact_query_ref`, `resolver_ref` y coherencia con el tipo de acción de C2.
- Cuando se declara `prior_decision_ref`, la propuesta es `CHECK_PRIOR_DECISION_CURRENTNESS_BEFORE_QUESTION`. **No** da por vigente ni reutilizada una decisión sin consultar el registro auténtico.
- Rechaza `prior_decision_current_verified=true` del invocador: nunca admite un testimonio autorreferencial como comprobante de vigencia.
- Ninguna salida contiene permiso de preguntar, enrutar, modificar requisitos o reanudar una ejecución.

## Límites y validación diferida
**SOURCE_PREPARED; NOT_TESTED; NOT_QUALIFIED; OFFICIAL_PENDING.**

Los tipos de problema son observaciones suministradas, no clasificación sobre un requisito real. Aún hace falta contrastar el registro canónico de decisiones (scope, versión, vigencia y fingerprint) y verificar bloqueo de preguntas duplicadas. Falta prueba exact-HEAD C1→C2→C3 con positivos y negativos; falta calificador independiente. No se ejecutó Worker, PG-03 ni Análisis.

Las rutas representan *solicitudes de acciones futuras*, no un resultado admitido. `human_questions_sent=false`, `pg03_dispatched=false`, `phase1_return_executed=false`, `pg10_c3_pass=false`, `production_authority=false`.

## Siguiente
PG-10_C4 — preparar `PROGRAMMING_HUMAN_DECISION_PACKET_V1`, incluyendo pregunta, opciones, recomendación, riesgo de no decidir, referencias y condición de reanudación; únicamente para situaciones clasificadas como humanas, sin emitirla ni bloquear el resto del scope READY.

**No se modificó Análisis, Supabase, main ni producto. Mantener PR #3528 draft.**
