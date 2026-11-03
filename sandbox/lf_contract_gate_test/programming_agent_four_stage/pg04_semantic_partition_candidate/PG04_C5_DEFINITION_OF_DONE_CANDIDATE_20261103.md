# PG-04_C5 — Definition of Done por SOLUTION (2026-11-03)

**Estado:** `PG04_C5_SOURCE_CANDIDATE_IMPLEMENTED / UNIT_REGRESSIONS_ADDED / EXACT_HEAD_QUALIFICATION_PENDING / NO_GO_RUNTIME`.

## Fuente contractual y reutilización

- Registro checkpoint fuente `PG-04_C5`: «Definition of done por lote: los STD y checks que debe pasar», en `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`.
- Contrato de particiones `PROGRAMMING_SOLUTION_PARTITION_CONTRACT_V1`, PR #1912, Git blob `54ea02669c2f9ad199ac6fde154ec5dd30d6decb`. **PR #1912 aún abierto**, fuente candidata, no asumir que está liberado/current.
- Guía de validadores `docs/programming/PROGRAMMING_VALIDATORS_AND_RESOLVERS_GUIDE_V1.md`. Los validadores son **procedimientos reutilizables**; los inputs y recibos se obtienen por checkpoint/ejecución. El resultado previo nunca se hereda como PASS.
- Lectura read-only de `programacion.programming_validation_registry`: `PROGRAMMING_GITHUB_FILE_TEXT_ASSERT_V1`, `PROGRAMMING_GITHUB_FILE_SHA256_ASSERT_V1` y `PROGRAMMING_SUPABASE_CATALOG_ASSERT_V1` existen `ACTIVE`, `rule_mode=DETERMINISTIC` en el readback. El catálogo del builder todavía es un snapshot **suministrado por el llamador**, no comprobación live de estado/identidad.
- No se crearon jueces, validadores, resolutores, operaciones ni tablas nuevos. No se editó Análisis.

## Nuevo componente (solo Programación)

`tools/pg04_definition_of_done_candidate_v1.py` exporta `prepare_dod(partition, standards_catalog_version, standards, validation_registry, solution_plans)`, todo por argumentos explícitos. Su salida se liga al `candidate_sha256` exacto de una partición PG04 y produce `PG04_SOLUTION_DOD_CANDIDATE_V1`, siempre `CANDIDATE_NOT_ADMITTED`.

Por cada `SOLUTION`:
1. Comprueba que el estándar seleccionado exista en el manifiesto tipado y aplique a un `write_scope` de esa solución; **no descarga todo el documento** ni arrastra STD de frontend a una solución backend por defecto.
2. Requiere check explícito para **cada STD aplicable**; sin usar contenido del estándar como fuente vigente hasta una validación externa de `source_ref` y `source_sha256`.
3. Exige cobertura de `requirement_ids` mediante checks tipo `REQUIREMENT` y de `acceptance_ids` mediante checks tipo `ACCEPTANCE`.
4. Para `depends_on`, exige cobertura por `dependency_ids` exactos con checks tipo `DEPENDENCY`; no basta con un check genérico.
5. Cada check declara `validation_code`, `input_ref` y referencias exactas; el código de validador debe declararse `ACTIVE` en el manifiesto de registro, **cuya autenticidad todavía no está atestiguada**. El código de validador no prueba por sí solo que ejecuta la semántica necesaria para el tipo de check; eso requiere calificación posterior del binding.
6. Rechaza campos de entrada `PASS`, `done=true`, `receipt_id` y `current_release_verified` introducidos por quien crea el plan. No acepta checks vacíos, huérfanos, IDs duplicados, ni códigos/refs de otro lote.
7. Registra `status=PLANNED_NOT_EXECUTED` por solución y `status=NOT_EXECUTED`, `receipt_id=null`, `pass_claim_allowed=false` por check; `production_authority=false` y `handoff_allowed=false`.

Ejemplo de intención — **fixtures sintéticos, no estándares canónicos de LF**:

| SOL | write_scope | STD ficticios seleccionados | Cobertura de checks |
|---|---|---|---|
| `SOL-001` | `backend/api` + `database/migration` | `STD-API`, `STD-DB` | STD por scope, requisitos y aceptaciones del lote |
| `SOL-002` | `frontend/ui` | `STD-UI` | STD UI, requisitos/aceptaciones, check de dependencia `SOL-001` |

Se incluyó `tests/test_pg04_definition_of_done_candidate_v1.py` con **27 casos** positivos y negativos (revisar contador en ejecución real). No atribuir PASS sin ejecutar las suites en checkout exacto.

### Ejecución que debe calificarse

```sh
cd sandbox/lf_contract_gate_test/programming_agent_four_stage/pg04_semantic_partition_candidate
python3 -m unittest discover -s tests -p 'test_pg04_*.py' -v
```

Para cualquier ejecución de DoD real se requerirá: selección STD con currentness y scope atestiguados, código de validador y `validation_input` efectivo por check, prueba actual en ejecutor gobernado, recibo de ejecución, prueba de aceptación técnica competente y revisión independiente semántica cuando corresponda.

## Dependencias restantes

- **C5 no se cierra** con el nuevo anexo; es implementación offline de su planificador.
- A9 y estrategia PG03 todavía sin admisión productiva; PG04_C2/C7 sin juez semántico real, y no existe un sujeto de partición PG04 `EVIDENCE_LEDGER VERIFIED` leído en la última inspección.
- El manifiesto `standards` es aportado por caller; pueden faltarle STD obligatorios de otras autoridades, de modo que el 100 % que comprueba es **solo relativo al manifiesto recibido**, no universal/current.
- La correspondencia `validation_code` ↔ capacidad real para validar el test debe revisarse: un `GITHUB_FILE_TEXT_ASSERT` no prueba por sí mismo comportamiento end-to-end.
- No se toca `programacion.engineering_work_checkpoints` ni `main`.

**Siguiente paso:** pruebas exact-HEAD y revisión C5; después PG04_C6 con mecanismo existente `CONTEXT_BUDGET_GOVERNANCE`, sin reimplementar el presupuesto.
