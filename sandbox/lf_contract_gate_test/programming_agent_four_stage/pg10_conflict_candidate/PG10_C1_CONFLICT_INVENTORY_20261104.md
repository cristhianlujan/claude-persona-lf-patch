# PG-10_C1 — Inventario tipado de conflictos (2026-11-04)

**Mandato oficial:** “Detección de conflictos requisito ↔ estándar ↔ contrato existente ↔ REUSE_AS_IS del spec”. Criterio de salida: **Conflicto tipado**. Fuente: `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`.

## Preparación fuente

Se incorpora `tools/pg10_c1_conflict_inventory_candidate_v1.py` con `prepare_pg10_c1(pg07_c5, pg09_c4, conflict_observations)`.

El productor reutiliza la propuesta de alcance de PG-07_C5 y los motivos de escalamiento de PG-09_C4, verificando sus huellas SHA-256 y el conjunto de soluciones. No crea un nuevo despachador ni modifica la fase de Análisis.

Para cada conflicto declarado exige un identificador, clasificación de pareja, tipo de problema, referencias a fuentes, evidencias y diagnóstico. El tipo de pareja distingue requisitos, estándares, contratos existentes y la instrucción `REUSE_AS_IS`.

Distingue tres clases de problema:
- `CONFLICT`: requiere dos fuentes contrapuestas explícitas; la resolución/precedencia queda sin decidir.
- `EVIDENCE_GAP`: marca `QUERY_EXACT_MISSING_EVIDENCE`, sin investigar unilateralmente.
- `REQUIREMENT_GAP`: marca `RETURN_PHASE1_A3`, indicando la futura ruta de regreso a Análisis, pero **sin ejecutarla**.

Los campos son suministrados por el invocador. Ningún documento real es consultado ni comparado por esta fuente: la ausencia de conflictos declarados **no significa ausencia real de conflictos**. Tampoco puede inferirse si una discrepancia requiere decisión humana o técnica sin consultar el material autorizado.

## Qué queda para el checkpoint real

1. Comparación exacta de requisito, STD, contrato vigente y spec `REUSE_AS_IS`, usando versiones y referencias auténticas.
2. Calificación de incompatibilidad y alcance sin alterar la fuente de Análisis.
3. Distinguir hueco de evidencia, hueco de requisito y conflicto verificable.
4. Entregar el resultado tipado a PG-10_C2/C3 para precedencia y ruta, sin pedir decisiones duplicadas.
5. Pruebas adversariales y dictamen independiente.

**Estado:** `PG10_C1_SOURCE_PREPARED / REAL_CONFLICT_DETECTION_NOT_EXECUTED / OFFICIAL_PENDING`.

La salida mantiene `analysis_modified=false`, `real_spec_scanned=false`, `real_contract_scanned=false`, `conflict_detection_authenticated=false`, `precedence_decided=false`, `owner_question_sent=false`, `pg10_c1_pass=false`, `pg10_c1_admitted=false`, `handoff_allowed=false` y `production_authority=false`.

**Siguiente:** PG-10_C2 — precedencia y prohibición de renombrar legado sin migración aprobada.

No se modifica Análisis, Supabase, `main` ni producto. PR #3528 continúa en draft; pruebas oficiales pausadas.
