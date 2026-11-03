# PG-04 — partición semántica candidata y preflight de revisión (source-only)

Se reutilizan **los contratos ya existentes** del PR #1912 y los criterios semánticos de atomicidad/trazabilidad de J02 como referencia; **NO** se copia el juez visual J02 ni se crea un orquestador adicional.

## Archivos

- `tools/pg04_semantic_partition_candidate_v1.py`: transforma obligaciones tipadas con resultados de negocio y `source_ref` en lotes `SOLUTION` coherentes y dependencias DAG. No infiere resultados desde texto libre. La procedencia de `outcome_id` es externa y sin atestación.
- `tools/pg04_partition_admission_probe_v1.py`: **sonda de forma** de soluciones externas: policy, digest PG03, cobertura, delta EXISTING/reuso NEW, shared-contract refs, DAG.
- `tools/pg04_independent_review_request_v1.py`: congela el digest exacto de una partición candidata y el manifiesto de cinco fuentes para **solicitar** revisión por el mecanismo existente `INDEPENDENT_ASSURANCE`. No ejecuta un juez, no autentica fuentes, no llama Supabase ni concede autoridad.
- `tests/`: regresiones de productor, sonda y preflight de revisión.

## Pruebas offline (sin proveedores ni base de datos)

```sh
cd sandbox/lf_contract_gate_test/programming_agent_four_stage/pg04_semantic_partition_candidate
python3 -m unittest discover -s tests -p 'test_pg04_*.py' -v
```

Se recomienda la ejecución exacta en la rama y el CI. Las pruebas de partición anteriores pasaron en el sandbox, pero **el conjunto total en esta nueva ruta aún requiere calificación exact-HEAD independiente**.

## Fuentes y restricciones

- Contrato canónico PG04 `PROGRAMMING_SOLUTION_PARTITION_CONTRACT_V1`: PR #1912, `sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/programming_solution_partition_contract_v1.json`, Git blob `54ea02669c2f9ad199ac6fde154ec5dd30d6decb`.
- Criterios PG-04_C1…C7: `supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql`.
- Procedencia de los criterios J02: `skills/creating-integral-user-stories/references/screen-decomposition-protocol.md`; su runtime es de descomposición de pantallas **y no equivale a particionador PG04**.
- Componentes de Assurance existentes PG03_C9: PRs #3523/#3524, `INDEPENDENT_ASSURANCE`, `REVISION_INDEPENDIENTE_ESTRATEGIA_LF`. El preflight específico de PG03 solo admite `PG03_TECHNICAL_STRATEGY` y **no autoriza** un nuevo sujeto PG04.

## Limitaciones de cierre

`CANDIDATE_NOT_ADMITTED` obligatorio. `semantic_judge_executed=false`, `source_readback_verified=false`, `ledger_receipt_verified=false`, `review_execution_allowed=false`, `production_authority=false`. La forma del manifiesto y sus hashes provienen del caller; una cadena `fixture://` no acredita nada. Exige A9 vigente con recibo real, PG03 aprobado, vínculo de sujeto PG04 y revisor independiente auténtico. PG01_C6, PG03_C3/C9 y PG04_C2/C7 permanecían `PENDING` en el último readback.

**Sin promoción a producción, sin merge, sin escrituras Supabase, sin cambios de workflows protegidos.** El PR debe permanecer draft hasta revisión y evidencia exact-HEAD.

## PG-04_C5: plan de Definition of Done por solución

`tools/pg04_definition_of_done_candidate_v1.py` prepara `PG04_SOLUTION_DOD_CANDIDATE_V1` ligado al digest de partición. Usa manifest de estándares con `applies_to_write_scopes` y manifiesto de validadores `ACTIVE` suministrados por el llamador; **no verifica** su currentness ni ejecuta esos validadores. Exige un check por estándar aplicable, por requisito, por aceptación y por dependencia `SOL-*` concreta. Nunca declara DoD cumplida: `PLANNED_NOT_EXECUTED`, `receipt_id=null`, `handoff_allowed=false`.

`tests/test_pg04_definition_of_done_candidate_v1.py` contiene 30 pruebas definidas (no atribuir PASS hasta ejecución exact-HEAD). Documentación completa: `PG04_C5_DEFINITION_OF_DONE_CANDIDATE_20261103.md`.
